import AppKit
import HyperpointKit

/// What the shortcut recorder has heard. A key down records it with the modifiers held, and a modifier pressed and let
/// go with nothing else records that modifier alone, so a shortcut can still start with one.
struct ShortcutRecording: Equatable {
    enum Outcome: Equatable {
        case waiting
        case recorded(Action)
        case cancelled
        /// A key the config file cannot name.
        case unnameable
    }

    private(set) var held = Modifiers()
    /// The one modifier down since none was, until another key joins it.
    private(set) var lone: HeldModifier?

    /// A modifier change carries the key that changed, and its side's flag says whether that key is now down. Hyper's
    /// change carries no side's flag, so it never counts as a modifier alone.
    mutating func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Outcome {
        let before = held
        held = Labels.modifiers(flags)
        guard let key = HeldModifier(virtualKeyCode: keyCode) else { return .waiting }
        if UInt64(flags.rawValue) & key.deviceFlag != 0 {
            lone = before.isEmpty ? key : nil
            return .waiting
        }
        guard held.isEmpty else { return .waiting }
        defer { lone = nil }
        return lone == key ? .recorded(.modifier(key)) : .waiting
    }

    mutating func keyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Outcome {
        lone = nil
        if keyCode == 53, Labels.modifiers(flags).isEmpty { return .cancelled }
        guard let chord = Labels.recordedChord(keyCode: keyCode, flags: flags) else { return .unnameable }
        return .recorded(.shortcut(chord))
    }

    var hint: String {
        if let lone { return "Let go to use \(Labels.modifier(lone))" }
        return held.isEmpty ? "Type a shortcut, or one modifier" : "Now press a key"
    }
}
