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
    /// One row at a time records a shortcut, since its key monitor takes every key the window gets.
    @State private var recordingShortcut: RuleKey?

    var body: some View {
        let choices = model.choices(for: device)
        let rules = device.profile?.rules ?? []
        let skipped = device.status?.hidpp?.skippedRules ?? []
        let cannotListen = device.cannotListen(paused: model.paused, permissions: model.permissions)
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
                        listen: model.listenPurpose == .replaceRule(rule.key) ? device.status?.listen : nil,
                        cannotListen: cannotListen, device: device.name,
                        recordingShortcut: Binding(
                            get: { recordingShortcut == rule.key },
                            set: { recordingShortcut = $0 ? rule.key : nil }),
                        startListening: { model.listen(for: device, to: .replaceRule(rule.key)) },
                        stopListening: { model.stopListening() },
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
            if device.isNew {
                Explanation(footer)
            } else {
                AddRule(
                    model: model, device: device, controls: choices.controls,
                    thumbWheel: choices.capabilities?.thumbWheel == true, note: note, footer: footer)
            }
        }
        .disabled(!model.editable)
    }

    private var note: LearnNote? { model.learnNote.flatMap { $0.match == device.match ? $0 : nil } }

    private var footer: String {
        if device.speaksHIDPP { return "Buttons without a rule, like Back and Forward, work as usual." }
        return "Hyperpoint carries out rules for plain buttons. It saves rules for keys, but does not carry them out yet."
    }
}

/// Add Rule listens for the next press or thumb-wheel turn on the mouse. Its menu adds a rule for a control without
/// pressing it, which a mouse that is not connected needs.
private struct AddRule: View {
    let model: SettingsModel
    let device: SettingsDevice
    let controls: [Control]
    let thumbWheel: Bool
    let note: LearnNote?
    let footer: String

    /// Fits the listening capsule as well as the button, so starting a listen does not grow the page. A page that
    /// grows in place hides until the window has its height, which flashed it blank on every Add Rule.
    static let height = 28.0

    /// A listen for a rule's Button cell shows in that row, not here. The line under it always holds one line of text,
    /// for the same reason.
    var body: some View {
        let blocked = device.cannotListen(paused: model.paused, permissions: model.permissions)
        VStack(alignment: .leading, spacing: 8) {
            Group {
                switch device.status?.listen {
                case .gettingReady(let until) where model.listenPurpose == .addRule:
                    ListenRow(device: device.name, thumbWheel: thumbWheel, ready: false, until: until) { model.stopListening() }
                case .listening(let until) where model.listenPurpose == .addRule:
                    ListenRow(device: device.name, thumbWheel: thumbWheel, ready: true, until: until) { model.stopListening() }
                default:
                    menu(blocked: blocked)
                }
            }
            .frame(height: Self.height, alignment: .leading)
            Explanation(status(blocked: blocked)).lineLimit(1)
        }
    }

    private func status(blocked: String?) -> String {
        switch device.status?.listen {
        case .gettingReady, .listening:
            model.listenPurpose == .addRule ? "The left button keeps working while Hyperpoint listens." : footer
        case .ended(let why): Labels.listenEnded(why, device: device.name)
        case nil: note.flatMap(Labels.learned) ?? blocked ?? footer
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
    let thumbWheel: Bool
    let ready: Bool
    let until: Date
    let cancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            RecorderField(
                state: .recording(
                    chips: [],
                    hint: ready
                        ? .prompt("\(ask) on \(device)")
                        : .gettingReady("Getting \(device) ready…"),
                    trailing: "\(Int(max(0, until.timeIntervalSince(context.date)).rounded(.up))) s"),
                cancel: cancel)
        }
    }

    private var ask: String { thumbWheel ? "Press a button or turn the thumb wheel" : "Press a button" }
}

private struct RuleRow: View {
    static let controlWidth = 152.0
    static let triggerWidth = 150.0

    enum ActionChoice: Hashable {
        case action(Action)
        case recordShortcut
    }

    let rule: Rule
    let choices: RuleChoices
    let skipped: Bool
    let highlighted: Bool
    /// This row's listen, when the window listens to give this rule a new button.
    let listen: ListenStatus?
    let cannotListen: String?
    let device: String
    @Binding var recordingShortcut: Bool
    let startListening: () -> Void
    let stopListening: () -> Void
    let replace: (Rule) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // A recording capsule needs more room than the Button cell has, so it takes When's too, as a shortcut
            // takes Do's.
            if recordingPress {
                RecorderField(state: buttonField, start: startListening, cancel: stopListening)
                    .frame(width: Self.controlWidth + 10 + Self.triggerWidth)
            } else {
                HStack(spacing: 2) {
                    RecorderField(state: buttonField, start: startListening, cancel: stopListening)
                        .disabled(cannotListen != nil)
                        .help(cannotListen ?? "Click, then press a button on \(device) to use it for this rule")
                    // The menu reaches every control while the mouse is away.
                    Menu {
                        Picker("Button", selection: Binding(get: { rule.control }, set: { edit(choices.rule(rule, withControl: $0)) })) {
                            ForEach(choices.controls(for: rule), id: \.self) { Text(Labels.control($0)).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Choose a button")
                    .accessibilityLabel("Choose a button")
                }
                .frame(width: Self.controlWidth)
            }
            // A shortcut's hint and live chips need more room than the Do cell has, so recording takes When's too.
            if recordingShortcut {
                ShortcutField { chord in
                    recordingShortcut = false
                    edit(Rule(control: rule.control, trigger: rule.trigger, action: .shortcut(chord)))
                } cancel: {
                    recordingShortcut = false
                }
                .frame(maxWidth: .infinity)
            } else {
                if !recordingPress {
                    Picker("When", selection: Binding(get: { rule.trigger }, set: { edit(choices.rule(rule, withTrigger: $0)) })) {
                        ForEach(choices.triggers(for: rule.control, besides: rule), id: \.self) { Text(Labels.trigger($0)).tag($0) }
                    }
                    .buttonSizing(.flexible)
                    .frame(width: Self.triggerWidth)
                }
                Picker("Do", selection: Binding(get: { ActionChoice.action(rule.action) }, set: choose)) {
                    ForEach(actionChoices, id: \.choice) { Text($0.label).tag($0.choice) }
                }
                .buttonSizing(.flexible)
                .frame(maxWidth: .infinity)
            }
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("This mouse cannot do this, so Hyperpoint skips the rule.")
                .accessibilityLabel("Skipped")
                .opacity(skipped ? 1 : 0)
                .accessibilityHidden(!skipped)
            Button {
                if recordingPress { stopListening() }
                remove()
            } label: {
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

    private var buttonField: RecorderField.State {
        switch listen {
        case .gettingReady: .recording(chips: [], hint: .gettingReady("Getting ready…"), trailing: nil)
        case .listening:
            .recording(
                chips: [],
                hint: .prompt(choices.capabilities?.thumbWheel == true ? "Press a button or turn the wheel" : "Press a button"),
                trailing: nil)
        case .ended, nil: .idle(chips: [Labels.control(rule.control)], label: nil)
        }
    }

    private var recordingPress: Bool {
        if case .recording = buttonField { true } else { false }
    }

    /// An edit made by hand ends this row's listen, whose press would otherwise find the rule gone.
    private func edit(_ edited: Rule) {
        if recordingPress { stopListening() }
        replace(edited)
    }

    private func choose(_ choice: ActionChoice) {
        switch choice {
        case .action(let action): edit(Rule(control: rule.control, trigger: rule.trigger, action: action))
        case .recordShortcut: recordingShortcut = true
        }
    }
}

/// Records a shortcut in place of the When and Do pickers. It saves on the first key down that makes a chord the file
/// can name, and Escape alone cancels.
private struct ShortcutField: View {
    let record: (Chord) -> Void
    let cancel: () -> Void
    @State private var monitor: Any?
    @State private var held = Modifiers()
    @State private var unnameable = false

    var body: some View {
        RecorderField(state: .recording(chips: Labels.modifierSymbols(held), hint: hint, trailing: nil), cancel: cancel)
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                    if event.type == .flagsChanged {
                        held = Labels.modifiers(event.modifierFlags)
                        return event
                    }
                    if event.keyCode == 53, Labels.modifiers(event.modifierFlags).isEmpty {
                        cancel()
                    } else if let chord = Labels.recordedChord(keyCode: event.keyCode, flags: event.modifierFlags) {
                        record(chord)
                    } else {
                        unnameable = true
                    }
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private var hint: RecorderField.Hint {
        if unnameable { return .problem("Hyperpoint cannot name that key in a shortcut. Try another.") }
        return .prompt(held.isEmpty ? "Type the shortcut" : "Now press a key")
    }
}
