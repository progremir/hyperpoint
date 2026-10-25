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
        let carriers = Self.clickCarriers(config)
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
            let keys = Self.keyRoutes(profile, on: device, carriers: carriers, tapAvailable: tapAvailable, taken: routes)
            routes += keys.routes
            var hidpp: HIDPPSetup?
            var skippedRules = keys.skipped
            if device.properties.speaksHIDPP {
                let compiled = HIDPPSetup.compile(profile, capabilities: device.hidpp)
                hidpp = compiled.0
                skippedRules = compiled.skipped + skippedRules
            }
            if !skippedRules.isEmpty { skipped[device.id] = skippedRules }
            setups[device.id] = DeviceSetup(keyMap: KeyMapSetup(routes: routes), hidpp: hidpp)
        }
        let routes = present.flatMap { setups[$0.id]?.keyMap.routes ?? [] }
        return Intent(
            setups: setups, tap: TapRules(routes: routes, smoothScroll: smoothScroll, buttons: buttons), skipped: skipped)
    }

    /// Each action a key clicks gets its own carrier, in file order, so a device that connects or leaves never moves
    /// another device's. Rules past the last carrier get none.
    private static func clickCarriers(_ config: Config) -> [Action: Carrier] {
        var carriers: [Action: Carrier] = [:]
        var free = Carrier.forKeyRules[...]
        for rule in config.devices.flatMap({ $0.rules ?? [] }) {
            guard case .key = rule.control, rule.trigger == .click, carriers[rule.action] == nil,
                let carrier = free.popFirst()
            else { continue }
            carriers[rule.action] = carrier
        }
        return carriers
    }

    /// A key held as a modifier becomes that modifier at the HID layer. A key that clicks becomes its action's carrier,
    /// which only the tap can turn into the action. A key the hyper route already maps keeps that route.
    private static func keyRoutes(
        _ profile: DeviceProfile, on device: PresentDevice, carriers: [Action: Carrier], tapAvailable: Bool,
        taken: [KeyRoute]
    ) -> (routes: [KeyRoute], skipped: [Rule]) {
        var routes: [KeyRoute] = []
        var skipped: [Rule] = []
        for rule in profile.rules ?? [] {
            guard case .key(let usage) = rule.control else { continue }
            let target: KeyTarget? =
                switch (rule.trigger, rule.action) {
                case (.hold, .modifier(let modifier)): .native(modifier.usage)
                case (.click, let action): carriers[action].map { .carrier($0, .press(action)) }
                default: nil
                }
            guard let target, device.properties.usagePairs.contains(.keyboard), !taken.contains(where: { $0.source == usage })
            else {
                skipped.append(rule)
                continue
            }
            if case .carrier = target, !tapAvailable { continue }
            routes.append(KeyRoute(source: usage, target: target))
        }
        return (routes, skipped)
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
