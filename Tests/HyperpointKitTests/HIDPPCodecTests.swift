@testable import HyperpointKit
import Testing

func report(_ hex: String) -> [UInt8] {
    let bytes = hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    return bytes + [UInt8](repeating: 0, count: HIDPP.reportLength - bytes.count)
}

extension HIDPPInbound {
    init(_ bytes: [UInt8]) { self = bytes.withUnsafeBufferPointer { HIDPPInbound($0) } }
}

func notice(_ bytes: [UInt8], _ feature: HIDPPFeature) -> HIDPPNotice? {
    guard case .notification(_, let event) = HIDPPInbound(bytes) else { return nil }
    return bytes.withUnsafeBufferPointer { HIDPPNotice($0, feature: feature, event: event) }
}

let gestureButton = CID(rawValue: 0xC3)
let topButton = CID(rawValue: 0xC4)

@Suite struct HIDPPCodecTests {
    struct Golden: CustomTestStringConvertible, Sendable {
        let request: HIDPPRequest
        let featureIndex: UInt8
        let bytes: String
        var testDescription: String { bytes }
    }

    static let applyScript: [Golden] = [
        Golden(request: .getFeature(.reprogControls), featureIndex: 0x00, bytes: "11 FF 00 0B 1B 04"),
        Golden(request: .getFeature(.thumbWheel), featureIndex: 0x00, bytes: "11 FF 00 0B 21 50"),
        Golden(request: .getFeature(.wirelessStatus), featureIndex: 0x00, bytes: "11 FF 00 0B 1D 4B"),
        Golden(request: .getControlCount, featureIndex: 0x08, bytes: "11 FF 08 0B"),
        Golden(request: .getControlInfo(5), featureIndex: 0x08, bytes: "11 FF 08 1B 05"),
        Golden(
            request: .setControlReporting(gestureButton, ControlReporting(divert: true, rawXY: true)), featureIndex: 0x08,
            bytes: "11 FF 08 3B 00 C3 33 00 00"),
        Golden(
            request: .setControlReporting(topButton, ControlReporting(divert: true, rawXY: false)), featureIndex: 0x08,
            bytes: "11 FF 08 3B 00 C4 23 00 00"),
        Golden(request: .setControlReporting(CID(rawValue: 0x52), .native), featureIndex: 0x08, bytes: "11 FF 08 3B 00 52 22 00 00"),
        Golden(request: .getControlReporting(gestureButton), featureIndex: 0x08, bytes: "11 FF 08 2B 00 C3"),
        Golden(request: .setThumbWheelReporting(inverted: true), featureIndex: 0x0E, bytes: "11 FF 0E 2B 00 01"),
        Golden(request: .setThumbWheelReporting(inverted: false), featureIndex: 0x0E, bytes: "11 FF 0E 2B 00 00"),
        Golden(request: .getThumbWheelReporting, featureIndex: 0x0E, bytes: "11 FF 0E 1B"),
    ]

    @Test(arguments: applyScript)
    func requestEncodesToItsDocumentedBytes(_ golden: Golden) {
        #expect(golden.request.report(featureIndex: golden.featureIndex) == report(golden.bytes))
    }

    @Test func measuredRepliesDecode() {
        #expect(
            HIDPPInbound(report("11 FF 00 0B 08 00 04"))
                == .reply(featureIndex: 0x00, function: 0, params: Array(report("08 00 04").prefix(16))))
        #expect(HIDPPInbound(report("11 FF FF 08 2B 02")) == .error(featureIndex: 0x08, function: 2, code: 0x02))
        guard case .reply(_, _, let diverted) = HIDPPInbound(report("11 FF 08 2B 00 C3 01 00 C3 00")) else {
            Issue.record("a getCidReporting reply")
            return
        }
        #expect(ControlReporting(readFlags: diverted[2]) == ControlReporting(divert: true, rawXY: false))
    }

    @Test func measuredControlInfoDecodes() {
        func control(_ hex: String) -> HIDPPCapabilities.Control? {
            guard case .reply(_, _, let params) = HIDPPInbound(report(hex)) else { return nil }
            return HIDPPCapabilities.Control(cidInfo: params)
        }
        #expect(
            control("11 FF 08 1B 00 C3 00 A9 31 00 03 07 05")
                == HIDPPCapabilities.Control(cid: gestureButton, divertable: true, rawXY: true))
        #expect(
            control("11 FF 08 1B 00 50 00 38 01 00 01 01 04")
                == HIDPPCapabilities.Control(cid: CID(rawValue: 0x50), divertable: false, rawXY: false),
            "the left button is not divertable, and additional flag 0x04 is not rawXY")
        #expect(
            control("11 FF 08 1B 00 D7 00 B4 A0 00 04 00 03")
                == HIDPPCapabilities.Control(cid: CID(rawValue: 0xD7), divertable: true, rawXY: true))
    }

    @Test func notificationsDecode() {
        #expect(notice(report("11 FF 08 00 00 C3"), .reprogControls) == .heldControls([gestureButton]))
        #expect(notice(report("11 FF 08 00 00 C4 00 C3"), .reprogControls) == .heldControls([topButton, gestureButton]))
        #expect(notice(report("11 FF 08 00"), .reprogControls) == .heldControls([]))
        #expect(notice(report("11 FF 08 10 FF BA 00 03"), .reprogControls) == .rawXY(dx: -70, dy: 3))
        #expect(notice(report("11 FF 04 00 01 01 01"), .wirelessStatus) == .wirelessStatus(reconfigure: true))
        #expect(notice(report("11 FF 04 00 01 00 01"), .wirelessStatus) == .wirelessStatus(reconfigure: false))
        #expect(notice(report("11 FF 0E 00 01 02"), .thumbWheel) == nil, "thumb wheel events are not acted on")
    }

    @Test func otherTrafficIsIgnored() {
        #expect(HIDPPInbound(report("11 FF 00 0A 08 00 04")) == .ignored, "another client's reply")
        #expect(HIDPPInbound(report("11 FF FF 08 2A 02")) == .ignored, "another client's error")
        #expect(HIDPPInbound(report("10 FF 00 0B 08 00 04")) == .ignored, "a short report id")
        #expect(HIDPPInbound(report("11 01 00 0B 08 00 04")) == .ignored, "a receiver's device index")
        #expect(HIDPPInbound(Array(report("11 FF 00 0B 08 00 04").prefix(7))) == .ignored, "a truncated report")
    }
}
