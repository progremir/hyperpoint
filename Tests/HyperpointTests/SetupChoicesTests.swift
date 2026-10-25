import HyperpointKit
import Testing

@testable import Hyperpoint

@Suite struct SetupChoicesTests {
    func new(_ match: DeviceMatch, _ name: String, _ kind: DeviceKind) -> SettingsDevice {
        SettingsDevice(match: match, name: name, kind: kind, profile: nil, status: nil)
    }

    @Test func anMXIsSetUpFromItsPreset() {
        let config = SettingsEdit.forget(mx).applied(to: .example)
        let choices = SetupChoices(for: new(mx, "MX Master 3", .mouse), in: config)
        #expect(choices.suggested == .preset(.mxMaster3))
        #expect(choices.others == [.blank, .copy(of: mouse24G)])
    }

    @Test func aMouseWithNoPresetStartsBlankOrAsACopyOfAnotherMouse() {
        let config = SettingsEdit.addDevice(karabiner, name: "Bare", .blank).applied(to: .example)
        let choices = SetupChoices(for: new(usbMouse, "USB Mouse", .mouse), in: config)
        #expect(choices.suggested == .blank)
        #expect(choices.others == [.copy(of: mx), .copy(of: mouse24G)], "no keyboard, and no profile with nothing in it")
    }

    @Test func aKeyboardGetsTheHyperKeyAndNoCopyOfAnotherHyperKeyboard() {
        let choices = SetupChoices(for: new(karabiner, "Virtual Keyboard", .keyboard), in: .example)
        #expect(choices.suggested == .preset(.keyboard))
        #expect(choices.others == [])
    }

    @Test func the24GMouseGetsItsOwnPresetFirstEvenAsAKeyboard() {
        let config = SettingsEdit.forget(mouse24G).applied(to: .example)
        let choices = SetupChoices(for: new(mouse24G, "2.4G Mouse", .keyboard), in: config)
        #expect(choices.suggested == .preset(.mouse24G))
        #expect(choices.others == [.preset(.keyboard)])
    }
}
