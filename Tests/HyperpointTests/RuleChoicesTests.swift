import HyperpointKit
import Testing

@testable import Hyperpoint

/// What discovery reported on this MX Master 3.
let mxCapabilities = HIDPPCapabilities(
    controls: [
        .init(cid: CID(rawValue: 0x50), divertable: false, rawXY: false),
        .init(cid: CID(rawValue: 0x51), divertable: false, rawXY: false),
        .init(cid: CID(rawValue: 0x52), divertable: true, rawXY: true),
        .init(cid: CID(rawValue: 0x53), divertable: true, rawXY: true),
        .init(cid: CID(rawValue: 0x56), divertable: true, rawXY: true),
        .init(cid: CID(rawValue: 0xC3), divertable: true, rawXY: true),
        .init(cid: CID(rawValue: 0xC4), divertable: true, rawXY: true),
        .init(cid: CID(rawValue: 0xD7), divertable: true, rawXY: true),
    ],
    thumbWheel: true)

@Suite struct RuleChoicesTests {
    let mxRules = profile(.default, mx)!.rules!
    let rules24G = profile(.default, mouse24G)!.rules!
    var mxChoices: RuleChoices { RuleChoices(rules: mxRules, capabilities: mxCapabilities, speaksHIDPP: true) }
    var choices24G: RuleChoices { RuleChoices(rules: rules24G, capabilities: nil, speaksHIDPP: false) }

    @Test func eachControlKindOffersItsOwnTriggersAndActions() {
        let fresh = RuleChoices(rules: [], capabilities: mxCapabilities, speaksHIDPP: true)
        #expect(fresh.triggers(for: gestureButton) == [.click] + Direction.allCases.map(Trigger.holdMove))
        #expect(fresh.actions(for: gestureButton, on: .click).contains(.system(.missionControl)))
        #expect(!fresh.actions(for: gestureButton, on: .click).contains(.modifier(.rightOption)))
        #expect(fresh.triggers(for: .thumbWheel) == [.scroll])
        #expect(fresh.actions(for: .thumbWheel, on: .scroll) == [.reverse])

        let escape = Control.key(HIDUsage(name: "escape")!)
        let keys = RuleChoices(rules: [], capabilities: nil, speaksHIDPP: false)
        #expect(keys.triggers(for: escape) == [.click, .hold])
        #expect(keys.actions(for: escape, on: .click) == [.shortcut(RuleChoices.placeholderChord)])
        #expect(keys.actions(for: escape, on: .hold) == HeldModifier.allCases.map(Action.modifier))
    }

    @Test func pickersOfferTheDivertableControlsTheDeviceReported() {
        #expect(
            mxChoices.controls
                == [0x52, 0x53, 0x56, 0xC3, 0xC4, 0xD7].map { Control.hidpp(CID(rawValue: $0)) } + [.thumbWheel])
        let offline = RuleChoices(rules: mxRules, capabilities: nil, speaksHIDPP: true)
        #expect(offline.controls == [gestureButton, topButton, .thumbWheel], "the rules' controls while not connected")
        #expect(choices24G.controls.count == HIDUsage.named.count)
    }

    @Test func aTriggerAnotherRuleUsesIsLeftOut() {
        let click = mxRules.first { $0.control == gestureButton && $0.trigger == .click }!
        #expect(mxChoices.triggers(for: gestureButton) == [.holdMove(.up)])
        #expect(mxChoices.triggers(for: gestureButton, besides: click) == [.click, .holdMove(.up)])
    }

    @Test func aControlWithoutRawMovementOffersNoSwipes() {
        let noRawXY = HIDPPCapabilities(controls: [.init(cid: CID(rawValue: 0x53), divertable: true, rawXY: false)], thumbWheel: false)
        let choices = RuleChoices(rules: [], capabilities: noRawXY, speaksHIDPP: true)
        #expect(choices.triggers(for: .hidpp(CID(rawValue: 0x53))) == [.click])
    }

    @Test func addRuleFillsAFreeTriggerOnAButtonThatAlreadyHasRules() {
        #expect(mxChoices.newRule == Rule(control: gestureButton, trigger: .holdMove(.up), action: .system(.missionControl)))
        #expect(
            choices24G.newRule
                == Rule(control: .key(HIDUsage(name: "escape")!), trigger: .click, action: .shortcut(RuleChoices.placeholderChord)))
        let full = RuleChoices(
            rules: [Rule(control: .thumbWheel, trigger: .scroll, action: .reverse)],
            capabilities: HIDPPCapabilities(controls: [], thumbWheel: true), speaksHIDPP: true)
        #expect(full.newRule == nil)
    }

    @Test func addRuleSavesUntilEveryTriggerIsTaken() throws {
        var config = Config.default
        for _ in 0..<40 {
            let rules = profile(config, mx)?.rules ?? []
            guard let rule = RuleChoices(rules: rules, capabilities: mxCapabilities, speaksHIDPP: true).newRule else { break }
            config = SettingsEdit.addRule(mx, name: "MX Master 3", rule).applied(to: config)
            #expect(saves(config), "\(rule)")
        }
        #expect(profile(config, mx)?.rules?.count == 6 * 5 + 1, "six controls with click and four swipes, and the wheel")
    }

    @Test func movingARuleKeepsWhatStillWorks() {
        let top = mxRules.first { $0.control == topButton }!
        #expect(!mxChoices.controls(for: top).contains(.thumbWheel), "the wheel's one trigger is taken")
        let withoutWheel = RuleChoices(rules: [top], capabilities: mxCapabilities, speaksHIDPP: true)
        #expect(withoutWheel.rule(top, withControl: .thumbWheel) == Rule(control: .thumbWheel, trigger: .scroll, action: .reverse))
        #expect(
            mxChoices.rule(top, withControl: gestureButton)
                == Rule(control: gestureButton, trigger: .holdMove(.up), action: top.action))

        let escapeHold = rules24G.first { $0.trigger == .hold }!
        let moved = choices24G.rule(escapeHold, withTrigger: .click)
        #expect(moved == Rule(control: escapeHold.control, trigger: .click, action: .shortcut(RuleChoices.placeholderChord)))
    }

    /// Whatever the user picks in a row's three pickers, the file still parses.
    @Test(arguments: [mx, mouse24G])
    func everyPickerChoiceSaves(_ device: DeviceMatch) {
        let base = Config.default
        let rules = profile(base, device)!.rules!
        let choices = RuleChoices(
            rules: rules, capabilities: device == mx ? mxCapabilities : nil, speaksHIDPP: device == mx)
        for rule in rules {
            var picked: [Rule] = choices.controls(for: rule).map { choices.rule(rule, withControl: $0) }
            picked += choices.triggers(for: rule.control, besides: rule).map { choices.rule(rule, withTrigger: $0) }
            picked += choices.actions(for: rule.control, on: rule.trigger).map {
                Rule(control: rule.control, trigger: rule.trigger, action: $0)
            }
            for choice in picked {
                let edited = SettingsEdit.replaceRule(device, RuleKey(rule), choice).applied(to: base)
                #expect(saves(edited), "\(rule) to \(choice)")
            }
        }
    }
}
