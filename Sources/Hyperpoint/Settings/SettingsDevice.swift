import Foundation
import HyperpointKit

enum SettingsPane: Hashable {
    case general
    case hyper
    case device(DeviceMatch)
}

enum DeviceTab: Hashable {
    case buttons
    case scrolling
}

/// One device in the sidebar: a profile from the file, or a device connected now that has none.
struct SettingsDevice: Identifiable, Equatable {
    var match: DeviceMatch
    var name: String
    var kind: DeviceKind
    /// Nil for a connected device that has no profile yet.
    var profile: DeviceProfile?
    var status: DeviceStatus?

    var id: DeviceMatch { match }
    var connected: Bool { status?.connectedAt != nil }
    var isNew: Bool { profile == nil }

    /// Logitech devices are the ones that speak HID++.
    var speaksHIDPP: Bool {
        if status?.hidpp != nil { return true }
        if case .device(let vendor, _) = match, vendor.rawValue == 0x046D { return true }
        return profile?.rules?.contains { rule in
            switch rule.control {
            case .hidpp, .thumbWheel: true
            case .key, .button: false
            }
        } ?? false
    }

    static func all(config: Config?, status: EngineStatus?) -> [SettingsDevice] {
        let profiles = (config?.devices ?? []).map { profile in
            let status = status?.devices.first { $0.match == profile.match }
            return SettingsDevice(
                match: profile.match, name: profile.name, kind: status?.kind ?? kind(of: profile), profile: profile,
                status: status)
        }
        let new = (status?.newDevices ?? []).filter { device in
            !profiles.contains { $0.match == device.match } && config?.ignored.contains(device.match) != true
        }
        return profiles
            + new.map {
                SettingsDevice(match: $0.match, name: $0.name, kind: $0.kind ?? .mouse, profile: nil, status: $0)
            }
    }

    /// A profile for a device that is not connected says what it is by what it sets.
    private static func kind(of profile: DeviceProfile) -> DeviceKind {
        profile.match == .builtIn || profile.hyper != nil ? .keyboard : .mouse
    }

    func card(paused: Bool, time: (Date) -> String) -> StatusCard {
        guard let status, let connectedAt = status.connectedAt else {
            return StatusCard(
                title: "Not connected", detail: "Hyperpoint applies this profile as soon as it connects.",
                connected: false)
        }
        let title =
            if match == .builtIn {
                "Built into this Mac"
            } else if let transport = status.transport, transport.contains("Bluetooth") {
                "Connected over Bluetooth"
            } else if let transport = status.transport, transport.contains("USB") {
                "Connected over USB"
            } else {
                "Connected"
            }
        guard profile != nil else {
            let next = kind == .keyboard ? "you turn on the hyper key for it" : "you add a rule"
            return StatusCard(
                title: title,
                detail: "First seen at \(time(connectedAt)). Hyperpoint changes nothing on it until \(next).",
                connected: true)
        }
        var parts = ["Connected at \(time(connectedAt))."]
        if paused {
            parts.append("Hyperpoint is paused, so it works as macOS has it.")
        } else {
            switch status.hidpp?.progress {
            case .applying: parts.append("Applying settings…")
            case .setUp:
                parts.append(status.hidpp?.lastApply.map { "Settings applied at \(time($0))." } ?? "Settings applied.")
                let skipped = status.hidpp?.skippedRules.count ?? 0
                if skipped > 0 {
                    parts.append(
                        skipped == 1
                            ? "1 rule is skipped because this mouse cannot do it."
                            : "\(skipped) rules are skipped because this mouse cannot do them.")
                }
            case .notSetUp(let why): parts.append("Settings not applied: \(why).")
            case nil: break
            }
            switch status.hyper {
            case .on: parts.append("Hyper key on.")
            case .off: parts.append("Hyper key off.")
            case .applying: parts.append("Turning on the hyper key…")
            case .failed(let why): parts.append("Hyper key not applied: \(why).")
            case nil: break
            }
        }
        return StatusCard(title: title, detail: parts.joined(separator: " "), connected: true)
    }
}

struct StatusCard: Equatable {
    var title: String
    var detail: String
    var connected: Bool
}
