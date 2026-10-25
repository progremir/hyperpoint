import HyperpointKit
import Testing

private let mx = DeviceMatch.device(vendor: .logitech, product: ProductID(rawValue: 0xB023))
private let mouse24G = DeviceMatch.device(vendor: VendorID(rawValue: 0x1EA7), product: ProductID(rawValue: 0x0002))
private let magicKeyboard = DeviceMatch.device(vendor: VendorID(rawValue: 0x004C), product: ProductID(rawValue: 0x0321))
private let unknown = DeviceMatch.device(vendor: VendorID(rawValue: 0x1234), product: ProductID(rawValue: 0x0001))
private let everyMatch = [mx, mouse24G, magicKeyboard, .builtIn, unknown]

@Suite struct PresetTests {
    @Test func aDeviceIsOfferedThePresetMadeForItFirst() {
        #expect(DevicePreset.offered(for: mx, kind: .mouse) == [.mxMaster3])
        #expect(DevicePreset.offered(for: mouse24G, kind: .mouse) == [.mouse24G])
        #expect(DevicePreset.offered(for: mouse24G, kind: .keyboard) == [.mouse24G, .keyboard], "its own, even as a keyboard")
        #expect(DevicePreset.offered(for: magicKeyboard, kind: .keyboard) == [.keyboard])
        #expect(DevicePreset.offered(for: .builtIn, kind: .keyboard) == [.keyboard])
        #expect(DevicePreset.offered(for: unknown, kind: .keyboard) == [.keyboard])
        #expect(DevicePreset.offered(for: unknown, kind: .mouse) == [], "no preset for a mouse nobody measured")
    }

    @Test func aModelPresetGoesOnlyOnItsOwnModel() {
        #expect(everyMatch.filter { !DevicePreset.mxMaster3.isForAnotherModel(than: $0) } == [mx])
        #expect(everyMatch.filter { !DevicePreset.mouse24G.isForAnotherModel(than: $0) } == [mouse24G])
        #expect(everyMatch.filter { !DevicePreset.keyboard.isForAnotherModel(than: $0) } == everyMatch)
    }

    @Test(arguments: DevicePreset.allCases)
    func aPresetSavesAsAProfileForTheDeviceItIsAppliedTo(_ preset: DevicePreset) throws {
        for match in everyMatch where !preset.isForAnotherModel(than: match) {
            let profile = preset.profile(for: match, name: "My Device")
            #expect(profile.match == match)
            #expect(profile.name == "My Device")
            var config = Config.empty
            config.devices = [profile]
            #expect(try ConfigCodec.decode(ConfigCodec.encode(config)) == config)
        }
    }
}
