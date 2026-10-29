import AppKit
import Foundation

@HIDActor
public final class Engine {
    /// Latest wins, so a slow UI never renders a stale status.
    public nonisolated let statuses: AsyncStream<EngineStatus>
    private nonisolated let statusSink: AsyncStream<EngineStatus>.Continuation
    /// Button actions, in order, for `ActionPerformer` on the main actor.
    public nonisolated let actions: AsyncStream<Action>
    private nonisolated let actionSink: AsyncStream<Action>.Continuation
    /// Heard presses, in order, each once, for the settings window.
    public nonisolated let heard: AsyncStream<LearnedPress>
    private nonisolated let heardSink: AsyncStream<LearnedPress>.Continuation
    /// What the tap does with keys, latest wins, for `CarrierHotkeys` on the main actor. None while there is no tap.
    nonisolated let carrierPlans: AsyncStream<CarrierPlan>
    private nonisolated let carrierPlanSink: AsyncStream<CarrierPlan>.Continuation
    private nonisolated let tapOrders: AsyncStream<TapOrder>
    private nonisolated let tapOrderSink: AsyncStream<TapOrder>.Continuation
    private nonisolated let tapSignals: AsyncStream<TapSignal>
    private nonisolated let tapSignalSink: AsyncStream<TapSignal>.Continuation
    /// Every event in order, because a lost end would leave the pointer frozen.
    private nonisolated let holdScrolls: AsyncStream<HoldScrollEvent>
    private nonisolated let holdScrollSink: AsyncStream<HoldScrollEvent>.Continuation
    /// Every event in order, because a lost release would leave a key held.
    private nonisolated let keyHolds: AsyncStream<KeyHoldEvent>
    private nonisolated let keyHoldSink: AsyncStream<KeyHoldEvent>.Continuation
    private nonisolated let tapHost: TapHost

    private var config: Config?
    private var configError: ConfigError?
    private var paused = false
    private var quitting = false
    private var permissions: PermissionState
    private var tap = TapState.off
    private var intent = Intent.neutral
    private var sentTapOrder: TapOrder?
    private var slots: [DeviceInstanceID: Slot] = [:]
    private var capabilities: [DeviceInstanceID: HIDPPCapabilities] = [:]
    private var lastReconnect: (device: DeviceInstanceID, name: String, at: Date)?
    private var listener = Listener()
    private var listenTimer: Task<Void, Never>?
    private let latch = DivertLatch()
    private var started = false
    private let journal = Journal()
    private lazy var hub = DeviceHub { [unowned self] event in handle(event) }

    public nonisolated init() {
        (statuses, statusSink) = AsyncStream.makeStream(of: EngineStatus.self, bufferingPolicy: .bufferingNewest(1))
        (actions, actionSink) = AsyncStream.makeStream(of: Action.self)
        (heard, heardSink) = AsyncStream.makeStream(of: LearnedPress.self)
        (carrierPlans, carrierPlanSink) = AsyncStream.makeStream(of: CarrierPlan.self, bufferingPolicy: .bufferingNewest(1))
        (tapOrders, tapOrderSink) = AsyncStream.makeStream(of: TapOrder.self, bufferingPolicy: .bufferingNewest(1))
        (tapSignals, tapSignalSink) = AsyncStream.makeStream(of: TapSignal.self)
        (holdScrolls, holdScrollSink) = AsyncStream.makeStream(of: HoldScrollEvent.self)
        (keyHolds, keyHoldSink) = AsyncStream.makeStream(of: KeyHoldEvent.self)
        tapHost = TapHost(signals: tapSignalSink, actions: actionSink)
        permissions = Permissions.current()
    }

    /// Runs until cancelled. Devices are tracked from the first config snapshot on.
    public func run(configs: AsyncStream<ConfigSnapshot>, permissions: AsyncStream<PermissionState>) async {
        publish()
        await withDiscardingTaskGroup { group in
            group.addTask { await self.tapHost.follow(self.tapOrders) }
            group.addTask { await self.tapHost.follow(holdScrolls: self.holdScrolls) }
            group.addTask { await self.tapHost.follow(keyHolds: self.keyHolds) }
            group.addTask { for await signal in self.tapSignals { await self.tapSignaled(signal) } }
            group.addTask { for await snapshot in configs { await self.configChanged(snapshot) } }
            group.addTask { for await state in permissions { await self.permissionsChanged(state) } }
            group.addTask { await self.followWakes() }
        }
    }

    public func reapplyAll() {
        reconcile(.manual, resendTapOrder: true)
    }

    /// Runtime state, not config, so a relaunch is never paused.
    public func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        if paused { endListen(.paused) }
        reconcile(.pauseChanged)
    }

    /// Writes the neutral intent to every device and removes the tap, then returns within one second.
    public func shutdown() async {
        quitting = true
        endListen(nil)
        reconcile(.quit)
        await tapHost.apply(TapOrder(install: false, rules: .empty))
        let deadline = ContinuousClock.now + .seconds(1)
        while slots.values.contains(where: \.busy), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if !slots.values.contains(where: \.busy) { latch.clear() }
    }

    /// Listens for the next press on the profile's device, replacing any listen. Refused, with the reason in its
    /// status, while paused, when the device is not connected, or when nothing can hear it.
    public func listen(for match: DeviceMatch) {
        let device = hub.devices.first { config?.profile(for: $0.properties)?.match == match }
        let refusal: ListenEnd? =
            if paused || quitting {
                .paused
            } else if let device {
                canHear(device) ? nil : .needsAccessibility
            } else {
                .disconnected
            }
        let previous = listener.target
        let armed = listener.start(match: match, device: device?.id, refusal: refusal, now: Date())
        if let armed, let device {
            if device.properties.speaksHIDPP { latch.insert(match) }
            listenTimer?.cancel()
            listenTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(ListenStatus.timeout))
                guard !Task.isCancelled else { return }
                self?.timedOut(armed.id)
            }
            journal.note("listen \(armed.id) on \(device.id) \(device.name)")
        } else if let refusal {
            journal.note("listen refused: \(refusal)")
        }
        relisten(previous)
    }

    /// Cancels the listen, or clears the note one left.
    public func stopListening() {
        let previous = listener.target
        if listener.end(nil) {
            journal.note("listen stopped")
            relisten(previous)
        } else if listener.dismiss() {
            publish()
        }
    }

    private func configChanged(_ snapshot: ConfigSnapshot) {
        let configChanged = snapshot.config != config
        config = snapshot.config
        configError = snapshot.error
        if !started {
            started = true
            for device in hub.start() { addSlot(for: device, atLaunch: true) }
            reconcile(.launch)
        } else if configChanged {
            let profile = listenedDevice.flatMap { config?.profile(for: $0.properties) }
            if let armed = listener.armed, profile?.match != armed.match { endListen(nil) }
            reconcile(.configChanged)
        } else {
            publish()
        }
    }

    private func permissionsChanged(_ state: PermissionState) {
        guard state != permissions else { return }
        permissions = state
        if let device = listenedDevice, !canHear(device) { endListen(.needsAccessibility) }
        reconcile(.permissionChanged)
    }

    /// Sleep loses HID++ diverts, and a keyboard service can come back without its key map.
    private nonisolated func followWakes() async {
        let center = await MainActor.run { NSWorkspace.shared.notificationCenter }
        for await _ in center.notifications(named: NSWorkspace.didWakeNotification) { await woke() }
    }

    /// The firmware lost the listen's divert, and the user was not pointing at a button while the Mac slept.
    private func woke() {
        journal.note("woke from sleep")
        endListen(.slept)
        reconcile(.wake)
    }

    private func tapSignaled(_ signal: TapSignal) {
        switch signal {
        case .installed: tap = .on
        case .removed: tap = .off
        case .installFailed: tap = .failed
        case .reenabled: journal.note("tap re-enabled after macOS disabled it")
        case .heard(let id, let press): return hear(press, from: .listen(id))
        }
        publish()
    }

    /// From the tap or from a slot. A press for a listen that already ended changes nothing.
    private func hear(_ press: ListenPress, from source: ListenSource) {
        let previous = listener.target
        guard let plan = intent.listening, let armed = listener.hear(from: source) else { return }
        heardSink.yield(LearnedPress(match: armed.match, heard: plan.heard(press)))
        journal.note("listen \(armed.id) heard \(press)")
        relisten(previous)
    }

    private func timedOut(_ id: ListenID) {
        let previous = listener.target
        guard listener.end(.timedOut, only: .listen(id)) else { return }
        journal.note("listen \(id) timed out")
        relisten(previous)
    }

    /// For an exit whose caller reconciles every device anyway.
    private func endListen(_ why: ListenEnd?, only source: ListenSource? = nil) {
        guard listener.end(why, only: source) else { return }
        listenTimer?.cancel()
        journal.note("listen ended: \(why.map { "\($0)" } ?? "stopped")")
    }

    /// Writes only the devices a listen started or ended on. The others keep what they hold.
    private func relisten(_ previous: ListenTarget?) {
        if listener.armed == nil { listenTimer?.cancel() }
        recompile()
        for id in Set([previous?.device, listener.target?.device].compactMap { $0 }) { slots[id]?.invalidate(.listen) }
        publish()
    }

    private var listenedDevice: PresentDevice? {
        listener.armed.flatMap { armed in hub.devices.first { $0.id == armed.device } }
    }

    /// The tap hears a device with an event service once Accessibility is granted, and HID++ hears its controls.
    private func canHear(_ device: PresentDevice) -> Bool {
        let tap = permissions.accessibility == .granted && !device.eventServices.isEmpty
        let hidpp =
            device.properties.speaksHIDPP && permissions.inputMonitoring == .granted
            && hub.hidppInterface(of: device.id) != nil
        return tap || hidpp
    }

    private func handle(_ event: DeviceRoster.Change) {
        switch event {
        case .appeared(let device):
            addSlot(for: device, atLaunch: false)
            recompile()
            slots[device.id]?.invalidate(.connected)
        case .changed(let device):
            journal.changed(device)
            // A slot reads its device once, so a keyboard interface enumerating after a pointer one needs a new slot
            // to write its key map.
            if let slot = slots[device.id], slot.device.properties != device.properties {
                slots.removeValue(forKey: device.id)?.close()
                addSlot(for: device, atLaunch: false)
                recompile()
                slots[device.id]?.invalidate(.connected)
            } else {
                recompile()
            }
        case .disappeared(let device):
            endListen(.disconnected, only: .device(device.id))
            slots.removeValue(forKey: device.id)?.close()
            capabilities[device.id] = nil
            journal.disconnected(device)
            recompile(resendTapOrder: true)
        }
        publish()
    }

    private func addSlot(for device: PresentDevice, atLaunch: Bool) {
        let profile = config?.profile(for: device.properties)
        journal.connected(device, profile: profile?.name, atLaunch: atLaunch)
        if !atLaunch, let profile { lastReconnect = (device.id, profile.name, Date()) }
        slots[device.id] = Slot(
            device: device, hidppInterface: hub.hidppInterface(of: device.id),
            owesNativeHIDPP: latch.contains(DeviceMatch(identifying: device.properties)), journal: journal,
            desired: { [unowned self] in intent.setup(for: device.id) },
            changed: { [unowned self] in publish() },
            discovered: { [unowned self] found in
                capabilities[device.id] = found
                recompile()
                publish()
            },
            perform: { [actionSink] in actionSink.yield($0) },
            holdScroll: { [holdScrollSink] in holdScrollSink.yield($0) },
            holdKeys: { [keyHoldSink] in keyHoldSink.yield($0) },
            heard: { [unowned self] in hear($0, from: .device(device.id)) })
    }

    private var present: [PresentDevice] {
        hub.devices.map { device in
            var device = device
            device.hidpp = capabilities[device.id]
            return device
        }
    }

    private func reconcile(_ reason: ApplyReason, resendTapOrder: Bool = false) {
        recompile(resendTapOrder: resendTapOrder)
        for slot in slots.values { slot.invalidate(reason) }
        publish()
    }

    private func recompile(resendTapOrder: Bool = false) {
        let tapAvailable = permissions.accessibility == .granted
        intent =
            config.map {
                Intent.compile(
                    $0, paused: paused || quitting, tapAvailable: tapAvailable, present: present,
                    listening: listener.target)
            } ?? .neutral
        let order = TapOrder(install: tapAvailable && !intent.tap.isEmpty, rules: intent.tap)
        if resendTapOrder || order != sentTapOrder {
            tapOrderSink.yield(order)
            carrierPlanSink.yield(order.install ? CarrierPlan(order.rules) : .none)
            sentTapOrder = order
        }
    }

    private func publish() {
        let present = hub.devices
        let rows = (config?.devices ?? []).map { profile in
            let device = present.first { config?.profile(for: $0.properties) == profile }
            let slot = device.flatMap { slots[$0.id] }
            return DeviceStatus(
                name: profile.name, match: profile.match, kind: device.map { profile.kind(of: $0.properties) },
                transport: device?.properties.transport, connectedAt: slot?.connectedAt,
                hyper: profile.hyper == true ? slot.map(Self.hyperStatus) ?? .off : nil,
                hidpp: slot.flatMap(hidppStatus), listen: listenStatus(for: profile.match, on: device))
        }
        var newDevices: [DeviceStatus] = []
        if let config {
            for device in present where !config.devices.contains(where: { $0.match.matches(device.properties) }) {
                let match = DeviceMatch(identifying: device.properties)
                guard !config.ignored.contains(match), !newDevices.contains(where: { $0.match == match }) else { continue }
                newDevices.append(
                    DeviceStatus(
                        name: device.name, match: match, kind: device.properties.kind,
                        transport: device.properties.transport, connectedAt: slots[device.id]?.connectedAt, hyper: nil))
            }
        }
        let reconnect = lastReconnect.map { last in
            Reconnect(device: last.name, at: last.at, reapplied: slots[last.device]?.reapplied ?? false)
        }
        statusSink.yield(
            EngineStatus(
                run: paused ? .paused : .active, permissions: permissions, configError: configError, tap: tap,
                devices: rows, newDevices: newDevices, lastReconnect: reconnect))
    }

    /// Getting ready until the device's writes land and the tap that hears it is on.
    private func listenStatus(for match: DeviceMatch, on device: PresentDevice?) -> ListenStatus? {
        switch listener.state {
        case .idle:
            return nil
        case .ended(let ended, let why):
            return ended == match ? .ended(why) : nil
        case .armed(let armed):
            guard armed.match == match, let device else { return nil }
            let tapReady = intent.tap.listen == nil || tap == .on
            let ready = tapReady && slots[device.id]?.busy == false
            return ready ? .listening(until: armed.until) : .gettingReady(until: armed.until)
        }
    }

    private func hidppStatus(_ slot: Slot) -> HIDPPStatus? {
        let progress: HIDPPStatus.Progress
        switch (slot.hidppApplying, slot.hidppLast?.outcome) {
        case (true, _): progress = .applying
        case (false, .applied): progress = .setUp
        case (false, .failed(let why)), (false, .skipped(let why)): progress = .notSetUp(why)
        case (false, nil): return nil
        }
        return HIDPPStatus(
            progress: progress, lastApply: slot.hidppLast?.at, capabilities: capabilities[slot.device.id],
            skippedRules: intent.skipped[slot.device.id] ?? [])
    }

    private static func hyperStatus(_ slot: Slot) -> HyperStatus {
        switch slot.phase {
        case .applying: .applying
        case .failed(let error): .failed(error.description)
        case .idle: slot.ownedOnDevice?.carriesHyper == true ? .on : .off
        }
    }
}
