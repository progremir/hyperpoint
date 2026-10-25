public import Foundation

public struct EngineStatus: Equatable, Sendable {
    public var run: RunState
    public var permissions: PermissionState
    /// Non-nil while the file is invalid. The last good config keeps running.
    public var configError: ConfigError?
    public var tap: TapState
    /// One row per profile, in config order.
    public var devices: [DeviceStatus]
    /// Connected devices that no profile matches and that are not ignored, one row per match. Hyperpoint leaves them
    /// as macOS has them.
    public var newDevices: [DeviceStatus]
    public var lastReconnect: Reconnect?

    public init(
        run: RunState, permissions: PermissionState, configError: ConfigError?, tap: TapState,
        devices: [DeviceStatus], newDevices: [DeviceStatus] = [], lastReconnect: Reconnect?
    ) {
        self.run = run
        self.permissions = permissions
        self.configError = configError
        self.tap = tap
        self.devices = devices
        self.newDevices = newDevices
        self.lastReconnect = lastReconnect
    }

    /// What the user must act on, most important first.
    public var attention: [Attention] {
        var items: [Attention] = []
        if permissions.accessibility != .granted { items.append(.permission(.accessibility)) }
        if permissions.inputMonitoring != .granted { items.append(.permission(.inputMonitoring)) }
        if let configError { items.append(.config(configError)) }
        if tap == .failed { items.append(.tapFailed) }
        return items
    }
}

public enum Attention: Equatable, Sendable {
    case permission(Permission)
    case config(ConfigError)
    case tapFailed
}

public enum RunState: Equatable, Sendable {
    case active
    case paused
}

public enum Permission: Equatable, Sendable {
    case accessibility
    case inputMonitoring
}

public struct PermissionState: Equatable, Sendable {
    public enum Grant: Equatable, Sendable {
        case granted
        case denied
        case notDetermined
    }

    public var accessibility: Grant
    public var inputMonitoring: Grant

    public init(accessibility: Grant, inputMonitoring: Grant) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }
}

public enum TapState: Equatable, Sendable {
    case off
    case on
    case failed
}

public struct DeviceStatus: Equatable, Sendable {
    public var name: String
    public var match: DeviceMatch
    /// Nil when the device is not connected.
    public var kind: DeviceKind?
    /// How the device connects as IOKit names it, such as "Bluetooth Low Energy" or "USB". Nil when not connected
    /// or unknown.
    public var transport: String?
    /// When the device connected, or nil when it is not connected.
    public var connectedAt: Date?
    /// Nil when the profile does not ask for the hyper key.
    public var hyper: HyperStatus?
    /// Nil until Hyperpoint has read or written the device over HID++.
    public var hidpp: HIDPPStatus?
    /// Non-nil while Hyperpoint listens for a press on this device, and after a listen that heard none, until the next
    /// listen or a stop.
    public var listen: ListenStatus?

    public init(
        name: String, match: DeviceMatch, kind: DeviceKind? = nil, transport: String? = nil, connectedAt: Date?,
        hyper: HyperStatus?, hidpp: HIDPPStatus? = nil, listen: ListenStatus? = nil
    ) {
        self.name = name
        self.match = match
        self.kind = kind
        self.transport = transport
        self.connectedAt = connectedAt
        self.hyper = hyper
        self.hidpp = hidpp
        self.listen = listen
    }
}

public enum ListenStatus: Equatable, Sendable {
    /// The device is still being set up to listen, so a press may still do its own thing.
    case gettingReady(until: Date)
    case listening(until: Date)
    case ended(ListenEnd)

    /// How long a listen waits for a press.
    public static let timeout: TimeInterval = 10
}

/// Why a listen ended without a press. A press, a stop and quit end it with no reason to show.
public enum ListenEnd: Equatable, Sendable {
    case timedOut
    case disconnected
    case paused
    case slept
    /// Neither the tap nor HID++ can hear the device.
    case needsAccessibility
}

/// A press heard on a device, named the way the config names controls. Each comes once, on `Engine.heard`.
public struct LearnedPress: Equatable, Sendable {
    public var match: DeviceMatch
    public var heard: Heard

    public init(match: DeviceMatch, heard: Heard) {
        self.match = match
        self.heard = heard
    }
}

public enum Heard: Equatable, Sendable {
    case control(Control)
    /// A key or button the config cannot name, such as F16.
    case unnamed
}

/// Hyperpoint guesses it from the device's interfaces, and a profile's `kind` replaces the guess.
public enum DeviceKind: String, Codable, Equatable, Sendable {
    /// Can host the hyper key. The guess is a keyboard that is not also an external mouse.
    case keyboard
    /// Any other device, such as a mouse that also sends keys. A mouse that speaks HID++ is read for its controls.
    case mouse
}

public struct HIDPPStatus: Equatable, Sendable {
    public enum Progress: Equatable, Sendable {
        case applying
        case setUp
        /// The last apply failed or could not start, and why.
        case notSetUp(String)
    }

    public var progress: Progress
    /// When the last apply finished, applied or not.
    public var lastApply: Date?
    /// Nil until discovery finishes on this connection.
    public var capabilities: HIDPPCapabilities?
    /// Rules the device cannot carry out, such as one on a control it lacks.
    public var skippedRules: [Rule]

    public init(progress: Progress, lastApply: Date?, capabilities: HIDPPCapabilities?, skippedRules: [Rule]) {
        self.progress = progress
        self.lastApply = lastApply
        self.capabilities = capabilities
        self.skippedRules = skippedRules
    }
}

public enum HyperStatus: Equatable, Sendable {
    case on
    case off
    case applying
    case failed(String)
}

public struct Reconnect: Equatable, Sendable {
    public var device: String
    public var at: Date
    public var reapplied: Bool

    public init(device: String, at: Date, reapplied: Bool) {
        self.device = device
        self.at = at
        self.reapplied = reapplied
    }
}
