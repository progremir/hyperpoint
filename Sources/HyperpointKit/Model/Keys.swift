/// A key on the HID keyboard usage page (0x07), as the HID layer and `hidutil` see it.
public struct HIDUsage: Hashable, Sendable {
    public let rawValue: UInt16
    init(rawValue: UInt16) { self.rawValue = rawValue }

    /// "escape", "capsLock", "s". Case-insensitive.
    public init?(name: String) {
        guard let key = KeyTable.byName[name.lowercased()] else { return nil }
        self = key.usage
    }

    public var name: String? { KeyTable.byUsage[self]?.name }

    /// Every key the config file can name, in keyboard order.
    public static let named: [HIDUsage] = KeyTable.keys.map(\.usage)
}

/// A virtual key code (`kVK_*`), as CGEvents carry it.
public struct KeyCode: Hashable, Sendable {
    public let rawValue: UInt16
    init(rawValue: UInt16) { self.rawValue = rawValue }

    public init?(name: String) {
        guard let key = KeyTable.byName[name.lowercased()] else { return nil }
        self = key.keyCode
    }

    /// Nil for a key the config file cannot name.
    public init?(virtualKeyCode: UInt16) {
        guard let key = KeyTable.byKeyCode[KeyCode(rawValue: virtualKeyCode)] else { return nil }
        self = key.keyCode
    }

    public var name: String? { KeyTable.byKeyCode[self]?.name }
}

public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)

    public static let hyper: Modifiers = [.control, .option, .shift, .command]
}

/// A physical modifier key that another key can become at the HID layer.
public enum HeldModifier: String, CaseIterable, Codable, Sendable {
    case leftControl, leftShift, leftOption, leftCommand
    case rightControl, rightShift, rightOption, rightCommand

    /// The keyboard page lists the eight modifiers from 0xE0 in this order.
    var usage: HIDUsage { HIDUsage(rawValue: 0xE0 + UInt16(Self.allCases.firstIndex(of: self)!)) }
}

enum KeyTable {
    struct Key {
        let name: String
        let usage: HIDUsage
        let keyCode: KeyCode
    }

    static let keys: [Key] = [
        ("a", 0x04, 0), ("b", 0x05, 11), ("c", 0x06, 8), ("d", 0x07, 2), ("e", 0x08, 14), ("f", 0x09, 3),
        ("g", 0x0A, 5), ("h", 0x0B, 4), ("i", 0x0C, 34), ("j", 0x0D, 38), ("k", 0x0E, 40), ("l", 0x0F, 37),
        ("m", 0x10, 46), ("n", 0x11, 45), ("o", 0x12, 31), ("p", 0x13, 35), ("q", 0x14, 12), ("r", 0x15, 15),
        ("s", 0x16, 1), ("t", 0x17, 17), ("u", 0x18, 32), ("v", 0x19, 9), ("w", 0x1A, 13), ("x", 0x1B, 7),
        ("y", 0x1C, 16), ("z", 0x1D, 6),
        ("1", 0x1E, 18), ("2", 0x1F, 19), ("3", 0x20, 20), ("4", 0x21, 21), ("5", 0x22, 23), ("6", 0x23, 22),
        ("7", 0x24, 26), ("8", 0x25, 28), ("9", 0x26, 25), ("0", 0x27, 29),
        ("return", 0x28, 36), ("escape", 0x29, 53), ("delete", 0x2A, 51), ("tab", 0x2B, 48), ("space", 0x2C, 49),
        ("minus", 0x2D, 27), ("equal", 0x2E, 24), ("leftBracket", 0x2F, 33), ("rightBracket", 0x30, 30),
        ("backslash", 0x31, 42), ("semicolon", 0x33, 41), ("quote", 0x34, 39), ("grave", 0x35, 50),
        ("comma", 0x36, 43), ("period", 0x37, 47), ("slash", 0x38, 44), ("capsLock", 0x39, 57),
        ("f1", 0x3A, 122), ("f2", 0x3B, 120), ("f3", 0x3C, 99), ("f4", 0x3D, 118), ("f5", 0x3E, 96),
        ("f6", 0x3F, 97), ("f7", 0x40, 98), ("f8", 0x41, 100), ("f9", 0x42, 101), ("f10", 0x43, 109),
        ("f11", 0x44, 103), ("f12", 0x45, 111),
        ("home", 0x4A, 115), ("pageUp", 0x4B, 116), ("forwardDelete", 0x4C, 117), ("end", 0x4D, 119),
        ("pageDown", 0x4E, 121), ("right", 0x4F, 124), ("left", 0x50, 123), ("down", 0x51, 125), ("up", 0x52, 126),
    ].map { Key(name: $0.0, usage: HIDUsage(rawValue: $0.1), keyCode: KeyCode(rawValue: $0.2)) }

    static let byName = Dictionary(uniqueKeysWithValues: keys.map { ($0.name.lowercased(), $0) })
    static let byUsage = Dictionary(uniqueKeysWithValues: keys.map { ($0.usage, $0) })
    static let byKeyCode = Dictionary(uniqueKeysWithValues: keys.map { ($0.keyCode, $0) })
}
