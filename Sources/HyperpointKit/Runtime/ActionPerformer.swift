import CoreGraphics
import Darwin
import os

/// Posts the events a button action stands for.
@MainActor
public final class ActionPerformer {
    private typealias GetSymbolicHotKeyValue = @convention(c) (
        Int32, UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer
    ) -> Int32
    private typealias IsSymbolicHotKeyEnabled = @convention(c) (Int32) -> Bool

    private static let unboundKey: UInt32 = 0xFFFF

    /// Private CoreGraphics functions, looked up at run time so a macOS that drops them disables only these actions.
    private let getSymbolicHotKeyValue: GetSymbolicHotKeyValue?
    private let isSymbolicHotKeyEnabled: IsSymbolicHotKeyEnabled?
    private let source = CGEventSource(stateID: .privateState)
    private let log = Logger(subsystem: "dev.emir.hyperpoint", category: "actions")

    public init() {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        getSymbolicHotKeyValue = dlsym(defaultHandle, "CGSGetSymbolicHotKeyValue").map {
            unsafeBitCast($0, to: GetSymbolicHotKeyValue.self)
        }
        isSymbolicHotKeyEnabled = dlsym(defaultHandle, "CGSIsSymbolicHotKeyEnabled").map {
            unsafeBitCast($0, to: IsSymbolicHotKeyEnabled.self)
        }
    }

    public func perform(_ action: Action) {
        switch action {
        case .system(let hotKey):
            postSymbolicHotKey(hotKey)
        case .shortcut(let chord):
            post(key: CGKeyCode(chord.key.rawValue), flags: chord.modifiers.cgFlags, to: .cghidEventTap)
        case .modifier, .reverse:
            log.fault("\(String(describing: action), privacy: .public) is not a button action")
        }
    }

    private func postSymbolicHotKey(_ hotKey: SystemAction) {
        guard let getSymbolicHotKeyValue, let isSymbolicHotKeyEnabled else {
            log.error("symbolic hotkeys are unavailable on this macOS")
            return
        }
        let id = Int32(hotKey.rawValue)
        // Declarations of these out-parameters disagree on their widths, so each gets room for the wider one.
        var keyEquivalent: UInt32 = 0
        var keyCode: UInt32 = 0
        var modifiers: UInt64 = 0
        guard getSymbolicHotKeyValue(id, &keyEquivalent, &keyCode, &modifiers) == 0, isSymbolicHotKeyEnabled(id),
            keyCode != Self.unboundKey
        else {
            log.notice("\(hotKey.name, privacy: .public) has no enabled shortcut in System Settings")
            return
        }
        post(key: CGKeyCode(truncatingIfNeeded: keyCode), flags: CGEventFlags(rawValue: modifiers), to: .cgSessionEventTap)
    }

    private func post(key: CGKeyCode, flags: CGEventFlags, to tap: CGEventTapLocation) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker)
            event.post(tap: tap)
        }
    }
}
