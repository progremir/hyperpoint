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

    @Test func aMouseMapWithACarrierIsClearedWhole() {
        let returnToF13 = KeyMapSetup.Pair(source: 0x7_0000_0028, destination: 0x7_0000_0068)
        let written = KeyMapSetup.hyperpointLeftover(in: [escapeToRightOption, returnToF13])
        #expect(KeyMapSetup.pendingWrite(desired: .neutral, written: written) == .neutral, "the write replaces both pairs")
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

    @Test func theHyperSwitchTurnsItOffOnEveryKeyboardAndBackOn() {
        var config = Config.example
        config.hyper.enabled = false
        let off = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(thisMac.allSatisfy { off.setup(for: $0.id).keyMap == .neutral })
        #expect(off.tap.isEmpty)

        config.hyper.enabled = true
        let on = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(thisMac.map { on.setup(for: $0.id).keyMap } == [hyperMap, hyperMap, .neutral, .neutral])
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

    @Test func theBuiltInKeyboardKeepsItsHyperKeyWhicheverInterfaceComesFirst() {
        let keyboardService = SenderID(rawValue: 0x1_0000_0CD0)
        let trackpadService = SenderID(rawValue: 0x1_0000_0D10)
        let keyboard = (UInt64(0xCC7), HIDProperties(bag: Bags.builtInKeyboard), keyboardService)
        let trackpad = (UInt64(0xD09), HIDProperties(bag: Bags.builtInTrackpad), trackpadService)
        var config = Config.example
        config.devices[2].scrolling = ScrollSettings(smooth: .default)
        for interfaces in [[trackpad, keyboard], [keyboard, trackpad]] {
            var roster = DeviceRoster()
            for (interface, properties, service) in interfaces {
                _ = roster.interfaceAppeared(interface, properties: properties, services: [service])
            }
            let intent = Intent.compile(config, paused: false, tapAvailable: true, present: roster.devices)
            #expect(roster.devices.map { intent.setup(for: $0.id).keyMap } == [hyperMap])
            #expect(intent.tap.smoothScroll.map(\.key) == [keyboardService], "never the trackpad")
        }
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

    @Test func pauseTurnsAnOpenedDeviceNative() {
        let paused = Intent.compile(.example, paused: true, tapAvailable: true, present: [mx]).setup(for: mx.id).hidpp
        #expect(HIDPPSetup.pendingWrite(desired: paused, opened: true) == .native)
        #expect(HIDPPSetup.pendingWrite(desired: paused, opened: false) == nil, "a device never opened stays untouched")
        #expect(HIDPPSetup.pendingWrite(desired: presetMX, opened: false) == presetMX)
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

@Suite struct PlainMouseIntentTests {
    let service = SenderID(rawValue: 0x1_0004_1000)
    var mouse: PresentDevice { present(5, Bags.plainMouse, services: [service.rawValue]) }
    var config: Config {
        var config = Config.example
        config.devices.append(
            DeviceProfile(
                match: DeviceMatch(identifying: HIDProperties(bag: Bags.plainMouse)), name: "USB Optical Mouse",
                rules: [
                    Rule(control: .button(1), trigger: .holdMove(nil), action: .scroll),
                    Rule(control: .button(3), trigger: .click, action: .system(.missionControl)),
                ],
                scrolling: ScrollSettings(smooth: .default, holdToScroll: .default)))
        return config
    }

    @Test func aSetUpPlainMouseScrollsSmoothlyAndHoldsToScrollByItsSender() {
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac + [mouse])
        #expect(intent.tap.smoothScroll == [service: .default])
        let rightButton = intent.tap.buttons[ButtonKey(sender: service, button: 1)]
        guard case .gesture(let plan) = rightButton, case .scroll = plan.moves else {
            Issue.record("holding the right button scrolls")
            return
        }
        #expect(intent.tap.buttons[ButtonKey(sender: service, button: 3)] == .press(.system(.missionControl)))
        #expect(intent.setup(for: mouse.id) == .neutral, "no key map and no HID++ to write")
    }

    @Test func aNewPlainMouseIsLeftAlone() {
        let intent = Intent.compile(.example, paused: false, tapAvailable: true, present: thisMac + [mouse])
        #expect(Config.example.profile(for: mouse.properties) == nil)
        #expect(intent.tap.smoothScroll.isEmpty && intent.tap.buttons.isEmpty)
    }
}

@Suite struct KeyRuleIntentTests {
    static let escape = HIDUsage(name: "escape")!
    static let enter = HIDUsage(name: "return")!
    static let optShiftS = Action.shortcut(Chord(key: KeyCode(name: "s")!, modifiers: [.option, .shift]))

    let keysService: UInt64 = 0x1_0005_2151
    let pointerService: UInt64 = 0x1_0005_214E
    var mouse: PresentDevice { present(6, Bags.mouse24GKeys, services: [pointerService, keysService]) }
    var presetMap: KeyMapSetup {
        KeyMapSetup(routes: [
            KeyRoute(source: Self.escape, target: .native(HeldModifier.rightOption.usage)),
            KeyRoute(source: Self.enter, target: .carrier(.f13, .press(Self.optShiftS))),
        ])
    }

    func compile(_ present: [PresentDevice], config: Config = .example, tapAvailable: Bool = true) -> Intent {
        Intent.compile(config, paused: false, tapAvailable: tapAvailable, present: present)
    }

    @Test func the24GPresetHoldsRightOptionAtTheHIDLayerAndClicksThroughACarrier() {
        let intent = compile(thisMac + [mouse])
        #expect(intent.setup(for: mouse.id) == DeviceSetup(keyMap: presetMap, hidpp: nil))
        #expect(intent.skipped.isEmpty)
        #expect(
            intent.setup(for: mouse.id).keyMap.pairs == [
                KeyMapSetup.Pair(source: 0x7_0000_0029, destination: 0x7_0000_00E6),
                KeyMapSetup.Pair(source: 0x7_0000_0028, destination: 0x7_0000_0068),
            ])
        #expect(
            intent.tap.carriers == [
                Carrier.hyper.keyCode: CarrierMeaning.holdModifiers(.hyper), Carrier.f13.keyCode: .press(Self.optShiftS),
            ],
            "Right Option needs no tap rule")
    }

    @Test func theModifiersAreTheKeyboardPagesLastEight() {
        #expect(HeldModifier.allCases.map(\.usage.rawValue) == Array(0xE0...0xE7))
        #expect(HeldModifier.rightOption.usage.rawValue == 0xE6)
    }

    @Test func the24GMapIsTheSameWhicheverInterfaceComesFirst() {
        let keys = (UInt64(0x2150), HIDProperties(bag: Bags.mouse24GKeys), SenderID(rawValue: keysService))
        let pointer = (UInt64(0x214D), HIDProperties(bag: Bags.mouse24GPointer), SenderID(rawValue: pointerService))
        for interfaces in [[pointer, keys], [keys, pointer]] {
            var roster = DeviceRoster()
            for (interface, properties, service) in interfaces {
                _ = roster.interfaceAppeared(interface, properties: properties, services: [service])
            }
            let intent = compile(roster.devices)
            #expect(roster.devices.map { intent.setup(for: $0.id).keyMap } == [presetMap])
        }
    }

    @Test func withoutTheTapEscapeStillHoldsRightOptionAndReturnStaysReturn() {
        let intent = compile([mouse], tapAvailable: false)
        #expect(intent.setup(for: mouse.id).keyMap == KeyMapSetup(routes: [presetMap.routes[0]]))
        #expect(intent.tap.isEmpty)
        #expect(intent.skipped.isEmpty, "the rule comes back with the tap, so it is not skipped")
    }

    @Test func pausedClearsTheMouseMap() {
        let intent = Intent.compile(.example, paused: true, tapAvailable: true, present: [mouse])
        #expect(intent.setup(for: mouse.id) == .neutral)
    }

    @Test func aClickCarrierDependsOnTheFileNotOnWhatIsConnected() {
        let alone = compile([mouse])
        #expect(alone.setup(for: mouse.id) == compile(thisMac + [mouse]).setup(for: mouse.id))
        #expect(alone.setup(for: mouse.id) == compile([mouse] + thisMac.reversed()).setup(for: mouse.id))
        #expect(alone.tap.carriers == [Carrier.f13.keyCode: .press(Self.optShiftS)])
    }

    @Test func keyRulesShareACarrierPerActionAndNeverTakeHypers() {
        var config = Config.example
        let other = DeviceMatch(identifying: HIDProperties(bag: Bags.magicKeyboard))
        let clicks = ["f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8"].map {
            Rule(
                control: .key(HIDUsage(name: $0)!), trigger: .click,
                action: .shortcut(Chord(key: KeyCode(name: $0)!, modifiers: [.command])))
        }
        config.devices[3] = DeviceProfile(
            match: other, name: "Magic Keyboard",
            rules: [Rule(control: .key(Self.escape), trigger: .click, action: Self.optShiftS)] + clicks, hyper: true)
        let magic = thisMac[1]
        let intent = compile([mouse, magic], config: config)
        let routes = intent.setup(for: magic.id).keyMap.routes
        #expect(routes.first == .hyper(from: capsLock))
        let carriers = routes.dropFirst().map(\.destination)
        #expect(carriers.first == Carrier.f13.usage, "the same action as the mouse's Return")
        #expect(!carriers.contains(Carrier.hyper.usage), "F18 is hyper's alone")
        #expect(Set(carriers).count == carriers.count)
        #expect(intent.skipped[magic.id] == [clicks[6], clicks[7]], "seven carriers, the first for opt+shift+s")
    }

    @Test func aKeyRuleOnTheHyperKeyIsSkipped() {
        var config = Config.example
        let rule = Rule(control: .key(capsLock), trigger: .hold, action: .modifier(.leftControl))
        config.devices[3].rules = [rule]
        let intent = compile([thisMac[1]], config: config)
        #expect(intent.setup(for: thisMac[1].id).keyMap == KeyMapSetup(routes: [.hyper(from: capsLock)]))
        #expect(intent.skipped[thisMac[1].id] == [rule])
    }

    @Test func keyRulesOnAMouseWithoutKeysAreSkipped() {
        var config = Config.example
        let rules = DevicePreset.mouse24G.profile(for: .builtIn, name: "").rules!
        config.devices.append(
            DeviceProfile(
                match: DeviceMatch(identifying: HIDProperties(bag: Bags.plainMouse)), name: "USB Optical Mouse",
                rules: rules))
        let plain = present(5, Bags.plainMouse, services: [0x1_0004_1000])
        let intent = compile([plain], config: config)
        #expect(intent.setup(for: plain.id) == .neutral)
        #expect(intent.skipped[plain.id] == rules)
    }
}

@Suite struct ChosenKindIntentTests {
    let hyperMap = KeyMapSetup(routes: [.hyper(from: capsLock)])

    @Test func aDeviceChosenAsAKeyboardHostsHyperOnItsKeys() {
        var config = Config.example
        config.devices[0].kind = .keyboard
        config.devices[0].hyper = true
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(intent.setup(for: thisMac[2].id).keyMap == hyperMap, "the MX's keyboard collection takes the map")
    }

    @Test func aKeyboardChosenAsAMouseHasNoHyper() {
        var config = Config.example
        config.devices[3].kind = .mouse
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(intent.setup(for: thisMac[1].id).keyMap == .neutral)
        #expect(intent.setup(for: thisMac[0].id).keyMap == hyperMap, "the other keyboard keeps it")
    }

    @Test func aMouseWithoutKeysHasNoHyperEvenAsAKeyboard() {
        var config = Config.example
        let mouse = present(5, Bags.plainMouse)
        config.devices.append(
            DeviceProfile(
                match: DeviceMatch(identifying: mouse.properties), name: "USB Optical Mouse", kind: .keyboard, hyper: true))
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: [mouse])
        #expect(intent.setup(for: mouse.id).keyMap == .neutral, "no keyboard collection to map")
    }
}

@Suite struct DeviceKindTests {
    @Test func aChosenKindOverridesTheInterfaces() {
        let keys = HIDProperties(bag: Bags.mouse24GKeys)
        let match = DeviceMatch(identifying: keys)
        #expect(DeviceProfile(match: match, name: "2.4G Mouse").kind(of: keys) == .keyboard, "its keys decide")
        #expect(DeviceProfile(match: match, name: "2.4G Mouse", kind: .mouse).kind(of: keys) == .mouse)
        let builtIn = HIDProperties(bag: Bags.builtInKeyboard)
        #expect(DeviceProfile(match: .builtIn, name: "Built-in", kind: .mouse).kind(of: builtIn) == .mouse)
    }

    @Test func aPlainMouseIsAMouseThatSpeaksNoHIDPP() {
        let mouse = HIDProperties(bag: Bags.plainMouse)
        #expect(mouse.kind == .mouse && !mouse.hostsHyper && !mouse.speaksHIDPP && !mouse.isTrackpad)
    }

    @Test func onlyTheTrackpadIsATrackpad() {
        #expect(HIDProperties(bag: Bags.builtInTrackpad).isTrackpad)
        for bag in [Bags.builtInKeyboard, Bags.magicKeyboard, Bags.mxMaster3, Bags.plainMouse] {
            #expect(!HIDProperties(bag: bag).isTrackpad)
        }
    }

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
