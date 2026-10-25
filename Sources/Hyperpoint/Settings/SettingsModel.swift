import AppKit
import HyperpointKit
import Observation
import OSLog
import ServiceManagement

enum LoginItemState: Equatable {
    case on
    case off
    case needsApproval
}

/// The window's tabs, in toolbar order.
enum SettingsTab: String, CaseIterable {
    case general, hyperKey, buttons, scrolling, devices

    var title: String {
        switch self {
        case .general: "General"
        case .hyperKey: "Hyper Key"
        case .buttons: "Buttons"
        case .scrolling: "Scrolling"
        case .devices: "Devices"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .hyperKey: "command"
        case .buttons: "computermouse"
        case .scrolling: "arrow.up.and.down"
        case .devices: "list.bullet"
        }
    }
}

/// What the settings window renders: the latest config snapshot and engine status, as published. It never holds
/// config of its own. Edits go to `ConfigStore.update` one at a time, and the window redraws from the snapshot the
/// save publishes.
@MainActor
@Observable
final class SettingsModel {
    private(set) var snapshot: ConfigSnapshot?
    private(set) var status: EngineStatus?
    private(set) var loadedAt: Date?
    private(set) var saveError: String?
    private(set) var loginItem = LoginItemState.off
    private(set) var loginItemError: String?
    /// Remembered across launches, so the window opens where the user left it.
    var tab: SettingsTab { didSet { defaults.set(tab.rawValue, forKey: Self.tabKey) } }
    /// The mouse the Buttons and Scrolling tabs both show. Nil, or a mouse no longer listed, means the first one.
    var mouse: DeviceMatch?

    let configURL: URL
    private let engine: Engine
    private let edits: AsyncStream<SettingsEdit>.Continuation
    private let log = Logger(subsystem: "dev.emir.hyperpoint", category: "settings")
    private let defaults: UserDefaults
    private static let tabKey = "settingsTab"
    /// Switching smooth scrolling off removes its section from the file, so the values tuned before are kept here
    /// and come back when it is switched on again.
    @ObservationIgnored private var lastSmooth: [DeviceMatch: SmoothScroll] = [:]
    /// Discovery runs again on every connection, so the rule pickers keep a mouse's controls while it is away.
    @ObservationIgnored private var seenCapabilities: [DeviceMatch: HIDPPCapabilities] = [:]
    /// The engine leaves ignored devices out of its status, so their names come from when they showed as new.
    @ObservationIgnored private var seenNames: [DeviceMatch: String] = [:]

    init(store: ConfigStore, engine: Engine, defaults: UserDefaults = .standard) {
        configURL = store.url
        self.engine = engine
        self.defaults = defaults
        tab = defaults.string(forKey: Self.tabKey).flatMap(SettingsTab.init(rawValue:)) ?? .general
        let (stream, continuation) = AsyncStream.makeStream(of: SettingsEdit.self)
        edits = continuation
        Task { [weak self] in
            for await edit in stream {
                do {
                    try await store.update { edit.applied(to: $0) }
                    self?.saved(edit)
                } catch {
                    self?.failed(edit, error)
                }
            }
        }
        refreshLoginItem()
    }

    var config: Config? { snapshot?.config }

    /// The window is read-only while the file is invalid, so a hand edit in progress is never overwritten.
    var editable: Bool { snapshot?.config != nil && snapshot?.error == nil }

    var paused: Bool { status?.run == .paused }

    var devices: [SettingsDevice] { SettingsDevice.all(config: config, status: status) }

    var mice: [SettingsDevice] { devices.filter { $0.kind == .mouse } }

    var selectedMouse: SettingsDevice? { mice.first { $0.match == mouse } ?? mice.first }

    var ignoredDevices: [IgnoredDevice] {
        (config?.ignored ?? []).map { IgnoredDevice(match: $0, name: seenNames[$0] ?? Labels.match($0)) }
    }

    func show(_ snapshot: ConfigSnapshot) {
        self.snapshot = snapshot
        guard let config = snapshot.config, snapshot.error == nil else { return }
        loadedAt = Date()
        for profile in config.devices {
            guard let smooth = profile.scrolling?.smooth else { continue }
            lastSmooth[profile.match] = smooth
        }
    }

    func show(_ status: EngineStatus) {
        self.status = status
        for device in status.devices {
            if let capabilities = device.hidpp?.capabilities { seenCapabilities[device.match] = capabilities }
        }
        for device in status.newDevices { seenNames[device.match] = device.name }
    }

    func choices(for device: SettingsDevice) -> RuleChoices {
        RuleChoices(
            rules: device.profile?.rules ?? [],
            capabilities: device.status?.hidpp?.capabilities ?? seenCapabilities[device.match],
            speaksHIDPP: device.speaksHIDPP)
    }

    func apply(_ edit: SettingsEdit) {
        guard editable else { return }
        edits.yield(edit)
    }

    func smoothWhenOn(_ match: DeviceMatch) -> SmoothScroll { lastSmooth[match] ?? .default }

    private func saved(_ edit: SettingsEdit) {
        saveError = nil
        log.notice("saved \(edit.logDescription, privacy: .public)")
    }

    private func failed(_ edit: SettingsEdit, _ error: any Error) {
        saveError = "\(error)"
        log.error("not saved \(edit.logDescription, privacy: .public): \(error, privacy: .public)")
    }

    func reapplyAll() { Task { await engine.reapplyAll() } }

    func refreshLoginItem() {
        loginItem =
            switch SMAppService.mainApp.status {
            case .enabled: .on
            case .requiresApproval: .needsApproval
            default: .off
            }
    }

    func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItem()
    }

    func requestPermission(_ permission: Permission) {
        Permissions.request(permission)
        NSWorkspace.shared.open(Permissions.settingsURL(for: permission))
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
    }

    func showConfigInFinder() { NSWorkspace.shared.activateFileViewerSelecting([configURL]) }

    func openConfigInEditor() { NSWorkspace.shared.open(configURL) }
}

struct LogLine: Identifiable, Sendable {
    var id: Int
    var date: Date
    var category: String
    var message: String
}

enum LogReader {
    /// This process's own entries, which reading needs no entitlement for.
    static func read() throws -> [LogLine] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", "dev.emir.hyperpoint"))
        return entries.compactMap { $0 as? OSLogEntryLog }.enumerated().map { index, entry in
            LogLine(id: index, date: entry.date, category: entry.category, message: entry.composedMessage)
        }
    }
}
