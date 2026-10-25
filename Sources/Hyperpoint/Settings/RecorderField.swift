import SwiftUI

/// A capsule that shows a recorded press or shortcut as key chips, and turns red while it records the next one.
/// Idle, the whole capsule starts recording. Recording, only its Cancel button acts.
struct RecorderField: View {
    enum State: Equatable {
        /// With no label, a small record glyph follows the chips.
        case idle(chips: [String], label: String?)
        case recording(chips: [String], hint: Hint, trailing: String?)
    }

    enum Hint: Equatable {
        /// The device is not listening yet, so the dot is dimmed.
        case gettingReady(String)
        case prompt(String)
        /// Shown in orange.
        case problem(String)

        var text: String {
            switch self {
            case .gettingReady(let text), .prompt(let text), .problem(let text): text
            }
        }

        fileprivate var dimsDot: Bool { if case .gettingReady = self { true } else { false } }

        fileprivate var color: Color { if case .problem = self { .orange } else { .primary } }
    }

    let state: State
    var start: () -> Void = {}
    var cancel: () -> Void = {}

    var body: some View {
        switch state {
        case .idle(let chips, let label):
            Button(action: start) {
                capsule(recording: false) {
                    if !chips.isEmpty { chipRow(chips) }
                    if let label {
                        Text(label).lineLimit(1)
                    } else {
                        Image(systemName: "record.circle").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel((chips + [label].compactMap(\.self)).joined(separator: ", "))
        case .recording(let chips, let hint, let trailing):
            capsule(recording: true) {
                HStack(spacing: 6) {
                    RecordingDot(dimmed: hint.dimsDot)
                    if !chips.isEmpty { chipRow(chips) }
                    Text(hint.text)
                        .foregroundStyle(hint.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let trailing {
                        Text(trailing).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(([hint.text] + chips + [trailing].compactMap(\.self)).joined(separator: ", "))
                Button("Cancel", action: cancel)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .fixedSize()
            }
        }
    }

    private func chipRow(_ chips: [String]) -> some View {
        HStack(spacing: 3) { ForEach(Array(chips.enumerated()), id: \.offset) { KeyChip(text: $0.element) } }
    }

    private func capsule(recording: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 6) { content() }
            .padding(.leading, 5)
            .padding(.trailing, recording ? 3 : 7)
            .padding(.vertical, 3)
            .frame(minHeight: 24)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(recording ? AnyShapeStyle(Color.red.opacity(0.12)) : AnyShapeStyle(.quaternary))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(recording ? Color.red.opacity(0.5) : Color(nsColor: .separatorColor))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// One key or control, drawn as a small keycap.
struct KeyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlColor))
                RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor))
            }
    }
}

private struct RecordingDot: View {
    let dimmed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dot = Circle().fill(Color.red).frame(width: 7, height: 7).opacity(dimmed ? 0.35 : 1)
        if reduceMotion || dimmed {
            dot
        } else {
            dot.phaseAnimator([1.0, 0.4]) { $0.opacity($1) } animation: { _ in .easeInOut(duration: 0.9) }
        }
    }
}
