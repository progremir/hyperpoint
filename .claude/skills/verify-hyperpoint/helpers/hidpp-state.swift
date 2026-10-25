// Read-only HID++ 2.0 state of the MX Master 3. Sends only get* requests, never set*.
// Usage: hidpp-state  (prints one line per fact; exit 1 when the mouse cannot be opened)
import Foundation
import IOKit.hid

final class Box: @unchecked Sendable { var replies: [[UInt8]] = [] }
let box = Box()
let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
let softwareID: UInt8 = 0x0E

func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
func die(_ message: String) -> Never { print("error: \(message)"); exit(1) }

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046D, kIOHIDProductIDKey: 0xB023] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
if IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) != 0 { die("IOHIDManagerOpen refused (this shell lacks Input Monitoring)") }
guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = devices.first else { die("MX Master 3 not connected") }
if IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) != 0 { die("IOHIDDeviceOpen refused (this shell lacks Input Monitoring)") }
IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { _, _, _, _, reportID, report, length in
    if reportID == 0x11 { box.replies.append(Array(UnsafeBufferPointer(start: report, count: length))) }
}, nil)

func call(_ feature: UInt8, _ function: UInt8, _ params: [UInt8] = []) -> [UInt8]? {
    var request = [UInt8](repeating: 0, count: 20)
    request[0] = 0x11; request[1] = 0xFF; request[2] = feature; request[3] = (function << 4) | softwareID
    for (i, byte) in params.enumerated() { request[4 + i] = byte }
    for _ in 0..<3 {
        box.replies.removeAll()
        let status = request.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, $0.baseAddress!, 20) }
        if status != 0 { continue }
        let start = Date()
        while Date().timeIntervalSince(start) < 1.5 {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
            for reply in box.replies where reply.count >= 7 {
                if reply[2] == feature && reply[3] == request[3] { return Array(reply[4...]) }
                if reply[2] == 0xFF && reply[3] == feature && reply[4] == request[3] { return nil }
            }
        }
    }
    return nil
}

func index(of id: UInt16) -> UInt8? {
    guard let reply = call(0x00, 0, [UInt8(id >> 8), UInt8(id & 0xFF)]), reply[0] != 0 else { return nil }
    return reply[0]
}

let names: [UInt16: String] = [0x50: "left", 0x51: "right", 0x52: "middle", 0x53: "back", 0x56: "forward", 0xC3: "gesture", 0xC4: "top", 0xD7: "virtual"]
let reprog = index(of: 0x1B04), thumb = index(of: 0x2150), smart = index(of: 0x2110), hires = index(of: 0x2121)
print("features reprog=\(reprog.map { String(format: "0x%02X", $0) } ?? "absent") thumbwheel=\(thumb.map { String(format: "0x%02X", $0) } ?? "absent") smartshift=\(smart.map { String(format: "0x%02X", $0) } ?? "absent") hires=\(hires.map { String(format: "0x%02X", $0) } ?? "absent")")

if let reprog, let count = call(reprog, 0)?.first {
    for i in 0..<count {
        guard let info = call(reprog, 1, [i]) else { continue }
        let cid = UInt16(info[0]) << 8 | UInt16(info[1])
        guard let reporting = call(reprog, 2, [info[0], info[1]]) else { continue }
        let flags = reporting[2]
        print(String(format: "control cid=0x%02X name=%@ diverted=%@ rawXY=%@ flags=0x%02X", cid, names[cid] ?? "?", flags & 0x01 != 0 ? "yes" : "no", flags & 0x10 != 0 ? "yes" : "no", flags))
    }
}
if let thumb, let reporting = call(thumb, 1) {
    print("thumbwheel diverted=\(reporting[0] & 1 != 0 ? "yes" : "no") inverted=\(reporting[1] & 1 != 0 ? "yes" : "no") raw=\(hex(reporting.prefix(2)))")
}
if let smart, let mode = call(smart, 0) {
    print("smartshift mode=\(mode[0] == 1 ? "freespin" : mode[0] == 2 ? "ratchet" : "?\(mode[0])") autoDisengage=\(mode[1]) default=\(mode[2])")
}
if let hires, let mode = call(hires, 1) {
    print("hireswheel hires=\(mode[0] & 2 != 0 ? "on" : "off") diverted=\(mode[0] & 1 != 0 ? "yes" : "no") inverted=\(mode[0] & 4 != 0 ? "yes" : "no")")
}
