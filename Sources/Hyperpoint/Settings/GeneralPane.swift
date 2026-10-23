import AppKit
import HyperpointKit
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    let model: SettingsModel
    @State private var showingLog = false

    var body: some View {
        PaneScaffold(title: "General", model: model) {
            Section("Startup") {
                Toggle(isOn: Binding(get: { model.loginItem != .off }, set: { model.setLoginItem($0) })) {
                    Text("Open Hyperpoint at login")
                    Text(loginDetail)
                }
                if model.loginItem == .needsApproval {
                    HStack {
                        Spacer()
                        Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }

            Section("Permissions") {
                let permissions = model.status?.permissions ?? Permissions.current()
                PermissionRow(
                    title: "Accessibility",
                    detail: "Lets the hyper key and smooth scrolling change keys and scrolls as they happen.",
                    grant: permissions.accessibility
                ) { model.requestPermission(.accessibility) }
                PermissionRow(
                    title: "Input Monitoring", detail: "Lets Hyperpoint set up the buttons on Logitech mice.",
                    grant: permissions.inputMonitoring
                ) { model.requestPermission(.inputMonitoring) }
                HStack {
                    Spacer()
                    Button("Open Privacy & Security") { model.openPrivacySettings() }
                }
            }

            Section("Config file") {
                LabeledContent {
                    EmptyView()
                } label: {
                    Text((model.configURL.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Text(loadDetail)
                }
                HStack {
                    Text("This window edits the same file.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Finder") { model.showConfigInFinder() }
                    Button("Open in Editor") { model.openConfigInEditor() }
                }
            }

            Section("Log") {
                LabeledContent {
                    Button("Show Log") { showingLog = true }
                } label: {
                    Text("Every device connect, re-apply and settings change is logged.")
                    Text("The log lists what Hyperpoint did since it started.")
                }
            }
        }
        .sheet(isPresented: $showingLog) { LogSheet() }
        .onAppear { model.refreshLoginItem() }
    }

    private var loginDetail: String {
        if let error = model.loginItemError { return "Could not change it: \(error)" }
        return switch model.loginItem {
        case .on: "Hyperpoint starts when you log in, so your devices are set up right away."
        case .off: "Hyperpoint starts only when you open it."
        case .needsApproval: "Waiting for you to allow it in Login Items."
        }
    }

    private var loadDetail: String {
        if let error = model.snapshot?.error {
            return "Has an error: \(error.description). Hyperpoint keeps using the last good settings."
        }
        guard let loadedAt = model.loadedAt else { return "Loading…" }
        return "Loaded at \(clockTime(loadedAt)). Saving the file reloads it."
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let grant: PermissionState.Grant
    let allow: () -> Void

    var body: some View {
        LabeledContent {
            if grant == .granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                HStack {
                    Text(grant == .denied ? "Not allowed" : "Not asked yet").foregroundStyle(.orange)
                    Button("Allow…", action: allow)
                }
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

private struct LogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [LogLine] = []
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log").font(.headline)
                Text("Since Hyperpoint started").foregroundStyle(.secondary)
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.map(Self.text).joined(separator: "\n"), forType: .string)
                }
                .disabled(lines.isEmpty)
                Button("Refresh") { Task { await load() } }
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                List(lines) { line in
                    Text(Self.text(line))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .id(line.id)
                }
                .overlay {
                    if let problem {
                        ContentUnavailableView("Cannot read the log", systemImage: "doc.text", description: Text(problem))
                    }
                }
                .onChange(of: lines.count) { proxy.scrollTo(lines.last?.id, anchor: .bottom) }
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 820, height: 520)
        .task { await load() }
    }

    private func load() async {
        do {
            lines = try await Task.detached { try LogReader.read() }.value
            problem = nil
        } catch {
            problem = "\(error)"
        }
    }

    private static func text(_ line: LogLine) -> String {
        "\(line.date.formatted(date: .omitted, time: .standard))  \(line.category)  \(line.message)"
    }
}
