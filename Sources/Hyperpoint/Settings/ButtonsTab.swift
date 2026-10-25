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
                Button {
                    if let rule = choices.newRule { model.apply(.addRule(device.match, rule)) }
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .disabled(choices.newRule == nil)
            }
            Explanation(footer)
        }
        .disabled(!model.editable)
    }

    private var footer: String {
        if device.speaksHIDPP { return "Buttons without a rule, like Back and Forward, work as usual." }
        return "Hyperpoint carries out rules for plain buttons. It saves rules for keys, but does not carry them out yet."
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
