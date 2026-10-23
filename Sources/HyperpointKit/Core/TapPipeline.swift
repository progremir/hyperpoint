import CoreGraphics

struct TapRules: Equatable, Sendable {
    var carriers: [KeyCode: CarrierMeaning]
    var smoothScroll: [SenderID: SmoothScroll]

    static let empty = TapRules(carriers: [:], smoothScroll: [:])

    init(carriers: [KeyCode: CarrierMeaning], smoothScroll: [SenderID: SmoothScroll]) {
        self.carriers = carriers
        self.smoothScroll = smoothScroll
    }

    init(routes: [KeyRoute], smoothScroll: [SenderID: SmoothScroll]) {
        var carriers: [KeyCode: CarrierMeaning] = [:]
        for route in routes {
            switch route.target {
            case .carrier(let carrier, let meaning): carriers[carrier.keyCode] = meaning
            }
        }
        self.init(carriers: carriers, smoothScroll: smoothScroll)
    }

    var isEmpty: Bool { carriers.isEmpty && smoothScroll.isEmpty }
}

enum TapVerdict: Equatable, Sendable {
    case pass
    case drop
    /// Drop the event and feed the tick to the scroll animator.
    case scroll(ScrollTick)
}

/// What the HID event behind a tap event says about it.
struct HIDOrigin: Equatable, Sendable {
    /// The registry id of the HID event service that sent it.
    var sender: SenderID
    /// The wheel's own vertical travel in detents, before macOS accelerates it into lines. 0 for other events.
    var wheelDetents: Double
}

struct TapPipeline {
    static let syntheticMarker: Int64 = 0x4859_5052

    private let origin: @Sendable (CGEvent) -> HIDOrigin?
    private var carriers: CarrierStage
    private var scroll: ScrollStage

    init(rules: TapRules, origin: @escaping @Sendable (CGEvent) -> HIDOrigin?) {
        self.origin = origin
        carriers = CarrierStage(rules: rules)
        scroll = ScrollStage(settings: rules.smoothScroll, origin: origin)
    }

    static var mask: CGEventMask {
        (CarrierStage.interests + ScrollStage.interests).reduce(0) { $0 | (1 << CGEventMask($1.rawValue)) }
    }

    mutating func replaceRulesAndForgetHeldKeys(_ rules: TapRules) { self = TapPipeline(rules: rules, origin: origin) }

    mutating func process(_ type: CGEventType, _ event: CGEvent) -> TapVerdict {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
        let verdict = carriers.process(type, event)
        return verdict == .pass ? scroll.process(type, event) : verdict
    }

    mutating func reset() { carriers.reset() }
}

/// Takes vertical wheel steps from senders with smooth scrolling. Continuous scrolls, horizontal ones such as the
/// thumb wheel's, and scrolls with a modifier held pass, so trackpads, other mice, shift-scroll and zoom stay native.
/// The line delta is already accelerated, so the steps come from the wheel's detents, or 1 when it has none.
struct ScrollStage {
    static let interests: [CGEventType] = [.scrollWheel]

    private static let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    let settings: [SenderID: SmoothScroll]
    let origin: @Sendable (CGEvent) -> HIDOrigin?

    func process(_ type: CGEventType, _ event: CGEvent) -> TapVerdict {
        guard type == .scrollWheel, !settings.isEmpty,
            event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
            Self.delta(event, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventDeltaAxis2) == 0,
            event.flags.isDisjoint(with: Self.modifiers)
        else { return .pass }
        let vertical = Self.delta(event, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventDeltaAxis1)
        guard vertical != 0, let origin = origin(event), let smooth = settings[origin.sender] else { return .pass }
        let steps = max(1, Int(abs(origin.wheelDetents).rounded()))
        return .scroll(ScrollTick(sign: vertical > 0 ? .positive : .negative, steps: steps, settings: smooth))
    }

    private static func delta(_ event: CGEvent, _ fixed: CGEventField, _ lines: CGEventField) -> Double {
        let value = event.getDoubleValueField(fixed)
        return value != 0 ? value : Double(event.getIntegerValueField(lines))
    }
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
