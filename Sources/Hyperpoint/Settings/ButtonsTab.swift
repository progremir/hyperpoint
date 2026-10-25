import AppKit
import HyperpointKit
import SwiftUI

struct ButtonsTab: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage(model: model) {
            if let device = model.selectedMouse {
                FormRow(label: "Device") {
                    MousePopup(model: model)
                    StatusLine(
                        card: device.card(paused: model.paused, time: clockTime),
                        reapply: device.isNew ? nil : { model.reapplyAll() })
                }
                Divider()
                Rules(model: model, device: device)
                if device.speaksHIDPP, let profile = device.profile {
                    let gestures = profile.gestures ?? .default
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        FormRow(
                            label: "Hold-and-move rules fire",
                            detail: "Past a distance fires as soon as you move far enough. On release waits until you let go."
                        ) {
                            Picker(
                                "Hold-and-move rules fire",
                                selection: Binding(get: { gestures.fire }, set: { model.apply(.gestureFire(device.match, $0)) })
                            ) {
                                Text("Past a distance").tag(GestureFire.pastDistance)
                                Text("On release").tag(GestureFire.onRelease)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                        KnobRow(
                            title: GestureKnob.title, detail: GestureKnob.detail, scale: GestureKnob.scale,
                            unit: GestureKnob.unit, value: Double(gestures.distance)
                        ) { model.apply(.gestureDistance(device.match, Int($0))) }
                    }
                    .disabled(!model.editable)
                }
            } else {
                NoMouseRow()
            }
        }
    }
}

/// Whether the mouse is connected, what was applied and when, and a way to apply it again.
private struct StatusLine: View {
    let card: StatusCard
    let reapply: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ConnectionDot(connected: card.connected)
                    Text(card.title)
                }
                Explanation(card.detail)
            }
            Spacer()
            if let reapply, card.connected {
                Button("Re-apply", action: reapply).help("Write this profile to the device again")
            }
        }
        .padding(.top, 2)
    }
}

private struct Rules: View {
    let model: SettingsModel
    let device: SettingsDevice

    var body: some View {
        let choices = model.choices(for: device)
        let rules = device.profile?.rules ?? []
        let skipped = device.status?.hidpp?.skippedRules ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GroupHeading("Rules")
                Spacer()
                Text(rules.count == 1 ? "1 rule" : "\(rules.count) rules").foregroundStyle(.secondary)
            }
            if device.isNew {
                SetUpButton(model: model, device: device)
                Explanation("Set this mouse up to give it rules.")
            } else if rules.isEmpty {
                Text("No rules yet, so every button works as usual.").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Text("Button").frame(width: RuleRow.controlWidth, alignment: .leading)
                    Text("When").frame(width: RuleRow.triggerWidth, alignment: .leading)
                    Text("Do")
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                ForEach(rules, id: \.key) { rule in
                    RuleRow(
                        rule: rule, choices: choices, skipped: skipped.contains(rule),
                        highlighted: note?.highlights(rule) == true,
                        replace: { model.apply(.replaceRule(device.match, rule.key, $0)) },
                        remove: { model.apply(.removeRule(device.match, rule.key)) })
                    if rule.action == .scroll {
                        Explanation(
                            Labels.holdToScroll(
                                control: rule.control,
                                hasClickRule: rules.contains { $0.control == rule.control && $0.trigger == .click }))
                        .padding(.leading, RuleRow.controlWidth + 10)
                    }
                }
            }
            if !device.isNew {
                AddRule(model: model, device: device, controls: choices.controls, note: note)
            }
            Explanation(footer)
        }
        .disabled(!model.editable)
    }

    private var note: LearnNote? { model.learnNote.flatMap { $0.match == device.match ? $0 : nil } }

    private var footer: String {
        if device.speaksHIDPP { return "Buttons without a rule, like Back and Forward, work as usual." }
        return "Hyperpoint carries out rules for plain buttons. It saves rules for keys, but does not carry them out yet."
    }
}

/// Add Rule listens for the next press on the mouse. Its menu adds a rule for a control without pressing it, which the
/// thumb wheel and a mouse that is not connected need.
private struct AddRule: View {
    let model: SettingsModel
    let device: SettingsDevice
    let controls: [Control]
    let note: LearnNote?

    var body: some View {
        switch device.status?.listen {
        case .gettingReady(let until):
            ListenRow(device: device.name, ready: false, until: until) { model.stopListening() }
        case .listening(let until):
            ListenRow(device: device.name, ready: true, until: until) { model.stopListening() }
        case .ended(let why):
            menu(blocked: device.cannotListen(paused: model.paused, permissions: model.permissions))
            Explanation(Labels.listenEnded(why, device: device.name))
        case nil:
            let blocked = device.cannotListen(paused: model.paused, permissions: model.permissions)
            menu(blocked: blocked)
            if let text = note.flatMap(Labels.learned) ?? blocked { Explanation(text) }
        }
    }

    /// Without a press to listen for, a click opens the menu.
    @ViewBuilder private func menu(blocked: String?) -> some View {
        Group {
            if blocked == nil {
                Menu { picks } label: { label } primaryAction: { model.listen(for: device) }
                    .help("Press a button on \(device.name) to add a rule for it, or pick one from the menu")
            } else {
                Menu { picks } label: { label }.help("Pick a button to add a rule for")
            }
        }
        .menuIndicator(.visible)
        .fixedSize()
    }

    private var label: some View { Label("Add Rule", systemImage: "plus") }

    @ViewBuilder private var picks: some View {
        Section("Choose a Button") {
            ForEach(controls, id: \.self) { control in
                Button(Labels.control(control)) { model.pick(control, on: device) }
            }
        }
    }
}

/// Replaces Add Rule while Hyperpoint listens. Esc on the Mac's keyboard cancels too. The listened mouse's own keys
/// never reach the window.
private struct ListenRow: View {
    let device: String
    let ready: Bool
    let until: Date
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(ready ? "Press a button on \(device). The left button keeps working." : "Getting \(device) ready…")
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("\(Int(max(0, until.timeIntervalSince(context.date)).rounded(.up))) s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
        }
    }
}

private struct RuleRow: View {
    static let controlWidth = 160.0
    static let triggerWidth = 150.0

    enum ActionChoice: Hashable {
        case action(Action)
        case recordShortcut
    }

    let rule: Rule
    let choices: RuleChoices
    let skipped: Bool
    let highlighted: Bool
    let replace: (Rule) -> Void
    let remove: () -> Void
    @State private var recording = false

    var body: some View {
        HStack(spacing: 10) {
            Picker("Button", selection: Binding(get: { rule.control }, set: { replace(choices.rule(rule, withControl: $0)) })) {
                ForEach(choices.controls(for: rule), id: \.self) { Text(Labels.control($0)).tag($0) }
            }
            .buttonSizing(.flexible)
            .frame(width: Self.controlWidth)
            Picker("When", selection: Binding(get: { rule.trigger }, set: { replace(choices.rule(rule, withTrigger: $0)) })) {
                ForEach(choices.triggers(for: rule.control, besides: rule), id: \.self) { Text(Labels.trigger($0)).tag($0) }
            }
            .buttonSizing(.flexible)
            .frame(width: Self.triggerWidth)
            Picker("Do", selection: Binding(get: { ActionChoice.action(rule.action) }, set: choose)) {
                ForEach(actionChoices, id: \.choice) { Text($0.label).tag($0.choice) }
            }
            .buttonSizing(.flexible)
            .frame(maxWidth: .infinity)
            .popover(isPresented: $recording, arrowEdge: .bottom) {
                ShortcutRecorder { chord in
                    recording = false
                    replace(Rule(control: rule.control, trigger: rule.trigger, action: .shortcut(chord)))
                } cancel: {
                    recording = false
                }
            }
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("This mouse cannot do this, so Hyperpoint skips the rule.")
                .accessibilityLabel("Skipped")
                .opacity(skipped ? 1 : 0)
                .accessibilityHidden(!skipped)
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this rule")
            .accessibilityLabel("Remove rule")
        }
        .labelsHidden()
        .background {
            RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(highlighted ? 0.18 : 0)).padding(-4)
        }
        .animation(.easeOut(duration: 0.3), value: highlighted)
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
