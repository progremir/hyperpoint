import AppKit
import HyperpointKit

/// Plain-word names for what the config file stores as identifiers.
enum Labels {
    /// HID++ control ids are shared across Logitech devices, so these names hold beyond the MX Master 3.
    static let controlNames: [UInt16: String] = [
        0x50: "Left button", 0x51: "Right button", 0x52: "Middle button", 0x53: "Back button",
        0x56: "Forward button", 0xC3: "Gesture button", 0xC4: "Top button",
    ]

    /// Plain buttons by their CGEvent number.
    static let buttonNames: [Int: String] = [1: "Right button", 2: "Middle button", 3: "Back button", 4: "Forward button"]

    static func control(_ control: Control) -> String {
        switch control {
        case .hidpp(let cid): controlNames[cid.rawValue] ?? "Button 0x\(String(cid.rawValue, radix: 16, uppercase: true))"
        case .thumbWheel: "Thumb wheel"
        case .key(let usage): "Sends \(key(usage.name ?? ""))"
        case .button(let number): buttonNames[number] ?? "Button \(number)"
        }
    }

    /// A device by its ids, for one Hyperpoint has no name for.
    static func match(_ match: DeviceMatch) -> String {
        switch match {
        case .builtIn: "Built-in keyboard"
        case .device(let vendor, let product): "Vendor \(hex(vendor.rawValue)), product \(hex(product.rawValue))"
        }
    }

    private static func hex(_ value: UInt16) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }

    static func setUp(_ source: ProfileSource) -> String {
        switch source {
        case .preset(let preset): Self.preset(preset).button
        case .copy, .blank: "Set Up"
        }
    }

    static func setUpItem(_ source: ProfileSource, in config: Config) -> String {
        switch source {
        case .preset(let preset): Self.preset(preset).item
        case .copy(let other): "Same as \(name(other, in: config))"
        case .blank: "Nothing yet"
        }
    }

    static func setUpHelp(_ source: ProfileSource, in config: Config) -> String {
        switch source {
        case .preset(let preset): Self.preset(preset).help
        case .copy(let other): "Starts with the same settings as \(name(other, in: config))."
        case .blank: "Adds the mouse with no rules, so you can add them on the Buttons tab."
        }
    }

    private static func preset(_ preset: DevicePreset) -> (button: String, item: String, help: String) {
        switch preset {
        case .mxMaster3:
            (
                "Set Up as MX Master 3", "MX Master 3 preset",
                "Gesture and top buttons, reversed thumb wheel, smooth scrolling, and hold the right button to scroll."
            )
        case .mouse24G:
            (
                "Set Up as 2.4G Mouse", "2.4G mouse preset",
                "Lists it with the mice. Escape becomes Right Option while held, and Return sends ⌥⇧S."
            )
        case .keyboard: ("Set Up with Hyper Key", "Hyper key", "Turns on the hyper key for this keyboard.")
        }
    }

    private static func name(_ match: DeviceMatch, in config: Config) -> String {
        config.devices.first { $0.match == match }?.name ?? Self.match(match)
    }

    static func trigger(_ trigger: Trigger) -> String {
        switch trigger {
        case .click: "Click"
        case .hold: "Hold"
        case .holdMove(let direction?): "Hold, move \(direction.rawValue.lowercased())"
        case .holdMove(nil): "Hold and move"
        case .scroll: "Scroll"
        }
    }

    /// Under Add Rule, after a listen that heard no press.
    static func listenEnded(_ why: ListenEnd, device: String) -> String {
        switch why {
        case .timedOut: "No press heard in \(Int(ListenStatus.timeout)) seconds. Add Rule to try again."
        case .disconnected: "\(device) disconnected, so Hyperpoint stopped listening."
        case .paused: "Hyperpoint is paused, so it stopped listening."
        case .slept: "The Mac went to sleep, so Hyperpoint stopped listening."
        case .needsAccessibility: "Hyperpoint needs Accessibility to hear this mouse's buttons."
        }
    }

    /// Under Add Rule, after a press or a pick that added nothing. A rule that was added is highlighted instead.
    static func learned(_ note: LearnNote) -> String? {
        switch note {
        case .added: nil
        case .full(_, .thumbWheel): "Thumb wheel already has a rule for every way to turn it. Change it here."
        case .full(_, let full): "\(control(full)) already has a rule for every way to press it. Change one of these."
        case .unnamed: "Hyperpoint cannot make a rule for that key."
        }
    }

    /// Under a hold rule, what stays down while the button or key is held.
    static func heldKeys(_ action: Action) -> String? {
        switch action {
        case .modifier(let held):
            "\(modifier(held)) stays down while you hold it, so a click meanwhile is a \(modifierSymbol(held))-click."
        case .shortcut(let chord): "\(Self.chord(chord)) stays down while you hold it, and goes up when you let go."
        case .system, .reverse, .scroll: nil
        }
    }

    private static func modifierSymbol(_ held: HeldModifier) -> String {
        switch held {
        case .leftControl, .rightControl: "⌃"
        case .leftOption, .rightOption: "⌥"
        case .leftShift, .rightShift: "⇧"
        case .leftCommand, .rightCommand: "⌘"
        }
    }

    /// Under a hold-and-move scroll rule, what the button still does on a quick press.
    static func holdToScroll(control: Control, hasClickRule: Bool) -> String {
        let press =
            if hasClickRule {
                "A quick press still does the click rule."
            } else if case .button = control {
                "A quick press still clicks as usual."
            } else {
                "A quick press does nothing until you add a click rule."
            }
        return "Hold the button and move the mouse to scroll. \(press)"
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
        case .scroll: "Scroll"
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
        modifierSymbols(chord.modifiers).joined() + keySymbol(chord.key.name ?? "")
    }

    /// One symbol per modifier, in the order macOS menus show them.
    static func modifierSymbols(_ modifiers: Modifiers) -> [String] {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1)
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
        return Chord(key: key, modifiers: modifiers(flags))
    }

    /// The modifiers a shortcut can use, out of an event's flags.
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Modifiers {
        let pairs: [(NSEvent.ModifierFlags, Modifiers)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        return pairs.reduce(into: Modifiers()) { result, pair in
            if flags.contains(pair.0) { result.insert(pair.1) }
        }
    }
}
