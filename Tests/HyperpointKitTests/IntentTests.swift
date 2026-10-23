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
        #expect(thisMac.allSatisfy { intent.setup(for: $0.id) == .neutral })
        #expect(intent.tap.isEmpty)
    }

    @Test func hyperOffLeavesTheKeyboardNeutral() {
        var config = Config.default
        config.devices[3].hyper = false
        config.devices[2].hyper = nil
        let intent = Intent.compile(config, paused: false, tapAvailable: true, present: thisMac)
        #expect(thisMac.allSatisfy { intent.setup(for: $0.id) == .neutral })
        #expect(intent.tap.isEmpty)
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
