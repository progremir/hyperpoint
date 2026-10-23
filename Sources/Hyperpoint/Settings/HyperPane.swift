import HyperpointKit
import SwiftUI

struct HyperPane: View {
    let model: SettingsModel

    /// Without a tap action the hyper key stops typing as itself, so the list keeps to keys most people never type.
    static let keys: [HIDUsage] = ["capsLock", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"]
        .compactMap(HIDUsage.init(name:))

    var body: some View {
        PaneScaffold(title: "Hyper key", model: model) {
            if let config = model.config {
                let keys = Self.keys.contains(config.hyper.key) ? Self.keys : [config.hyper.key] + Self.keys
                Section("Hyper key") {
                    Picker(selection: Binding(get: { config.hyper.key }, set: { model.apply(.hyperKey($0)) })) {
                        ForEach(keys, id: \.self) { Text(Labels.key($0.name ?? "")).tag($0) }
                    } label: {
                        Text("Key")
                        Text("Holding it holds ⌃⌥⇧⌘ on the keyboards below. It no longer types as itself.")
                    }
                    LabeledContent {
                        Text("⌃ ⌥ ⇧ ⌘").font(.body.monospaced())
                    } label: {
                        Text("While held")
                        Text("Every key you press gets Control, Option, Shift and Command, for app shortcuts.")
                    }
                    LabeledContent {
                        Text("Does nothing").foregroundStyle(.secondary)
                    } label: {
                        Text("Tapped alone")
                        Text("Other tap actions are not available yet.")
                    }
                }
                .disabled(!model.editable)

                Section {
                    ForEach(model.devices.filter { $0.kind == .keyboard }) { keyboard in
                        Toggle(
                            isOn: Binding(
                                get: { keyboard.profile?.hyper == true },
                                set: { model.apply(.hyperOn(keyboard.match, name: keyboard.name, $0)) })
                        ) {
                            Text(keyboard.name)
                            Text(Self.detail(keyboard))
                        }
                    }
                } header: {
                    Text("Use on")
                } footer: {
                    Text("Keyboards you connect later show up here, switched off.")
                        .foregroundStyle(.secondary)
                }
                .disabled(!model.editable)
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
