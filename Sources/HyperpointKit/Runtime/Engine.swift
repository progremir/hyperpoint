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
    private nonisolated let tapOrders: AsyncStream<TapOrder>
    private nonisolated let tapOrderSink: AsyncStream<TapOrder>.Continuation
    private nonisolated let tapSignals: AsyncStream<TapSignal>
    private nonisolated let tapSignalSink: AsyncStream<TapSignal>.Continuation
    /// Every event in order, because a lost end would leave the pointer frozen.
    private nonisolated let holdScrolls: AsyncStream<HoldScrollEvent>
    private nonisolated let holdScrollSink: AsyncStream<HoldScrollEvent>.Continuation
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
    private var started = false
    private let journal = Journal()
    private lazy var hub = DeviceHub { [unowned self] event in handle(event) }

    public nonisolated init() {
        (statuses, statusSink) = AsyncStream.makeStream(of: EngineStatus.self, bufferingPolicy: .bufferingNewest(1))
        (actions, actionSink) = AsyncStream.makeStream(of: Action.self)
        (tapOrders, tapOrderSink) = AsyncStream.makeStream(of: TapOrder.self, bufferingPolicy: .bufferingNewest(1))
        (tapSignals, tapSignalSink) = AsyncStream.makeStream(of: TapSignal.self)
        (holdScrolls, holdScrollSink) = AsyncStream.makeStream(of: HoldScrollEvent.self)
        tapHost = TapHost(signals: tapSignalSink, actions: actionSink)
        permissions = Permissions.current()
    }

    /// Runs until cancelled. Devices are tracked from the first config snapshot on.
    public func run(configs: AsyncStream<ConfigSnapshot>, permissions: AsyncStream<PermissionState>) async {
        publish()
        await withDiscardingTaskGroup { group in
            group.addTask { await self.tapHost.follow(self.tapOrders) }
            group.addTask { await self.tapHost.follow(holdScrolls: self.holdScrolls) }
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
        reconcile(.pauseChanged)
    }

    /// Writes the neutral intent to every device and removes the tap, then returns within one second.
    public func shutdown() async {
        quitting = true
        reconcile(.quit)
        await tapHost.apply(TapOrder(install: false, rules: .empty))
        let deadline = ContinuousClock.now + .seconds(1)
        while slots.values.contains(where: \.busy), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
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
            reconcile(.configChanged)
        } else {
            publish()
        }
    }

    private func permissionsChanged(_ state: PermissionState) {
        guard state != permissions else { return }
        permissions = state
        reconcile(.permissionChanged)
    }

    /// Sleep loses HID++ diverts, and a keyboard service can come back without its key map.
    private nonisolated func followWakes() async {
        let center = await MainActor.run { NSWorkspace.shared.notificationCenter }
        for await _ in center.notifications(named: NSWorkspace.didWakeNotification) { await woke() }
    }

    private func woke() {
        journal.note("woke from sleep")
        reconcile(.wake)
    }

    private func tapSignaled(_ signal: TapSignal) {
        switch signal {
        case .installed: tap = .on
        case .removed: tap = .off
        case .installFailed: tap = .failed
        case .reenabled: journal.note("tap re-enabled after macOS disabled it")
        case .heard: break
        }
        publish()
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
            if slots[device.id]?.device.properties != device.properties {
                slots.removeValue(forKey: device.id)?.close()
                addSlot(for: device, atLaunch: false)
                recompile()
                slots[device.id]?.invalidate(.connected)
            } else {
                recompile()
            }
        case .disappeared(let device):
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
            device: device, hidppInterface: hub.hidppInterface(of: device.id), journal: journal,
            desired: { [unowned self] in intent.setup(for: device.id) },
            changed: { [unowned self] in publish() },
            discovered: { [unowned self] found in
                capabilities[device.id] = found
                recompile()
                publish()
            },
            perform: { [actionSink] in actionSink.yield($0) },
            holdScroll: { [holdScrollSink] in holdScrollSink.yield($0) })
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
                Intent.compile($0, paused: paused || quitting, tapAvailable: tapAvailable, present: present)
            } ?? .neutral
        let order = TapOrder(install: tapAvailable && !intent.tap.isEmpty, rules: intent.tap)
        if resendTapOrder || order != sentTapOrder {
            tapOrderSink.yield(order)
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
                hidpp: slot.flatMap(hidppStatus))
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
