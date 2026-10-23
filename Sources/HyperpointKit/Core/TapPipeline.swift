import CoreGraphics

/// The tap's whole configuration, derived from the same routes as the `hidutil` mappings.
struct TapRules: Equatable, Sendable {
    var carriers: [KeyCode: CarrierMeaning]

    static let empty = TapRules(carriers: [:])

    init(carriers: [KeyCode: CarrierMeaning]) { self.carriers = carriers }

    init(routes: [KeyRoute]) {
        var carriers: [KeyCode: CarrierMeaning] = [:]
        for route in routes {
            switch route.target {
            case .carrier(let carrier, let meaning): carriers[carrier.keyCode] = meaning
            }
        }
        self.init(carriers: carriers)
    }

    var isEmpty: Bool { carriers.isEmpty }
}

enum TapVerdict: Equatable, Sendable {
    case pass
    case drop
}

/// What the event tap does with an event: a value in, a verdict out, with the event rewritten in place. Every stage
/// runs on fabricated CGEvents in tests, with no tap and no permission.
struct TapPipeline {
    /// Every event Hyperpoint posts carries this in `eventSourceUserData`, and no stage touches such an event.
    static let syntheticMarker: Int64 = 0x4859_5052

    private var carriers: CarrierStage

    init(rules: TapRules) { carriers = CarrierStage(rules: rules) }

    static var mask: CGEventMask {
        CarrierStage.interests.reduce(0) { $0 | (1 << CGEventMask($1.rawValue)) }
    }

    /// Swaps the rules in whole and forgets held keys, so a rule change cannot strand a modifier.
    mutating func apply(_ rules: TapRules) { carriers = CarrierStage(rules: rules) }

    mutating func process(_ type: CGEventType, _ event: CGEvent) -> TapVerdict {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
        return carriers.process(type, event)
    }

    /// Runs on tap timeout and keyboard removal, where a key-up may have been lost.
    mutating func reset() { carriers.reset() }
}

/// Carrier keys. A hold-modifiers carrier's own key-down and key-up are rewritten in place into `flagsChanged`
/// events that set and clear its modifiers, and keys pressed while it is down get its modifiers too. The hyper
/// prototype measured this as the strategy that fires hotkeys and never leaves the system's modifier state stuck.
struct CarrierStage {
    static let interests: [CGEventType] = [.keyDown, .keyUp]

    /// A `flagsChanged` event names a modifier key. Left Command is the one the prototype measured.
    private static let modifierKeyCode: Int64 = 55

    let rules: TapRules
    private var held: [KeyCode: Modifiers] = [:]

    init(rules: TapRules) { self.rules = rules }

    private var heldFlags: CGEventFlags { held.values.reduce([]) { $0.union($1.cgFlags) } }

    mutating func process(_ type: CGEventType, _ event: CGEvent) -> TapVerdict {
        guard type == .keyDown || type == .keyUp else { return .pass }
        let code = KeyCode(rawValue: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
        guard let meaning = rules.carriers[code] else {
            if !held.isEmpty { event.flags.formUnion(heldFlags) }
            return .pass
        }
        switch meaning {
        case .holdModifiers(let modifiers):
            if type == .keyDown {
                guard held[code] == nil else { return .drop }
                held[code] = modifiers
                event.type = .flagsChanged
                event.setIntegerValueField(.keyboardEventKeycode, value: Self.modifierKeyCode)
                event.flags.formUnion(modifiers.cgFlags)
            } else {
                // A key-up always clears, even after a reset, so the system's modifier state cannot stay set.
                held[code] = nil
                event.type = .flagsChanged
                event.setIntegerValueField(.keyboardEventKeycode, value: Self.modifierKeyCode)
                event.flags.subtract(modifiers.cgFlags.subtracting(heldFlags))
            }
            return .pass
        }
    }

    mutating func reset() { held = [:] }
}

extension Modifiers {
    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}
