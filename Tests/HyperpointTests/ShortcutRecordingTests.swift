import AppKit
import HyperpointKit
import Testing

@testable import Hyperpoint

/// Flags as a keyboard's modifier change carries them: the generic flag and the side's.
private func flags(_ held: HeldModifier...) -> NSEvent.ModifierFlags {
    held.reduce(into: NSEvent.ModifierFlags()) { result, modifier in
        let generic: NSEvent.ModifierFlags =
            switch modifier.generic {
            case .control: .control
            case .option: .option
            case .shift: .shift
            default: .command
            }
        result.formUnion(NSEvent.ModifierFlags(rawValue: generic.rawValue | UInt(modifier.deviceFlag)))
    }
}

@Suite struct ShortcutRecordingTests {
    let s: UInt16 = 1

    @Test func aModifierPressedAloneIsRecordedOnItsRelease() {
        var recording = ShortcutRecording()
        #expect(recording.flagsChanged(keyCode: 61, flags: flags(.rightOption)) == .waiting, "a shortcut may follow")
        #expect(recording.hint == "Let go to use Right Option")
        #expect(recording.flagsChanged(keyCode: 61, flags: []) == .recorded(.modifier(.rightOption)))
    }

    @Test func aShortcutStartingWithThatModifierStillRecords() throws {
        var recording = ShortcutRecording()
        _ = recording.flagsChanged(keyCode: 61, flags: flags(.rightOption))
        #expect(recording.keyDown(keyCode: s, flags: flags(.rightOption)) == .recorded(.shortcut(Chord(key: KeyCode(name: "s")!, modifiers: .option))))
        #expect(recording.flagsChanged(keyCode: 61, flags: []) == .waiting, "letting go after the key records nothing more")
    }

    @Test func twoModifiersAloneRecordNothing() {
        var recording = ShortcutRecording()
        _ = recording.flagsChanged(keyCode: 55, flags: flags(.leftCommand))
        _ = recording.flagsChanged(keyCode: 56, flags: flags(.leftCommand, .leftShift))
        #expect(recording.hint == "Now press a key")
        #expect(recording.flagsChanged(keyCode: 56, flags: flags(.leftCommand)) == .waiting)
        #expect(recording.flagsChanged(keyCode: 55, flags: []) == .waiting, "Command was not alone")
        #expect(recording.hint == "Type a shortcut, or one modifier")
    }

    @Test func hyperIsNeverAModifierAlone() {
        var recording = ShortcutRecording()
        let hyper: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        #expect(recording.flagsChanged(keyCode: 55, flags: hyper) == .waiting, "hyper's change carries no side")
        #expect(
            recording.keyDown(keyCode: 15, flags: hyper)
                == .recorded(.shortcut(Chord(key: KeyCode(name: "r")!, modifiers: .hyper))))
        #expect(recording.flagsChanged(keyCode: 55, flags: []) == .waiting)
    }

    @Test func escapeCancelsAndAnUnnamedKeyIsAProblem() {
        var recording = ShortcutRecording()
        #expect(recording.keyDown(keyCode: 53, flags: []) == .cancelled)
        #expect(recording.keyDown(keyCode: 105, flags: []) == .unnameable, "F13 has no name in the file")
        #expect(recording.keyDown(keyCode: 53, flags: flags(.leftShift)) == .recorded(.shortcut(Chord(key: KeyCode(name: "escape")!, modifiers: .shift))))
    }
}
