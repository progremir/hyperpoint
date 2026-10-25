import HyperpointKit
import SwiftUI

struct HyperKeyTab: View {
    let model: SettingsModel

    /// Without a tap action the hyper key stops typing as itself, so the list keeps to keys most people never type.
    static let keys: [HIDUsage] = ["capsLock", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"]
        .compactMap(HIDUsage.init(name:))

    var body: some View {
        SettingsPage(model: model) {
            if let config = model.config {
                let keys = Self.keys.contains(config.hyper.key) ? Self.keys : [config.hyper.key] + Self.keys
                VStack(alignment: .leading, spacing: 12) {
                    FormRow(label: "Key", detail: "Holding it holds ⌃⌥⇧⌘ on the keyboards below. It no longer types as itself.") {
                        Picker("Key", selection: Binding(get: { config.hyper.key }, set: { model.apply(.hyperKey($0)) })) {
                            ForEach(keys, id: \.self) { Text(Labels.key($0.name ?? "")).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    FormRow(label: "While held", detail: "Every key you press gets Control, Option, Shift and Command, for app shortcuts.") {
                        Text("⌃ ⌥ ⇧ ⌘").font(.body.monospaced())
                    }
                    FormRow(label: "Tapped alone", detail: "Other tap actions are not available yet.") {
                        Text("Does nothing").foregroundStyle(.secondary)
                    }
                    Divider()
                    FormRow(label: "Use on", detail: "Keyboards you connect later show up here, switched off.") {
                        ForEach(model.devices.filter { $0.kind == .keyboard }) { keyboard in
                            VStack(alignment: .leading, spacing: 1) {
                                Toggle(
                                    keyboard.name,
                                    isOn: Binding(
                                        get: { keyboard.profile?.hyper == true },
                                        set: { model.apply(.hyperOn(keyboard.match, name: keyboard.name, $0)) }))
                                Explanation(Self.detail(keyboard)).padding(.leading, 20)
                            }
                        }
                    }
                }
                .disabled(!model.editable)
                Divider()
                FormRow(label: "How it works") {
                    Text("Hyperpoint turns the key into F18 on each keyboard above, then holds ⌃⌥⇧⌘ while you hold F18.")
                        .fixedSize(horizontal: false, vertical: true)
                    Explanation("In password fields macOS keeps typing away from other apps, so the hyper key does nothing there.")
                }
            }
        }
    }

    static func detail(_ keyboard: SettingsDevice) -> String {
        guard keyboard.connected else { return "Not connected" }
        guard keyboard.profile != nil else { return "Connected, new" }
        return switch keyboard.status?.hyper {
        case .on: "Connected, hyper key on"
        case .off: "Connected, hyper key off"
        case .applying: "Connected, turning the hyper key on…"
        case .failed(let why): "Connected, not applied: \(why)"
        case nil: "Connected"
        }
    }
}
