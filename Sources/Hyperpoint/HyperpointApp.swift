import AppKit
import os

@main
@MainActor
enum HyperpointMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var termination: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { [model] in
            await OtherCopies.quit()
            model.start()
            if let directory = UserDefaults.standard.string(forKey: "snapshotSettings") {
                model.snapshotSettings(to: URL(fileURLWithPath: directory))
            }
        }
        // SIGTERM would otherwise skip the quit path and leave Caps Lock mapped to Right Control.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        source.resume()
        termination = source
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// The release and the development build, Hyperpoint Dev, are separate apps that drive the same devices, so the one
/// opened last quits the other and waits for it to put the devices back before setting them up itself. A copy that
/// opened later is left alone: it quits this one.
@MainActor
enum OtherCopies {
    private static let bundleIDs = ["dev.emir.hyperpoint", "dev.emir.hyperpoint.dev"]
    private static let log = Logger(subsystem: "dev.emir.hyperpoint", category: "launch")

    static func quit() async {
        let opened = NSRunningApplication.current.launchDate ?? .now
        let others = bundleIDs.filter { $0 != Bundle.main.bundleIdentifier }
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { ($0.launchDate ?? .distantPast) <= opened }
        for other in others {
            log.info("quitting \(other.bundleIdentifier ?? "?", privacy: .public) pid \(other.processIdentifier)")
            other.terminate()
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while others.contains(where: { !$0.isTerminated }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
