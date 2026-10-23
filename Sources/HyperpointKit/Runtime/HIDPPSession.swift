import Foundation
import IOKit.hid

/// The device stays scheduled on the HID run loop by the hub's manager, so input reports arrive on this thread.
@HIDActor
final class HIDPPSession {
    enum OpenFailure: Error, Equatable, CustomStringConvertible {
        case notPermitted
        case failed(IOReturn)

        var description: String {
            switch self {
            case .notPermitted: "waiting for Input Monitoring"
            case .failed(let result): "the device did not open (0x\(String(UInt32(bitPattern: result), radix: 16)))"
            }
        }
    }

    private static let notPermitted = IOReturn(bitPattern: 0xE000_02E2)

    private let device: IOHIDDevice
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int
    private let journal: Journal
    private let onEvent: @HIDActor (HIDPPEvent) -> Void
    private var link = HIDPPLink()
    private var wake: Task<Void, Never>?
    private var closed = false

    /// The MX reports keyboard as its primary usage, so opening it needs Input Monitoring.
    init(opening device: IOHIDDevice, journal: Journal, onEvent: @escaping @HIDActor (HIDPPEvent) -> Void)
        throws(OpenFailure)
    {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw result == Self.notPermitted ? .notPermitted : .failed(result) }
        self.device = device
        self.journal = journal
        self.onEvent = onEvent
        bufferSize = max(HIDPP.reportLength, IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64)
        buffer = .allocate(capacity: bufferSize)
        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, bufferSize, hidppReportArrived, Unmanaged.passUnretained(self).toOpaque())
    }

    var isApplying: Bool { link.isApplying }

    func request(_ reason: ApplyReason, plan: HIDPPSetup) {
        pump(link.request(reason, plan: plan, now: .now))
    }

    func close() {
        guard !closed else { return }
        closed = true
        wake?.cancel()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
    }

    fileprivate func received(_ report: UnsafeBufferPointer<UInt8>) {
        pump(link.receive(report, now: .now))
    }

    private func tick() {
        pump(link.tick(now: .now))
    }

    private func pump(_ output: HIDPPOutput) {
        guard !closed else { return }
        for report in output.reports {
            let result = report.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), $0.baseAddress!, $0.count)
            }
            if result != kIOReturnSuccess {
                journal.note("HID++ write returned 0x\(String(UInt32(bitPattern: result), radix: 16)); the link asks again")
            }
        }
        wake?.cancel()
        wake = output.deadline.map { deadline in
            Task { [weak self] in
                try? await Task.sleep(until: deadline, clock: .continuous)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
        for event in output.events { onEvent(event) }
    }
}

nonisolated private func hidppReportArrived(
    _ context: UnsafeMutableRawPointer?, _ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ type: IOHIDReportType,
    _ reportID: UInt32, _ report: UnsafeMutablePointer<UInt8>, _ length: CFIndex
) {
    // Pointer reports arrive here too, at the mouse's report rate.
    guard reportID == HIDPP.reportID, let context else { return }
    let session = Unmanaged<HIDPPSession>.fromOpaque(context).takeUnretainedValue()
    nonisolated(unsafe) let bytes = UnsafeBufferPointer(start: report, count: length)
    HIDActor.assumeIsolated { session.received(bytes) }
}
