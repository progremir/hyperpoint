import Foundation

/// The runtime behind a small public API. The engine owns the desired state (config, pause, permissions) and
/// recompiles the intent from it. Each slot owns what is on its device, and `TapHost` owns the tap. Every trigger
/// ends in `slot.invalidate(reason)`.
@HIDActor
public final class Engine {
    /// Latest wins, so a slow UI never renders a stale status.
    public nonisolated let statuses: AsyncStream<EngineStatus>
    private nonisolated let statusSink: AsyncStream<EngineStatus>.Continuation
    private nonisolated let tapOrders: AsyncStream<TapOrder>
    private nonisolated let tapOrderSink: AsyncStream<TapOrder>.Continuation
    private nonisolated let tapSignals: AsyncStream<TapSignal>
    private nonisolated let tapSignalSink: AsyncStream<TapSignal>.Continuation
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
    private var lastReconnect: (device: DeviceInstanceID, name: String, at: Date)?
    private var started = false
    private let journal = Journal()
    private lazy var hub = DeviceHub { [unowned self] event in handle(event) }

    public nonisolated init() {
        (statuses, statusSink) = AsyncStream.makeStream(of: EngineStatus.self, bufferingPolicy: .bufferingNewest(1))
        (tapOrders, tapOrderSink) = AsyncStream.makeStream(of: TapOrder.self, bufferingPolicy: .bufferingNewest(1))
        (tapSignals, tapSignalSink) = AsyncStream.makeStream(of: TapSignal.self)
        tapHost = TapHost(signals: tapSignalSink)
        permissions = Permissions.current()
    }

    /// Runs until cancelled. Devices are tracked from the first config snapshot on.
    public func run(configs: AsyncStream<ConfigSnapshot>, permissions: AsyncStream<PermissionState>) async {
        publish()
        await withDiscardingTaskGroup { group in
            group.addTask { await self.tapHost.follow(self.tapOrders) }
            group.addTask { for await signal in self.tapSignals { await self.tapSignaled(signal) } }
            group.addTask { for await snapshot in configs { await self.configChanged(snapshot) } }
            group.addTask { for await state in permissions { await self.permissionsChanged(state) } }
        }
    }

    /// Menu: Re-apply Settings Now.
    public func reapplyAll() {
        reconcile(.manual, resendTapOrder: true)
    }

    /// Menu: Pause Hyperpoint. Runtime state, not config, so a relaunch is never paused.
    public func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        reconcile(.pauseChanged)
    }

    /// Writes the neutral intent to every device and removes the tap, then returns within one second.
    public func shutdown() async {
        quitting = true
        reconcile(.quit)
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
        let tapPermissionChanged = state.accessibility != permissions.accessibility
        permissions = state
        if tapPermissionChanged { reconcile(.permissionChanged) } else { publish() }
    }

    private func tapSignaled(_ signal: TapSignal) {
        switch signal {
        case .installed: tap = .on
        case .removed: tap = .off
        case .installFailed: tap = .failed
        case .reenabled: journal.note("tap re-enabled after macOS disabled it")
        }
        publish()
    }

    private func handle(_ event: DeviceHub.Event) {
        switch event {
        case .appeared(let device):
            addSlot(for: device, atLaunch: false)
            recompile()
            slots[device.id]?.invalidate(.connected)
        case .disappeared(let device):
            slots.removeValue(forKey: device.id)?.close()
            journal.disconnected(device)
            // A keyboard that vanishes while hyper is held never sends the key-up, and every order resets the tap.
            recompile(resendTapOrder: true)
        }
        publish()
    }

    private func addSlot(for device: PresentDevice, atLaunch: Bool) {
        let profile = config?.profile(for: device.properties)
        journal.connected(device, profile: profile?.name, atLaunch: atLaunch)
        if !atLaunch, let profile { lastReconnect = (device.id, profile.name, Date()) }
        slots[device.id] = Slot(
            device: device, journal: journal,
            desired: { [unowned self] in intent.setup(for: device.id) },
            changed: { [unowned self] in publish() })
    }

    /// Idempotent. Every write is absolute, so running it twice, or after a crash halfway, ends in the same state.
    private func reconcile(_ reason: ApplyReason, resendTapOrder: Bool = false) {
        recompile(resendTapOrder: resendTapOrder)
        for slot in slots.values { slot.invalidate(reason) }
        publish()
    }

    private func recompile(resendTapOrder: Bool = false) {
        let tapAvailable = permissions.accessibility == .granted
        intent =
            config.map {
                Intent.compile($0, paused: paused || quitting, tapAvailable: tapAvailable, present: hub.devices)
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
                name: profile.name, connectedAt: slot?.connectedAt,
                hyper: profile.hyper == true ? slot.map(Self.hyperStatus) ?? .off : nil)
        }
        let reconnect = lastReconnect.map { last in
            Reconnect(
                device: last.name, at: last.at,
                reapplied: slots[last.device].map { $0.phase == .idle && $0.written?.carriesHyper == true } ?? false)
        }
        statusSink.yield(
            EngineStatus(
                run: paused ? .paused : .active, permissions: permissions, configError: configError, tap: tap,
                devices: rows, lastReconnect: reconnect))
    }

    private static func hyperStatus(_ slot: Slot) -> HyperStatus {
        switch slot.phase {
        case .applying: .applying
        case .failed(let error): .failed(error.description)
        case .idle: slot.written?.carriesHyper == true ? .on : .off
        }
    }
}
