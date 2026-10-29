import AppKit
import HyperpointKit

@MainActor
final class AppModel {
    private let store = ConfigStore()
    private let engine = Engine()
    private let performer = ActionPerformer()
    private lazy var carrierHotkeys = CarrierHotkeys(performer: performer)
    private let settings: SettingsModel
    private lazy var settingsWindow = SettingsWindow(model: settings)
    private var menu: StatusMenu?
    private var engineRun: Task<Void, Never>?

    init() { settings = SettingsModel(store: store, engine: engine) }

    func start() {
        let menu = StatusMenu(model: self)
        self.menu = menu
        engineRun = Task { [store, engine] in
            await store.start()
            await engine.run(configs: await store.snapshots(), permissions: Permissions.updates())
        }
        Task { [engine, settings] in
            for await status in engine.statuses {
                menu.show(status)
                settings.show(status)
            }
        }
        Task { [store, settings] in
            for await snapshot in await store.snapshots() { settings.show(snapshot) }
        }
        Task { [engine, performer] in
            for await action in engine.actions { performer.perform(action) }
        }
        Task { [engine, carrierHotkeys] in await carrierHotkeys.follow(engine) }
        Task { [engine, settings] in
            for await press in engine.heard { settings.learned(press) }
        }
    }

    func reapplyAll() { Task { await engine.reapplyAll() } }

    func setPaused(_ paused: Bool) { Task { await engine.setPaused(paused) } }

    /// Nil until the config file has loaded.
    var hyperKeyEnabled: Bool? { settings.config?.hyper.enabled }

    var configEditable: Bool { settings.editable }

    func setHyperKeyEnabled(_ on: Bool) { settings.apply(.hyperEnabled(on)) }

    func openConfig() { NSWorkspace.shared.open(store.url) }

    func openSettings() { settingsWindow.show() }

    func snapshotSettings(to directory: URL) { Task { await settingsWindow.snapshot(to: directory) } }

    func fix(_ fix: MenuPresentation.Fix) {
        switch fix {
        case .permission(let permission):
            Permissions.request(permission)
            NSWorkspace.shared.open(Permissions.settingsURL(for: permission))
        case .openConfig:
            openConfig()
        case .reapply:
            reapplyAll()
        }
    }

    func shutdown() async {
        await engine.shutdown()
        engineRun?.cancel()
    }
}
