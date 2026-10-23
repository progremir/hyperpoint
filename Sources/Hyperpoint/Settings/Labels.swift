import AppKit
import HyperpointKit

/// Plain-word names for what the config file stores as identifiers.
enum Labels {
    /// HID++ control ids are shared across Logitech devices, so these names hold beyond the MX Master 3.
    static let controlNames: [UInt16: String] = [
        0x50: "Left button", 0x51: "Right button", 0x52: "Middle button", 0x53: "Back button",
        0x56: "Forward button", 0xC3: "Gesture button", 0xC4: "Top button",
    ]

    static func control(_ control: Control) -> String {
        switch control {
        case .hidpp(let cid): controlNames[cid.rawValue] ?? "Button 0x\(String(cid.rawValue, radix: 16, uppercase: true))"
        case .thumbWheel: "Thumb wheel"
        case .key(let usage): "Sends \(key(usage.name ?? ""))"
        case .button(let number): "Button \(number)"
        }
    }

    static func trigger(_ trigger: Trigger) -> String {
        switch trigger {
        case .click: "Click"
        case .hold: "Hold"
        case .holdMove(let direction): "Hold, move \(direction.rawValue.lowercased())"
        case .scroll: "Scroll"
        }
    }

    static func action(_ action: Action) -> String {
        switch action {
        case .system(.missionControl): "Mission Control"
        case .system(.appExpose): "App Exposé"
        case .system(.spaceLeft): "Space to the left"
        case .system(.spaceRight): "Space to the right"
        case .shortcut(let chord): "Shortcut \(Self.chord(chord))"
        case .modifier(let modifier): Self.modifier(modifier)
        case .reverse: "Horizontal scroll, reversed"
        }
    }

    static func modifier(_ modifier: HeldModifier) -> String {
        switch modifier {
        case .leftControl: "Left Control"
        case .leftShift: "Left Shift"
        case .leftOption: "Left Option"
        case .leftCommand: "Left Command"
        case .rightControl: "Right Control"
        case .rightShift: "Right Shift"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        }
    }

    /// In the order macOS menus show them, as in ⌃⌥⇧⌘S.
    static func chord(_ chord: Chord) -> String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let modifiers = symbols.filter { chord.modifiers.contains($0.0) }.map(\.1).joined()
        return modifiers + keySymbol(chord.key.name ?? "")
    }

    private static let keySymbols: [String: String] = [
        "return": "↩", "escape": "⎋", "delete": "⌫", "forwardDelete": "⌦", "tab": "⇥", "space": "Space",
        "capsLock": "⇪", "left": "←", "right": "→", "up": "↑", "down": "↓", "home": "↖", "end": "↘",
        "pageUp": "⇞", "pageDown": "⇟", "minus": "-", "equal": "=", "leftBracket": "[", "rightBracket": "]",
        "backslash": "\\", "semicolon": ";", "quote": "'", "grave": "`", "comma": ",", "period": ".", "slash": "/",
    ]

    static func keySymbol(_ name: String) -> String { keySymbols[name] ?? name.uppercased() }

    private static let keyWords: [String: String] = [
        "left": "Left Arrow", "right": "Right Arrow", "up": "Up Arrow", "down": "Down Arrow", "grave": "Backtick",
        "equal": "Equals",
    ]

    /// "capsLock" reads "Caps Lock", "f5" reads "F5".
    static func key(_ name: String) -> String {
        if let word = keyWords[name] { return word }
        if name.count <= 3, name.first?.isLetter == true, name.dropFirst().allSatisfy(\.isNumber) { return name.uppercased() }
        var words: [String] = []
        for character in name {
            if character.isUppercase || words.isEmpty {
                words.append(String(character).uppercased())
            } else {
                words[words.count - 1].append(character)
            }
        }
        return words.joined(separator: " ")
    }

    /// The chord a key press records, or nil for a key the config file cannot name.
    static func recordedChord(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Chord? {
        guard let key = KeyCode(virtualKeyCode: keyCode) else { return nil }
        let pairs: [(NSEvent.ModifierFlags, Modifiers)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        let modifiers = pairs.reduce(into: Modifiers()) { result, pair in
            if flags.contains(pair.0) { result.insert(pair.1) }
        }
        return Chord(key: key, modifiers: modifiers)
    }
}
