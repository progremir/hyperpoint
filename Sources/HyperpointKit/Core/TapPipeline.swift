import CoreGraphics

struct TapRules: Equatable, Sendable {
    var carriers: [KeyCode: CarrierMeaning]
    var smoothScroll: [SenderID: SmoothScroll]
    var buttons: [ButtonKey: ControlBehavior]
    var listen: TapListen?

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
            if case .carrier(let carrier, let meaning) = route.target { carriers[carrier.keyCode] = meaning }
        }
        self.init(carriers: carriers, smoothScroll: smoothScroll, buttons: buttons)
    }

    /// A listen alone installs the tap.
    var isEmpty: Bool { carriers.isEmpty && smoothScroll.isEmpty && buttons.isEmpty && listen == nil }
}

struct TapListen: Equatable, Sendable {
    var id: ListenID
    /// Every HID event service of the device listened to, pointer and keyboard alike.
    var senders: Set<SenderID>
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
    /// Drop the event and press or release the keys a held button holds.
    case keys(KeyHoldEvent)
    /// Drop the event and tell the engine.
    case heard(ListenID, ListenPress)
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
    private var learn: LearnStage
    private var carriers: CarrierStage
    private var scroll: ScrollStage
    private var buttons: ButtonStage

    init(rules: TapRules, origin: @escaping @Sendable (CGEvent) -> HIDOrigin?) {
        self.origin = origin
        learn = LearnStage(listen: rules.listen, origin: origin)
        carriers = CarrierStage(rules: rules)
        scroll = ScrollStage(settings: rules.smoothScroll, origin: origin)
        buttons = ButtonStage(rules: rules.buttons, origin: origin)
    }

    static var mask: CGEventMask {
        (LearnStage.interests + CarrierStage.interests + ScrollStage.interests + ButtonStage.interests).reduce(0) {
            $0 | (1 << CGEventMask($1.rawValue))
        }
    }

    /// Call `reset` first, so that a button held back from apps is not lost. A press the learn stage took stays taken,
    /// so its release is still kept from apps once the listen is over.
    mutating func replaceRules(_ rules: TapRules) {
        let learned = learn
        self = TapPipeline(rules: rules, origin: origin)
        learn.carry(learned)
    }

    /// A listened press reaches no rule and no carrier.
    mutating func process(_ type: CGEventType, _ event: CGEvent) -> TapVerdict {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
        var verdict = learn.process(type, event)
        if verdict == .pass { verdict = carriers.process(type, event) }
        if verdict == .pass { verdict = scroll.process(type, event) }
        return verdict == .pass ? buttons.process(type, event) : verdict
    }

    /// Whether a held button keeps the pointer where it was pressed.
    var holdsPointer: Bool { buttons.holdsPointer }

    @discardableResult
    mutating func reset() -> ButtonStage.Release {
        carriers.reset()
        return buttons.reset()
    }
}

/// Takes one press from the device listened to and keeps it, its drags, repeats and release from apps and from every
/// later stage. It reads the sender on presses only, and only while it listens. The left button is not in
/// `interests`, so it can never be taken.
struct LearnStage {
    static let interests: [CGEventType] = [
        .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .keyDown, .keyUp,
    ]

    private enum Press: Equatable {
        case button(Int)
        case key(KeyCode)

        var reported: ListenPress {
            switch self {
            case .button(let number): .button(number)
            case .key(let code): .key(code)
            }
        }
    }

    let listen: TapListen?
    let origin: @Sendable (CGEvent) -> HIDOrigin?
    /// The listen already heard, so later presses pass.
    private var heard: ListenID?
    /// The press taken, until its release.
    private var taken: Press?

    init(listen: TapListen?, origin: @escaping @Sendable (CGEvent) -> HIDOrigin?) {
        self.listen = listen
        self.origin = origin
    }

    /// Keeps what the stage it replaces heard and took.
    mutating func carry(_ previous: LearnStage) {
        heard = previous.heard
        taken = previous.taken
    }

    mutating func process(_ type: CGEventType, _ event: CGEvent) -> TapVerdict {
        if let taken, let verdict = follow(taken, type, event) { return verdict }
        guard let listen, listen.id != heard, let press = Self.press(type, event),
            let sender = origin(event)?.sender, listen.senders.contains(sender)
        else { return .pass }
        heard = listen.id
        taken = press
        return .heard(listen.id, press.reported)
    }

    /// The taken press's drags, repeats and release drop. A new press of it means its release was lost, so it is
    /// no longer taken.
    private mutating func follow(_ taken: Press, _ type: CGEventType, _ event: CGEvent) -> TapVerdict? {
        switch (taken, type) {
        case (.button(let number), .rightMouseDragged), (.button(let number), .otherMouseDragged):
            return Self.button(event) == number ? .drop : nil
        case (.button(let number), .rightMouseUp), (.button(let number), .otherMouseUp):
            guard Self.button(event) == number else { return nil }
            self.taken = nil
            return .drop
        case (.button(let number), .rightMouseDown), (.button(let number), .otherMouseDown):
            if Self.button(event) == number { self.taken = nil }
            return nil
        case (.key(let code), .keyDown):
            guard Self.key(event) == code else { return nil }
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return .drop }
            self.taken = nil
            return nil
        case (.key(let code), .keyUp):
            guard Self.key(event) == code else { return nil }
            self.taken = nil
            return .drop
        default:
            return nil
        }
    }

    private static func press(_ type: CGEventType, _ event: CGEvent) -> Press? {
        switch type {
        case .rightMouseDown, .otherMouseDown: .button(button(event))
        case .keyDown where event.getIntegerValueField(.keyboardEventAutorepeat) == 0: .key(key(event))
        default: nil
        }
    }

    private static func button(_ event: CGEvent) -> Int { Int(event.getIntegerValueField(.mouseEventButtonNumber)) }

    private static func key(_ event: CGEvent) -> KeyCode {
        KeyCode(rawValue: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
    }
}

/// Carries out the rules on plain mouse buttons, for the senders that have them. A button whose rule waits on its
/// movement is held back from apps. A release before the distance is its click, and moving past it scrolls. A
/// button that scrolls holds the pointer from its press, so a fast flick cannot move it before the scroll starts. A
/// button that holds keys holds them from its press to its release, and apps see its drags as plain movement. The
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
        /// A button that held keys, whose keys go up now.
        var letsGo: KeyHolder? = nil
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

    var holdsPointer: Bool {
        guard case .gesture(let plan)? = held?.behavior, case .scroll = plan.moves else { return false }
        return true
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
        let holding: KeyHolder? = held.flatMap { if case .hold = $0.behavior { .button($0.button) } else { nil } }
        return Release(press: ended ? nil : held?.press, endsScroll: ended, letsGo: holding)
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
        case .hold(let keys):
            held = Held(button: button, behavior: behavior)
            return .keys(.press(.button(button), keys))
        }
    }

    /// Apps never saw the press of a button that holds keys, so its drags reach them as plain movement.
    private mutating func dragged(_ event: CGEvent) -> TapVerdict {
        guard let held, held.button == Self.button(event) else { return .pass }
        switch held.behavior {
        case .gesture:
            let move = GestureMachine.Input.move(
                dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
            return machine.step(move).map(verdict) ?? .drop
        case .hold:
            event.type = .mouseMoved
            return .pass
        case .native, .press:
            return .drop
        }
    }

    private mutating func released(_ event: CGEvent) -> TapVerdict {
        guard let held, held.button == Self.button(event) else { return .pass }
        self.held = nil
        if case .hold = held.behavior { return .keys(.release(.button(held.button))) }
        guard case .gesture = held.behavior else { return .drop }
        switch machine.step(.release) {
        case .click(nil):
            guard let press = held.press, let release = Self.replayable(event) else { return .pass }
            release.location = press.location
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
        case .press(let action):
            guard type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return .drop }
            return .perform(action)
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
