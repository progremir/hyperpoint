import HyperpointKit

enum LearnedRule: Equatable {
    case add(Rule)
    /// The rule with this key becomes the new one.
    case replace(RuleKey, Rule)
    /// The press named the rule's own control.
    case unchanged
    /// Every trigger the control accepts already has a rule, so nothing is saved.
    case everyTriggerTaken(Control)
    /// A key or button the config cannot name.
    case unnamed
}

/// What the rule pickers offer for one profile. Validity comes from the rule table the parser enforces, the controls
/// from what the device reported, and a control and trigger already used by another rule are left out, so every
/// choice saves.
struct RuleChoices {
    var rules: [Rule]
    var capabilities: HIDPPCapabilities?
    var speaksHIDPP: Bool

    static let triggers: [Trigger] = [.click, .hold] + Direction.allCases.map(Trigger.holdMove) + [.holdMove(nil), .scroll]

    /// A new shortcut rule needs some chord before the user records one.
    static let placeholderChord = Chord(key: KeyCode(name: "4")!, modifiers: [.shift, .command])

    /// A hold lists its modifiers before a shortcut, so a click rule turned into a hold starts by holding one key.
    static let actions: [Action] =
        SystemAction.allCases.map(Action.system) + HeldModifier.allCases.map(Action.modifier) + [.shortcut(placeholderChord)]
        + [.reverse, .scroll]

    /// The standard HID++ control of each plain button, so a Logitech mouse that reports a button it cannot divert
    /// still offers it, as a plain button.
    static let plainButtons: [(number: Int, cid: UInt16)] = [(1, 0x51), (2, 0x52), (3, 0x53), (4, 0x56)]

    var controls: [Control] {
        var controls = rules.map(\.control)
        if speaksHIDPP {
            if let capabilities {
                controls += capabilities.controls.filter(\.divertable).map { .hidpp($0.cid) }
                if capabilities.thumbWheel { controls.append(.thumbWheel) }
                let fixed = capabilities.controls.filter { !$0.divertable }.map(\.cid.rawValue)
                controls += Self.plainButtons.filter { fixed.contains($0.cid) }.map { .button($0.number) }
            } else {
                controls.append(.thumbWheel)
            }
        } else {
            controls += Self.plainButtons.map { .button($0.number) } + HIDUsage.named.map(Control.key)
        }
        var seen = Set<Control>()
        return controls.filter { seen.insert($0).inserted }.sorted { Self.order($0) < Self.order($1) }
    }

    /// The controls the Button picker offers for `rule`: its own, and every other with a trigger still free.
    func controls(for rule: Rule) -> [Control] {
        controls.filter { $0 == rule.control || !triggers(for: $0, besides: rule).isEmpty }
    }

    func triggers(for control: Control, besides rule: Rule? = nil) -> [Trigger] {
        let taken = rules.filter { $0.control == control && RuleKey($0) != rule.map(RuleKey.init) }.map(\.trigger)
        return Self.triggers.filter { trigger in
            control.accepts(trigger) && !taken.contains { $0 == trigger || $0.conflicts(with: trigger) }
                && canMove(control, on: trigger)
        }
    }

    /// A click or a swipe can tap a modifier alone, which the shortcut recorder sets, so the eight are listed for a
    /// hold only.
    func actions(for control: Control, on trigger: Trigger) -> [Action] {
        Self.actions.filter { action in
            guard control.accepts(action, on: trigger) else { return false }
            if case .modifier = action { return trigger == .hold }
            return true
        }
    }

    /// What Add Rule adds for a pressed button or one picked from its menu: the control as the pickers name it, on
    /// its first free trigger, with that trigger's first action.
    func learned(_ heard: Heard) -> LearnedRule {
        guard case .control(let pressed) = heard else { return .unnamed }
        let control = canonical(pressed)
        guard let trigger = triggers(for: control).first, let action = actions(for: control, on: trigger).first else {
            return .everyTriggerTaken(control)
        }
        return .add(Rule(control: control, trigger: trigger, action: action))
    }

    /// What a press in a rule's Button cell does to `rule`: it moves to the pressed control, keeping its trigger and
    /// action where they still work.
    func learned(_ heard: Heard, replacing rule: Rule) -> LearnedRule {
        guard case .control(let pressed) = heard else { return .unnamed }
        let control = canonical(pressed)
        if control == rule.control { return .unchanged }
        guard !triggers(for: control, besides: rule).isEmpty else { return .everyTriggerTaken(control) }
        return .replace(RuleKey(rule), self.rule(rule, withControl: control))
    }

    /// A plain button whose standard HID++ control the device can divert is that control, so a press that beat the
    /// listen's divert names the control the pickers offer.
    func canonical(_ control: Control) -> Control {
        guard case .button(let number) = control, let cid = Self.plainButtons.first(where: { $0.number == number })?.cid,
            capabilities?.control(CID(rawValue: cid))?.divertable == true
        else { return control }
        return .hidpp(CID(rawValue: cid))
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

    /// Hold and move needs raw movement, which only some HID++ controls report.
    private func canMove(_ control: Control, on trigger: Trigger) -> Bool {
        guard case .holdMove = trigger, case .hidpp(let cid) = control, let capabilities else { return true }
        return capabilities.control(cid)?.rawXY ?? true
    }

    /// A plain button sorts just after its HID++ control.
    private static func order(_ control: Control) -> Int {
        switch control {
        case .hidpp(let cid): Int(cid.rawValue) << 1
        case .thumbWheel: 0x1_0000 << 1
        case .key(let usage): (0x2_0000 + (HIDUsage.named.firstIndex(of: usage) ?? 0)) << 1
        case .button(let number):
            plainButtons.first { $0.number == number }.map { Int($0.cid) << 1 | 1 } ?? (0x3_0000 + number) << 1
        }
    }
}
