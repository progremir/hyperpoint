import CoreGraphics

/// The keys a held button holds down from its press to its release: modifier keys in the order they go down, then at
/// most one other key.
struct KeyHold: Hashable, Sendable {
    var modifiers: [HeldModifier]
    var key: KeyCode?

    init(modifiers: [HeldModifier], key: KeyCode? = nil) {
        self.modifiers = modifiers
        self.key = key
    }

    /// A shortcut's modifiers are the left keys, in the order macOS menus show them.
    init?(_ action: Action) {
        switch action {
        case .modifier(let modifier):
            (modifiers, key) = ([modifier], nil)
        case .shortcut(let chord):
            let sides: [(Modifiers, HeldModifier)] = [
                (.control, .leftControl), (.option, .leftOption), (.shift, .leftShift), (.command, .leftCommand),
            ]
            (modifiers, key) = (sides.filter { chord.modifiers.contains($0.0) }.map(\.1), chord.key)
        case .system, .reverse, .scroll:
            return nil
        }
    }
}

/// What holds keys down. Each holds one set at a time.
enum KeyHolder: Hashable, Sendable {
    /// A plain button, seen in the tap.
    case button(Int)
    /// An HID++ control of one device.
    case control(DeviceInstanceID, CID)
}

enum KeyHoldEvent: Equatable, Sendable {
    case press(KeyHolder, KeyHold)
    case release(KeyHolder)
}

/// The keys every held button holds, and the key events that press and release them. Hyperpoint posts the events at
/// the HID tap, marked, so apps see the keys go down and up as a keyboard's would. A key two holds share goes up when
/// the last of them lets go.
///
/// A posted modifier does not stay in the system's modifier state: the next hardware event, such as the hand moving
/// the mouse, puts the real state back (measured: 20 ms after the press). So while modifiers are held, every other
/// event gets them added on its way through the HID tap, as hyper's carrier does for keys.
struct HeldKeys {
    private var holds: [KeyHolder: KeyHold] = [:]

    var isEmpty: Bool { holds.isEmpty }

    /// What every other event carries while modifiers are held, with the flags that tell left from right.
    var flags: CGEventFlags { Self.flags(of: held) }

    /// The events a click, a drag, a move, a scroll or a key can come in, from any device.
    static let overlayInterests: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved, .scrollWheel, .keyDown, .keyUp, .flagsChanged,
    ]

    /// Adds the held modifiers to an event that is not Hyperpoint's own. Hyperpoint's events carry exactly the flags
    /// they mean, such as the modifier changes that press and release the held keys.
    func overlay(_ event: CGEvent) {
        guard !flags.isEmpty, event.getIntegerValueField(.eventSourceUserData) != TapPipeline.syntheticMarker else { return }
        event.flags.formUnion(flags)
    }

    /// `flags` is the system's modifier state now. A holder that already holds keys lost its release, so it lets go
    /// first.
    mutating func receive(_ event: KeyHoldEvent, flags: CGEventFlags) -> [CGEvent] {
        let base = Self.unheld(flags, by: held)
        switch event {
        case .press(let holder, let hold):
            var events = release(holder, base: base)
            var held = self.held
            for modifier in hold.modifiers where held.insert(modifier).inserted {
                events.append(Self.event(modifier.keyCode, .flagsChanged, flags: base.union(Self.flags(of: held))))
            }
            if let key = hold.key, !holds.values.contains(where: { $0.key == key }) {
                events.append(Self.event(key, .keyDown, flags: base.union(Self.flags(of: held))))
            }
            holds[holder] = hold
            return events
        case .release(let holder):
            return release(holder, base: base)
        }
    }

    /// Lets go of every hold, for a tap that stops or lost events.
    mutating func releaseAll(flags: CGEventFlags) -> [CGEvent] {
        let base = Self.unheld(flags, by: held)
        return holds.keys.sorted { "\($0)" < "\($1)" }.flatMap { release($0, base: base) }
    }

    /// Every modifier some hold holds.
    private var held: Set<HeldModifier> { Set(holds.values.flatMap(\.modifiers)) }

    /// `base` is the modifier state without anything a hold holds.
    private mutating func release(_ holder: KeyHolder, base: CGEventFlags) -> [CGEvent] {
        guard let hold = holds.removeValue(forKey: holder) else { return [] }
        let others = held
        var held = others.union(hold.modifiers)
        var events: [CGEvent] = []
        if let key = hold.key, !holds.values.contains(where: { $0.key == key }) {
            events.append(Self.event(key, .keyUp, flags: base.union(Self.flags(of: held))))
        }
        for modifier in hold.modifiers.reversed() where !others.contains(modifier) {
            held.remove(modifier)
            events.append(Self.event(modifier.keyCode, .flagsChanged, flags: base.union(Self.flags(of: held))))
        }
        return events
    }

    /// Each event replaces the system's modifier state with its flags, so it keeps Caps Lock and the modifiers held
    /// elsewhere, such as on a keyboard. Fn is left out, because F-key events carry it without it being held.
    private static func unheld(_ flags: CGEventFlags, by held: Set<HeldModifier>) -> CGEventFlags {
        flags.intersection(modifierState).subtracting(Self.flags(of: held))
    }

    private static let modifierState = CGEventFlags(rawValue: CGEventFlags.maskAlphaShift.rawValue | Self.generic | 0x207F)
    private static let generic = CGEventFlags([.maskShift, .maskControl, .maskAlternate, .maskCommand]).rawValue

    /// A left and a right modifier of one kind share its generic flag, so it stays while either is down.
    private static func flags(of held: Set<HeldModifier>) -> CGEventFlags {
        held.reduce([]) { $0.union($1.flags) }
    }

    private static func event(_ key: KeyCode, _ type: CGEventType, flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key.rawValue), keyDown: type != .keyUp)!
        event.type = type
        event.flags = flags.union(.maskNonCoalesced)
        event.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker)
        return event
    }
}

extension HeldModifier {
    var keyCode: KeyCode { KeyCode(rawValue: virtualKeyCode) }

    /// The generic flag and the device flag, so a left and a right modifier of one kind share the generic one.
    var flags: CGEventFlags { CGEventFlags(rawValue: generic.cgFlags.rawValue | deviceFlag) }
}
