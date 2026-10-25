import Foundation
import HyperpointKit
import Testing

@testable import Hyperpoint

@Suite struct SettingsDeviceTests {
    let at = Date(timeIntervalSince1970: 0)
    func time(_ date: Date) -> String { date == at ? "15:06" : "?" }

    func status(devices: [DeviceStatus], newDevices: [DeviceStatus] = [], paused: Bool = false) -> EngineStatus {
        EngineStatus(
            run: paused ? .paused : .active,
            permissions: PermissionState(accessibility: .granted, inputMonitoring: .granted), configError: nil, tap: .on,
            devices: devices, newDevices: newDevices, lastReconnect: nil)
    }

    var connectedMX: DeviceStatus {
        DeviceStatus(
            name: "MX Master 3", match: mx, kind: .mouse, transport: "Bluetooth Low Energy", connectedAt: at, hyper: nil,
            hidpp: HIDPPStatus(progress: .setUp, lastApply: at, capabilities: mxCapabilities, skippedRules: []))
    }

    var virtualKeyboard: DeviceStatus {
        DeviceStatus(name: "Karabiner VirtualHIDKeyboard", match: karabiner, kind: .keyboard, connectedAt: at, hyper: nil)
    }

    @Test func theWindowListsProfilesThenNewDevices() {
        let devices = SettingsDevice.all(config: .example, status: status(devices: [connectedMX], newDevices: [virtualKeyboard]))
        #expect(devices.map(\.name) == ["MX Master 3", "2.4G Mouse", "Built-in Keyboard", "Magic Keyboard", "Karabiner VirtualHIDKeyboard"])
        #expect(devices.map(\.kind) == [.mouse, .mouse, .keyboard, .keyboard, .keyboard])
        #expect(devices.map(\.connected) == [true, false, false, false, true])
        #expect(devices.map(\.isNew) == [false, false, false, false, true])
    }

    @Test func aChosenKindWinsOverWhatTheDeviceSays() {
        var config = Config.example
        let connected24G = DeviceStatus(
            name: "2.4G Mouse", match: mouse24G, kind: .keyboard, transport: "USB", connectedAt: at, hyper: nil)
        func kind() -> DeviceKind? {
            SettingsDevice.all(config: config, status: status(devices: [connected24G])).first { $0.match == mouse24G }?.kind
        }
        #expect(kind() == .mouse, "the preset chose mouse")
        config.devices[1].kind = nil
        #expect(kind() == .keyboard, "without a choice the connected device decides")
        config.devices[3].kind = .mouse
        #expect(SettingsDevice.all(config: config, status: nil).first { $0.match == magicKeyboard }?.kind == .mouse)
    }

    @Test func aNewDeviceIsListedOnceAfterItGetsAProfile() {
        let config = SettingsEdit.addDevice(karabiner, name: "Virtual", .preset(.keyboard)).applied(to: .example)
        let devices = SettingsDevice.all(config: config, status: status(devices: [], newDevices: [virtualKeyboard]))
        #expect(devices.filter { $0.match == karabiner }.map(\.isNew) == [false])
    }

    @Test func anIgnoredDeviceIsNotListed() {
        var config = Config.example
        config.ignored = [karabiner]
        #expect(!SettingsDevice.all(config: config, status: status(devices: [], newDevices: [virtualKeyboard])).contains { $0.match == karabiner })
    }

    @Test func theStatusCardSaysHowItConnectsAndWhatWasApplied() {
        let devices = SettingsDevice.all(config: .example, status: status(devices: [connectedMX], newDevices: [virtualKeyboard]))
        #expect(
            devices[0].card(paused: false, time: time)
                == StatusCard(title: "Connected over Bluetooth", detail: "Connected at 15:06. Settings applied at 15:06.", connected: true))
        #expect(devices[1].card(paused: false, time: time).title == "Not connected")
        #expect(
            devices[4].card(paused: false, time: time).detail
                == "First seen at 15:06. Hyperpoint changes nothing on it until you set it up.")
        #expect(devices[0].card(paused: true, time: time).detail.contains("paused"))
    }

    @Test func theCardCountsSkippedRules() {
        var mxStatus = connectedMX
        mxStatus.hidpp?.skippedRules = [Rule(control: .hidpp(CID(rawValue: 0x99)), trigger: .click, action: .system(.appExpose))]
        let device = SettingsDevice.all(config: .example, status: status(devices: [mxStatus]))[0]
        #expect(device.card(paused: false, time: time).detail.hasSuffix("1 rule is skipped because this mouse cannot do it."))
    }

    @Test func onlyLogitechDevicesGetHIDPPControls() {
        let devices = SettingsDevice.all(config: .example, status: nil)
        #expect(devices.map(\.speaksHIDPP) == [true, false, false, false])
    }
}
