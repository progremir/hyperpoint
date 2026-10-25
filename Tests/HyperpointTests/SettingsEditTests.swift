import Foundation
import HyperpointKit
import Testing

@testable import Hyperpoint

let karabiner = DeviceMatch.device(vendor: VendorID(rawValue: 0x05AC), product: ProductID(rawValue: 0x024F))
let usbMouse = DeviceMatch.device(vendor: VendorID(rawValue: 0x1234), product: ProductID(rawValue: 0x1))
let gestureButton = Control.hidpp(CID(rawValue: 0xC3))
let topButton = Control.hidpp(CID(rawValue: 0xC4))

func profile(_ config: Config, _ match: DeviceMatch) -> DeviceProfile? { config.devices.first { $0.match == match } }

func saves(_ config: Config) -> Bool { (try? ConfigCodec.decode(ConfigCodec.encode(config))) == config }

@Suite struct SettingsEditTests {
    let base = Config.example

    @Test func addDeviceAppendsAProfileFromAPreset() {
        let forgotten = SettingsEdit.forget(mx).applied(to: base)
        let added = SettingsEdit.addDevice(mx, name: " MX Master 3  ", .preset(.mxMaster3)).applied(to: forgotten)
        #expect(added.devices == forgotten.devices + [profile(base, mx)!], "the name is trimmed")

        let keyboard = SettingsEdit.addDevice(karabiner, name: "Virtual Keyboard", .preset(.keyboard)).applied(to: base)
        #expect(keyboard.devices == base.devices + [DeviceProfile(match: karabiner, name: "Virtual Keyboard", hyper: true)])
    }

    @Test func addDeviceCopiesAnotherProfileAsItIsInTheFile() {
        let edited = SettingsEdit.smooth(mx, nil).applied(to: base)
        let copied = SettingsEdit.addDevice(usbMouse, name: "USB Mouse", .copy(of: mx)).applied(to: edited)
        let source = profile(edited, mx)!
        #expect(
            copied.devices
                == edited.devices + [
                    DeviceProfile(
                        match: usbMouse, name: "USB Mouse", rules: source.rules, gestures: source.gestures,
                        scrolling: source.scrolling, hyper: source.hyper)
                ])
        #expect(profile(copied, usbMouse)?.scrolling?.smooth == nil, "the copy has the edit made before it")
    }

    @Test func addDeviceCanStartBlank() {
        let added = SettingsEdit.addDevice(usbMouse, name: "USB Mouse", .blank).applied(to: base)
        #expect(added.devices == base.devices + [DeviceProfile(match: usbMouse, name: "USB Mouse")])
    }

    static let refusedAdds: [SettingsEdit] = [
        .addDevice(mx, name: "Another MX", .blank),
        .addDevice(mouse24G, name: "2.4G Mouse", .preset(.mouse24G)),
        .addDevice(usbMouse, name: "  ", .blank),
        .addDevice(usbMouse, name: "USB Mouse", .preset(.mxMaster3)),
        .addDevice(usbMouse, name: "USB Mouse", .preset(.mouse24G)),
        .addDevice(usbMouse, name: "USB Mouse", .copy(of: karabiner)),
        .addDevice(usbMouse, name: "USB Mouse", .copy(of: usbMouse)),
    ]

    @Test(arguments: refusedAdds)
    func addDeviceChangesNothingWhenItCannotApply(_ edit: SettingsEdit) {
        #expect(edit.applied(to: base) == base)
    }

    @Test func addDeviceRefusesAnIgnoredDevice() {
        let ignored = SettingsEdit.ignore(usbMouse, true).applied(to: base)
        #expect(SettingsEdit.addDevice(usbMouse, name: "USB Mouse", .blank).applied(to: ignored) == ignored)
    }

    @Test func addingADeviceTwiceAddsItOnce() {
        let once = SettingsEdit.addDevice(usbMouse, name: "USB Mouse", .copy(of: mx)).applied(to: base)
        #expect(SettingsEdit.addDevice(usbMouse, name: "USB Mouse", .copy(of: mx)).applied(to: once) == once)
        #expect(SettingsEdit.addDevice(usbMouse, name: "Other", .blank).applied(to: once) == once)
    }

    @Test func theHyperSwitchKeepsEveryKeyboardsOwnSetting() {
        let off = SettingsEdit.hyperEnabled(false).applied(to: base)
        #expect(off.hyper.enabled == false)
        #expect(off.devices == base.devices)
        #expect(SettingsEdit.hyperEnabled(true).applied(to: off) == base)
    }

    @Test func hyperOnTurnsAProfileOffAndOn() {
        let off = SettingsEdit.hyperOn(magicKeyboard, false).applied(to: base)
        #expect(profile(off, magicKeyboard)?.hyper == false)
        #expect(off.devices.count == base.devices.count)
        #expect(SettingsEdit.hyperOn(magicKeyboard, true).applied(to: off) == base)
    }

    @Test func hyperOnAndAddRuleChangeNothingWithoutAProfile() {
        let rule = Rule(control: .button(1), trigger: .click, action: .system(.missionControl))
        #expect(SettingsEdit.hyperOn(karabiner, true).applied(to: base) == base)
        #expect(SettingsEdit.addRule(usbMouse, rule).applied(to: base) == base)
    }

    @Test func renameTrimsAndIgnoresAnEmptyName() {
        #expect(profile(SettingsEdit.rename(mx, "  My MX ").applied(to: base), mx)?.name == "My MX")
        #expect(SettingsEdit.rename(mx, "  ").applied(to: base) == base)
    }

    @Test func kindSetsWhatTheProfileIs() {
        #expect(profile(SettingsEdit.kind(magicKeyboard, .mouse).applied(to: base), magicKeyboard)?.kind == .mouse)
        #expect(profile(SettingsEdit.kind(mouse24G, .keyboard).applied(to: base), mouse24G)?.kind == .keyboard)
        #expect(SettingsEdit.kind(karabiner, .mouse).applied(to: base) == base, "a device without a profile has no kind to set")
    }

    @Test func addRuleAppendsToTheProfile() {
        let rule = Rule(control: gestureButton, trigger: .holdMove(.up), action: .system(.missionControl))
        let added = SettingsEdit.addRule(mx, rule).applied(to: base)
        #expect(profile(added, mx)?.rules == (profile(base, mx)?.rules ?? []) + [rule])
    }

    @Test func replaceAndRemoveFindTheRuleByControlAndTrigger() {
        let old = Rule(control: topButton, trigger: .click, action: .shortcut(RuleChoices.placeholderChord))
        let new = Rule(control: topButton, trigger: .click, action: .system(.appExpose))
        let replaced = SettingsEdit.replaceRule(mx, RuleKey(old), new).applied(to: base)
        #expect(profile(replaced, mx)?.rules?.contains(new) == true)
        #expect(profile(replaced, mx)?.rules?.contains(old) == false)

        let stale = Rule(control: topButton, trigger: .holdMove(.up), action: .system(.appExpose))
        #expect(SettingsEdit.replaceRule(mx, RuleKey(stale), new).applied(to: base) == base)

        let removed = SettingsEdit.removeRule(mx, RuleKey(old)).applied(to: base)
        #expect(profile(removed, mx)?.rules == profile(base, mx)?.rules?.filter { $0 != old })
        #expect(SettingsEdit.removeRule(mx, RuleKey(old)).applied(to: removed) == removed)
    }

    @Test func gestureEditsStartFromTheDefaults() {
        var config = base
        config.devices[0].gestures = nil
        #expect(
            profile(SettingsEdit.gestureFire(mx, .onRelease).applied(to: config), mx)?.gestures
                == GestureSettings(fire: .onRelease, distance: GestureSettings.default.distance))
        #expect(
            profile(SettingsEdit.gestureDistance(mx, 300).applied(to: config), mx)?.gestures
                == GestureSettings(fire: GestureSettings.default.fire, distance: 300))
    }

    @Test func smoothOffRemovesOnlyTheSmoothSection() {
        let off = SettingsEdit.smooth(mx, nil).applied(to: base)
        #expect(profile(off, mx)?.scrolling?.smooth == nil)
        #expect(profile(off, mx)?.scrolling?.hiResWheel == true)
        #expect(SettingsEdit.smooth(mouse24G, nil).applied(to: base) == base, "no empty scrolling section appears")

        let on = SettingsEdit.smooth(mouse24G, .default).applied(to: base)
        #expect(profile(on, mouse24G)?.scrolling == ScrollSettings(smooth: .default))
    }

    @Test func knobEditsChangeOneValue() {
        let longer = SettingsEdit.smoothKnob(mx, .duration, 7).applied(to: base)
        var expected = SmoothScroll.default
        expected.duration = 7
        #expect(profile(longer, mx)?.scrolling?.smooth == expected)
    }

    static let everyEdit: [SettingsEdit] = [
        .hyperKey(HIDUsage(name: "f5")!),
        .hyperEnabled(false),
        .addDevice(karabiner, name: "Virtual Keyboard", .preset(.keyboard)),
        .addDevice(usbMouse, name: "USB Mouse", .copy(of: mx)),
        .addDevice(usbMouse, name: "USB Mouse", .blank),
        .hyperOn(magicKeyboard, false),
        .rename(mx, "My MX"),
        .addRule(mx, Rule(control: gestureButton, trigger: .holdMove(.up), action: .system(.appExpose))),
        .addRule(mouse24G, Rule(control: .key(HIDUsage(name: "f1")!), trigger: .hold, action: .modifier(.leftCommand))),
        .replaceRule(
            mx, RuleKey(Rule(control: topButton, trigger: .click, action: .system(.appExpose))),
            Rule(
                control: .hidpp(CID(rawValue: 0x53)), trigger: .holdMove(.left),
                action: .shortcut(Chord(key: KeyCode(name: "left")!, modifiers: [.control])))),
        .removeRule(mx, RuleKey(Rule(control: .thumbWheel, trigger: .scroll, action: .reverse))),
        .kind(mx, .keyboard),
        .kind(mouse24G, .keyboard),
        .gestureFire(mx, .onRelease),
        .gestureDistance(mx, 2000),
        .smooth(mx, nil),
        .smooth(mouse24G, .default),
        .curve(mx, CurveGraph.dragging(.default, point: 1, to: SpeedCurve.Point(stepsPerSecond: 6, pointsPerSecond: 400))),
        .holdToScroll(mx, HoldToScroll(speed: 2, direction: .wheel, momentum: false)),
        .holdToScroll(mouse24G, .default),
        .forget(mx),
        .ignore(karabiner, true),
    ] + SmoothKnob.allCases.map { .smoothKnob(mx, $0, $0.scale.value(at: 0.7)) }

    @Test(arguments: everyEdit)
    func everyEditChangesTheFileAndSurvivesTheCodec(_ edit: SettingsEdit) throws {
        let edited = edit.applied(to: base)
        #expect(edited != base)
        #expect(try ConfigCodec.decode(ConfigCodec.encode(edited)) == edited)
    }

    @Test(arguments: everyEdit)
    func onlyAddDeviceAddsAProfileAndOnlyForgetRemovesOne(_ edit: SettingsEdit) {
        let before = Set(base.devices.map(\.match))
        let after = Set(edit.applied(to: base).devices.map(\.match))
        switch edit {
        case .addDevice(let match, _, _): #expect(after == before.union([match]))
        case .forget(let match): #expect(after == before.subtracting([match]))
        default: #expect(after == before)
        }
    }

    @Test func holdToScrollEditsCreateTheScrollingSection() {
        let edited = SettingsEdit.holdToScroll(mouse24G, HoldToScroll(speed: 0.5, direction: .grab, momentum: false)).applied(to: base)
        #expect(profile(edited, mouse24G)?.scrolling == ScrollSettings(holdToScroll: HoldToScroll(speed: 0.5, direction: .grab, momentum: false)))
        let mxEdited = SettingsEdit.holdToScroll(mx, HoldToScroll(speed: 2, direction: .wheel, momentum: true)).applied(to: base)
        #expect(profile(mxEdited, mx)?.scrolling?.smooth == profile(base, mx)?.scrolling?.smooth, "the rest of the section stays")
        #expect(profile(mxEdited, mx)?.scrolling?.holdToScroll?.direction == .wheel)
    }

    @Test func forgetRemovesOnlyThatProfile() {
        let forgotten = SettingsEdit.forget(mx).applied(to: base)
        #expect(forgotten.devices == base.devices.filter { $0.match != mx })
        #expect(forgotten.hyper == base.hyper)
        #expect(forgotten.ignored == base.ignored)
        #expect(SettingsEdit.forget(karabiner).applied(to: base) == base, "a device without a profile has nothing to forget")
    }

    @Test func ignoreAddsANewDeviceOnceAndCanBeUndone() throws {
        let ignored = SettingsEdit.ignore(karabiner, true).applied(to: base)
        #expect(ignored.ignored == base.ignored + [karabiner])
        #expect(SettingsEdit.ignore(karabiner, true).applied(to: ignored) == ignored)
        #expect(SettingsEdit.ignore(karabiner, false).applied(to: ignored) == base)
        #expect(SettingsEdit.ignore(mx, true).applied(to: base) == base, "a device with a profile cannot also be ignored")
    }

    @Test func theLogLineUsesTheFileKeys() {
        #expect(
            SettingsEdit.smoothKnob(mx, .brake, 2.5).logDescription
                == #"devices[{"product":"0xB023","vendor":"0x046D"}].scrolling.smooth.brake = 2.5"#)
        #expect(SettingsEdit.hyperEnabled(false).logDescription == "hyper.enabled = false")
        #expect(
            SettingsEdit.addDevice(mx, name: "MX Master 3", .preset(.mxMaster3)).logDescription
                == #"devices += {"product":"0xB023","vendor":"0x046D"} from preset mxMaster3"#)
        #expect(
            SettingsEdit.addDevice(usbMouse, name: "USB Mouse", .copy(of: mx)).logDescription
                == #"devices += {"product":"0x0001","vendor":"0x1234"} from copy of {"product":"0xB023","vendor":"0x046D"}"#)
        #expect(
            SettingsEdit.kind(mouse24G, .mouse).logDescription == #"devices[{"product":"0x0002","vendor":"0x1EA7"}].kind = mouse"#)
        #expect(
            SettingsEdit.addDevice(usbMouse, name: "USB Mouse", .blank).logDescription
                == #"devices += {"product":"0x0001","vendor":"0x1234"} blank"#)
    }
}

extension SettingsEdit: CustomTestStringConvertible {
    var testDescription: String { logDescription }
}
