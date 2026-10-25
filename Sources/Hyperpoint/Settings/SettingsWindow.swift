import AppKit
import HyperpointKit
import SwiftUI

/// The one settings window: a toolbar of tabs with a page each. Closing it only hides it, so reopening keeps the tab.
@MainActor
final class SettingsWindow {
    private let model: SettingsModel
    private lazy var tabs = SettingsTabs(model: model)
    private lazy var window: NSWindow = {
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("HyperpointPreferences")
        return window
    }()

    init(model: SettingsModel) { self.model = model }

    /// Hyperpoint has no Dock icon, so the window has to bring the app forward itself.
    func show() {
        model.refreshLoginItem()
        NSApp.activate()
        tabs.fitWindow(animated: false)
        window.makeKeyAndOrderFront(nil)
    }

    /// Writes a PNG of every tab in light and then dark appearance, at the window's own size for that tab with the
    /// toolbar, Buttons and Scrolling once per mouse, and General again with a permission missing. The window draws
    /// itself, so this needs no Screen Recording access.
    func snapshot(to directory: URL) async {
        show()
        for _ in 0..<50 where model.snapshot == nil || model.status == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(2))
        let shown = (tab: model.tab, mouse: model.mouse)
        var pages: [(name: String, tab: SettingsTab, mouse: DeviceMatch?)] = []
        for tab in SettingsTab.allCases {
            let mice = tab == .buttons || tab == .scrolling ? model.mice : []
            if mice.isEmpty { pages.append((Self.slug(tab.title), tab, nil)) }
            for mouse in mice { pages.append((Self.slug(tab.title) + "-" + Self.slug(mouse.name), tab, mouse.match)) }
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (suffix, appearance) in [("", NSAppearance.Name.aqua), ("-dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            for (index, page) in pages.enumerated() {
                model.mouse = page.mouse ?? shown.mouse
                tabs.tab = page.tab
                try? await Task.sleep(for: .milliseconds(800))
                let name = String(format: "%02d-%@", index + 1, page.name)
                await shoot(to: directory, name: name + suffix)
                guard page.tab == .general else { continue }
                model.snapshotPermissions = PermissionState(accessibility: .granted, inputMonitoring: .denied)
                try? await Task.sleep(for: .milliseconds(800))
                await shoot(to: directory, name: name + "-permission-missing" + suffix)
                model.snapshotPermissions = nil
            }
        }
        window.appearance = nil
        model.mouse = shown.mouse
        tabs.tab = shown.tab
    }

    /// A page taller than the screen is drawn again scrolled to its end.
    private func shoot(to directory: URL, name: String) async {
        render(to: directory.appending(path: name + ".png"))
        guard let scroller = window.contentView.flatMap(Self.tallestScrollView), let document = scroller.documentView,
            document.frame.height > scroller.contentView.bounds.height + 1
        else { return }
        document.scroll(NSPoint(x: 0, y: document.isFlipped ? document.frame.height : 0))
        try? await Task.sleep(for: .milliseconds(400))
        render(to: directory.appending(path: name + "-end.png"))
        document.scroll(NSPoint(x: 0, y: document.isFlipped ? 0 : document.frame.height))
    }

    private func render(to file: URL) {
        guard let view = window.contentView?.superview, let layer = view.layer,
            let image = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * window.backingScaleFactor),
                pixelsHigh: Int(view.bounds.height * window.backingScaleFactor), bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: image)?.cgContext
        else { return }
        context.scaleBy(x: window.backingScaleFactor, y: window.backingScaleFactor)
        layer.render(in: context)
        try? image.representation(using: .png, properties: [:])?.write(to: file)
    }

    private static func slug(_ name: String) -> String { name.lowercased().replacingOccurrences(of: " ", with: "-") }

    private static func tallestScrollView(in view: NSView) -> NSScrollView? {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        let nested = view.subviews.compactMap(tallestScrollView)
        return (own + nested).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
    }
}

/// One toolbar item and SwiftUI page per `SettingsTab`, and the window sized to the selected page. The pages report
/// their own size, so the window animates to it both on a tab switch and when a page grows or shrinks.
private final class SettingsTabs: NSTabViewController {
    private let model: SettingsModel
    /// A page reports its size once it has been laid out, which is the first time its tab is shown.
    private var sizes: [SettingsTab: CGSize] = [:]

    init(model: SettingsModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        // Adding the first item selects it, which would overwrite the remembered tab.
        let remembered = model.tab
        for tab in SettingsTab.allCases {
            let fit = FitPage { [weak self] size in self?.measured(tab, size) }
            let page = NSHostingController(rootView: SettingsTabPage(tab: tab, model: model).environment(\.fitPage, fit))
            page.sizingOptions = []
            page.title = tab.title
            let item = NSTabViewItem(viewController: page)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
            addTabViewItem(item)
        }
        self.tab = remembered
    }

    required init?(coder: NSCoder) { fatalError("built in code") }

    var tab: SettingsTab {
        get { SettingsTab.allCases[selectedTabViewItemIndex] }
        set { selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: newValue) ?? 0 }
    }

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        model.tab = tab
        fitSoon()
    }

    private func measured(_ tab: SettingsTab, _ size: CGSize) {
        sizes[tab] = size
        if tab == self.tab { fitSoon() }
    }

    /// A tab switch and a SwiftUI update both apply a frame change at once instead of animating it, so the window
    /// follows on the next turn of the run loop.
    private func fitSoon() {
        Task { @MainActor [weak self] in self?.fitWindow(animated: self?.view.window?.isVisible == true) }
    }

    /// Keeps the top edge in place, and stops at the bottom of the screen, where the page scrolls instead.
    func fitWindow(animated: Bool) {
        guard let window = view.window, let size = sizes[tab] else { return }
        let screen = window.screen?.visibleFrame ?? .infinite
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.size.height = min(frame.height, screen.height)
        frame.origin = NSPoint(x: window.frame.minX, y: max(window.frame.maxY - frame.height, screen.minY))
        guard frame != window.frame else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { _ in window.animator().setFrame(frame, display: true) }
        } else {
            window.setFrame(frame, display: true)
        }
    }
}

private struct SettingsTabPage: View {
    let tab: SettingsTab
    let model: SettingsModel

    var body: some View {
        switch tab {
        case .general: GeneralTab(model: model)
        case .hyperKey: HyperKeyTab(model: model)
        case .buttons: ButtonsTab(model: model)
        case .scrolling: ScrollingTab(model: model)
        case .devices: DevicesTab(model: model)
        }
    }
}
