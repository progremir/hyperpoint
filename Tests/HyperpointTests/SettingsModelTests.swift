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

    func model(_ config: Config = .example, devices: [DeviceStatus] = [], newDevices: [DeviceStatus] = []) -> SettingsModel {
        let model = SettingsModel(store: store, engine: Engine(), defaults: defaults)
        model.show(ConfigSnapshot(config: config, error: nil))
        model.show(
            EngineStatus(
                run: .active, permissions: PermissionState(accessibility: .granted, inputMonitoring: .granted),
                configError: nil, tap: .on, devices: devices, newDevices: newDevices, lastReconnect: nil))
        return model
    }

    let connectedMX = DeviceStatus(
        name: "MX Master 3", match: mx, kind: .mouse, connectedAt: Date(timeIntervalSince1970: 0), hyper: nil,
        hidpp: HIDPPStatus(progress: .setUp, lastApply: nil, capabilities: mxCapabilities, skippedRules: []))

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

    @Test(.timeLimit(.minutes(1))) func aHeardPressAddsExactlyOneRule() async throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ConfigCodec.encode(.example).write(to: store.url)
        var saved = await store.snapshots().makeAsyncIterator()
        let model = model(devices: [connectedMX])
        model.learned(LearnedPress(match: mx, heard: .unnamed))
        #expect(model.learnNote == .unnamed(mx))
        model.learned(LearnedPress(match: mx, heard: .control(.thumbWheel)))
        #expect(model.learnNote == .full(mx, .thumbWheel))
        model.learned(LearnedPress(match: mx, heard: .control(.button(3))))
        let back = Rule(control: .hidpp(CID(rawValue: 0x53)), trigger: .click, action: .system(.missionControl))
        #expect(model.learnNote == .added(mx, RuleKey(back)))
        let first = await saved.next()
        #expect(
            first?.config.flatMap { profile($0, mx) }?.rules == profile(.example, mx)!.rules! + [back],
            "the first save is the one rule, so the presses before it saved nothing")
    }

    @Test func switchingTheMouseClearsTheNote() {
        let model = model(devices: [connectedMX])
        model.learned(LearnedPress(match: mx, heard: .unnamed))
        model.mouse = mouse24G
        #expect(model.learnNote == nil)
    }
}
