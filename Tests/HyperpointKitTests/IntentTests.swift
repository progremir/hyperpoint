@testable import HyperpointKit
import Testing

@Suite struct DeviceMatchTests {
    @Test func theExampleProfilesClassifyThisMacsKeyboards() {
        let names = [
            Bags.builtInKeyboard, Bags.builtInKeyboardAsListed, Bags.magicKeyboard, Bags.mxMaster3,
            Bags.karabinerVirtualKeyboard,
        ].map { Config.example.profile(for: HIDProperties(bag: $0))?.name }
        #expect(names == ["Built-in Keyboard", "Built-in Keyboard", "Magic Keyboard", "MX Master 3", nil])
    }

    @Test func builtInIsTheAuthorityNotVendorZero() {
        let builtIn = HIDProperties(bag: Bags.builtInKeyboardAsListed)
        #expect(!DeviceMatch.device(vendor: VendorID(rawValue: 0), product: ProductID(rawValue: 0)).matches(builtIn))
        #expect(!DeviceMatch.builtIn.matches(HIDProperties(bag: Bags.magicKeyboard)))
    }

    @Test func ignoredDeviceHasNoProfile() {
        var config = Config.example
        config.ignored = [.device(vendor: VendorID(rawValue: 0x4C), product: ProductID(rawValue: 0x321))]
        #expect(config.profile(for: HIDProperties(bag: Bags.magicKeyboard)) == nil)
    }

    @Test func hidutilMatchingSelectsTheKeyboardService() {
        #expect(DeviceMatch.builtIn.hidutilKeyboardMatching == #"{"Built-In":1,"PrimaryUsagePage":1,"PrimaryUsage":6}"#)
        #expect(
            DeviceMatch(identifying: HIDProperties(bag: Bags.magicKeyboard)).hidutilKeyboardMatching
                == #"{"VendorID":0x4C,"ProductID":0x321,"PrimaryUsagePage":1,"PrimaryUsage":6}"#)
    }
}

@Suite struct KeyMapSetupTests {
    @Test func hyperRouteRendersTheTN2450Mapping() {
        let setup = KeyMapSetup(routes: [.hyper(from: capsLock)])
        #expect(
            setup.userKeyMappingJSON
                == #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#
        )
        #expect(setup.pairs == [KeyMapSetup.Pair(source: 0x7_0000_0039, destination: 0x7_0000_006D)])
    }

    @Test func neutralClearsTheWholeProperty() {
        #expect(KeyMapSetup.neutral.userKeyMappingJSON == #"{"UserKeyMapping":[]}"#)
    }

    @Test func aDeviceIsWrittenOnlyWhenSomethingIsWantedOrOursIsOnIt() {
        let hyper = KeyMapSetup(routes: [.hyper(from: capsLock)])
        #expect(KeyMapSetup.pendingWrite(desired: .neutral, written: nil) == nil)
        #expect(KeyMapSetup.pendingWrite(desired: .neutral, written: .neutral) == nil)
        #expect(KeyMapSetup.pendingWrite(desired: .neutral, written: hyper) == .neutral)
        #expect(KeyMapSetup.pendingWrite(desired: hyper, written: hyper) == hyper, "every apply is absolute")
        #expect(KeyMapSetup.pendingWrite(desired: hyper, written: nil) == hyper)
    }
}

@Suite struct RecoveredKeyMapTests {
    let capsLockToF18 = KeyMapSetup.Pair(source: 0x7_0000_0039, destination: 0x7_0000_006D)
    let escapeToF13 = KeyMapSetup.Pair(source: 0x7_0000_0029, destination: 0x7_0000_0068)
    let escapeToRightOption = KeyMapSetup.Pair(source: 0x7_0000_0029, destination: 0x7_0000_00E6)
    let returnToF21 = KeyMapSetup.Pair(source: 0x7_0000_0028, destination: 0x7_0000_0070)

    @Test func aCarrierDestinationMakesTheMapOurs() {
        #expect(KeyMapSetup.hyperpointLeftover(in: [capsLockToF18])?.carriesHyper == true)
        #expect(KeyMapSetup.hyperpointLeftover(in: [escapeToF13]) != nil, "every carrier in the pool counts")
        #expect(KeyMapSetup.hyperpointLeftover(in: [capsLockToF18, escapeToRightOption]) != nil)
    }

    @Test func aMapWithNoCarrierIsSomeoneElses() {
        #expect(KeyMapSetup.hyperpointLeftover(in: [escapeToRightOption, returnToF21]) == nil)
    }

    @Test func anEmptyMapIsNotOurs() {
        #expect(KeyMapSetup.hyperpointLeftover(in: []) == nil)
    }

    @Test func aStaleHyperMapIsClearedOnceHyperIsDisabled() {
        let leftByACrash = """
            RegistryID  Key                   Value
            10001bc2e   UserKeyMapping   (
                    {
                    HIDKeyboardModifierMappingDst = 30064771181;
                    HIDKeyboardModifierMappingSrc = 30064771129;
                }
            )

            """
        let held = HidutilReadback.parse(leftByACrash).values.reduce(into: Set()) { $0.formUnion($1) }
        let written = KeyMapSetup.hyperpointLeftover(in: held)
        #expect(KeyMapSetup.pendingWrite(desired: .neutral, written: written) == .neutral)
        let hyper = KeyMapSetup(routes: [.hyper(from: capsLock)])
        #expect(KeyMapSetup.pendingWrite(desired: hyper, written: written) == hyper)
    }

    @Test func aForeignMapIsLeftAloneWhenNothingIsWanted() {
        let written = KeyMapSetup.hyperpointLeftover(in: [escapeToRightOption])
        #expect(KeyMapSetup.pendingWrite(desired: .neutral, written: written) == nil)
    }
}

@Suite struct IntentTests {
    let hyperMap = KeyMapSetup(routes: [.hyper(from: capsLock)])

    @Test func hyperKeyboardsMapCapsLockToTheHyperCarrier() {
        let intent = Intent.compile(.example, paused: false, tapAvailable: true, present: thisMac)
        #expect(thisMac.map { intent.setup(for: $0.id).keyMap } == [hyperMap, hyperMap, .neutral, .neutral])
        #expect(intent.tap == TapRules(carriers: [Carrier.hyper.keyCode: .holdModifiers(.hyper)], smoothScroll: [:]))
    }

    @Test func pausedIsNeutralEverywhere() {
        let intent = Intent.compile(.example, paused: true, tapAvailable: true, present: thisMac)
        #expect(thisMac.allSatisfy { intent.setup(for: $0.id) == .neutral })
        #expect(intent.tap.isEmpty)
    }

    @Test func withoutTheTapNoKeyBecomesACarrier() {
        let intent = Intent.compile(.example, paused: false, tapAvailable: false, present: thisMac)
        #expect(thisMac.allSatisfy { intent.setup(for: $0.id).keyMap == .neutral })
        #expect(intent.tap.isEmpty)
    }

    @Test func hyperOffLeavesTheKeyboardNeutral() {
        var config = Config.example
        config.devices[3].hyper = false
        config.devices[2].hyper = nil
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(thisMac.allSatisfy { intent.setup(for: $0.id).keyMap == .neutral })
        #expect(intent.tap.isEmpty)
    }

    @Test func theMXIsNotAHyperKeyboard() {
        var config = Config.example
        config.devices[0].hyper = true
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(intent.setup(for: thisMac[2].id).keyMap == .neutral, "its keyboard collection does not make it one")
        #expect(intent.setup(for: thisMac[1].id).keyMap == hyperMap)
    }

    @Test func theConfiguredKeyIsTheSource() {
        var config = Config.example
        config.hyper.key = HIDUsage(name: "grave")!
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(intent.setup(for: thisMac[1].id).keyMap.pairs == [.init(source: 0x7_0000_0035, destination: 0x7_0000_006D)])
    }

    @Test func carrierAssignmentDoesNotDependOnDeviceOrder() {
        let forward = Intent.compile(.example, paused: false, tapAvailable: true, present: thisMac)
        let reversed = Intent.compile(.example, paused: false, tapAvailable: true, present: thisMac.reversed())
        let onlyMagic = Intent.compile(.example, paused: false, tapAvailable: true, present: [thisMac[1]])
        #expect(forward == reversed)
        #expect(onlyMagic.setup(for: thisMac[1].id) == forward.setup(for: thisMac[1].id))
        #expect(onlyMagic.tap == forward.tap)
    }
}

@Suite struct SmoothScrollIntentTests {
    let mxService = SenderID(rawValue: 0x1_0003_7032)
    let keyboardService = SenderID(rawValue: 0x1_0001_BC2E)
    var present: [PresentDevice] {
        [
            HyperpointKitTests.present(1, Bags.builtInKeyboard, services: [0x1_0000_0D10]),
            HyperpointKitTests.present(2, Bags.magicKeyboard, services: [keyboardService.rawValue]),
            HyperpointKitTests.present(3, Bags.mxMaster3, services: [mxService.rawValue]),
        ]
    }

    @Test func theMXScrollsSmoothlyByItsEventService() {
        let intent = Intent.compile(.example, paused: false, tapAvailable: true, present: present)
        #expect(intent.tap.smoothScroll == [mxService: Config.example.devices[0].scrolling!.smooth!])
    }

    @Test func aProfileWithoutSmoothScrollingAddsNoSender() {
        var config = Config.example
        config.devices[0].scrolling?.smooth = nil
        #expect(Intent.compile(config, paused: false, tapAvailable: true, present: present).tap.smoothScroll.isEmpty)
        config.devices[0].scrolling = nil
        #expect(Intent.compile(config, paused: false, tapAvailable: true, present: present).tap.smoothScroll.isEmpty)
    }

    @Test func aDeviceWhoseServiceIsNotPublishedYetHasNoSender() {
        let reconnected = HyperpointKitTests.present(5, Bags.mxMaster3)
        #expect(Intent.compile(.example, paused: false, tapAvailable: true, present: [reconnected]).tap.smoothScroll.isEmpty)
    }

    @Test func pauseStopsSmoothScrolling() {
        #expect(Intent.compile(.example, paused: true, tapAvailable: true, present: present).tap.isEmpty)
    }

    @Test func smoothScrollingAloneInstallsTheTap() {
        var config = Config.example
        config.devices = [config.devices[0]]
        #expect(!Intent.compile(config, paused: false, tapAvailable: true, present: present).tap.isEmpty)
    }
}

@Suite struct HIDPPIntentTests {
    let mx = discovered(thisMac[2])
    let shot = Action.shortcut(Chord(key: KeyCode(name: "4")!, modifiers: [.shift, .command]))

    var presetMX: HIDPPSetup {
        HIDPPSetup(
            controls: [
                gestureButton: .gesture(
                    GesturePlan(
                        distance: 120, click: .system(.missionControl),
                        moves: .swipes(
                            [.down: .system(.appExpose), .left: .system(.spaceLeft), .right: .system(.spaceRight)],
                            fire: .pastDistance))),
                topButton: .press(shot),
            ],
            thumbWheelInverted: true)
    }

    @Test func theMXPresetReproducesBetterMouse() {
        let intent = Intent.compile(.example, paused: false, tapAvailable: true, present: [thisMac[0], thisMac[1], mx])
        #expect(intent.setup(for: mx.id).hidpp == presetMX)
        #expect(intent.skipped.isEmpty)
        #expect(intent.setup(for: thisMac[0].id).hidpp == nil, "keyboards do not speak HID++")
        #expect(intent.setup(for: thisMac[1].id).hidpp == nil)
    }

    @Test func theFirmwareFlagsFollowTheBehavior() {
        let control = HIDPPCapabilities.Control(cid: gestureButton, divertable: true, rawXY: true)
        #expect(presetMX.behavior(of: gestureButton).reporting(for: control).writeFlags == 0x33)
        #expect(presetMX.behavior(of: topButton).reporting(for: control).writeFlags == 0x23)
        #expect(presetMX.behavior(of: CID(rawValue: 0x52)).reporting(for: control).writeFlags == 0x22, "no rule is native")
        let noRawXY = HIDPPCapabilities.Control(cid: gestureButton, divertable: true, rawXY: false)
        #expect(presetMX.behavior(of: gestureButton).reporting(for: noRawXY).writeFlags == 0x23)
    }

    @Test func beforeDiscoveryTheRulesCompileUnfiltered() {
        let intent = Intent.compile(.example, paused: false, tapAvailable: true, present: [thisMac[2]])
        #expect(intent.setup(for: mx.id).hidpp == presetMX)
    }

    @Test func rulesOnControlsTheDeviceLacksAreSkipped() throws {
        var config = Config.example
        let absent = Rule(control: .hidpp(CID(rawValue: 0x1A0)), trigger: .click, action: .system(.spaceLeft))
        let leftButton = Rule(control: .hidpp(CID(rawValue: 0x50)), trigger: .click, action: .system(.spaceRight))
        config.devices[0].rules = [absent, leftButton] + (config.devices[0].rules ?? [])
        let noWheel = HIDPPCapabilities(controls: measuredMXCapabilities.controls, thumbWheel: false)

        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: [discovered(thisMac[2], noWheel)])

        let wheel = try #require(config.devices[0].rules?.first { $0.control == .thumbWheel })
        #expect(intent.skipped[mx.id] == [absent, leftButton, wheel])
        var expected = presetMX
        expected.thumbWheelInverted = false
        #expect(intent.setup(for: mx.id).hidpp == expected, "the rules the device can carry out still apply")
    }

    @Test func aClickWithoutHoldMoveIsAPress() {
        var config = Config.example
        config.devices[0].rules = config.devices[0].rules?.filter { $0.trigger == .click }
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: [mx])
        #expect(
            intent.setup(for: mx.id).hidpp
                == HIDPPSetup(controls: [gestureButton: .press(.system(.missionControl)), topButton: .press(shot)], thumbWheelInverted: false))
    }

    @Test func gestureSettingsComeFromTheProfile() {
        var config = Config.example
        config.devices[0].gestures = GestureSettings(fire: .onRelease, distance: 300)
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: [mx])
        guard case .gesture(let plan) = intent.setup(for: mx.id).hidpp?.behavior(of: gestureButton),
            case .swipes(_, let fire) = plan.moves
        else {
            Issue.record("the gesture button swipes")
            return
        }
        #expect(fire == .onRelease && plan.distance == 300)
    }

    @Test func aProfileWithoutButtonRulesLeavesTheDeviceAlone() {
        var config = Config.example
        config.devices[0].rules = nil
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: [mx])
        #expect(intent.setup(for: mx.id).hidpp == nil)
    }

    @Test func aMouseWithNothingToWriteStillReadsItsControls() {
        var config = Config.example
        config.devices[0].rules = nil
        let unknown = Intent.compile(config, paused: false, tapAvailable: true, present: [thisMac[2]]).setup(for: mx.id)
        #expect(unknown.hidpp == nil && unknown.discoverHIDPP)
        let known = Intent.compile(config, paused: false, tapAvailable: true, present: [mx]).setup(for: mx.id)
        #expect(!known.discoverHIDPP, "nothing is left to read")
        let paused = Intent.compile(config, paused: true, tapAvailable: true, present: [thisMac[2]]).setup(for: mx.id)
        #expect(!paused.discoverHIDPP)
    }

    @Test func aLogitechKeyboardWithoutHIDPPRulesIsNotRead() {
        let keys = present(6, Bags.mxKeys)
        var config = Config.example
        config.devices.append(DevicePreset.keyboard.profile(for: DeviceMatch(identifying: keys.properties), name: "MX Keys"))
        let setup = Intent.compile(config, paused: false, tapAvailable: true, present: [keys]).setup(for: keys.id)
        #expect(setup.hidpp == nil && !setup.discoverHIDPP)
    }

    @Test func aScrollRuleDivertsWithRawMovementAndKeepsTheClick() {
        var config = Config.example
        config.devices[0].rules = [
            Rule(control: .hidpp(topButton), trigger: .click, action: shot),
            Rule(control: .hidpp(topButton), trigger: .holdMove(nil), action: .scroll),
        ]
        config.devices[0].scrolling?.holdToScroll = HoldToScroll(speed: 2, direction: .wheel, momentum: false)
        let setup = Intent.compile(config, paused: false, tapAvailable: true, present: [mx]).setup(for: mx.id).hidpp
        guard case .gesture(let plan) = setup?.behavior(of: topButton), case .scroll(let scroll) = plan.moves else {
            Issue.record("the top button scrolls")
            return
        }
        #expect(plan.click == shot)
        #expect(scroll.gain == -2 * HoldScrollPlan.pointsPerCount, "twice the speed, against the hand")
        #expect(scroll.momentum == nil)
        let control = HIDPPCapabilities.Control(cid: topButton, divertable: true, rawXY: true)
        #expect(setup?.behavior(of: topButton).reporting(for: control) == ControlReporting(divert: true, rawXY: true))
    }

    @Test func theGlideAfterAScrollIsTheWheelsGlide() {
        var config = Config.example
        config.devices[0].rules = [Rule(control: .hidpp(topButton), trigger: .holdMove(nil), action: .scroll)]
        config.devices[0].scrolling?.smooth?.duration = 8
        config.devices[0].scrolling?.smooth?.brake = 3
        let setup = Intent.compile(config, paused: false, tapAvailable: true, present: [mx]).setup(for: mx.id).hidpp
        guard case .gesture(let plan) = setup?.behavior(of: topButton), case .scroll(let scroll) = plan.moves else {
            Issue.record("the top button scrolls")
            return
        }
        #expect(scroll.momentum == Glide(seconds: 0.8, brake: 3))
    }

    @Test func aScrollRuleOnAControlWithoutRawMovementIsSkipped() {
        var config = Config.example
        let scroll = Rule(control: .hidpp(topButton), trigger: .holdMove(nil), action: .scroll)
        config.devices[0].rules = [scroll]
        let noRawXY = HIDPPCapabilities(
            controls: [HIDPPCapabilities.Control(cid: topButton, divertable: true, rawXY: false)], thumbWheel: false)
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: [discovered(thisMac[2], noRawXY)])
        #expect(intent.skipped[mx.id] == [scroll])
    }

    @Test func pauseTurnsAWrittenDeviceNative() {
        let paused = Intent.compile(.example, paused: true, tapAvailable: true, present: [mx]).setup(for: mx.id).hidpp
        #expect(HIDPPSetup.pendingWrite(desired: paused, written: true) == .native)
        #expect(HIDPPSetup.pendingWrite(desired: paused, written: false) == nil, "a device never written stays untouched")
        #expect(HIDPPSetup.pendingWrite(desired: presetMX, written: false) == presetMX)
    }
}

@Suite struct PlainButtonIntentTests {
    let mxService = SenderID(rawValue: 0x1_0003_7032)
    let otherService = SenderID(rawValue: 0x1_0003_7099)
    var mx: PresentDevice { present(3, Bags.mxMaster3, services: [mxService.rawValue, otherService.rawValue]) }
    var rightScroll: Config {
        var config = Config.example
        config.devices[0].rules = [Rule(control: .button(1), trigger: .holdMove(nil), action: .scroll)]
        return config
    }

    @Test func aRightButtonScrollRuleIsATapRuleForEachOfTheDevicesSenders() {
        let tap = Intent.compile(rightScroll, paused: false, tapAvailable: true, present: [thisMac[0], mx]).tap
        let expected = ControlBehavior.gesture(
            GesturePlan(
                distance: 120 * HoldScrollPlan.pointsPerCount, click: nil,
                moves: .scroll(HoldScrollPlan(.default, glide: .default, pointsPerUnit: 1))))
        #expect(tap.buttons == [
            ButtonKey(sender: mxService, button: 1): expected, ButtonKey(sender: otherService, button: 1): expected,
        ])
    }

    @Test func theMXPresetScrollsWithItsRightButton() {
        let tap = Intent.compile(.example, paused: false, tapAvailable: true, present: [mx]).tap
        guard case .gesture(let plan) = tap.buttons[ButtonKey(sender: mxService, button: 1)], case .scroll = plan.moves else {
            Issue.record("the right button scrolls")
            return
        }
        #expect(plan.click == nil, "a quick press is the ordinary right click")
    }

    @Test func aPlainButtonClickRuleIsAPress() {
        var config = Config.example
        config.devices[0].rules = [Rule(control: .button(3), trigger: .click, action: .system(.spaceLeft))]
        let tap = Intent.compile(config, paused: false, tapAvailable: true, present: [mx]).tap
        #expect(tap.buttons[ButtonKey(sender: mxService, button: 3)] == .press(.system(.spaceLeft)))
        #expect(!tap.isEmpty, "button rules alone install the tap")
    }

    @Test func noButtonRulesOrNoServiceMeansNoTapRules() {
        var config = rightScroll
        config.devices[0].rules = config.devices[0].rules?.filter { if case .button = $0.control { false } else { true } }
        #expect(Intent.compile(config, paused: false, tapAvailable: true, present: [mx]).tap.buttons.isEmpty)
        #expect(Intent.compile(rightScroll, paused: false, tapAvailable: true, present: [present(3, Bags.mxMaster3)]).tap.buttons.isEmpty)
        #expect(Intent.compile(rightScroll, paused: true, tapAvailable: true, present: [mx]).tap.buttons.isEmpty)
    }
}

@Suite struct DeviceKindTests {
    @Test func theMXSpeaksHIDPPAndIsNotAKeyboard() {
        let mx = HIDProperties(bag: Bags.mxMaster3)
        #expect(mx.speaksHIDPP)
        #expect(!mx.hostsHyper)
        #expect(mx.kind == .mouse)
    }

    @Test func keyboardsHostHyperAndDoNotSpeakHIDPP() {
        for bag in [Bags.builtInKeyboard, Bags.magicKeyboard, Bags.karabinerVirtualKeyboard] {
            let properties = HIDProperties(bag: bag)
            #expect(properties.hostsHyper && !properties.speaksHIDPP, "\(properties.name ?? "")")
            #expect(properties.kind == .keyboard, "\(properties.name ?? "")")
        }
    }

    @Test func aNonLogitechVendorCollectionIsNotHIDPP() {
        var bag = Bags.mxMaster3
        bag["VendorID"] = 0x1EA7
        #expect(!HIDProperties(bag: bag).speaksHIDPP)
    }
}
