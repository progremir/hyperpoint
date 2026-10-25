import HyperpointKit
import SwiftUI

struct DevicesTab: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage(model: model) {
            VStack(alignment: .leading, spacing: 12) {
                FormRow(label: "Mice") {
                    DeviceList(model: model, devices: model.mice, none: "No mouse yet.")
                }
                Divider()
                FormRow(label: "Keyboards", detail: "Keyboards and mice you connect later show up here as new.") {
                    DeviceList(model: model, devices: model.devices.filter { $0.kind == .keyboard }, none: "No keyboard yet.")
                }
                if !model.ignoredDevices.isEmpty {
                    Divider()
                    FormRow(label: "Ignored", detail: "Hyperpoint leaves these as macOS has them and does not list them as new.") {
                        ForEach(model.ignoredDevices) { device in
                            HStack {
                                Text(device.name)
                                Spacer()
                                Button("Stop Ignoring") { model.apply(.ignore(device.match, false)) }
                            }
                        }
                    }
                }
            }
            .disabled(!model.editable)
        }
    }
}

private struct DeviceList: View {
    let model: SettingsModel
    let devices: [SettingsDevice]
    let none: String

    var body: some View {
        if devices.isEmpty {
            Text(none).foregroundStyle(.secondary)
        }
        ForEach(devices) { device in
            DeviceRow(model: model, device: device)
        }
    }
}

private struct DeviceRow: View {
    let model: SettingsModel
    let device: SettingsDevice
    @State private var confirmingForget = false

    var body: some View {
        let card = device.card(paused: model.paused, time: clockTime)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                ConnectionDot(connected: card.connected)
                if let profile = device.profile {
                    NameField(name: profile.name) { model.apply(.rename(device.match, $0)) }
                        .frame(width: 220)
                    Picker("Kind", selection: Binding(get: { device.kind }, set: { model.apply(.kind(device.match, $0)) })) {
                        Text("Mouse").tag(DeviceKind.mouse)
                        Text("Keyboard").tag(DeviceKind.keyboard)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("A mouse gets the Buttons and Scrolling tabs. A keyboard can have the hyper key.")
                    Spacer()
                    Button("Forget…") { confirmingForget = true }
                        .help("Remove this device's settings from the config file")
                } else {
                    Text(device.name)
                    Text("New")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                }
            }
            Explanation("\(card.title). \(card.detail)").padding(.leading, 16)
            if device.isNew {
                HStack(spacing: 8) {
                    SetUpButton(model: model, device: device)
                    Button("Ignore") { model.apply(.ignore(device.match, true)) }
                        .help("Stop listing this device as new. Hyperpoint leaves it as macOS has it.")
                }
                .padding(.leading, 16)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 4)
        .confirmationDialog("Forget \(device.name)?", isPresented: $confirmingForget) {
            Button("Forget", role: .destructive) { model.apply(.forget(device.match)) }
        } message: {
            Text(
                "Hyperpoint removes its rules and settings from the config file and leaves it as macOS has it. If it is connected, it shows here as new."
            )
        }
    }
}
