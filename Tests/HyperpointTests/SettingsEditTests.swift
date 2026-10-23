import Foundation
import HyperpointKit
import Testing

@testable import Hyperpoint

let mx = DeviceMatch.device(vendor: VendorID(rawValue: 0x046D), product: ProductID(rawValue: 0xB023))
let mouse24G = DeviceMatch.device(vendor: VendorID(rawValue: 0x1EA7), product: ProductID(rawValue: 0x0002))
let magicKeyboard = DeviceMatch.device(vendor: VendorID(rawValue: 0x004C), product: ProductID(rawValue: 0x0321))
let karabiner = DeviceMatch.device(vendor: VendorID(rawValue: 0x05AC), product: ProductID(rawValue: 0x024F))
let gestureButton = Control.hidpp(CID(rawValue: 0xC3))
let topButton = Control.hidpp(CID(rawValue: 0xC4))

func profile(_ config: Config, _ match: DeviceMatch) -> DeviceProfile? { config.devices.first { $0.match == match } }

func saves(_ config: Config) -> Bool { (try? ConfigCodec.decode(ConfigCodec.encode(config))) == config }

@Suite struct SettingsEditTests {
    let base = Config.default

    @Test func hyperOnTurnsAProfileOffAndCreatesOneForANewKeyboard() {
        let off = SettingsEdit.hyperOn(magicKeyboard, name: "Magic Keyboard", false).applied(to: base)
        #expect(profile(off, magicKeyboard)?.hyper == false)
        #expect(off.devices.count == base.devices.count)

        let added = SettingsEdit.hyperOn(karabiner, name: "Virtual Keyboard", true).applied(to: base)
        #expect(added.devices.last == DeviceProfile(match: karabiner, name: "Virtual Keyboard", hyper: true))

        #expect(SettingsEdit.hyperOn(karabiner, name: "Virtual Keyboard", false).applied(to: base) == base)
    }

    @Test func renameTrimsAndIgnoresAnEmptyName() {
        #expect(profile(SettingsEdit.rename(mx, "  My MX ").applied(to: base), mx)?.name == "My MX")
        #expect(SettingsEdit.rename(mx, "  ").applied(to: base) == base)
    }

    @Test func addRuleAppendsOrCreatesTheProfile() {
        let rule = Rule(control: gestureButton, trigger: .holdMove(.up), action: .system(.missionControl))
        let added = SettingsEdit.addRule(mx, name: "MX Master 3", rule).applied(to: base)
        #expect(profile(added, mx)?.rules?.last == rule)
        #expect(profile(added, mx)?.rules?.count == (profile(base, mx)?.rules?.count ?? 0) + 1)

        let newMouse = DeviceMatch.device(vendor: VendorID(rawValue: 0x1234), product: ProductID(rawValue: 0x1))
        let created = SettingsEdit.addRule(newMouse, name: "USB Mouse", rule).applied(to: base)
        #expect(created.devices.last == DeviceProfile(match: newMouse, name: "USB Mouse", rules: [rule]))
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
        .hyperOn(magicKeyboard, name: "Magic Keyboard", false),
        .hyperOn(karabiner, name: "Virtual Keyboard", true),
        .rename(mx, "My MX"),
        .addRule(mx, name: "MX Master 3", Rule(control: gestureButton, trigger: .holdMove(.up), action: .system(.appExpose))),
        .addRule(karabiner, name: "Virtual Keyboard", Rule(control: .key(HIDUsage(name: "f1")!), trigger: .hold, action: .modifier(.leftCommand))),
        .replaceRule(
            mx, RuleKey(Rule(control: topButton, trigger: .click, action: .system(.appExpose))),
            Rule(control: topButton, trigger: .holdMove(.left), action: .shortcut(Chord(key: KeyCode(name: "left")!, modifiers: [.control])))),
        .removeRule(mx, RuleKey(Rule(control: .thumbWheel, trigger: .scroll, action: .reverse))),
        .gestureFire(mx, .onRelease),
        .gestureDistance(mx, 2000),
        .smooth(mx, nil),
        .smooth(mouse24G, .default),
    ] + SmoothKnob.allCases.map { .smoothKnob(mx, $0, $0.scale.value(at: 0.7)) }

    @Test(arguments: everyEdit)
    func everyEditChangesTheFileAndSurvivesTheCodec(_ edit: SettingsEdit) throws {
        let edited = edit.applied(to: base)
        #expect(edited != base)
        #expect(try ConfigCodec.decode(ConfigCodec.encode(edited)) == edited)
    }

    @Test func theLogLineUsesTheFileKeys() {
        #expect(
            SettingsEdit.smoothKnob(mx, .brake, 2.5).logDescription
                == #"devices[{"product":"0xB023","vendor":"0x046D"}].scrolling.smooth.brake = 2.5"#)
    }
}

extension SettingsEdit: CustomTestStringConvertible {
    var testDescription: String { logDescription }
}
