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
