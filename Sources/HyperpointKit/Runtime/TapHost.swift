import CoreGraphics
import Foundation

struct TapOrder: Equatable, Sendable {
    var install: Bool
    var rules: TapRules
}

enum TapSignal: Sendable {
    case installed
    case installFailed
    case removed
    case reenabled
}

@TapActor
final class TapHost {
    private static let frameInterval = 1.0 / 120
    private static let never = Date.distantFuture.timeIntervalSinceReferenceDate

    private var pipeline = TapPipeline(rules: .empty, sender: eventSender)
    private var animator = ScrollAnimator()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: CFRunLoopTimer?
    private var glider: CFRunLoopTimer?
    private let signals: AsyncStream<TapSignal>.Continuation

    nonisolated init(signals: AsyncStream<TapSignal>.Continuation) { self.signals = signals }

    func follow(_ orders: AsyncStream<TapOrder>) async {
        for await order in orders { apply(order) }
    }

    func apply(_ order: TapOrder) {
        pipeline.replaceRulesAndForgetHeldKeys(order.rules)
        if order.install { install() } else { uninstall() }
    }

    private func install() {
        if let port, CFMachPortIsValid(port) { return }
        uninstall()
        guard
            let port = CGEvent.tapCreate(
                tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: TapPipeline.mask, callback: tapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            signals.yield(.installFailed)
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        var context = CFRunLoopTimerContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        let watchdog = CFRunLoopTimerCreate(nil, CFAbsoluteTimeGetCurrent() + 5, 5, 0, 0, tapWatchdog, &context)
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), watchdog, .commonModes)
        let glider = CFRunLoopTimerCreate(nil, Self.never, Self.frameInterval, 0, 0, tapGlide, &context)
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), glider, .commonModes)
        (self.port, self.source, self.watchdog, self.glider) = (port, source, watchdog, glider)
        signals.yield(.installed)
    }

    private func uninstall() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        if let watchdog { CFRunLoopTimerInvalidate(watchdog) }
        if let glider { CFRunLoopTimerInvalidate(glider) }
        if let ended = animator.stop() { Self.post(ended) }
        CFMachPortInvalidate(port)
        (self.port, self.source, self.watchdog, self.glider) = (nil, nil, nil, nil)
        pipeline.reset()
        signals.yield(.removed)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenable()
            return Unmanaged.passUnretained(event)
        default:
            switch pipeline.process(type, event) {
            case .pass:
                return Unmanaged.passUnretained(event)
            case .drop:
                return nil
            case .scroll(let tick):
                let wasIdle = animator.isIdle
                animator.tick(tick, at: Self.uptime())
                if wasIdle, let glider { CFRunLoopTimerSetNextFireDate(glider, CFAbsoluteTimeGetCurrent()) }
                return nil
            }
        }
    }

    fileprivate func glide() {
        if let frame = animator.frame(at: Self.uptime()) { Self.post(frame) }
        if animator.isIdle, let glider { CFRunLoopTimerSetNextFireDate(glider, Self.never) }
    }

    /// A fresh event per frame, because CG derives the line, fixed-point and point deltas from one another, so a
    /// reused event cannot be set to a new delta safely (measured).
    private static func post(_ frame: ScrollFrame) {
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: frame.points, wheel2: 0, wheel3: 0)
        else { return }
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(frame.phase.rawValue))
        event.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker)
        event.post(tap: .cgSessionEventTap)
    }

    private static func uptime() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000 }

    /// macOS disables a tap that answers slowly, and a key-up may have been lost while it was off.
    private func reenable() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        pipeline.reset()
        signals.yield(.reenabled)
    }

    fileprivate func checkHealth() {
        guard let port else { return }
        if !CFMachPortIsValid(port) {
            uninstall()
            install()
        } else if !CGEvent.tapIsEnabled(tap: port) {
            reenable()
        }
    }
}

nonisolated private func tapCallback(
    _ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let host = Unmanaged<TapHost>.fromOpaque(refcon).takeUnretainedValue()
    nonisolated(unsafe) let event = event
    return TapActor.assumeIsolated { host.handle(type, event) }
}

nonisolated private func tapGlide(_ timer: CFRunLoopTimer?, _ info: UnsafeMutableRawPointer?) {
    guard let info else { return }
    let host = Unmanaged<TapHost>.fromOpaque(info).takeUnretainedValue()
    TapActor.assumeIsolated { host.glide() }
}

nonisolated private func tapWatchdog(_ timer: CFRunLoopTimer?, _ info: UnsafeMutableRawPointer?) {
    guard let info else { return }
    let host = Unmanaged<TapHost>.fromOpaque(info).takeUnretainedValue()
    TapActor.assumeIsolated { host.checkHealth() }
}

/// The registry id of the HID event service that produced the event. Private API, as LinearMouse uses it.
nonisolated private func eventSender(_ event: CGEvent) -> SenderID? {
    guard let hid = CGEventCopyIOHIDEvent(event)?.takeRetainedValue() else { return nil }
    return SenderID(rawValue: IOHIDEventGetSenderID(hid))
}

@_silgen_name("CGEventCopyIOHIDEvent")
nonisolated private func CGEventCopyIOHIDEvent(_ event: CGEvent) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetSenderID")
nonisolated private func IOHIDEventGetSenderID(_ event: CFTypeRef) -> UInt64
