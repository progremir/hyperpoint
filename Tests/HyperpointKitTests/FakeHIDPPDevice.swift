@testable import HyperpointKit

/// A model of the MX Master 3's HID++ firmware, seeded with what was measured on this Mac after BetterMouse ran:
/// 0x1B04 at 0x08, 0x2150 at 0x0E, 0x1D4B at 0x04, eight controls, 0xC3 and 0xC4 diverted without rawXY, and the
/// thumb wheel diverted and not inverted. It answers requests the way the firmware does, change bits included.
struct FakeHIDPPDevice {
    var featureIndex: [UInt16: UInt8] = [0x1B04: 0x08, 0x2150: 0x0E, 0x1D4B: 0x04]
    /// getCidInfo in device order: control, flags, additional flags.
    var controls: [(cid: UInt16, flags: UInt8, additional: UInt8)] = [
        (0x50, 0x01, 0x04), (0x51, 0x01, 0x04), (0x52, 0x31, 0x05), (0x53, 0x31, 0x05), (0x56, 0x31, 0x05),
        (0xC3, 0x31, 0x05), (0xC4, 0x31, 0x05), (0xD7, 0xA0, 0x03),
    ]
    /// getCidReporting flags per control: divert 0x01, rawXY 0x10.
    var reporting: [UInt16: UInt8] = [0xC3: 0x01, 0xC4: 0x01]
    var wheelDiverted = true
    var wheelInverted = false
    /// Requests to drop without a reply, like the first ones after a Bluetooth connect.
    var unanswered = 0
    private(set) var writes = 0

    /// Every control that is not native, as getCidReporting would report it.
    var diverted: [UInt16: UInt8] { reporting.filter { $0.value != 0 } }

    /// What a sleep or power cycle does to volatile state.
    mutating func forget() {
        reporting = [:]
        wheelDiverted = false
        wheelInverted = false
    }

    mutating func answer(_ request: [UInt8]) -> [UInt8]? {
        precondition(request.count == 20 && request[0] == 0x11 && request[1] == 0xFF, "a long HID++ report")
        if unanswered > 0 {
            unanswered -= 1
            return nil
        }
        let index = request[2]
        let function = request[3] >> 4
        let params = Array(request[4...])
        let feature = index == 0 ? 0x0000 : featureIndex.first { $0.value == index }?.key
        func reply(_ payload: [UInt8]) -> [UInt8] { pad([0x11, 0xFF, index, request[3]] + payload) }
        let invalidArgument = pad([0x11, 0xFF, 0xFF, index, request[3], 0x02])
        let cid = UInt16(params[0]) << 8 | UInt16(params[1])
        let control = controls.first { $0.cid == cid }

        switch (feature, function) {
        case (0x0000, 0):
            return reply([featureIndex[cid] ?? 0, 0, 0])
        case (0x1B04, 0):
            return reply([UInt8(controls.count)])
        case (0x1B04, 1):
            guard Int(params[0]) < controls.count else { return invalidArgument }
            let info = controls[Int(params[0])]
            return reply([UInt8(info.cid >> 8), UInt8(info.cid & 0xFF), 0, 0, info.flags, 0, 0, 0, info.additional])
        case (0x1B04, 2):
            guard control != nil else { return invalidArgument }
            return reply([params[0], params[1], reporting[cid] ?? 0, 0, 0, 0])
        case (0x1B04, 3):
            guard let control, control.flags & 0x20 != 0 else { return invalidArgument }
            var flags = reporting[cid] ?? 0
            if params[2] & 0x02 != 0 { flags = flags & ~0x01 | params[2] & 0x01 }
            if params[2] & 0x20 != 0 { flags = flags & ~0x10 | params[2] & 0x10 }
            reporting[cid] = flags
            writes += 1
            return reply([params[0], params[1], flags, 0, 0])
        case (0x2150, 1):
            return reply([wheelDiverted ? 1 : 0, wheelInverted ? 1 : 0])
        case (0x2150, 2):
            wheelDiverted = params[0] & 1 == 1
            wheelInverted = params[1] & 1 == 1
            writes += 1
            return reply([params[0], params[1]])
        default:
            return invalidArgument
        }
    }

    func notification(_ feature: UInt16, event: UInt8, _ payload: [UInt8]) -> [UInt8] {
        pad([0x11, 0xFF, featureIndex[feature]!, event << 4] + payload)
    }

    func held(_ cids: UInt16...) -> [UInt8] {
        notification(0x1B04, event: 0, cids.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
    }

    func rawXY(dx: Int16, dy: Int16) -> [UInt8] {
        let x = UInt16(bitPattern: dx)
        let y = UInt16(bitPattern: dy)
        return notification(0x1B04, event: 1, [UInt8(x >> 8), UInt8(x & 0xFF), UInt8(y >> 8), UInt8(y & 0xFF)])
    }

    /// 0x1D4B after a reconnect: status 1, software reconfiguration requested, powered on.
    func askedToReconfigure() -> [UInt8] { notification(0x1D4B, event: 0, [0x01, 0x01, 0x01]) }

    private func pad(_ bytes: [UInt8]) -> [UInt8] { bytes + [UInt8](repeating: 0, count: 20 - bytes.count) }
}
