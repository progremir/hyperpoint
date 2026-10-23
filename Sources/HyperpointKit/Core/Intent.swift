struct DeviceSetup: Equatable, Sendable {
    var keyMap: KeyMapSetup
    var hidpp: HIDPPSetup?

    static let neutral = DeviceSetup(keyMap: .neutral, hidpp: nil)
}

struct Intent: Equatable, Sendable {
    var setups: [DeviceInstanceID: DeviceSetup]
    var tap: TapRules
    var skipped: [DeviceInstanceID: [Rule]] = [:]

    static let neutral = Intent(setups: [:], tap: .empty)

    func setup(for device: DeviceInstanceID) -> DeviceSetup { setups[device] ?? .neutral }

    static func compile(_ config: Config, paused: Bool, tapAvailable: Bool, present: [PresentDevice]) -> Intent {
        guard !paused else { return .neutral }
        var setups: [DeviceInstanceID: DeviceSetup] = [:]
        var skipped: [DeviceInstanceID: [Rule]] = [:]
        for device in present {
            guard let profile = config.profile(for: device.properties) else { continue }
            var routes: [KeyRoute] = []
            if profile.hyper == true, tapAvailable, device.properties.hostsHyper {
                routes.append(.hyper(from: config.hyper.key))
            }
            var hidpp: HIDPPSetup?
            if device.properties.speaksHIDPP {
                let compiled = HIDPPSetup.compile(profile, capabilities: device.hidpp)
                hidpp = compiled.0
                if !compiled.skipped.isEmpty { skipped[device.id] = compiled.skipped }
            }
            setups[device.id] = DeviceSetup(keyMap: KeyMapSetup(routes: routes), hidpp: hidpp)
        }
        let routes = present.flatMap { setups[$0.id]?.keyMap.routes ?? [] }
        return Intent(setups: setups, tap: TapRules(routes: routes), skipped: skipped)
    }
}
