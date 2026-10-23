import AppKit
import HyperpointKit
import os

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let model: AppModel
    private var presentation: MenuPresentation
    private let log = Logger(subsystem: "dev.emir.hyperpoint", category: "menu")

    init(model: AppModel) {
        self.model = model
        presentation = MenuPresentation(nil, time: Self.time)
        super.init()
        let image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Hyperpoint")
        image?.isTemplate = true
        item.button?.image = image
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        rebuild()
    }

    func show(_ status: EngineStatus) {
        let next = MenuPresentation(status, time: Self.time)
        if next != presentation { log.notice("\(next.summary, privacy: .public)") }
        presentation = next
        item.button?.contentTintColor = presentation.needsAttention ? .systemOrange : nil
        item.button?.setAccessibilityLabel(presentation.needsAttention ? "Hyperpoint, needs attention" : "Hyperpoint")
        rebuild()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        menu.removeAllItems()
        menu.addItem(info(left: "Hyperpoint", right: presentation.state, bold: true))
        for notice in presentation.notices {
            let fix = ActionItem(title: notice.title) { [model] in model.fix(notice.fix) }
            fix.subtitle = notice.detail
            menu.addItem(fix)
        }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Devices"))
        for row in presentation.rows { menu.addItem(info(left: row.name, right: row.detail)) }
        if let footnote = presentation.footnote { menu.addItem(info(left: footnote, right: nil)) }
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: "Re-apply Settings Now", key: "r") { [model] in model.reapplyAll() })
        let paused = presentation.paused
        menu.addItem(
            ActionItem(title: paused ? "Resume Hyperpoint" : "Pause Hyperpoint") { [model] in
                model.setPaused(!paused)
            })
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: "Settings…", key: ",") { [model] in model.openSettings() })
        menu.addItem(ActionItem(title: "Open Config File") { [model] in model.openConfig() })
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: "Quit Hyperpoint", key: "q") { NSApp.terminate(nil) })
    }

    private func info(left: String, right: String?, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: left, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 280)]
        let font = bold ? NSFont.menuFont(ofSize: 0).withWeight(.semibold) : NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(
            string: left, attributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        if let right {
            title.append(
                NSAttributedString(
                    string: "\t" + right,
                    attributes: [
                        .font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor,
                        .paragraphStyle: style,
                    ]))
        }
        item.attributedTitle = title
        return item
    }

    private static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

@MainActor
private final class ActionItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, key: String = "", run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("menu items are built in code") }

    @objc private func fire() { run() }
}

extension NSFont {
    fileprivate func withWeight(_ weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
