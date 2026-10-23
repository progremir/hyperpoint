import Foundation
import HyperpointKit

/// The menu as a pure function of the engine's status, so all wording lives in one place.
struct MenuPresentation: Equatable {
    enum Fix: Equatable {
        case permission(Permission)
        case openConfig
        case reapply
    }

    struct Notice: Equatable {
        var title: String
        var detail: String
        var fix: Fix
    }

    struct Row: Equatable {
        var name: String
        var detail: String
    }

    var state: String
    var needsAttention: Bool
    var notices: [Notice]
    var rows: [Row]
    var footnote: String?
    var paused: Bool

    init(_ status: EngineStatus?, time: (Date) -> String) {
        guard let status else {
            self.init(state: "Starting", needsAttention: false, notices: [], rows: [], footnote: nil, paused: false)
            return
        }
        let paused = status.run == .paused
        let notices = status.attention.map(Self.notice)
        let footnote = status.lastReconnect.map {
            "\($0.device) reconnected at \(time($0.at))." + ($0.reapplied ? " Settings re-applied." : "")
        }
        self.init(
            state: paused ? "Paused" : notices.isEmpty ? "Active" : "Needs attention",
            needsAttention: !notices.isEmpty,
            notices: notices,
            rows: status.devices.map { Row(name: $0.name, detail: Self.detail($0, paused: paused)) },
            footnote: footnote,
            paused: paused)
    }

    private init(
        state: String, needsAttention: Bool, notices: [Notice], rows: [Row], footnote: String?, paused: Bool
    ) {
        self.state = state
        self.needsAttention = needsAttention
        self.notices = notices
        self.rows = rows
        self.footnote = footnote
        self.paused = paused
    }

    private static func notice(_ attention: Attention) -> Notice {
        switch attention {
        case .permission(.accessibility):
            Notice(
                title: "Accessibility is off", detail: "The hyper key needs it. Click to allow.",
                fix: .permission(.accessibility))
        case .permission(.inputMonitoring):
            Notice(
                title: "Input Monitoring is off", detail: "Mouse buttons will need it. Click to allow.",
                fix: .permission(.inputMonitoring))
        case .config(let error):
            Notice(
                title: "Config file has an error", detail: "\(error). Still using the last good settings.",
                fix: .openConfig)
        case .tapFailed:
            Notice(
                title: "The keyboard tap could not start", detail: "Click to try again.", fix: .reapply)
        }
    }

    private static func detail(_ device: DeviceStatus, paused: Bool) -> String {
        guard device.connectedAt != nil else { return "Not connected" }
        switch device.hyper {
        case nil: return "Connected"
        case .on: return "Hyper key on"
        case .off: return paused ? "Paused" : "Hyper key off"
        case .applying: return "Applying…"
        case .failed(let reason): return "Not applied: \(reason)"
        }
    }
}
