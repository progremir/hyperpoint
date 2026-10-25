import HyperpointKit
import SwiftUI

struct ScrollingTab: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage(model: model) {
            if let device = model.selectedMouse {
                FormRow(label: "Device") { MousePopup(model: model) }
                Divider()
                ScrollingSettings(model: model, device: device)
            } else {
                NoMouseRow()
            }
        }
    }
}

private struct ScrollingSettings: View {
    let model: SettingsModel
    let device: SettingsDevice

    var body: some View {
        let match = device.match
        let smooth = device.profile?.scrolling?.smooth
        let shown = smooth ?? model.smoothWhenOn(match)
        FormRow(label: "Smooth scrolling") {
            Toggle(
                "Smooth scrolling",
                isOn: Binding(
                    get: { smooth != nil },
                    set: { model.apply(.smooth(match, $0 ? model.smoothWhenOn(match) : nil)) })
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(device.profile == nil)
            Explanation("The wheel glides like a trackpad instead of jumping a few lines per step.")
            if device.isNew {
                SetUpButton(model: model, device: device)
                Explanation("Set this mouse up first.")
            }
        }
        .disabled(!model.editable)

        Divider()
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                GroupHeading("How fast the page scrolls")
                Explanation("Spin the wheel faster and the page scrolls faster. The shaded bands are how fast this wheel spins.")
            }
            SpeedGraph(curve: shown.curve) { model.apply(.curve(match, $0)) }
            Divider()
            ForEach(SmoothKnob.allCases, id: \.self) { knob in
                KnobRow(knob: knob, smooth: shown) { model.apply(.smoothKnob(match, knob, $0)) }
            }
            FormRow(label: "", detail: "Puts the scroll speed and every glide setting back to how Hyperpoint ships.") {
                Button("Reset to Defaults") { model.apply(.smooth(match, .default)) }
                    .disabled(smooth == .default)
            }
        }
        .disabled(!model.editable || smooth == nil)

        Divider()
        HoldToScrollSettings(model: model, device: device)

        Divider()
        if device.speaksHIDPP {
            UnavailableRow(title: "High-resolution wheel", detail: "Reads the wheel's finer steps for smoother input.")
        }
        UnavailableRow(
            title: "Click-through",
            detail: "A click on a background window would act right away instead of only bringing it forward.")
    }
}

private struct HoldToScrollSettings: View {
    let model: SettingsModel
    let device: SettingsDevice

    var body: some View {
        let match = device.match
        let settings = device.profile?.scrolling?.holdToScroll ?? .default
        let buttons = (device.profile?.rules ?? []).filter { $0.action == .scroll }.map { Labels.control($0.control) }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                GroupHeading("Hold to scroll")
                Explanation(
                    buttons.isEmpty
                        ? "No button scrolls yet. On the Buttons tab, pick Hold and move, then Scroll, for any button."
                        : "Buttons that scroll: \(ListFormatter.localizedString(byJoining: buttons)). Change them on the Buttons tab.")
            }
            KnobRow(
                title: HoldScrollKnob.title, detail: HoldScrollKnob.detail, scale: HoldScrollKnob.scale,
                unit: HoldScrollKnob.unit, value: settings.speed
            ) { speed in
                model.apply(.holdToScroll(match, HoldToScroll(speed: speed, direction: settings.direction, momentum: settings.momentum)))
            }
            FormRow(
                label: "Direction",
                detail: "Grabbing moves the page with your hand. The scroll wheel way scrolls down when you move down."
            ) {
                Picker(
                    "Direction",
                    selection: Binding(
                        get: { settings.direction },
                        set: {
                            model.apply(.holdToScroll(match, HoldToScroll(speed: settings.speed, direction: $0, momentum: settings.momentum)))
                        })
                ) {
                    Text("Like grabbing the page").tag(HoldScrollDirection.grab)
                    Text("Like the scroll wheel").tag(HoldScrollDirection.wheel)
                }
                .labelsHidden()
                .fixedSize()
            }
            FormRow(label: "", detail: "Let go while moving and the page coasts to a stop, like on a trackpad.") {
                Toggle(
                    "Keep gliding after you let go",
                    isOn: Binding(
                        get: { settings.momentum },
                        set: {
                            model.apply(.holdToScroll(match, HoldToScroll(speed: settings.speed, direction: settings.direction, momentum: $0)))
                        }))
            }
        }
        .disabled(!model.editable || device.profile == nil)
    }
}

/// A slider that saves when the drag ends, so one drag writes the file once.
struct KnobRow: View {
    let title: String
    let detail: String
    let scale: SliderScale
    let unit: KnobUnit
    let value: Double
    let commit: (Double) -> Void
    /// The slider position while a drag is in progress or a save has not come back yet.
    @State private var draft: Double?
    @State private var dragging = false

    init(
        title: String, detail: String, scale: SliderScale, unit: KnobUnit, value: Double,
        commit: @escaping (Double) -> Void
    ) {
        self.title = title
        self.detail = detail
        self.scale = scale
        self.unit = unit
        self.value = value
        self.commit = commit
    }

    init(knob: SmoothKnob, smooth: SmoothScroll, commit: @escaping (Double) -> Void) {
        self.init(
            title: knob.title, detail: knob.detail, scale: knob.scale, unit: knob.unit,
            value: knob.value(in: smooth), commit: commit)
    }

    var body: some View {
        let shown = draft.map(scale.value(at:)) ?? value
        FormRow(label: title, detail: detail) {
            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { draft ?? scale.position(of: value) },
                        set: { position in
                            draft = position
                            if !dragging { finish(position) }
                        }),
                    in: 0...1
                ) { editing in
                    dragging = editing
                    if !editing, let draft { finish(draft) }
                }
                .frame(width: 190)
                .accessibilityLabel(title)
                .accessibilityValue(unit.format(shown))
                Text(unit.format(shown))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: value) { draft = nil }
    }

    private func finish(_ position: Double) {
        let next = scale.value(at: position)
        if next == value {
            draft = nil
        } else {
            commit(next)
        }
    }
}

private struct UnavailableRow: View {
    let title: String
    let detail: String

    var body: some View {
        FormRow(label: title, detail: detail) {
            Text("Not available yet")
        }
        .foregroundStyle(.secondary)
    }
}
