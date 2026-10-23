struct DeviceSetup: Equatable, Sendable {
    var keyMap: KeyMapSetup

    static let neutral = DeviceSetup(keyMap: .neutral)
}

/// The desired state of every present device and of the tap. The only place `Config` is interpreted.
struct Intent: Equatable, Sendable {
    var setups: [DeviceInstanceID: DeviceSetup]
    var tap: TapRules

    static let neutral = Intent(setups: [:], tap: .empty)

    func setup(for device: DeviceInstanceID) -> DeviceSetup { setups[device] ?? .neutral }

    /// Paused compiles to `neutral`, so pausing is the same reconcile as a config change. A carrier is a dead key
    /// without the tap to give it meaning, so carrier routes exist only while the tap can run.
    static func compile(_ config: Config, paused: Bool, tapAvailable: Bool, present: [PresentDevice]) -> Intent {
        guard !paused else { return .neutral }
        var setups: [DeviceInstanceID: DeviceSetup] = [:]
        for device in present {
            guard let profile = config.profile(for: device.properties) else { continue }
            var routes: [KeyRoute] = []
            if profile.hyper == true, tapAvailable { routes.append(.hyper(from: config.hyper.key)) }
            setups[device.id] = DeviceSetup(keyMap: KeyMapSetup(routes: routes))
        }
        let routes = present.flatMap { setups[$0.id]?.keyMap.routes ?? [] }
        return Intent(setups: setups, tap: TapRules(routes: routes))
    }
}
