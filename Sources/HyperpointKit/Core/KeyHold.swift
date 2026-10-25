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
/// the HID tap, marked, so the system's modifier state holds the keys as if a keyboard did, and a click or a key
/// meanwhile carries them. A key two holds share goes up when the last of them lets go.
struct HeldKeys {
    private var holds: [KeyHolder: KeyHold] = [:]

    var isEmpty: Bool { holds.isEmpty }

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
    /// Its virtual key code, as a keyboard's modifier change carries it.
    var keyCode: KeyCode {
        switch self {
        case .leftControl: KeyCode(rawValue: 59)
        case .leftShift: KeyCode(rawValue: 56)
        case .leftOption: KeyCode(rawValue: 58)
        case .leftCommand: KeyCode(rawValue: 55)
        case .rightControl: KeyCode(rawValue: 62)
        case .rightShift: KeyCode(rawValue: 60)
        case .rightOption: KeyCode(rawValue: 61)
        case .rightCommand: KeyCode(rawValue: 54)
        }
    }

    /// The generic flag and the device flag that tells left from right (`NX_DEVICE*KEYMASK`).
    var flags: CGEventFlags {
        switch self {
        case .leftControl: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x0001)
        case .leftShift: CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x0002)
        case .rightShift: CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x0004)
        case .leftCommand: CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0008)
        case .rightCommand: CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0010)
        case .leftOption: CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0020)
        case .rightOption: CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0040)
        case .rightControl: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x2000)
        }
    }
}
