import AppKit
import HyperpointKit
import SwiftUI

struct DevicePane: View {
    @Bindable var model: SettingsModel
    let device: SettingsDevice

    var body: some View {
        PaneScaffold(title: device.name, model: model, accessory: { tabs }, content: { sections })
    }

    @ViewBuilder private var tabs: some View {
        if device.kind == .mouse {
            Picker("Settings", selection: $model.tab) {
                Text("Buttons").tag(DeviceTab.buttons)
                Text("Scrolling and clicks").tag(DeviceTab.scrolling)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    @ViewBuilder private var sections: some View {
        Section {
            StatusCardView(
                card: device.card(paused: model.paused, time: clockTime),
                reapply: device.isNew ? nil : { model.reapplyAll() })
        }
        if device.kind == .keyboard {
            KeyboardSections(model: model, device: device)
        } else if model.tab == .buttons {
            ButtonsTab(model: model, device: device)
        } else {
            ScrollingTab(model: model, device: device)
        }
    }
}

private struct StatusCardView: View {
    let card: StatusCard
    let reapply: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ConnectionDot(connected: card.connected)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).fontWeight(.semibold)
                Text(card.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let reapply, card.connected {
                Button("Re-apply", action: reapply).help("Write this profile to the device again")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct KeyboardSections: View {
    let model: SettingsModel
    let device: SettingsDevice

    var body: some View {
        Section("Hyper key") {
            Toggle(
                isOn: Binding(
                    get: { device.profile?.hyper == true },
                    set: { model.apply(.hyperOn(device.match, name: device.name, $0)) })
            ) {
                Text("Use the hyper key on this keyboard")
                Text("Holding \(Labels.key(model.config?.hyper.key.name ?? "capsLock")) holds ⌃⌥⇧⌘. Pick the key under Hyper key.")
            }
        }
        .disabled(!model.editable)
        if let profile = device.profile {
            Section("This keyboard") {
                NameField(name: profile.name) { model.apply(.rename(device.match, $0)) }
            }
            .disabled(!model.editable)
        }
    }
}

private struct ButtonsTab: View {
    let model: SettingsModel
    let device: SettingsDevice

    var body: some View {
        let choices = model.choices(for: device)
        let rules = device.profile?.rules ?? []
        let skipped = device.status?.hidpp?.skippedRules ?? []
        Section {
            if rules.isEmpty {
                Text("No rules yet, so every button works as usual.").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Text("Button").frame(width: RuleRow.controlWidth, alignment: .leading)
                    Text("When").frame(width: RuleRow.triggerWidth, alignment: .leading)
                    Text("Do")
                    Spacer()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                ForEach(rules, id: \.key) { rule in
                    RuleRow(
                        rule: rule, choices: choices, skipped: skipped.contains(rule),
                        replace: { model.apply(.replaceRule(device.match, rule.key, $0)) },
                        remove: { model.apply(.removeRule(device.match, rule.key)) })
                    if rule.action == .scroll {
                        Text(
                            Labels.holdToScroll(
                                control: rule.control,
                                hasClickRule: rules.contains { $0.control == rule.control && $0.trigger == .click })
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, RuleRow.controlWidth + 10)
                    }
                }
            }
            HStack {
                Button {
                    if let rule = choices.newRule { model.apply(.addRule(device.match, name: device.name, rule)) }
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .disabled(choices.newRule == nil)
                Spacer()
            }
        } header: {
            HStack {
                Text("Rules")
                Spacer()
                Text(rules.count == 1 ? "1 rule" : "\(rules.count) rules").fontWeight(.regular)
            }
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }
        .disabled(!model.editable)

        if device.speaksHIDPP, let profile = device.profile {
            let gestures = profile.gestures ?? .default
            Section("Gestures") {
                Picker(
                    selection: Binding(get: { gestures.fire }, set: { model.apply(.gestureFire(device.match, $0)) })
                ) {
                    Text("Past a distance").tag(GestureFire.pastDistance)
                    Text("On release").tag(GestureFire.onRelease)
                } label: {
                    Text("Hold-and-move rules fire")
                    Text("Past a distance fires as soon as you move far enough. On release waits until you let go.")
                }
                .pickerStyle(.segmented)
                KnobRow(
                    title: GestureKnob.title, detail: GestureKnob.detail, scale: GestureKnob.scale,
                    unit: GestureKnob.unit, value: Double(gestures.distance)
                ) { model.apply(.gestureDistance(device.match, Int($0))) }
            }
            .disabled(!model.editable)
        }

        if let profile = device.profile {
            Section("This mouse") {
                NameField(name: profile.name) { model.apply(.rename(device.match, $0)) }
            }
            .disabled(!model.editable)
        }
    }

    private var footer: String {
        if device.speaksHIDPP { return "Buttons without a rule, like Back and Forward, work as usual." }
        return "Hyperpoint carries out rules for plain buttons. It saves rules for keys, but does not carry them out yet."
    }
}

private struct RuleRow: View {
    static let controlWidth = 170.0
    static let triggerWidth = 150.0

    enum ActionChoice: Hashable {
        case action(Action)
        case recordShortcut
    }

    let rule: Rule
    let choices: RuleChoices
    let skipped: Bool
    let replace: (Rule) -> Void
    let remove: () -> Void
    @State private var recording = false

    var body: some View {
        HStack(spacing: 10) {
            Picker("Button", selection: Binding(get: { rule.control }, set: { replace(choices.rule(rule, withControl: $0)) })) {
                ForEach(choices.controls(for: rule), id: \.self) { Text(Labels.control($0)).tag($0) }
            }
            .frame(width: Self.controlWidth, alignment: .leading)
            Picker("When", selection: Binding(get: { rule.trigger }, set: { replace(choices.rule(rule, withTrigger: $0)) })) {
                ForEach(choices.triggers(for: rule.control, besides: rule), id: \.self) { Text(Labels.trigger($0)).tag($0) }
            }
            .frame(width: Self.triggerWidth, alignment: .leading)
            Picker("Do", selection: Binding(get: { ActionChoice.action(rule.action) }, set: choose)) {
                ForEach(actionChoices, id: \.choice) { Text($0.label).tag($0.choice) }
            }
            .popover(isPresented: $recording, arrowEdge: .bottom) {
                ShortcutRecorder { chord in
                    recording = false
                    replace(Rule(control: rule.control, trigger: rule.trigger, action: .shortcut(chord)))
                } cancel: {
                    recording = false
                }
            }
            if skipped {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This mouse cannot do this, so Hyperpoint skips the rule.")
                    .accessibilityLabel("Skipped")
            }
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this rule")
            .accessibilityLabel("Remove rule")
        }
        .labelsHidden()
    }

    private var actionChoices: [(choice: ActionChoice, label: String)] {
        choices.actions(for: rule.control, on: rule.trigger).flatMap { action -> [(choice: ActionChoice, label: String)] in
            guard case .shortcut = action else { return [(.action(action), Labels.action(action))] }
            guard case .shortcut = rule.action else { return [(.recordShortcut, "Keyboard Shortcut…")] }
            return [(.action(rule.action), Labels.action(rule.action)), (.recordShortcut, "Record Another Shortcut…")]
        }
    }

    private func choose(_ choice: ActionChoice) {
        switch choice {
        case .action(let action): replace(Rule(control: rule.control, trigger: rule.trigger, action: action))
        case .recordShortcut: recording = true
        }
    }
}

private struct ShortcutRecorder: View {
    let record: (Chord) -> Void
    let cancel: () -> Void
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 10) {
            Text("Type the shortcut").font(.headline)
            Text(problem ?? "Press the keys together, for example ⇧⌘4. Escape cancels.")
                .foregroundStyle(problem == nil ? Color.secondary : Color.orange)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Cancel", action: cancel)
        }
        .padding(16)
        .frame(width: 260)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
                if event.keyCode == 53, modifiers.isEmpty {
                    cancel()
                } else if let chord = Labels.recordedChord(keyCode: event.keyCode, flags: event.modifierFlags) {
                    record(chord)
                } else {
                    problem = "Hyperpoint cannot name that key in a shortcut. Try another."
                }
                return nil
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
