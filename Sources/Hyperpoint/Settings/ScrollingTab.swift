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

        Section("More") {
            if device.speaksHIDPP {
                UnavailableRow(title: "High-resolution wheel", detail: "Reads the wheel's finer steps for smoother input.")
            }
            UnavailableRow(
                title: "Hold the right button and drag to scroll",
                detail: "A right click without dragging would still open the menu.")
            UnavailableRow(
                title: "Click-through",
                detail: "A click on a background window would act right away instead of only bringing it forward.")
        }
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
