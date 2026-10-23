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
    private var pipeline = TapPipeline(rules: .empty)
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: CFRunLoopTimer?
    private let signals: AsyncStream<TapSignal>.Continuation

    nonisolated init(signals: AsyncStream<TapSignal>.Continuation) { self.signals = signals }

    func follow(_ orders: AsyncStream<TapOrder>) async {
        for await order in orders { apply(order) }
    }

    func apply(_ order: TapOrder) {
        pipeline.apply(order.rules)
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
        (self.port, self.source, self.watchdog) = (port, source, watchdog)
        signals.yield(.installed)
    }

    private func uninstall() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        if let watchdog { CFRunLoopTimerInvalidate(watchdog) }
        CFMachPortInvalidate(port)
        (self.port, self.source, self.watchdog) = (nil, nil, nil)
        pipeline.reset()
        signals.yield(.removed)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenable()
            return Unmanaged.passUnretained(event)
        default:
            return pipeline.process(type, event) == .drop ? nil : Unmanaged.passUnretained(event)
        }
    }

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

nonisolated private func tapWatchdog(_ timer: CFRunLoopTimer?, _ info: UnsafeMutableRawPointer?) {
    guard let info else { return }
    let host = Unmanaged<TapHost>.fromOpaque(info).takeUnretainedValue()
    TapActor.assumeIsolated { host.checkHealth() }
}
