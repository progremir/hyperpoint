import HyperpointKit

/// What the rule pickers offer for one profile. Validity comes from the rule table the parser enforces, the controls
/// from what the device reported, and a control and trigger already used by another rule are left out, so every
/// choice saves.
struct RuleChoices {
    var rules: [Rule]
    var capabilities: HIDPPCapabilities?
    var speaksHIDPP: Bool

    static let triggers: [Trigger] = [.click, .hold] + Direction.allCases.map(Trigger.holdMove) + [.scroll]

    /// A new shortcut rule needs some chord before the user records one.
    static let placeholderChord = Chord(key: KeyCode(name: "4")!, modifiers: [.shift, .command])

    static let actions: [Action] =
        SystemAction.allCases.map(Action.system) + [.shortcut(placeholderChord)] + HeldModifier.allCases.map(Action.modifier)
        + [.reverse]

    var controls: [Control] {
        var controls = rules.map(\.control)
        if speaksHIDPP {
            if let capabilities {
                controls += capabilities.controls.filter(\.divertable).map { .hidpp($0.cid) }
                if capabilities.thumbWheel { controls.append(.thumbWheel) }
            } else {
                controls.append(.thumbWheel)
            }
        } else {
            controls += HIDUsage.named.map(Control.key)
        }
        var seen = Set<Control>()
        return controls.filter { seen.insert($0).inserted }.sorted { Self.order($0) < Self.order($1) }
    }

    /// The controls the Button picker offers for `rule`: its own, and every other with a trigger still free.
    func controls(for rule: Rule) -> [Control] {
        controls.filter { $0 == rule.control || !triggers(for: $0, besides: rule).isEmpty }
    }

    func triggers(for control: Control, besides rule: Rule? = nil) -> [Trigger] {
        let taken = Set(rules.filter { $0.control == control && RuleKey($0) != rule.map(RuleKey.init) }.map(\.trigger))
        return Self.triggers.filter { trigger in
            control.accepts(trigger) && !taken.contains(trigger) && canMove(control, on: trigger)
        }
    }

    func actions(for control: Control, on trigger: Trigger) -> [Action] {
        Self.actions.filter { control.accepts($0, on: trigger) }
    }

    /// What Add Rule adds: the first free trigger, preferring controls that already have rules, so a new rule
    /// starts on a button the user has already handed to Hyperpoint. Nil when every trigger is taken.
    var newRule: Rule? {
        var seen = Set<Control>()
        let used = rules.map(\.control).filter { seen.insert($0).inserted }
        let candidates = used + controls.filter { !used.contains($0) }
        for control in candidates {
            if let trigger = triggers(for: control).first, let action = actions(for: control, on: trigger).first {
                return Rule(control: control, trigger: trigger, action: action)
            }
        }
        return nil
    }

    /// `rule` moved to `control`, keeping its trigger and action where they still work.
    func rule(_ rule: Rule, withControl control: Control) -> Rule {
        let triggers = triggers(for: control, besides: rule)
        let trigger = triggers.contains(rule.trigger) ? rule.trigger : triggers.first ?? rule.trigger
        return self.rule(Rule(control: control, trigger: trigger, action: rule.action), withTrigger: trigger)
    }

    /// `rule` with `trigger`, keeping its action where it still works.
    func rule(_ rule: Rule, withTrigger trigger: Trigger) -> Rule {
        let action =
            rule.control.accepts(rule.action, on: trigger)
            ? rule.action : actions(for: rule.control, on: trigger).first ?? rule.action
        return Rule(control: rule.control, trigger: trigger, action: action)
    }

    /// A swipe needs raw movement, which only some HID++ controls report.
    private func canMove(_ control: Control, on trigger: Trigger) -> Bool {
        guard case .holdMove = trigger, case .hidpp(let cid) = control, let capabilities else { return true }
        return capabilities.control(cid)?.rawXY ?? true
    }

    private static func order(_ control: Control) -> Int {
        switch control {
        case .hidpp(let cid): Int(cid.rawValue)
        case .thumbWheel: 0x1_0000
        case .key(let usage): 0x2_0000 + (HIDUsage.named.firstIndex(of: usage) ?? 0)
        case .button(let number): 0x3_0000 + number
        }
    }
}
