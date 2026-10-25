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
    let mxRules = profile(.example, mx)!.rules!
    let rules24G = profile(.example, mouse24G)!.rules!
    var mxChoices: RuleChoices { RuleChoices(rules: mxRules, capabilities: mxCapabilities, speaksHIDPP: true) }
    var choices24G: RuleChoices { RuleChoices(rules: rules24G, capabilities: nil, speaksHIDPP: false) }

    @Test func eachControlKindOffersItsOwnTriggersAndActions() {
        let fresh = RuleChoices(rules: [], capabilities: mxCapabilities, speaksHIDPP: true)
        #expect(fresh.triggers(for: gestureButton) == [.click] + Direction.allCases.map(Trigger.holdMove) + [.holdMove(nil)])
        #expect(fresh.actions(for: gestureButton, on: .holdMove(nil)) == [.scroll])
        #expect(fresh.triggers(for: .button(1)) == [.click, .holdMove(nil)])
        #expect(fresh.actions(for: .button(1), on: .holdMove(nil)) == [.scroll])
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
                == [.button(1)] + [0x52, 0x53, 0x56, 0xC3, 0xC4, 0xD7].map { Control.hidpp(CID(rawValue: $0)) } + [.thumbWheel],
            "the right button cannot be diverted, so it is a plain button")
        let offline = RuleChoices(rules: mxRules, capabilities: nil, speaksHIDPP: true)
        #expect(offline.controls == [.button(1), gestureButton, topButton, .thumbWheel], "the rules' controls while not connected")
        #expect(choices24G.controls == (1...4).map(Control.button) + HIDUsage.named.map(Control.key))
    }

    @Test func aTriggerAnotherRuleUsesIsLeftOut() {
        let click = mxRules.first { $0.control == gestureButton && $0.trigger == .click }!
        #expect(mxChoices.triggers(for: gestureButton) == [.holdMove(.up)], "swipes rule out scrolling")
        #expect(mxChoices.triggers(for: gestureButton, besides: click) == [.click, .holdMove(.up)])
        let scroll = Rule(control: topButton, trigger: .holdMove(nil), action: .scroll)
        let scrolling = RuleChoices(
            rules: [Rule(control: topButton, trigger: .click, action: .system(.appExpose)), scroll],
            capabilities: mxCapabilities, speaksHIDPP: true)
        #expect(scrolling.triggers(for: topButton).isEmpty, "scrolling rules out swipes")
        #expect(scrolling.triggers(for: topButton, besides: scroll) == Direction.allCases.map(Trigger.holdMove) + [.holdMove(nil)])
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
        var config = Config.example
        for _ in 0..<40 {
            let rules = profile(config, mx)?.rules ?? []
            guard let rule = RuleChoices(rules: rules, capabilities: mxCapabilities, speaksHIDPP: true).newRule else { break }
            config = SettingsEdit.addRule(mx, rule).applied(to: config)
            #expect(saves(config), "\(rule)")
        }
        #expect(
            profile(config, mx)?.rules?.count == 33,
            "5 each for six HID++ controls (click, four swipes), 2 for the right button (click, scroll), 1 for the wheel")
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
        let base = Config.example
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
