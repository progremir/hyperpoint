public import Foundation

public struct EngineStatus: Equatable, Sendable {
    public var run: RunState
    public var permissions: PermissionState
    /// Non-nil while the file is invalid. The last good config keeps running.
    public var configError: ConfigError?
    public var tap: TapState
    /// One row per profile, in config order.
    public var devices: [DeviceStatus]
    public var lastReconnect: Reconnect?

    public init(
        run: RunState, permissions: PermissionState, configError: ConfigError?, tap: TapState,
        devices: [DeviceStatus], lastReconnect: Reconnect?
    ) {
        self.run = run
        self.permissions = permissions
        self.configError = configError
        self.tap = tap
        self.devices = devices
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
    /// When the device connected, or nil when it is not connected.
    public var connectedAt: Date?
    /// Nil when the profile does not ask for the hyper key.
    public var hyper: HyperStatus?

    public init(name: String, connectedAt: Date?, hyper: HyperStatus?) {
        self.name = name
        self.connectedAt = connectedAt
        self.hyper = hyper
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
