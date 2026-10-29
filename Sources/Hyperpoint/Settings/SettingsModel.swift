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

/// Why the window is listening: to add a rule, or to give the rule with this key the button pressed next. Only the
/// window knows, so the engine listens the same way for both.
enum ListenPurpose: Equatable {
    case addRule
    case replaceRule(RuleKey)
}

/// What the last heard press or menu pick did, for the note under Add Rule and the rows it highlights. Window feedback,
/// not engine state.
enum LearnNote: Equatable {
    /// A rule was added or given a new button.
    case added(DeviceMatch, RuleKey)
    case full(DeviceMatch, Control)
    case unnamed(DeviceMatch)

    var match: DeviceMatch {
        switch self {
        case .added(let match, _), .full(let match, _), .unnamed(let match): match
        }
    }

    func highlights(_ rule: Rule) -> Bool {
        switch self {
        case .added(_, let key): RuleKey(rule) == key
        case .full(_, let control): rule.control == control
        case .unnamed: false
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
    private(set) var learnNote: LearnNote?
    private(set) var listenPurpose = ListenPurpose.addRule
    /// Remembered across launches, so the window opens where the user left it. A listen belongs to the Buttons tab.
    var tab: SettingsTab {
        didSet {
            defaults.set(tab.rawValue, forKey: Self.tabKey)
            if tab != .buttons { stopListening() }
        }
    }
    /// The mouse the Buttons and Scrolling tabs both show. Nil, or a mouse no longer listed, means the first one.
    var mouse: DeviceMatch? { didSet { if mouse != oldValue { stopListening() } } }

    let configURL: URL
    /// Nil in tests, which have no updater.
    let updates: Updates?
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

    init(store: ConfigStore, engine: Engine, updates: Updates? = nil, defaults: UserDefaults = .standard) {
        configURL = store.url
        self.updates = updates
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

    /// Set only by the window's snapshot, to draw General as it looks with a permission missing.
    var snapshotPermissions: PermissionState?

    var permissions: PermissionState { snapshotPermissions ?? status?.permissions ?? Permissions.current() }

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

    func listen(for device: SettingsDevice, to purpose: ListenPurpose = .addRule) {
        learnNote = nil
        listenPurpose = purpose
        Task { await engine.listen(for: device.match) }
    }

    /// Ends a listen, and clears the note under Add Rule.
    func stopListening() {
        learnNote = nil
        Task { await engine.stopListening() }
    }

    /// Add Rule's menu, for a control picked instead of pressed, which a mouse that is not connected needs.
    func pick(_ control: Control, on device: SettingsDevice) {
        stopListening()
        learned(.control(control), on: device.match, for: .addRule)
    }

    func learned(_ press: LearnedPress) { learned(press.heard, on: press.match, for: listenPurpose) }

    /// The only place a heard press or a picked control becomes config.
    private func learned(_ heard: Heard, on match: DeviceMatch, for purpose: ListenPurpose) {
        guard editable, let device = devices.first(where: { $0.match == match }), device.profile != nil else { return }
        let choices = choices(for: device)
        let learned: LearnedRule
        switch purpose {
        case .addRule:
            learned = choices.learned(heard)
        case .replaceRule(let key):
            guard let rule = choices.rules.first(where: { $0.key == key }) else { return }
            learned = choices.learned(heard, replacing: rule)
        }
        switch learned {
        case .add(let rule):
            apply(.addRule(device.match, rule))
            note(.added(device.match, rule.key))
        case .replace(let key, let rule):
            apply(.replaceRule(device.match, key, rule))
            note(.added(device.match, rule.key))
        case .unchanged:
            break
        case .everyTriggerTaken(let control):
            note(.full(device.match, control))
        case .unnamed:
            note(.unnamed(device.match))
        }
    }

    /// A new rule stays highlighted for two seconds. The other notes stay until the next listen or a stop.
    private func note(_ note: LearnNote) {
        learnNote = note
        guard case .added = note else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.learnNote == note { self?.learnNote = nil }
        }
    }

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

    func requestPermission(_ permission: Permission) { PermissionGuide.shared.open(permission) }

    func showPermission(_ permission: Permission) { NSWorkspace.shared.open(Permissions.settingsURL(for: permission)) }

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
