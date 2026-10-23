import ApplicationServices
public import Foundation
import IOKit.hid

public enum Permissions {
    public static func current() -> PermissionState {
        let listen = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        return PermissionState(
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            inputMonitoring: listen == kIOHIDAccessTypeGranted
                ? .granted : listen == kIOHIDAccessTypeDenied ? .denied : .notDetermined)
    }

    /// The current state, then each change.
    public static func updates(every interval: Duration = .seconds(1)) -> AsyncStream<PermissionState> {
        AsyncStream { continuation in
            let poll = Task {
                var last: PermissionState?
                while !Task.isCancelled {
                    let now = current()
                    if now != last { continuation.yield(now) }
                    last = now
                    try? await Task.sleep(for: interval)
                }
            }
            continuation.onTermination = { _ in poll.cancel() }
        }
    }

    /// Lists the app in the System Settings pane, which a toggle needs, and opens the system prompt.
    public static func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            // The literal is kAXTrustedCheckOptionPrompt, a C global that Swift 6 treats as shared mutable state.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    public static func settingsURL(for permission: Permission) -> URL {
        let anchor = permission == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}
