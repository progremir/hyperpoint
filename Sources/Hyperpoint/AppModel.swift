import AppKit
import HyperpointKit

@MainActor
final class AppModel {
    private let store = ConfigStore()
    private let engine = Engine()
    private let performer = ActionPerformer()
    private var menu: StatusMenu?
    private var engineRun: Task<Void, Never>?

    func start() {
        let menu = StatusMenu(model: self)
        self.menu = menu
        engineRun = Task { [store, engine] in
            await store.start()
            await engine.run(configs: await store.snapshots(), permissions: Permissions.updates())
        }
        Task { [engine] in
            for await status in engine.statuses { menu.show(status) }
        }
        Task { [engine, performer] in
            for await action in engine.actions { performer.perform(action) }
        }
    }

    func reapplyAll() { Task { await engine.reapplyAll() } }

    func setPaused(_ paused: Bool) { Task { await engine.setPaused(paused) } }

    func openConfig() { NSWorkspace.shared.open(store.url) }

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
