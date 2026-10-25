import AppKit
import HyperpointKit
import Testing

@testable import Hyperpoint

@Suite struct LabelsTests {
    func chord(_ text: String) throws -> Chord {
        try JSONDecoder().decode(Chord.self, from: Data("\"\(text)\"".utf8))
    }

    @Test func chordsReadAsInMacOSMenus() throws {
        #expect(Labels.chord(try chord("shift+cmd+4")) == "⇧⌘4")
        #expect(Labels.chord(try chord("opt+shift+s")) == "⌥⇧S")
        #expect(Labels.chord(try chord("cmd+shift+opt+ctrl+r")) == "⌃⌥⇧⌘R")
        #expect(Labels.chord(try chord("ctrl+left")) == "⌃←")
    }

    @Test func rulesReadInPlainWords() throws {
        #expect(Labels.control(gestureButton) == "Gesture button")
        #expect(Labels.control(topButton) == "Top button")
        #expect(Labels.control(.thumbWheel) == "Thumb wheel")
        #expect(Labels.control(.key(HIDUsage(name: "escape")!)) == "Sends Escape")
        #expect(Labels.trigger(.holdMove(.down)) == "Hold, move down")
        #expect(Labels.action(.system(.spaceLeft)) == "Space to the left")
        #expect(Labels.action(.modifier(.rightOption)) == "Right Option")
        #expect(Labels.action(.shortcut(try chord("shift+cmd+4"))) == "Shortcut ⇧⌘4")
        #expect(Labels.action(.reverse) == "Horizontal scroll, reversed")
        #expect(Labels.control(.button(1)) == "Right button")
        #expect(Labels.control(.button(7)) == "Button 7")
        #expect(Labels.trigger(.holdMove(nil)) == "Hold and move")
        #expect(Labels.action(.scroll) == "Scroll")
    }

    @Test func aScrollRuleSaysWhatAQuickPressStillDoes() {
        #expect(
            Labels.holdToScroll(control: topButton, hasClickRule: true)
                == "Hold the button and move the mouse to scroll. A quick press still does the click rule.")
        #expect(Labels.holdToScroll(control: .button(1), hasClickRule: false).hasSuffix("A quick press still clicks as usual."))
        #expect(Labels.holdToScroll(control: topButton, hasClickRule: false).hasSuffix("A quick press does nothing until you add a click rule."))
    }

    @Test func everyKeyHasAPlainName() {
        #expect(Labels.key("capsLock") == "Caps Lock")
        #expect(Labels.key("f5") == "F5")
        #expect(Labels.key("a") == "A")
        #expect(Labels.key("left") == "Left Arrow")
        for usage in HIDUsage.named {
            let label = Labels.key(usage.name!)
            #expect(label.split(separator: " ").allSatisfy { $0.first?.isLowercase != true }, "\(label)")
        }
    }

    @Test func aKeyPressRecordsItsChord() throws {
        #expect(Labels.recordedChord(keyCode: 21, flags: [.shift, .command, .capsLock]) == (try chord("shift+cmd+4")))
        #expect(Labels.recordedChord(keyCode: 105, flags: [.command]) == nil, "F13 has no name in the file")
    }

    @Test func aCopyIsNamedAfterTheProfileItCopies() {
        let renamed = SettingsEdit.rename(mx, "My MX").applied(to: .example)
        #expect(Labels.setUpItem(.copy(of: mx), in: renamed) == "Same as My MX")
    }
}
