@testable import HyperpointKit
import Testing

@Suite struct DeviceMatchTests {
    @Test func defaultProfilesClassifyThisMacsKeyboards() {
        let names = [
            Bags.builtInKeyboard, Bags.builtInKeyboardAsListed, Bags.magicKeyboard, Bags.mxMaster3,
            Bags.karabinerVirtualKeyboard,
        ].map { Config.default.profile(for: HIDProperties(bag: $0))?.name }
        #expect(names == ["Built-in Keyboard", "Built-in Keyboard", "Magic Keyboard", "MX Master 3", nil])
    }

    @Test func builtInIsTheAuthorityNotVendorZero() {
        let builtIn = HIDProperties(bag: Bags.builtInKeyboardAsListed)
        #expect(!DeviceMatch.device(vendor: VendorID(rawValue: 0), product: ProductID(rawValue: 0)).matches(builtIn))
        #expect(!DeviceMatch.builtIn.matches(HIDProperties(bag: Bags.magicKeyboard)))
    }

    @Test func ignoredDeviceHasNoProfile() {
        var config = Config.default
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
        let intent = Intent.compile(.default, paused: false, tapAvailable: true, present: thisMac)
        #expect(thisMac.map { intent.setup(for: $0.id).keyMap } == [hyperMap, hyperMap, .neutral, .neutral])
        #expect(intent.tap == TapRules(carriers: [Carrier.hyper.keyCode: .holdModifiers(.hyper)]))
    }

    @Test func pausedIsNeutralEverywhere() {
        let intent = Intent.compile(.default, paused: true, tapAvailable: true, present: thisMac)
        #expect(thisMac.allSatisfy { intent.setup(for: $0.id) == .neutral })
        #expect(intent.tap.isEmpty)
    }

    @Test func withoutTheTapNoKeyBecomesACarrier() {
        let intent = Intent.compile(.default, paused: false, tapAvailable: false, present: thisMac)
        #expect(thisMac.allSatisfy { intent.setup(for: $0.id).keyMap == .neutral })
        #expect(intent.tap.isEmpty)
    }

    @Test func hyperOffLeavesTheKeyboardNeutral() {
        var config = Config.default
        config.devices[3].hyper = false
        config.devices[2].hyper = nil
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(thisMac.allSatisfy { intent.setup(for: $0.id).keyMap == .neutral })
        #expect(intent.tap.isEmpty)
    }

    @Test func theMXIsNotAHyperKeyboard() {
        var config = Config.default
        config.devices[0].hyper = true
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(intent.setup(for: thisMac[2].id).keyMap == .neutral, "its keyboard collection does not make it one")
        #expect(intent.setup(for: thisMac[1].id).keyMap == hyperMap)
    }

    @Test func theConfiguredKeyIsTheSource() {
        var config = Config.default
        config.hyper.key = HIDUsage(name: "grave")!
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(intent.setup(for: thisMac[1].id).keyMap.pairs == [.init(source: 0x7_0000_0035, destination: 0x7_0000_006D)])
    }

    @Test func carrierAssignmentDoesNotDependOnDeviceOrder() {
        let forward = Intent.compile(.default, paused: false, tapAvailable: true, present: thisMac)
        let reversed = Intent.compile(.default, paused: false, tapAvailable: true, present: thisMac.reversed())
        let onlyMagic = Intent.compile(.default, paused: false, tapAvailable: true, present: [thisMac[1]])
        #expect(forward == reversed)
        #expect(onlyMagic.setup(for: thisMac[1].id) == forward.setup(for: thisMac[1].id))
        #expect(onlyMagic.tap == forward.tap)
    }
}

@Suite struct HIDPPIntentTests {
    let mx = discovered(thisMac[2])
    let shot = Action.shortcut(Chord(key: KeyCode(name: "4")!, modifiers: [.shift, .command]))

    var defaultMX: HIDPPSetup {
        HIDPPSetup(
            controls: [
                gestureButton: .gesture(
                    GesturePlan(
                        fire: .pastDistance, distance: 120, click: .system(.missionControl),
                        swipes: [.down: .system(.appExpose), .left: .system(.spaceLeft), .right: .system(.spaceRight)])),
                topButton: .press(shot),
            ],
            thumbWheelInverted: true)
    }

    @Test func theDefaultConfigReproducesBetterMouse() {
        let intent = Intent.compile(.default, paused: false, tapAvailable: true, present: [thisMac[0], thisMac[1], mx])
        #expect(intent.setup(for: mx.id).hidpp == defaultMX)
        #expect(intent.skipped.isEmpty)
        #expect(intent.setup(for: thisMac[0].id).hidpp == nil, "keyboards do not speak HID++")
        #expect(intent.setup(for: thisMac[1].id).hidpp == nil)
    }

    @Test func theFirmwareFlagsFollowTheBehavior() {
        let control = HIDPPCapabilities.Control(cid: gestureButton, divertable: true, rawXY: true)
        #expect(defaultMX.behavior(of: gestureButton).reporting(for: control).writeFlags == 0x33)
        #expect(defaultMX.behavior(of: topButton).reporting(for: control).writeFlags == 0x23)
        #expect(defaultMX.behavior(of: CID(rawValue: 0x52)).reporting(for: control).writeFlags == 0x22, "no rule is native")
        let noRawXY = HIDPPCapabilities.Control(cid: gestureButton, divertable: true, rawXY: false)
        #expect(defaultMX.behavior(of: gestureButton).reporting(for: noRawXY).writeFlags == 0x23)
    }

    @Test func beforeDiscoveryTheRulesCompileUnfiltered() {
        let intent = Intent.compile(.default, paused: false, tapAvailable: true, present: [thisMac[2]])
        #expect(intent.setup(for: mx.id).hidpp == defaultMX)
    }

    @Test func rulesOnControlsTheDeviceLacksAreSkipped() throws {
        var config = Config.default
        let absent = Rule(control: .hidpp(CID(rawValue: 0x1A0)), trigger: .click, action: .system(.spaceLeft))
        let leftButton = Rule(control: .hidpp(CID(rawValue: 0x50)), trigger: .click, action: .system(.spaceRight))
        config.devices[0].rules = [absent, leftButton] + (config.devices[0].rules ?? [])
        let noWheel = HIDPPCapabilities(controls: measuredMXCapabilities.controls, thumbWheel: false)

        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: [discovered(thisMac[2], noWheel)])

        let wheel = try #require(config.devices[0].rules?.last)
        #expect(intent.skipped[mx.id] == [absent, leftButton, wheel])
        var expected = defaultMX
        expected.thumbWheelInverted = false
        #expect(intent.setup(for: mx.id).hidpp == expected, "the rules the device can carry out still apply")
    }

    @Test func aClickWithoutHoldMoveIsAPress() {
        var config = Config.default
        config.devices[0].rules = config.devices[0].rules?.filter { $0.trigger == .click }
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: [mx])
        #expect(
            intent.setup(for: mx.id).hidpp
                == HIDPPSetup(controls: [gestureButton: .press(.system(.missionControl)), topButton: .press(shot)], thumbWheelInverted: false))
    }

    @Test func gestureSettingsComeFromTheProfile() {
        var config = Config.default
        config.devices[0].gestures = GestureSettings(fire: .onRelease, distance: 300)
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: [mx])
        guard case .gesture(let plan) = intent.setup(for: mx.id).hidpp?.behavior(of: gestureButton) else {
            Issue.record("the gesture button is a gesture")
            return
        }
        #expect(plan.fire == .onRelease && plan.distance == 300)
    }

    @Test func aProfileWithoutButtonRulesLeavesTheDeviceAlone() {
        var config = Config.default
        config.devices[0].rules = nil
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: [mx])
        #expect(intent.setup(for: mx.id).hidpp == nil)
    }

    @Test func pauseTurnsAnOpenedDeviceNative() {
        let paused = Intent.compile(.default, paused: true, tapAvailable: true, present: [mx]).setup(for: mx.id).hidpp
        #expect(HIDPPSetup.pendingWrite(desired: paused, opened: true) == .native)
        #expect(HIDPPSetup.pendingWrite(desired: paused, opened: false) == nil, "a device never opened stays untouched")
        #expect(HIDPPSetup.pendingWrite(desired: defaultMX, opened: false) == defaultMX)
    }
}

@Suite struct DeviceKindTests {
    @Test func theMXSpeaksHIDPPAndIsNotAKeyboard() {
        let mx = HIDProperties(bag: Bags.mxMaster3)
        #expect(mx.speaksHIDPP)
        #expect(!mx.hostsHyper)
    }

    @Test func keyboardsHostHyperAndDoNotSpeakHIDPP() {
        for bag in [Bags.builtInKeyboard, Bags.magicKeyboard, Bags.karabinerVirtualKeyboard] {
            let properties = HIDProperties(bag: bag)
            #expect(properties.hostsHyper && !properties.speaksHIDPP, "\(properties.name ?? "")")
        }
    }

    @Test func aNonLogitechVendorCollectionIsNotHIDPP() {
        var bag = Bags.mxMaster3
        bag["VendorID"] = 0x1EA7
        #expect(!HIDProperties(bag: bag).speaksHIDPP)
    }
}
