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
    var pane: SettingsPane? = .general
    var tab = DeviceTab.buttons

    let configURL: URL
    private let engine: Engine
    private let edits: AsyncStream<SettingsEdit>.Continuation
    private let log = Logger(subsystem: "dev.emir.hyperpoint", category: "settings")
    /// Switching smooth scrolling or acceleration off removes its section from the file, so the values tuned before
    /// are kept here and come back when it is switched on again.
    @ObservationIgnored private var lastSmooth: [DeviceMatch: SmoothScroll] = [:]
    @ObservationIgnored private var lastAcceleration: [DeviceMatch: Acceleration] = [:]
    /// Discovery runs again on every connection, so the rule pickers keep a mouse's controls while it is away.
    @ObservationIgnored private var seenCapabilities: [DeviceMatch: HIDPPCapabilities] = [:]

    init(store: ConfigStore, engine: Engine) {
        configURL = store.url
        self.engine = engine
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

    func show(_ snapshot: ConfigSnapshot) {
        self.snapshot = snapshot
        guard let config = snapshot.config, snapshot.error == nil else { return }
        loadedAt = Date()
        for profile in config.devices {
            guard let smooth = profile.scrolling?.smooth else { continue }
            lastSmooth[profile.match] = smooth
            if let acceleration = smooth.acceleration { lastAcceleration[profile.match] = acceleration }
        }
    }

    func show(_ status: EngineStatus) {
        self.status = status
        for device in status.devices {
            if let capabilities = device.hidpp?.capabilities { seenCapabilities[device.match] = capabilities }
        }
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

    func accelerationWhenOn(_ match: DeviceMatch) -> Acceleration { lastAcceleration[match] ?? .default }

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
    nonisolated static func read() throws -> [LogLine] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", "dev.emir.hyperpoint"))
        return entries.compactMap { $0 as? OSLogEntryLog }.enumerated().map { index, entry in
            LogLine(id: index, date: entry.date, category: entry.category, message: entry.composedMessage)
        }
    }
}
