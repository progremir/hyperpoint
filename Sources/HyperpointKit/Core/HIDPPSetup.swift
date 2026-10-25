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
