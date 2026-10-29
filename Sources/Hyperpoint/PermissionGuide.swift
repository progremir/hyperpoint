import AppKit
import HyperpointKit
import SwiftUI

/// Asks for a permission the way other Mac apps do: the system prompt, the System Settings pane, and a small panel
/// under the System Settings window holding Hyperpoint's icon to drag into the list. Dropping the app there adds it
/// even when the prompt did not, for example after its entry was removed. The panel follows the window, shows only
/// while System Settings is in front, and closes once the permission is granted, when System Settings quits, or
/// from its close button.
@MainActor
final class PermissionGuide {
    static let shared = PermissionGuide()

    private var panel: GuidePanel?
    private var follow: Task<Void, Never>?
    private static let settingsID = "com.apple.systempreferences"

    func open(_ permission: Permission) {
        Permissions.request(permission)
        NSWorkspace.shared.open(Permissions.settingsURL(for: permission))
        show(permission)
    }

    /// Draws the panel for each permission, in light and then dark appearance, beside the settings snapshots. It is
    /// placed off screen, so nothing shows.
    func snapshot(to directory: URL) async {
        for (suffix, appearance) in [("", NSAppearance.Name.aqua), ("-dark", .darkAqua)] {
            for (name, permission) in [("accessibility", Permission.accessibility), ("input-monitoring", .inputMonitoring)] {
                let panel = GuidePanel(content: GuideView(permission: permission) {})
                panel.appearance = NSAppearance(named: appearance)
                panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
                panel.orderFrontRegardless()
                try? await Task.sleep(for: .milliseconds(500))
                panel.renderPNG(to: directory.appending(path: "permission-guide-\(name)\(suffix).png"))
                panel.orderOut(nil)
            }
        }
    }

    func close() {
        follow?.cancel()
        follow = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func show(_ permission: Permission) {
        close()
        let panel = GuidePanel(content: GuideView(permission: permission) { [weak self] in self?.close() })
        self.panel = panel
        follow = Task { [weak self] in
            // System Settings can take a few seconds to open the pane, so its absence ends the guide only after that.
            let opened = ContinuousClock.now
            while !Task.isCancelled {
                if Self.granted(permission, in: Permissions.current()) { break }
                let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsID).isEmpty
                if !running, ContinuousClock.now - opened > .seconds(5) { break }
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.settingsID
                if front, let window = Self.settingsWindowFrame() {
                    panel.place(under: window)
                    panel.orderFrontRegardless()
                } else {
                    panel.orderOut(nil)
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
            if !Task.isCancelled { self?.close() }
        }
    }

    private static func granted(_ permission: Permission, in state: PermissionState) -> Bool {
        (permission == .accessibility ? state.accessibility : state.inputMonitoring) == .granted
    }

    /// The largest on-screen window of System Settings, in AppKit coordinates. The window list gives bounds and owners
    /// of other apps' windows without Screen Recording.
    private static func settingsWindowFrame() -> NSRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: settingsID).first?.processIdentifier,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        let frames = windows.compactMap { info -> CGRect? in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid, info[kCGWindowLayer as String] as? Int == 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        guard let frame = frames.max(by: { $0.width * $0.height < $1.width * $1.height }),
            let primary = NSScreen.screens.first
        else { return nil }
        // The window list measures from the top left of the primary display, AppKit from its bottom left.
        return NSRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }
}

/// A floating panel that never activates Hyperpoint, so System Settings stays in front and keeps taking the drop.
private final class GuidePanel: NSPanel {
    init(content: some View) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        let host = NSHostingView(rootView: content)
        host.setFrameSize(host.fittingSize)
        contentView = host
        setContentSize(host.fittingSize)
    }

    override var canBecomeKey: Bool { true }

    /// Just below the window, or over its bottom edge when the screen has no room below.
    func place(under window: NSRect) {
        let size = frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(window) }?.visibleFrame ?? window
        var origin = NSPoint(x: window.midX - size.width / 2, y: window.minY - size.height - 10)
        if origin.y < screen.minY { origin.y = window.minY + 16 }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        if frame.origin != origin { setFrameOrigin(origin) }
    }
}

private struct GuideView: View {
    let permission: Permission
    let close: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Drawn like a file in Finder, so it reads as something to pick up.
            VStack(spacing: 2) {
                AppIconDrag().frame(width: 44, height: 44)
                Text("Hyperpoint").font(.caption)
            }
            VStack(alignment: .leading, spacing: 3) {
                Label("Drag Hyperpoint into the list above", systemImage: "arrow.up").font(.headline)
                Text("This allows \(permission == .accessibility ? "Accessibility" : "Input Monitoring"). Then check that its switch is on.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Close")
        }
        .padding(14)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Hyperpoint's icon, which drags the app bundle itself, as dragging it from Finder does.
private struct AppIconDrag: NSViewRepresentable {
    func makeNSView(context: Context) -> DragSource { DragSource() }
    func updateNSView(_ view: DragSource, context: Context) {}

    final class DragSource: NSImageView, NSDraggingSource {
        init() {
            super.init(frame: .zero)
            image = NSApp.applicationIconImage
            imageScaling = .scaleProportionallyUpOrDown
            setAccessibilityLabel("Hyperpoint")
        }

        required init?(coder: NSCoder) { fatalError("built in code") }

        /// The icon's own size is 1024 points, which SwiftUI would otherwise let spill past the frame it gives.
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {}

        override func mouseDragged(with event: NSEvent) {
            let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
            item.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
            -> NSDragOperation
        { .copy }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}
