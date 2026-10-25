import HyperpointKit
import SwiftUI

/// A page's link to the window. The page reports its full size as SwiftUI places it, so the window can take its
/// height, and the window says whether it stopped at the bottom of the screen, the only time the page scrolls.
@MainActor
@Observable
final class PageFit {
    @ObservationIgnored private(set) var size: CGSize?
    var scrolls = false
    @ObservationIgnored private let resized: () -> Void

    init(resized: @escaping () -> Void) { self.resized = resized }

    func place(_ size: CGSize) {
        guard size != self.size else { return }
        self.size = size
        resized()
    }
}

/// Places its one subview and reports the subview's size to `fit` while placing it, in the update that draws the
/// change. `onGeometryChange` reports after that update, which would let a page that grew draw once, clipped, before
/// the window could hide it.
struct PageMeasure: Layout {
    let fit: PageFit?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        MainActor.assumeIsolated { fit?.place(bounds.size) }
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}

extension EnvironmentValues {
    @Entry var pageFit: PageFit?
}

/// One tab's page at the window's fixed width. The window takes the page's height, and the page scrolls only when
/// the screen is shorter than it. Every page says when the file is invalid or a save failed, since any tab can be
/// open when that happens.
struct SettingsPage<Content: View>: View {
    let model: SettingsModel
    @ViewBuilder var content: Content
    @Environment(\.pageFit) private var pageFit

    var body: some View {
        ScrollView {
            PageMeasure(fit: pageFit) {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = model.snapshot?.error {
                        FormRow(label: "Config file") {
                            Label("The config file has an error", systemImage: "exclamationmark.triangle.fill")
                                .symbolRenderingMode(.multicolor)
                            Explanation(
                                "\(error.description). Hyperpoint keeps using the last good settings. Fix the file to change settings here.")
                            Button("Open in Editor") { model.openConfigInEditor() }
                        }
                        Divider()
                    }
                    if let saveError = model.saveError {
                        FormRow(label: "Not saved") {
                            Label(saveError, systemImage: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                        }
                        Divider()
                    }
                    content
                }
                // A fixed width keeps a scroll bar that shows up mid-animation from rewrapping the text, which would
                // change the height the window is heading for.
                .frame(width: 584)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // A page that fits the screen has nothing to scroll to, even in a frame where the window is still catching up.
        .scrollIndicators(pageFit?.scrolls == true ? .automatic : .never)
        .frame(width: 640)
    }
}

/// A right-aligned label in the left column, and the control with its explanation in the right one. Every page uses
/// the same label width, so the columns line up from tab to tab.
struct FormRow<Content: View>: View {
    static var labelWidth: CGFloat { 170 }

    let label: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.isEmpty ? "" : "\(label):")
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.labelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 5) {
                content
                if let detail { Explanation(detail) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A bold heading over a group of rows or a short how-to.
struct GroupHeading: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View { Text(title).font(.headline).padding(.top, 2) }
}

/// The small secondary line under a control that says what it does.
struct Explanation: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// The Device popup on the Buttons and Scrolling tabs. Both bind the model's one selection, so they show the same mouse.
struct MousePopup: View {
    let model: SettingsModel

    var body: some View {
        Picker("Device", selection: Binding(get: { model.selectedMouse?.match }, set: { model.mouse = $0 })) {
            ForEach(model.mice) { mouse in
                Text(mouse.isNew ? "\(mouse.name) (New)" : mouse.name).tag(Optional(mouse.match))
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

struct SetUpButton: View {
    let model: SettingsModel
    let device: SettingsDevice

    var body: some View {
        if let config = model.config {
            let choices = SetupChoices(for: device, in: config)
            Menu(Labels.setUp(choices.suggested)) {
                ForEach(choices.others, id: \.self) { source in
                    Button(Labels.setUpItem(source, in: config)) { setUp(source) }
                        .help(Labels.setUpHelp(source, in: config))
                }
            } primaryAction: {
                setUp(choices.suggested)
            }
            .menuIndicator(choices.others.isEmpty ? .hidden : .visible)
            .help(Labels.setUpHelp(choices.suggested, in: config))
            .fixedSize()
        }
    }

    private func setUp(_ source: ProfileSource) { model.apply(.addDevice(device.match, name: device.name, source)) }
}

/// What the Buttons and Scrolling tabs show before any mouse has been seen.
struct NoMouseRow: View {
    var body: some View {
        FormRow(label: "Device", detail: "Connect a mouse and it shows up here.") {
            Text("No mouse yet").foregroundStyle(.secondary)
        }
    }
}

struct ConnectionDot: View {
    let connected: Bool

    var body: some View {
        Circle()
            .fill(connected ? Color.green : Color.clear)
            .strokeBorder(connected ? Color.clear : Color.secondary, lineWidth: 1.5)
            .frame(width: 8, height: 8)
            .accessibilityLabel(connected ? "Connected" : "Not connected")
    }
}

/// A name shown as text. A click turns it into a field that saves on Return or when it loses focus, and Escape puts
/// the name back.
struct NameField: View {
    let name: String
    let save: (String) -> Void
    @State private var draft: String?
    /// Shown until the saved file brings the new name back, so the old one does not flash in between.
    @State private var saved: String?
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if let draft {
                TextField("Name", text: Binding(get: { draft }, set: { self.draft = $0 }))
                    .labelsHidden()
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit(commit)
                    .onExitCommand { self.draft = nil }
                    .onChange(of: focused) { if !focused { commit() } }
                    .accessibilityLabel("Name in Hyperpoint")
            } else {
                HStack(spacing: 4) {
                    Text(saved ?? name).lineLimit(1)
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                        .opacity(hovering && isEnabled ? 1 : 0)
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .onTapGesture(perform: edit)
                .help("Click to rename")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Name in Hyperpoint")
                .accessibilityValue(saved ?? name)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { edit() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: name) { saved = nil }
    }

    private func edit() {
        if isEnabled { draft = saved ?? name }
    }

    private func commit() {
        guard let draft else { return }
        self.draft = nil
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return }
        saved = trimmed
        save(trimmed)
    }
}

extension Rule {
    var key: RuleKey { RuleKey(self) }
}

func clockTime(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
