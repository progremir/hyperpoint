import HyperpointKit
import SwiftUI

struct ScrollingTab: View {
    let model: SettingsModel
    let device: SettingsDevice

    var body: some View {
        let match = device.match
        let smooth = device.profile?.scrolling?.smooth
        let shown = smooth ?? model.smoothWhenOn(match)
        Section {
            Toggle(
                isOn: Binding(
                    get: { smooth != nil },
                    set: { model.apply(.smooth(match, $0 ? model.smoothWhenOn(match) : nil)) })
            ) {
                Text("Smooth scrolling")
                Text("The wheel glides like a trackpad instead of jumping a few lines per step.")
            }
            .disabled(device.profile == nil)
        } header: {
            Text("Wheel")
        } footer: {
            if device.profile == nil {
                Text("Add a rule on the Buttons tab first, which gives this mouse a profile.").foregroundStyle(.secondary)
            }
        }
        .disabled(!model.editable)

        Section {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How fast the page scrolls")
                    Text("Spin the wheel faster and the page scrolls faster. The shaded bands are how fast this wheel spins.")
                        .foregroundStyle(.secondary)
                }
                SpeedGraph(curve: shown.curve) { model.apply(.curve(match, $0)) }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Scroll speed")
        }
        .disabled(!model.editable || smooth == nil)

        Section {
            ForEach(SmoothKnob.allCases, id: \.self) { knob in
                KnobRow(knob: knob, smooth: shown) { model.apply(.smoothKnob(match, knob, $0)) }
            }
            HStack {
                Text("Puts the scroll speed and every glide setting back to how Hyperpoint ships.").foregroundStyle(.secondary)
                Spacer()
                Button("Reset to Defaults") { model.apply(.smooth(match, .default)) }
                    .disabled(smooth == .default)
            }
        } header: {
            Text("Glide")
        }
        .disabled(!model.editable || smooth == nil)

        HoldToScrollSection(model: model, device: device)

        Section("More") {
            if device.speaksHIDPP {
                UnavailableRow(title: "High-resolution wheel", detail: "Reads the wheel's finer steps for smoother input.")
            }
            UnavailableRow(
                title: "Click-through",
                detail: "A click on a background window would act right away instead of only bringing it forward.")
        }
    }
}

private struct HoldToScrollSection: View {
    let model: SettingsModel
    let device: SettingsDevice

    var body: some View {
        let match = device.match
        let settings = device.profile?.scrolling?.holdToScroll ?? .default
        let buttons = (device.profile?.rules ?? []).filter { $0.action == .scroll }.map { Labels.control($0.control) }
        Section {
            KnobRow(
                title: HoldScrollKnob.title, detail: HoldScrollKnob.detail, scale: HoldScrollKnob.scale,
                unit: HoldScrollKnob.unit, value: settings.speed
            ) { speed in
                model.apply(.holdToScroll(match, HoldToScroll(speed: speed, direction: settings.direction, momentum: settings.momentum)))
            }
            Picker(
                selection: Binding(
                    get: { settings.direction },
                    set: {
                        model.apply(.holdToScroll(match, HoldToScroll(speed: settings.speed, direction: $0, momentum: settings.momentum)))
                    })
            ) {
                Text("Like grabbing the page").tag(HoldScrollDirection.grab)
                Text("Like the scroll wheel").tag(HoldScrollDirection.wheel)
            } label: {
                Text("Direction")
                Text("Grabbing moves the page with your hand. The scroll wheel way scrolls down when you move down.")
            }
            Toggle(
                isOn: Binding(
                    get: { settings.momentum },
                    set: {
                        model.apply(.holdToScroll(match, HoldToScroll(speed: settings.speed, direction: settings.direction, momentum: $0)))
                    })
            ) {
                Text("Keep gliding after you let go")
                Text("Let go while moving and the page coasts to a stop, like on a trackpad.")
            }
        } header: {
            Text("Hold to scroll")
        } footer: {
            Text(
                buttons.isEmpty
                    ? "No button scrolls yet. On the Buttons tab, pick Hold and move, then Scroll, for any button."
                    : "Buttons that scroll: \(ListFormatter.localizedString(byJoining: buttons)). Change them on the Buttons tab."
            )
            .foregroundStyle(.secondary)
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
        LabeledContent {
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
                    .frame(minWidth: 82, alignment: .trailing)
            }
        } label: {
            Text(title)
            Text(detail)
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
        LabeledContent {
            Text("Not available yet").foregroundStyle(.secondary)
        } label: {
            Text(title)
            Text(detail)
        }
        .foregroundStyle(.secondary)
    }
}
