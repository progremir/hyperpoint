/// What one HID++ device should hold. A control missing from `controls` is native, so the neutral setup needs no
/// knowledge of the device and every divertable control is written on every apply.
struct HIDPPSetup: Equatable, Sendable {
    var controls: [CID: ControlBehavior]
    var thumbWheelInverted: Bool

    static let native = HIDPPSetup(controls: [:], thumbWheelInverted: false)

    func behavior(of cid: CID) -> ControlBehavior { controls[cid] ?? .native }

    /// A device Hyperpoint has opened goes back to native when nothing is wanted any more. One it never opened is
    /// left alone.
    static func pendingWrite(desired: HIDPPSetup?, opened: Bool) -> HIDPPSetup? {
        desired ?? (opened ? .native : nil)
    }
}

/// The firmware flags and the host routing of a control both derive from this one value, so a control cannot be
/// diverted with rawXY without its presses reaching the gesture machine.
enum ControlBehavior: Equatable, Sendable {
    case native
    /// The action fires on the press edge.
    case press(Action)
    case gesture(GesturePlan)

    /// A gesture on a control without rawXY still diverts, and its release is a click.
    func reporting(for control: HIDPPCapabilities.Control) -> ControlReporting {
        switch self {
        case .native: .native
        case .press: ControlReporting(divert: true, rawXY: false)
        case .gesture: ControlReporting(divert: true, rawXY: control.rawXY)
        }
    }
}

extension HIDPPSetup {
    static let defaultGestures = GestureSettings(fire: .pastDistance, distance: 120)

    /// Nil when the profile has no rule for a HID++ control or the thumb wheel, so the device is left alone. Before
    /// discovery `capabilities` is nil and nothing is skipped. The link only writes controls the device has.
    static func compile(_ profile: DeviceProfile, capabilities: HIDPPCapabilities?) -> (HIDPPSetup?, skipped: [Rule]) {
        var clicks: [CID: Action] = [:]
        var swipes: [CID: [Direction: Action]] = [:]
        var order: [CID] = []
        var inverted = false
        var relevant = false
        var skipped: [Rule] = []
        for rule in profile.rules ?? [] {
            switch (rule.control, rule.trigger) {
            case (.hidpp(let cid), .click), (.hidpp(let cid), .holdMove):
                relevant = true
                if let capabilities, !capabilities.allows(rule.trigger, on: cid) {
                    skipped.append(rule)
                    continue
                }
                if !order.contains(cid) { order.append(cid) }
                if case .holdMove(let direction) = rule.trigger {
                    swipes[cid, default: [:]][direction] = rule.action
                } else {
                    clicks[cid] = rule.action
                }
            case (.thumbWheel, .scroll):
                relevant = true
                guard capabilities?.thumbWheel ?? true else {
                    skipped.append(rule)
                    continue
                }
                inverted = rule.action == .reverse
            default:
                continue
            }
        }
        guard relevant else { return (nil, []) }
        let settings = profile.gestures ?? defaultGestures
        var controls: [CID: ControlBehavior] = [:]
        for cid in order {
            if let swipes = swipes[cid] {
                controls[cid] = .gesture(
                    GesturePlan(fire: settings.fire, distance: settings.distance, click: clicks[cid], swipes: swipes))
            } else if let click = clicks[cid] {
                controls[cid] = .press(click)
            }
        }
        return (HIDPPSetup(controls: controls, thumbWheelInverted: inverted), skipped)
    }
}

extension HIDPPCapabilities {
    func allows(_ trigger: Trigger, on cid: CID) -> Bool {
        guard let control = control(cid), control.divertable else { return false }
        if case .holdMove = trigger { return control.rawXY }
        return true
    }
}
