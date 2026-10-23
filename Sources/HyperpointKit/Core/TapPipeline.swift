import CoreGraphics

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

struct TapPipeline {
    static let syntheticMarker: Int64 = 0x4859_5052

    private var carriers: CarrierStage

    init(rules: TapRules) { carriers = CarrierStage(rules: rules) }

    static var mask: CGEventMask {
        CarrierStage.interests.reduce(0) { $0 | (1 << CGEventMask($1.rawValue)) }
    }

    mutating func replaceRulesAndForgetHeldKeys(_ rules: TapRules) { carriers = CarrierStage(rules: rules) }

    mutating func process(_ type: CGEventType, _ event: CGEvent) -> TapVerdict {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
        return carriers.process(type, event)
    }

    mutating func reset() { carriers.reset() }
}

struct CarrierStage {
    static let interests: [CGEventType] = [.keyDown, .keyUp]

    private static let leftCommandKeyCode: Int64 = 55

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
                event.flags.formUnion(modifiers.cgFlags)
            } else {
                held[code] = nil
                event.flags.subtract(modifiers.cgFlags.subtracting(heldFlags))
            }
            event.type = .flagsChanged
            event.setIntegerValueField(.keyboardEventKeycode, value: Self.leftCommandKeyCode)
            // F-key events carry Fn, and a flagsChanged event with it marks Fn held.
            event.flags.remove(.maskSecondaryFn)
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
