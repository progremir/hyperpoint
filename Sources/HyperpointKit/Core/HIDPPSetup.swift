struct HIDPPSetup: Equatable, Sendable {
    var controls: [CID: ControlBehavior]
    var thumbWheelInverted: Bool
    /// Every divertable control but the left button diverts without raw movement and only reports its press.
    /// `controls` and the wheel's direction keep their values, so the next write without it is the real setup again.
    var listening = false
    /// Only while listening, so a turn is reported instead of scrolling.
    var thumbWheelDiverted = false

    static let native = HIDPPSetup(controls: [:], thumbWheelInverted: false)

    /// The user clicks Cancel with it, so a listen leaves it native even on a mouse that lets it divert.
    static let leftButton = CID(rawValue: 0x50)

    /// `plan` listening, or a native setup listening when the profile has no HID++ rules. A mouse with a thumb wheel
    /// diverts it too.
    static func listening(over plan: HIDPPSetup?, thumbWheel: Bool) -> HIDPPSetup {
        var setup = plan ?? .native
        setup.listening = true
        setup.thumbWheelDiverted = thumbWheel
        return setup
    }

    var thumbWheel: ThumbWheelReporting {
        ThumbWheelReporting(diverted: thumbWheelDiverted, inverted: thumbWheelInverted)
    }

    func behavior(of cid: CID) -> ControlBehavior { controls[cid] ?? .native }

    func listens(to cid: CID) -> Bool { listening && cid != Self.leftButton }

    func reporting(for control: HIDPPCapabilities.Control) -> ControlReporting {
        guard listening else { return behavior(of: control.cid).reporting(for: control) }
        return listens(to: control.cid) ? ControlReporting(divert: true, rawXY: false) : .native
    }

    /// Nil writes nothing. Once this connection has written, nil desired turns the device back to native.
    static func pendingWrite(desired: HIDPPSetup?, written: Bool) -> HIDPPSetup? {
        desired ?? (written ? .native : nil)
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
        var rules: [CID: [Rule]] = [:]
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
                rules[cid, default: []].append(rule)
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
        var controls: [CID: ControlBehavior] = [:]
        for cid in order {
            controls[cid] = ControlBehavior(rules[cid] ?? [], profile: profile, movement: .sensorCounts)
        }
        return (HIDPPSetup(controls: controls, thumbWheelInverted: inverted), skipped)
    }
}

/// What a control's movement is measured in. The gesture distance is in sensor counts, so a pointer drag's
/// distance is converted with the same factor that sizes its scrolling.
enum MovementUnit {
    /// HID++ raw movement.
    case sensorCounts
    /// Pointer drags, already accelerated into screen points.
    case points

    var pointsPerUnit: Double { self == .sensorCounts ? HoldScrollPlan.pointsPerCount : 1 }

    func distance(_ counts: Int) -> Double { Double(counts) * HoldScrollPlan.pointsPerCount / pointsPerUnit }
}

extension ControlBehavior {
    /// One control's behavior from its rules, which the parser has already checked fit together.
    init(_ rules: [Rule], profile: DeviceProfile, movement: MovementUnit) {
        var click: Action?
        var swipes: [Direction: Action] = [:]
        var scrolls = false
        for rule in rules {
            switch rule.trigger {
            case .click: click = rule.action
            case .holdMove(let direction?): swipes[direction] = rule.action
            case .holdMove(nil): scrolls = rule.action == .scroll
            case .hold, .scroll: break
            }
        }
        let gestures = profile.gestures ?? .default
        let distance = movement.distance(gestures.distance)
        if scrolls {
            let plan = HoldScrollPlan(
                profile.scrolling?.holdToScroll ?? .default, glide: profile.scrolling?.smooth ?? .default,
                pointsPerUnit: movement.pointsPerUnit)
            self = .gesture(GesturePlan(distance: distance, click: click, moves: .scroll(plan)))
        } else if !swipes.isEmpty {
            self = .gesture(GesturePlan(distance: distance, click: click, moves: .swipes(swipes, fire: gestures.fire)))
        } else if let click {
            self = .press(click)
        } else {
            self = .native
        }
    }
}

extension HIDPPCapabilities {
    func allows(_ trigger: Trigger, on cid: CID) -> Bool {
        guard let control = control(cid), control.divertable else { return false }
        if case .holdMove = trigger { return control.rawXY }
        return true
    }
}
