import Foundation

struct ListenID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UInt64
    var description: String { "#\(rawValue)" }
}

/// What a route reports for a press, before it is named.
enum ListenPress: Equatable, Sendable, CustomStringConvertible {
    case hidpp(CID)
    /// A CGEvent button number, never 0.
    case button(Int)
    /// The virtual key code as the tap saw it, which may be a carrier.
    case key(KeyCode)

    var description: String {
        switch self {
        case .hidpp(let cid): "control \(cid.hex)"
        case .button(let number): "button \(number)"
        case .key(let code): "key code \(code.rawValue)"
        }
    }
}

/// What `Intent.compile` needs to listen on one device.
struct ListenTarget: Equatable, Sendable {
    var id: ListenID
    var device: DeviceInstanceID
}

/// Who reports a press or an end. The tap knows the listen it was armed for, a slot or a disconnect its device.
enum ListenSource: Equatable, Sendable {
    case listen(ListenID)
    case device(DeviceInstanceID)
}

/// The engine's one listen. Every exit is a transition, and an event for a listen that already ended names no armed
/// listen, so a late press, a late timer or a second stop changes nothing.
struct Listener: Sendable {
    struct Armed: Equatable, Sendable {
        let id: ListenID
        let match: DeviceMatch
        let device: DeviceInstanceID
        let until: Date

        func isNamed(by source: ListenSource) -> Bool {
            switch source {
            case .listen(let id): id == self.id
            case .device(let device): device == self.device
            }
        }
    }

    enum State: Equatable, Sendable {
        case idle
        case armed(Armed)
        case ended(DeviceMatch, ListenEnd)
    }

    private(set) var state = State.idle
    private var nextID: UInt64 = 1

    var armed: Armed? {
        if case .armed(let armed) = state { armed } else { nil }
    }

    var target: ListenTarget? { armed.map { ListenTarget(id: $0.id, device: $0.device) } }

    /// Replaces any listen. A refusal ends the new one at once, so the window can say why.
    mutating func start(match: DeviceMatch, device: DeviceInstanceID?, refusal: ListenEnd?, now: Date) -> Armed? {
        guard refusal == nil, let device else {
            state = .ended(match, refusal ?? .disconnected)
            return nil
        }
        let armed = Armed(
            id: ListenID(rawValue: nextID), match: match, device: device,
            until: now.addingTimeInterval(ListenStatus.timeout))
        nextID += 1
        state = .armed(armed)
        return armed
    }

    /// The armed listen, if `source` names it. The press ends it.
    mutating func hear(from source: ListenSource) -> Armed? {
        guard let armed, armed.isNamed(by: source) else { return nil }
        state = .idle
        return armed
    }

    /// Ends the armed listen when `source` is nil or names it, with a note unless `why` is nil. True when it ended one.
    mutating func end(_ why: ListenEnd?, only source: ListenSource? = nil) -> Bool {
        guard let armed, source.map(armed.isNamed) ?? true else { return false }
        state = why.map { .ended(armed.match, $0) } ?? .idle
        return true
    }

    /// Clears the note a listen left. True when there was one.
    mutating func dismiss() -> Bool {
        guard case .ended = state else { return false }
        state = .idle
        return true
    }
}

/// The compiled side of a listen. Only the compiler sees the routes the listen cleared, so it names the keys.
struct ListenPlan: Equatable, Sendable {
    var target: ListenTarget
    /// Each carrier's key code to the key that sent it, from the routes the listen cleared. A key pressed before the
    /// clear lands still arrives as its carrier.
    var carrierSources: [KeyCode: HIDUsage]

    func heard(_ press: ListenPress) -> Heard {
        switch press {
        case .hidpp(let cid): .control(.hidpp(cid))
        case .button(let number): Control.buttonRange.contains(number) ? .control(.button(number)) : .unnamed
        case .key(let code):
            (carrierSources[code] ?? KeyTable.byKeyCode[code]?.usage).map { .control(.key($0)) } ?? .unnamed
        }
    }
}
