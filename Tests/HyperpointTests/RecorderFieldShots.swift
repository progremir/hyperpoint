import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Hyperpoint

/// Draws `RecorderField` in each state the window shows, in light and dark, since the window's own snapshots cannot
/// catch a live listen. When `HYPERPOINT_RECORDER_SHOTS` names a directory, each image is also written there as a PNG.
@MainActor
@Suite struct RecorderFieldShots {
    private let directory = ProcessInfo.processInfo.environment["HYPERPOINT_RECORDER_SHOTS"].map {
        URL(fileURLWithPath: $0)
    }

    static let shots: [(name: String, width: CGFloat, state: RecorderField.State)] = [
        ("idle-control", 164, .idle(chips: ["Gesture button"], label: nil)),
        ("idle-chord", 260, .idle(chips: ["⌥", "⇧", "S"], label: "Change shortcut")),
        ("recording-press", 312, .recording(chips: [], hint: .prompt("Press a button"), trailing: nil)),
        ("recording-turn", 312, .recording(chips: [], hint: .prompt("Press a button or turn the wheel"), trailing: nil)),
        ("row-getting-ready", 312, .recording(chips: [], hint: .gettingReady("Getting ready…"), trailing: nil)),
        (
            "getting-ready", 584,
            .recording(chips: [], hint: .gettingReady("Getting MX Master 3 ready…"), trailing: "10 s")
        ),
        (
            "listening", 584,
            .recording(
                chips: [], hint: .prompt("Press a button on MX Master 3"),
                trailing: "9 s")
        ),
        (
            "listening-wheel", 584,
            .recording(
                chips: [],
                hint: .prompt("Press a button or turn the thumb wheel on MX Master 3"),
                trailing: "9 s")
        ),
        ("recording-shortcut", 337, .recording(chips: ["⇧", "⌘"], hint: .prompt("Now press a key"), trailing: nil)),
        (
            "shortcut-problem", 337,
            .recording(
                chips: ["⌘"], hint: .problem("Can't use that key. Try another."),
                trailing: nil)
        ),
    ]

    @Test(arguments: [ColorScheme.light, .dark])
    func everyStateRenders(_ scheme: ColorScheme) throws {
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        for shot in Self.shots {
            let image = try #require(render(shot.state, width: shot.width, scheme: scheme), "\(shot.name)")
            #expect(image.width >= Int(shot.width * 2), "\(shot.name) is drawn at the width it was given")
            guard let directory else { continue }
            let file = directory.appending(path: "\(shot.name)-\(scheme == .dark ? "dark" : "light").png")
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: file)
        }
    }

    /// A rule row's pickers give way to the capsule while it records, and a row that grew would flash the page.
    @Test func everyStateIsAsTallAsAPicker() {
        let picker = NSHostingView(
            rootView: Picker("Do", selection: .constant(0)) { Text("Shortcut ⇧⌘4").tag(0) }.labelsHidden().frame(width: 200))
        #expect(abs(picker.fittingSize.height - RecorderField.height) < 0.5, "\(picker.fittingSize.height)")
        for shot in Self.shots {
            let field = NSHostingView(rootView: RecorderField(state: shot.state).frame(width: shot.width))
            #expect(abs(field.fittingSize.height - RecorderField.height) < 0.5, "\(shot.name) \(field.fittingSize.height)")
        }
    }

    private func render(_ state: RecorderField.State, width: CGFloat, scheme: ColorScheme) -> CGImage? {
        let view = RecorderField(state: state)
            .frame(width: width)
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            image = renderer.cgImage
        }
        return image
    }
}
