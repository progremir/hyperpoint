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
        var smoothScroll: [SenderID: SmoothScroll] = [:]
        var buttons: [ButtonKey: ControlBehavior] = [:]
        for device in present {
            guard let profile = config.profile(for: device.properties) else { continue }
            if let smooth = profile.scrolling?.smooth {
                for sender in device.eventServices { smoothScroll[sender] = smooth }
            }
            for (button, behavior) in Self.plainButtons(profile) {
                for sender in device.eventServices { buttons[ButtonKey(sender: sender, button: button)] = behavior }
            }
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
        return Intent(
            setups: setups, tap: TapRules(routes: routes, smoothScroll: smoothScroll, buttons: buttons), skipped: skipped)
    }

    /// Plain buttons are seen in the tap, so their movement is pointer drags in points.
    private static func plainButtons(_ profile: DeviceProfile) -> [Int: ControlBehavior] {
        var rules: [Int: [Rule]] = [:]
        for rule in profile.rules ?? [] {
            if case .button(let number) = rule.control { rules[number, default: []].append(rule) }
        }
        return rules.mapValues { ControlBehavior($0, profile: profile, movement: .points) }
    }
}
