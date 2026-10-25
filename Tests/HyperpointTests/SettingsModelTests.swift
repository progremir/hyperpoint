import Foundation
import HyperpointKit
import Testing

@testable import Hyperpoint

@MainActor
@Suite struct SettingsModelTests {
    /// One suite for every run, so the tests leave a single preferences file behind rather than one per run.
    static let suite = "dev.emir.hyperpoint.tests"
    let defaults = UserDefaults(suiteName: suite)!
    let store = ConfigStore(url: FileManager.default.temporaryDirectory.appending(path: "hyperpoint-\(UUID().uuidString)/config.json"))

    func model(_ config: Config = .example, newDevices: [DeviceStatus] = []) -> SettingsModel {
        let model = SettingsModel(store: store, engine: Engine(), defaults: defaults)
        model.show(ConfigSnapshot(config: config, error: nil))
        model.show(
            EngineStatus(
                run: .active, permissions: PermissionState(accessibility: .granted, inputMonitoring: .granted),
                configError: nil, tap: .on, devices: [], newDevices: newDevices, lastReconnect: nil))
        return model
    }

    let usbMouse = DeviceStatus(
        name: "USB Optical Mouse", match: .device(vendor: VendorID(rawValue: 0x1234), product: ProductID(rawValue: 0x1)),
        kind: .mouse, connectedAt: Date(timeIntervalSince1970: 0), hyper: nil)

    @Test func theWindowReopensOnTheLastTab() {
        defaults.removePersistentDomain(forName: Self.suite)
        #expect(model().tab == .general, "a first launch opens on General")
        model().tab = .scrolling
        #expect(model().tab == .scrolling)
        defaults.set("sidebar", forKey: "settingsTab")
        #expect(model().tab == .general, "a tab this version does not have opens General")
    }

    @Test func buttonsAndScrollingShowOneSharedMouse() {
        let model = model(newDevices: [usbMouse])
        #expect(model.mice.map(\.name) == ["MX Master 3", "2.4G Mouse", "USB Optical Mouse"])
        #expect(model.selectedMouse?.match == mx, "the first mouse until one is picked")
        model.mouse = mouse24G
        #expect(model.selectedMouse?.match == mouse24G)
        model.show(ConfigSnapshot(config: SettingsEdit.forget(mouse24G).applied(to: .example), error: nil))
        #expect(model.selectedMouse?.match == mx, "a forgotten mouse that is not connected falls back to the first")
    }

    @Test func anIgnoredDeviceLeavesThePickersButStaysListedAsIgnored() {
        let model = model(newDevices: [usbMouse])
        #expect(model.mice.last?.isNew == true)
        model.show(ConfigSnapshot(config: SettingsEdit.ignore(usbMouse.match, true).applied(to: .example), error: nil))
        #expect(!model.devices.contains { $0.match == usbMouse.match })
        #expect(!model.mice.contains { $0.match == usbMouse.match })
        #expect(model.ignoredDevices == [IgnoredDevice(match: usbMouse.match, name: "USB Optical Mouse")])
    }

    @Test func anIgnoredDeviceNeverSeenIsNamedByItsIds() {
        var config = Config.example
        config.ignored = [karabiner]
        #expect(model(config).ignoredDevices.map(\.name) == ["Vendor 0x05AC, product 0x024F"])
    }
}
