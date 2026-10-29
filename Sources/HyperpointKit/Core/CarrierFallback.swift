/// What `CarrierFallback` stands in for: the carriers the tap takes, and whether Right Control is hyper.
struct CarrierPlan: Equatable, Sendable {
    var carriers: [KeyCode: CarrierMeaning]
    var hyper: Bool

    static let none = CarrierPlan(carriers: [:], hyper: false)

    init(carriers: [KeyCode: CarrierMeaning], hyper: Bool) {
        self.carriers = carriers
        self.hyper = hyper
    }

    init(_ rules: TapRules) { self.init(carriers: rules.carriers, hyper: rules.hyper) }
}

/// Does the tap's work with hotkeys where the tap sees no keys, as in secure input (a terminal's hidden prompt, a
/// password field). A press carrier is a hotkey with no modifiers, which macOS matches after the tap, so it fires
/// only for a press the tap did not take. In secure input macOS still gives hotkeys every key held with Control
/// (measured), so while it is on every key is a Control hotkey: one held with Right Control, hyper's key, goes on
/// with ⌃⌥⇧⌘ instead, and one held with the other Control key goes back to the app as it was.
struct CarrierFallback {
    enum Effect: Equatable {
        case perform(Action)
        /// Take exactly these keys from apps as hotkeys with Control.
        case take(Set<KeyCode>)
        /// Send the key on with ⌃⌥⇧⌘.
        case hyper(KeyCode, down: Bool)
        /// Send the press on to the focused app as it came. Its hotkey is already given back.
        case passBack(KeyCode)
    }

    /// Every key hyper can go with: every key the config names and F13 to F20. Caps Lock is hyper's own key on a hyper
    /// keyboard.
    static let controlKeys = Set(KeyTable.keys.map(\.keyCode) + Carrier.pool.map(\.keyCode))
        .subtracting([KeyCode(name: "capsLock")!])

    private(set) var plan = CarrierPlan.none
    private var taken: Set<KeyCode> = []
    /// Keys sent on with hyper, until their release.
    private var down: Set<KeyCode> = []
    /// Keys given back to apps, until their release, so that their hotkeys do not take the press passed on.
    private var passing: Set<KeyCode> = []

    /// Keys sent on with hyper go up first.
    mutating func replace(_ plan: CarrierPlan) -> [Effect] {
        var effects = releaseAll()
        self.plan = plan
        passing = []
        if !taken.isEmpty {
            taken = []
            effects.append(.take([]))
        }
        return effects
    }

    mutating func carrierPressed(_ code: KeyCode) -> [Effect] {
        guard case .press(let action) = plan.carriers[code] else { return [] }
        return [.perform(action)]
    }

    /// Run often while hyper is on, since nothing reports secure input starting or a key's release that went to an
    /// app. Keys are taken while secure input is on, and until the last key sent on with hyper is up.
    mutating func check(secureInput: Bool, isDown: (KeyCode) -> Bool) -> [Effect] {
        var effects: [Effect] = []
        for code in down.sorted(by: { $0.rawValue < $1.rawValue }) where !isDown(code) {
            down.remove(code)
            effects.append(.hyper(code, down: false))
        }
        passing = passing.filter(isDown)
        let wanted = plan.hyper && (secureInput || !down.isEmpty) ? Self.controlKeys.subtracting(passing) : []
        if wanted != taken {
            taken = wanted
            effects.append(.take(wanted))
        }
        return effects
    }

    mutating func controlKeyPressed(_ code: KeyCode, rightControl: Bool) -> [Effect] {
        guard taken.contains(code) else { return [] }
        if rightControl { return down.insert(code).inserted ? [.hyper(code, down: true)] : [] }
        taken.remove(code)
        passing.insert(code)
        return [.take(taken), .passBack(code)]
    }

    mutating func controlKeyReleased(_ code: KeyCode) -> [Effect] {
        down.remove(code) == nil ? [] : [.hyper(code, down: false)]
    }

    private mutating func releaseAll() -> [Effect] {
        defer { down = [] }
        return down.sorted { $0.rawValue < $1.rawValue }.map { .hyper($0, down: false) }
    }
}

extension Action {
    /// A shortcut that only types a character: a letter, digit or punctuation key with neither Command nor Control.
    /// In secure input macOS gives it to the focused field instead of any hotkey (measured), so posting it there
    /// would type into the password.
    var typesCharacter: Bool {
        guard case .shortcut(let chord) = self, chord.modifiers.isDisjoint(with: [.command, .control]),
            let name = chord.key.name
        else { return false }
        return name.count == 1
            || ["minus", "equal", "leftBracket", "rightBracket", "backslash", "semicolon", "quote", "grave", "comma",
                "period", "slash"].contains(name)
    }
}
