import AppKit
import Observation
import Sparkle

/// Sparkle's updater. It reads https://hyperpoint.progremir.dev/appcast.xml, which `scripts/release.sh` publishes,
/// once a day after the user allows it, and installs a newer release only when the user agrees or has chosen
/// automatic installs. Only Developer ID releases carry the feed, so a development build (Hyperpoint Dev), or one run
/// outside its bundle, never starts it.
@MainActor
@Observable
final class Updates: NSObject {
    /// Copies of the updater's KVO-compliant state, so the settings window redraws when Sparkle changes them.
    private(set) var canCheck = false
    private(set) var automaticallyChecks = false
    private(set) var automaticallyDownloads = false
    private(set) var allowsAutomaticDownloads = false
    private(set) var lastCheck: Date?
    /// The version a scheduled check found, from when Sparkle shows it until the user looks at it. A menu-bar app has
    /// no window to badge, so the menu offers it at the top.
    private(set) var found: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let defaults: UserDefaults
    private static let betaKey = "betaUpdates"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        beta = defaults.bool(forKey: Self.betaKey)
        super.init()
    }

    var available: Bool { controller != nil }

    /// Prereleases are published on Sparkle's beta channel, which only this switch lets the updater see.
    var beta: Bool { didSet { defaults.set(beta, forKey: Self.betaKey) } }

    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: .initial) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: .initial) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticallyChecks = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: .initial) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticallyDownloads = updater.automaticallyDownloadsUpdates }
            },
            updater.observe(\.allowsAutomaticUpdates, options: .initial) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.allowsAutomaticDownloads = updater.allowsAutomaticUpdates }
            },
        ]
        lastCheck = updater.lastUpdateCheckDate
    }

    func check() { controller?.checkForUpdates(nil) }

    func setAutomaticallyChecks(_ on: Bool) { controller?.updater.automaticallyChecksForUpdates = on }

    func setAutomaticallyDownloads(_ on: Bool) { controller?.updater.automaticallyDownloadsUpdates = on }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}

extension Updates: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { beta ? ["beta"] : [] }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastCheck = updater.lastUpdateCheckDate
    }
}

extension Updates: @preconcurrency SPUStandardUserDriverDelegate {
    /// Sparkle still shows a scheduled update itself, but behind other windows unless the app just launched, so the
    /// menu keeps it in reach.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !state.userInitiated { found = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { found = nil }

    func standardUserDriverWillFinishUpdateSession() { found = nil }
}
