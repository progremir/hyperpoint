/// HID++ 2.0 over a direct Bluetooth LE connection. Only long reports exist and the device answers on index 0xFF
/// (measured on the MX Master 3). Bytes in, values out. The runtime owns the device, the clock and the threads.
enum HIDPP {
    static let reportID: UInt8 = 0x11
    static let reportLength = 20
    static let deviceIndex: UInt8 = 0xFF
    /// Notifications carry 0 here, so any other value marks our replies.
    static let softwareID: UInt8 = 0x0B
    static let errorFeatureIndex: UInt8 = 0xFF
}

enum HIDPPFeature: UInt16, CaseIterable, Sendable {
    case root = 0x0000
    case reprogControls = 0x1B04
    case wirelessStatus = 0x1D4B
    case thumbWheel = 0x2150
}

/// Where each feature sits on one device. Indices differ per device and firmware, so they are always discovered.
struct FeatureMap: Equatable, Sendable {
    private var indices: [HIDPPFeature: UInt8] = [.root: 0]
    private var features: [UInt8: HIDPPFeature] = [0: .root]

    subscript(feature: HIDPPFeature) -> UInt8? { indices[feature] }

    func feature(at index: UInt8) -> HIDPPFeature? { features[index] }

    mutating func record(_ feature: HIDPPFeature, at index: UInt8) {
        indices[feature] = index
        features[index] = feature
    }
}

struct HIDPPRequest: Equatable, Sendable {
    var feature: HIDPPFeature
    var function: UInt8
    var params: [UInt8]

    func report(featureIndex: UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: HIDPP.reportLength)
        bytes[0] = HIDPP.reportID
        bytes[1] = HIDPP.deviceIndex
        bytes[2] = featureIndex
        bytes[3] = function << 4 | HIDPP.softwareID
        bytes.replaceSubrange(4..<4 + params.count, with: params)
        return bytes
    }

    /// IRoot fn0. The reply's first byte is the feature index, and 0 means the device lacks the feature.
    static func getFeature(_ feature: HIDPPFeature) -> HIDPPRequest {
        HIDPPRequest(feature: .root, function: 0, params: bigEndian(feature.rawValue))
    }

    static let getControlCount = HIDPPRequest(feature: .reprogControls, function: 0, params: [])

    static func getControlInfo(_ index: UInt8) -> HIDPPRequest {
        HIDPPRequest(feature: .reprogControls, function: 1, params: [index])
    }

    static func getControlReporting(_ cid: CID) -> HIDPPRequest {
        HIDPPRequest(feature: .reprogControls, function: 2, params: bigEndian(cid.rawValue))
    }

    /// The remap word stays 0, which means no remap.
    static func setControlReporting(_ cid: CID, _ reporting: ControlReporting) -> HIDPPRequest {
        HIDPPRequest(feature: .reprogControls, function: 3, params: bigEndian(cid.rawValue) + [reporting.writeFlags, 0, 0])
    }

    static let getThumbWheelReporting = HIDPPRequest(feature: .thumbWheel, function: 1, params: [])

    /// Byte 0 is the divert, byte 1 the invert. The wheel is never diverted, so macOS keeps scrolling natively.
    static func setThumbWheelReporting(inverted: Bool) -> HIDPPRequest {
        HIDPPRequest(feature: .thumbWheel, function: 2, params: [0, inverted ? 1 : 0])
    }

    private static func bigEndian(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }
}

/// The setCidReporting flags byte. Each state bit has a change bit one place above it, and both change bits are
/// always set, so one write decides the whole state whatever another app left there.
struct ControlReporting: Equatable, Sendable {
    var divert: Bool
    var rawXY: Bool

    static let native = ControlReporting(divert: false, rawXY: false)

    private static let divertBit: UInt8 = 0x01
    private static let rawXYBit: UInt8 = 0x10
    static let readMask = divertBit | rawXYBit

    /// 0x22 native, 0x23 divert, 0x33 divert with rawXY.
    var writeFlags: UInt8 { stateBits | Self.divertBit << 1 | Self.rawXYBit << 1 }

    var stateBits: UInt8 { (divert ? Self.divertBit : 0) | (rawXY ? Self.rawXYBit : 0) }

    init(divert: Bool, rawXY: Bool) {
        self.divert = divert
        self.rawXY = rawXY
    }

    init(readFlags: UInt8) {
        self.init(divert: readFlags & Self.divertBit != 0, rawXY: readFlags & Self.rawXYBit != 0)
    }
}

enum HIDPPInbound: Equatable, Sendable {
    /// A reply to a request carrying our software id. `params` are bytes 4 to 19.
    case reply(featureIndex: UInt8, function: UInt8, params: [UInt8])
    case error(featureIndex: UInt8, function: UInt8, code: UInt8)
    case notification(featureIndex: UInt8, event: UInt8)
    /// Another report id, another device index, or another client's reply.
    case ignored

    init(_ report: UnsafeBufferPointer<UInt8>) {
        guard report.count >= HIDPP.reportLength, report[0] == HIDPP.reportID, report[1] == HIDPP.deviceIndex else {
            self = .ignored
            return
        }
        if report[2] == HIDPP.errorFeatureIndex {
            self =
                report[4] & 0x0F == HIDPP.softwareID
                ? .error(featureIndex: report[3], function: report[4] >> 4, code: report[5]) : .ignored
            return
        }
        switch report[3] & 0x0F {
        case 0: self = .notification(featureIndex: report[2], event: report[3] >> 4)
        case HIDPP.softwareID:
            self = .reply(featureIndex: report[2], function: report[3] >> 4, params: Array(report[4..<HIDPP.reportLength]))
        default: self = .ignored
        }
    }
}

/// The notifications Hyperpoint acts on, decoded straight from the report so the gesture path never allocates.
enum HIDPPNotice: Equatable, Sendable {
    /// Every diverted control held right now, up to four, zero terminated.
    case heldControls([CID])
    /// Only while a control diverted with rawXY is held. Positive dy is down.
    case rawXY(dx: Int, dy: Int)
    /// 0x1D4B event 0. Byte 1 is 1 when the device asks software to configure it again.
    case wirelessStatus(reconfigure: Bool)

    init?(_ report: UnsafeBufferPointer<UInt8>, feature: HIDPPFeature, event: UInt8) {
        func word(_ offset: Int) -> UInt16 { UInt16(report[4 + offset]) << 8 | UInt16(report[5 + offset]) }
        switch (feature, event) {
        case (.reprogControls, 0):
            self = .heldControls(stride(from: 0, to: 8, by: 2).map(word).prefix { $0 != 0 }.map(CID.init(rawValue:)))
        case (.reprogControls, 1):
            self = .rawXY(dx: Int(Int16(bitPattern: word(0))), dy: Int(Int16(bitPattern: word(2))))
        case (.wirelessStatus, 0):
            self = .wirelessStatus(reconfigure: report[5] == 1)
        default:
            return nil
        }
    }
}

extension HIDPPCapabilities.Control {
    private static let temporarilyDivertable: UInt8 = 0x20
    private static let rawXYCapable: UInt8 = 0x01

    /// getCidInfo reply: cid, task, flags, fkey position, group, group mask, additional flags.
    init(cidInfo params: [UInt8]) {
        self.init(
            cid: CID(rawValue: UInt16(params[0]) << 8 | UInt16(params[1])),
            divertable: params[4] & Self.temporarilyDivertable != 0,
            rawXY: params[8] & Self.rawXYCapable != 0)
    }
}
