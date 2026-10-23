import AppKit
import HyperpointKit
import SwiftUI

/// The one settings window. Closing it only hides it, so reopening keeps the pane the user was on.
@MainActor
final class SettingsWindow {
    private let model: SettingsModel
    private lazy var window: NSWindow = {
        let controller = NSHostingController(rootView: SettingsView(model: model))
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.title = "Hyperpoint Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 880, height: 680))
        window.contentMinSize = NSSize(width: 780, height: 520)
        window.center()
        window.setFrameAutosaveName("HyperpointSettings")
        return window
    }()

    init(model: SettingsModel) { self.model = model }

    /// Hyperpoint has no Dock icon, so the window has to bring the app forward itself.
    func show() {
        model.refreshLoginItem()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Writes a PNG of every pane and tab to `directory`. The window draws itself, so this needs no Screen
    /// Recording access, and the window grows to fit each pane so nothing is cut off. The sidebar is a glass
    /// surface the window server composites, so it comes out blank.
    func snapshot(to directory: URL) async {
        show()
        for _ in 0..<50 where model.snapshot == nil || model.status == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(2))
        var pages: [(name: String, pane: SettingsPane, tab: DeviceTab)] = [
            ("general", .general, .buttons), ("hyper-key", .hyper, .buttons),
        ]
        for device in model.devices {
            let name = device.name.lowercased().replacingOccurrences(of: " ", with: "-")
            if device.kind == .mouse {
                pages.append((name + "-buttons", .device(device.match), .buttons))
                pages.append((name + "-scrolling", .device(device.match), .scrolling))
            } else {
                pages.append((name, .device(device.match), .buttons))
            }
        }
        let size = window.frame.size
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, page) in pages.enumerated() {
            model.pane = page.pane
            model.tab = page.tab
            window.setContentSize(NSSize(width: size.width, height: 1500))
            try? await Task.sleep(for: .milliseconds(700))
            guard let view = window.contentView?.superview, let layer = view.layer,
                let image = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * window.backingScaleFactor),
                    pixelsHigh: Int(view.bounds.height * window.backingScaleFactor), bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                    bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: image)?.cgContext
            else { continue }
            context.scaleBy(x: window.backingScaleFactor, y: window.backingScaleFactor)
            layer.render(in: context)
            let file = directory.appending(path: String(format: "%02d-%@.png", index + 1, page.name))
            try? image.representation(using: .png, properties: [:])?.write(to: file)
        }
        window.setContentSize(size)
        model.pane = .general
        model.tab = .buttons
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $model.pane) {
                Label("General", systemImage: "gearshape").tag(SettingsPane.general)
                Label("Hyper key", systemImage: "command").tag(SettingsPane.hyper)
                Section("Devices") {
                    ForEach(model.devices) { device in
                        Label {
                            Text(device.name).lineLimit(1)
                        } icon: {
                            ConnectionDot(connected: device.connected)
                        }
                        .badge(device.isNew ? Text("New") : nil)
                        .tag(SettingsPane.device(device.match))
                    }
                }
            }
            .frame(minWidth: 200, idealWidth: 210)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch model.pane {
            case .general, nil: GeneralPane(model: model)
            case .hyper: HyperPane(model: model)
            case .device(let match):
                if let device = model.devices.first(where: { $0.match == match }) {
                    DevicePane(model: model, device: device)
                } else {
                    ContentUnavailableView(
                        "Device gone", systemImage: "cable.connector.slash",
                        description: Text("It disconnected before it had a profile."))
                }
            }
        }
    }
}

/// A pane's title, an optional control beside it, and its grouped form. Every pane says when the file is invalid
/// or a save failed, since any pane can be open when that happens.
struct PaneScaffold<Accessory: View, Content: View>: View {
    let title: String
    let model: SettingsModel
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title2.weight(.semibold))
                Spacer()
                accessory
            }
            .padding(.horizontal, 28)
            .padding(.top, 10)
            Form {
                if let error = model.snapshot?.error {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("The config file has an error").fontWeight(.semibold)
                                Text(
                                    "\(error.description). Hyperpoint keeps using the last good settings. Fix the file to change settings here."
                                )
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        HStack {
                            Spacer()
                            Button("Open in Editor") { model.openConfigInEditor() }
                        }
                    }
                }
                if let saveError = model.saveError {
                    Section {
                        Label("Not saved: \(saveError)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                content
            }
            .formStyle(.grouped)
        }
    }
}

extension PaneScaffold where Accessory == EmptyView {
    init(title: String, model: SettingsModel, @ViewBuilder content: () -> Content) {
        self.init(title: title, model: model, accessory: { EmptyView() }, content: content)
    }
}

struct ConnectionDot: View {
    let connected: Bool

    var body: some View {
        Circle()
            .fill(connected ? Color.green : Color.clear)
            .strokeBorder(connected ? Color.clear : Color.secondary, lineWidth: 1.5)
            .frame(width: 8, height: 8)
            .accessibilityLabel(connected ? "Connected" : "Not connected")
    }
}

/// A name field that saves on Return or when it loses focus, not on every keystroke.
struct NameField: View {
    let name: String
    let save: (String) -> Void
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: Binding(get: { draft ?? name }, set: { draft = $0 })) {
            Text("Name in Hyperpoint")
            Text("Shown here and in the menu.")
        }
        .focused($focused)
        .onSubmit(commit)
        .onChange(of: focused) { if !focused { commit() } }
        .onChange(of: name) { draft = nil }
    }

    private func commit() {
        guard let draft, draft != name else { return }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.draft = nil
        } else {
            save(draft)
        }
    }
}

extension Rule {
    var key: RuleKey { RuleKey(self) }
}

func clockTime(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
