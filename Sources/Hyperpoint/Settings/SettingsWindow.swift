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
        _ = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) {
            [model] _ in MainActor.assumeIsolated { model.stopListening() }
        }
        return window
    }()

    init(model: SettingsModel) { self.model = model }

    /// Hyperpoint has no Dock icon, so the window has to bring the app forward itself. The page is measured in the
    /// window, so the window exists before it takes the page's height.
    func show() {
        model.refreshLoginItem()
        NSApp.activate()
        let window = self.window
        tabs.fitWindow(animated: false)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
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

    private func render(to file: URL) { window.renderPNG(to: file) }

    private static func slug(_ name: String) -> String { name.lowercased().replacingOccurrences(of: " ", with: "-") }

    private static func tallestScrollView(in view: NSView) -> NSScrollView? {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        let nested = view.subviews.compactMap(tallestScrollView)
        return (own + nested).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
    }
}

/// One toolbar item and SwiftUI page per `SettingsTab`, and the window sized to the selected page. A tab switch works
/// like a native preferences window: the new page stays hidden while the window animates to its height, then shows.
/// Another mouse's page hides the same way when it is taller. A page that grows or shrinks where it is, as when a rule
/// is added, stays in view while the window follows.
private final class SettingsTabs: NSTabViewController {
    private let model: SettingsModel
    private var fits: [SettingsTab: PageFit] = [:]
    /// The frame the window is animating to, so a second fit to the same frame does not restart the animation.
    private var heading: NSRect?
    private var nextFrame: CADisplayLink?

    init(model: SettingsModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
        // Adding the first item selects it, which would overwrite the remembered tab.
        let remembered = model.tab
        for tab in SettingsTab.allCases {
            let fit = PageFit { [weak self] replaced in self?.resized(tab, replaced: replaced) }
            fits[tab] = fit
            let page = NSHostingController(rootView: SettingsTabPage(tab: tab, model: model).environment(\.pageFit, fit))
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

    /// Shown at the window's old height, the new page would be clipped and flash a scroll bar, so it is hidden until
    /// the window has its height.
    override func tabView(_ tabView: NSTabView, willSelect item: NSTabViewItem?) {
        super.tabView(tabView, willSelect: item)
        item?.view?.isHidden = view.window?.isVisible == true
    }

    /// Laying the hidden page out makes it report its size before the window starts moving. The tab view puts the
    /// caret in the page's first text field, which on Devices is a device's name, so it would look mid-edit.
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        view.window?.makeFirstResponder(nil)
        model.tab = tab
        item?.view?.layoutSubtreeIfNeeded()
        fitSoon()
    }

    /// Another mouse's page, taller than the last, is a new page, so it is hidden until the window has its height. This
    /// runs while SwiftUI places the page, so the page is hidden in the same update that draws it. A page that grew
    /// where it is, by a rule added, stays in view with its bottom revealed as the window grows: hiding it blanked the
    /// whole page for the length of the animation on every added rule.
    private func resized(_ tab: SettingsTab, replaced: Bool) {
        guard tab == self.tab else { return }
        if replaced, let window = view.window, window.isVisible, let size = fits[tab]?.size,
            target(for: size, in: window).frame.height > window.frame.height
        {
            tabView.selectedTabViewItem?.view?.isHidden = true
        }
        fitSoon()
    }

    /// Started in the same turn of the run loop as a tab switch or a SwiftUI update, the window's animation often ends
    /// on its first frame, so the window jumps. It starts on the next frame instead.
    private func fitSoon() {
        guard nextFrame == nil, let window = view.window, window.isVisible else { return }
        nextFrame = window.displayLink(target: self, selector: #selector(fitOnFrame))
        nextFrame?.add(to: .main, forMode: .common)
    }

    @objc private func fitOnFrame() { fitWindow(animated: true) }

    /// Keeps the top edge in place, and stops at the bottom of the screen, where the page scrolls instead. Shows the
    /// page once the window has its height. A page laid out outside the window reports its size at another scale, half
    /// a point off, so it is laid out in the window first.
    func fitWindow(animated: Bool) {
        nextFrame?.invalidate()
        nextFrame = nil
        guard let window = view.window, let fit = fits[tab] else { return }
        tabView.selectedTabViewItem?.view?.layoutSubtreeIfNeeded()
        guard let size = fit.size else { return }
        let (frame, scrolls) = target(for: size, in: window)
        if fit.scrolls != scrolls { fit.scrolls = scrolls }
        guard animated, frame != window.frame else {
            heading = nil
            window.setFrame(frame, display: true)
            tabView.selectedTabViewItem?.view?.isHidden = false
            return
        }
        guard frame != heading else { return }
        heading = frame
        NSAnimationContext.runAnimationGroup { context in
            // Short enough that a switch to the slowest page to attach, Buttons, still ends within 0.35 s.
            context.duration = 0.18
            // Ease-in would hold a small resize under a point, so unmoved, for its first two frames.
            context.timingFunction = CAMediaTimingFunction(name: .default)
            window.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self, frame] in
            MainActor.assumeIsolated { self?.arrived(at: frame) }
        }
    }

    /// The window's frame for a page of `size`, top edge in place, and whether it had to stop at the screen's bottom.
    private func target(for size: CGSize, in window: NSWindow) -> (frame: NSRect, scrolls: Bool) {
        let screen = window.screen?.visibleFrame ?? .infinite
        let content = NSSize(width: size.width, height: size.height.rounded(.up))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        let scrolls = frame.height > screen.height
        frame.size.height = min(frame.height, screen.height)
        frame.origin = NSPoint(x: window.frame.minX, y: max(window.frame.maxY - frame.height, screen.minY))
        return (frame, scrolls)
    }

    /// A later fit to another frame owns the page from here, so an overtaken animation leaves it alone.
    private func arrived(at frame: NSRect) {
        guard heading == frame else { return }
        heading = nil
        tabView.selectedTabViewItem?.view?.isHidden = false
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

extension NSWindow {
    /// Draws the window's frame view and everything in it, which needs no Screen Recording access. Materials that blur
    /// what is behind the window come out empty.
    func renderPNG(to file: URL) {
        guard let view = contentView?.superview, let layer = view.layer,
            let image = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * backingScaleFactor),
                pixelsHigh: Int(view.bounds.height * backingScaleFactor), bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: image)?.cgContext
        else { return }
        context.scaleBy(x: backingScaleFactor, y: backingScaleFactor)
        layer.render(in: context)
        try? image.representation(using: .png, properties: [:])?.write(to: file)
    }
}
