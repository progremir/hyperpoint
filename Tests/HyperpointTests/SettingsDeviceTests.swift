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

    @Test func theSidebarListsProfilesThenNewDevices() {
        let devices = SettingsDevice.all(config: .default, status: status(devices: [connectedMX], newDevices: [virtualKeyboard]))
        #expect(devices.map(\.name) == ["MX Master 3", "2.4G Mouse", "Built-in Keyboard", "Magic Keyboard", "Karabiner VirtualHIDKeyboard"])
        #expect(devices.map(\.kind) == [.mouse, .mouse, .keyboard, .keyboard, .keyboard])
        #expect(devices.map(\.connected) == [true, false, false, false, true])
        #expect(devices.map(\.isNew) == [false, false, false, false, true])
    }

    @Test func aNewDeviceIsListedOnceAfterItGetsAProfile() {
        let config = SettingsEdit.hyperOn(karabiner, name: "Virtual", true).applied(to: .default)
        let devices = SettingsDevice.all(config: config, status: status(devices: [], newDevices: [virtualKeyboard]))
        #expect(devices.filter { $0.match == karabiner }.map(\.isNew) == [false])
    }

    @Test func anIgnoredDeviceIsNotListed() {
        var config = Config.default
        config.ignored = [karabiner]
        #expect(!SettingsDevice.all(config: config, status: status(devices: [], newDevices: [virtualKeyboard])).contains { $0.match == karabiner })
    }

    @Test func theStatusCardSaysHowItConnectsAndWhatWasApplied() {
        let devices = SettingsDevice.all(config: .default, status: status(devices: [connectedMX], newDevices: [virtualKeyboard]))
        #expect(
            devices[0].card(paused: false, time: time)
                == StatusCard(title: "Connected over Bluetooth", detail: "Connected at 15:06. Settings applied at 15:06.", connected: true))
        #expect(devices[1].card(paused: false, time: time).title == "Not connected")
        #expect(
            devices[4].card(paused: false, time: time).detail
                == "First seen at 15:06. Hyperpoint changes nothing on it until you turn on the hyper key for it.")
        #expect(devices[0].card(paused: true, time: time).detail.contains("paused"))
    }

    @Test func theCardCountsSkippedRules() {
        var mxStatus = connectedMX
        mxStatus.hidpp?.skippedRules = [Rule(control: .hidpp(CID(rawValue: 0x99)), trigger: .click, action: .system(.appExpose))]
        let device = SettingsDevice.all(config: .default, status: status(devices: [mxStatus]))[0]
        #expect(device.card(paused: false, time: time).detail.hasSuffix("1 rule is skipped because this mouse cannot do it."))
    }

    @Test func onlyLogitechDevicesGetHIDPPControls() {
        let devices = SettingsDevice.all(config: .default, status: nil)
        #expect(devices.map(\.speaksHIDPP) == [true, false, false, false])
    }
}
