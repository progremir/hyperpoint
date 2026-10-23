import CoreGraphics

struct TapRules: Equatable, Sendable {
    var carriers: [KeyCode: CarrierMeaning]
    var smoothScroll: [SenderID: SmoothScroll]
    var buttons: [ButtonKey: ControlBehavior]

    static let empty = TapRules(carriers: [:], smoothScroll: [:])

    init(
        carriers: [KeyCode: CarrierMeaning], smoothScroll: [SenderID: SmoothScroll],
        buttons: [ButtonKey: ControlBehavior] = [:]
    ) {
        self.carriers = carriers
        self.smoothScroll = smoothScroll
        self.buttons = buttons
    }

    init(routes: [KeyRoute], smoothScroll: [SenderID: SmoothScroll], buttons: [ButtonKey: ControlBehavior] = [:]) {
        var carriers: [KeyCode: CarrierMeaning] = [:]
        for route in routes {
            switch route.target {
            case .carrier(let carrier, let meaning): carriers[carrier.keyCode] = meaning
            }
        }
        self.init(carriers: carriers, smoothScroll: smoothScroll, buttons: buttons)
    }

    var isEmpty: Bool { carriers.isEmpty && smoothScroll.isEmpty && buttons.isEmpty }
}

/// A plain button on one device, by its HID event service and its CGEvent button number.
struct ButtonKey: Hashable, Sendable {
    var sender: SenderID
    var button: Int
}

enum TapVerdict: Equatable {
    case pass
    case drop
    /// Drop the event and feed the tick to the scroll animator.
    case scroll(ScrollTick)
    /// Drop the event and post these two instead, in order. They carry the synthetic marker already.
    case replay(CGEvent, CGEvent)
    /// Drop the event and perform the action.
    case perform(Action)
    /// Drop the event and feed the hold-to-scroll animator.
    case holdScroll(HoldScrollEvent)
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
    private var buttons: ButtonStage

    init(rules: TapRules, origin: @escaping @Sendable (CGEvent) -> HIDOrigin?) {
        self.origin = origin
        carriers = CarrierStage(rules: rules)
        scroll = ScrollStage(settings: rules.smoothScroll, origin: origin)
        buttons = ButtonStage(rules: rules.buttons, origin: origin)
    }

    static var mask: CGEventMask {
        (CarrierStage.interests + ScrollStage.interests + ButtonStage.interests).reduce(0) {
            $0 | (1 << CGEventMask($1.rawValue))
        }
    }

    /// Call `reset` first, so that a button held back from apps is not lost.
    mutating func replaceRulesAndForgetHeldKeys(_ rules: TapRules) { self = TapPipeline(rules: rules, origin: origin) }

    mutating func process(_ type: CGEventType, _ event: CGEvent) -> TapVerdict {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
        var verdict = carriers.process(type, event)
        if verdict == .pass { verdict = scroll.process(type, event) }
        return verdict == .pass ? buttons.process(type, event) : verdict
    }

    @discardableResult
    mutating func reset() -> ButtonStage.Release {
        carriers.reset()
        return buttons.reset()
    }
}

/// Carries out the rules on plain mouse buttons, for the senders that have them. A button whose rule waits on its
/// movement is held back from apps. A release before the distance is its click, and moving past it scrolls. The
/// left button never has rules, so it is not watched.
struct ButtonStage {
    static let interests: [CGEventType] = [
        .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    ]

    /// What the host must do for a button the stage forgets while it is down.
    struct Release: Equatable {
        /// A press held back from apps, marked, which goes to them now so that the button's own release pairs with it.
        var press: CGEvent?
        var endsScroll: Bool
    }

    /// The button Hyperpoint has taken from apps, until it is released. One at a time.
    private struct Held {
        var button: Int
        var behavior: ControlBehavior
        /// The press, for a click with no rule of its own, which replays it.
        var press: CGEvent?
    }

    let rules: [ButtonKey: ControlBehavior]
    let origin: @Sendable (CGEvent) -> HIDOrigin?
    private var held: Held?
    private var machine = GestureMachine()

    init(rules: [ButtonKey: ControlBehavior], origin: @escaping @Sendable (CGEvent) -> HIDOrigin?) {
        self.rules = rules
        self.origin = origin
    }

    mutating func process(_ type: CGEventType, _ event: CGEvent) -> TapVerdict {
        guard !rules.isEmpty else { return .pass }
        switch type {
        case .rightMouseDown, .otherMouseDown: return pressed(event)
        case .rightMouseDragged, .otherMouseDragged: return dragged(event)
        case .rightMouseUp, .otherMouseUp: return released(event)
        default: return .pass
        }
    }

    mutating func reset() -> Release {
        defer {
            held = nil
            machine = GestureMachine()
        }
        let ended = machine.step(.cancel) == .scroll(.ended)
        return Release(press: ended ? nil : held?.press, endsScroll: ended)
    }

    private static func button(_ event: CGEvent) -> Int { Int(event.getIntegerValueField(.mouseEventButtonNumber)) }

    /// A copy to post later, marked so that no stage takes it again.
    private static func replayable(_ event: CGEvent) -> CGEvent? {
        let copy = event.copy()
        copy?.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker)
        return copy
    }

    /// The sender is looked up on presses only, so drags cost no IOHIDEvent copy.
    private mutating func pressed(_ event: CGEvent) -> TapVerdict {
        let button = Self.button(event)
        guard held == nil || held?.button == button, let sender = origin(event)?.sender,
            let behavior = rules[ButtonKey(sender: sender, button: button)]
        else { return .pass }
        switch behavior {
        case .native:
            return .pass
        case .press(let action):
            held = Held(button: button, behavior: behavior)
            return .perform(action)
        case .gesture(let plan):
            let ended = machine.step(.press(plan))
            held = Held(button: button, behavior: behavior, press: Self.replayable(event))
            return ended.map(verdict) ?? .drop
        }
    }

    private mutating func dragged(_ event: CGEvent) -> TapVerdict {
        guard let held, held.button == Self.button(event) else { return .pass }
        guard case .gesture = held.behavior else { return .drop }
        let move = GestureMachine.Input.move(
            dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
        return machine.step(move).map(verdict) ?? .drop
    }

    private mutating func released(_ event: CGEvent) -> TapVerdict {
        guard let held, held.button == Self.button(event) else { return .pass }
        self.held = nil
        guard case .gesture = held.behavior else { return .drop }
        switch machine.step(.release) {
        case .click(nil):
            guard let press = held.press, let release = Self.replayable(event) else { return .pass }
            return .replay(press, release)
        case let output?:
            return verdict(output)
        case nil:
            return .drop
        }
    }

    private func verdict(_ output: GestureMachine.Output) -> TapVerdict {
        switch output {
        case .click(let action?), .perform(let action): .perform(action)
        case .click(nil): .drop
        case .scroll(let event): .holdScroll(event)
        }
    }
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
