struct DeviceSetup: Equatable, Sendable {
    var keyMap: KeyMapSetup

    static let neutral = DeviceSetup(keyMap: .neutral)
}

struct Intent: Equatable, Sendable {
    var setups: [DeviceInstanceID: DeviceSetup]
    var tap: TapRules

    static let neutral = Intent(setups: [:], tap: .empty)

    func setup(for device: DeviceInstanceID) -> DeviceSetup { setups[device] ?? .neutral }

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
