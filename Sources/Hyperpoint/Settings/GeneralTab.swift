import AppKit
import HyperpointKit
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    let model: SettingsModel
    @State private var showingLog = false

    var body: some View {
        SettingsPage(model: model) {
            FormRow(label: "Startup", detail: loginDetail) {
                Toggle("Open Hyperpoint at login", isOn: Binding(get: { model.loginItem != .off }, set: { model.setLoginItem($0) }))
                if model.loginItem == .needsApproval {
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Divider()
            permissions
            Divider()
            FormRow(label: "Config file") {
                Text((model.configURL.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Explanation("\(loadDetail) This window edits the same file.")
                HStack {
                    Button("Show in Finder") { model.showConfigInFinder() }
                    Button("Open in Editor") { model.openConfigInEditor() }
                }
                .padding(.top, 3)
            }
            Divider()
            FormRow(
                label: "Log",
                detail: "Every device connect, re-apply and settings change is logged. The log lists what Hyperpoint did since it started."
            ) {
                Button("Show Log") { showingLog = true }
            }
            if let updates = model.updates, updates.available {
                Divider()
                UpdatesRow(updates: updates)
            }
        }
        .sheet(isPresented: $showingLog) { LogSheet() }
        .onAppear { model.refreshLoginItem() }
    }

    @ViewBuilder private var permissions: some View {
        let permissions = model.permissions
        if permissions.accessibility != .granted || permissions.inputMonitoring != .granted {
            FormRow(label: "") {
                VStack(alignment: .leading, spacing: 8) {
                    GroupHeading("How to grant permissions")
                    Step(number: 1) {
                        Text("Go to System Settings › Privacy & Security")
                        Button("Open System Settings") { model.openPrivacySettings() }
                            .padding(.top, 3)
                    }
                    Step(number: 2) { Text("Switch on Hyperpoint under Accessibility and under Input Monitoring") }
                    Step(number: 3) { Text("Check that both say Granted below, or click Allow… to be asked") }
                }
            }
        }
        FormRow(label: "Accessibility", detail: "Lets the hyper key and smooth scrolling change keys and scrolls as they happen.") {
            PermissionStatus(grant: permissions.accessibility) { model.requestPermission(.accessibility) } show: {
                model.showPermission(.accessibility)
            }
        }
        FormRow(label: "Input Monitoring", detail: "Lets Hyperpoint set up the buttons on Logitech mice.") {
            PermissionStatus(grant: permissions.inputMonitoring) { model.requestPermission(.inputMonitoring) } show: {
                model.showPermission(.inputMonitoring)
            }
        }
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

/// A numbered how-to step. Whatever sits under the step's text lines up with the text, not the number.
private struct Step<Content: View>: View {
    let number: Int
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(number).").monospacedDigit()
            VStack(alignment: .leading, spacing: 5) { content }
        }
    }
}

private struct UpdatesRow: View {
    let updates: Updates

    var body: some View {
        FormRow(label: "Updates", detail: detail) {
            Toggle(
                "Check for updates automatically",
                isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.setAutomaticallyChecks($0) }))
            Toggle(
                "Download and install them automatically",
                isOn: Binding(get: { updates.automaticallyDownloads }, set: { updates.setAutomaticallyDownloads($0) })
            )
            .disabled(!updates.allowsAutomaticDownloads)
            Toggle("Include beta versions", isOn: Binding(get: { updates.beta }, set: { updates.beta = $0 }))
            Button("Check Now") { updates.check() }
                .disabled(!updates.canCheck)
                .padding(.top, 3)
        }
    }

    private var detail: String {
        let schedule =
            updates.automaticallyChecks
            ? "Once a day Hyperpoint asks hyperpoint.progremir.dev for the latest version, and sends nothing else."
            : "Hyperpoint checks only when you ask."
        let last = updates.lastCheck.map { " Last checked \($0.formatted(.relative(presentation: .named)))." } ?? ""
        return "You have version \(Updates.version). \(schedule)\(last)"
    }
}

/// A granted permission keeps a way into its System Settings list, where it can be checked or removed.
private struct PermissionStatus: View {
    let grant: PermissionState.Grant
    let allow: () -> Void
    let show: () -> Void

    var body: some View {
        if grant == .granted {
            HStack {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Show in System Settings", action: show)
            }
        } else {
            HStack {
                Text(grant == .denied ? "Not allowed" : "Not asked yet").foregroundStyle(.orange)
                Button("Allow…", action: allow)
            }
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
        .frame(width: 600, height: 440)
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
