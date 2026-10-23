struct HIDPPSetup: Equatable, Sendable {
    var controls: [CID: ControlBehavior]
    var thumbWheelInverted: Bool

    static let native = HIDPPSetup(controls: [:], thumbWheelInverted: false)

    func behavior(of cid: CID) -> ControlBehavior { controls[cid] ?? .native }

    static func pendingWrite(desired: HIDPPSetup?, opened: Bool) -> HIDPPSetup? {
        desired ?? (opened ? .native : nil)
    }
}

enum ControlBehavior: Equatable, Sendable {
    case native
    case press(Action)
    case gesture(GesturePlan)

    func reporting(for control: HIDPPCapabilities.Control) -> ControlReporting {
        switch self {
        case .native: .native
        case .press: ControlReporting(divert: true, rawXY: false)
        case .gesture: ControlReporting(divert: true, rawXY: control.rawXY)
        }
    }
}

extension HIDPPSetup {
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
                if case .holdMove(let direction?) = rule.trigger {
                    swipes[cid, default: [:]][direction] = rule.action
                } else if rule.trigger == .click {
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
        let settings = profile.gestures ?? .default
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
