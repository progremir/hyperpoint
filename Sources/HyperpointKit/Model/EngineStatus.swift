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
    /// Nil until Hyperpoint has something to write to the device over HID++.
    public var hidpp: HIDPPStatus?

    public init(
        name: String, match: DeviceMatch, kind: DeviceKind? = nil, transport: String? = nil, connectedAt: Date?,
        hyper: HyperStatus?, hidpp: HIDPPStatus? = nil
    ) {
        self.name = name
        self.match = match
        self.kind = kind
        self.transport = transport
        self.connectedAt = connectedAt
        self.hyper = hyper
        self.hidpp = hidpp
    }
}

public enum DeviceKind: String, Codable, Equatable, Sendable {
    /// A keyboard that can host the hyper key.
    case keyboard
    /// Any other device, such as a mouse that also sends keys.
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
