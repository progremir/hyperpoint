import AppKit
import CoreGraphics
import Foundation
import QuartzCore

struct TapOrder: Equatable, Sendable {
    var install: Bool
    var rules: TapRules
}

enum TapSignal: Sendable {
    case installed
    case installFailed
    case removed
    case reenabled
    case heard(ListenID, ListenPress)
}

@TapActor
final class TapHost {
    /// Frames come at least every 17 ms. A glide that waits longer lost its display link with its display.
    private static let stalled = 0.1

    private var pipeline = TapPipeline(rules: .empty, origin: eventOrigin)
    private var animator = ScrollAnimator()
    private var wholePoints = WholePoints()
    private var holdScroll = HoldScrollAnimator()
    private var holdPoints = (dx: WholePoints(), dy: WholePoints())
    private var cursorFrozen = false
    private var heldKeys = HeldKeys()
    /// The tap that adds held modifiers to every other event. It is newer than the main tap, so it runs first and the
    /// stages see the modifiers, and it is enabled only while modifiers are held.
    private var overlay: (port: CFMachPort, source: CFRunLoopSource)?
    /// Between a hold scroll's began and ended, from either recognizer.
    private var handScrolling = false
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: CFRunLoopTimer?
    private var frames: CADisplayLink?
    private var framesDisplay: CGDirectDisplayID?
    private var lastFrame = 0.0
    private let signals: AsyncStream<TapSignal>.Continuation
    /// Plain-button actions, for `ActionPerformer`.
    private let actions: AsyncStream<Action>.Continuation

    nonisolated init(signals: AsyncStream<TapSignal>.Continuation, actions: AsyncStream<Action>.Continuation) {
        self.signals = signals
        self.actions = actions
    }

    func follow(_ orders: AsyncStream<TapOrder>) async {
        for await order in orders { apply(order) }
    }

    /// HID++ controls' hold-to-scroll, from the HID thread.
    func follow(holdScrolls: AsyncStream<HoldScrollEvent>) async {
        for await event in holdScrolls { holdScrolled(event, at: nil) }
    }

    /// HID++ controls' held keys, from the HID thread. Posting needs no tap, so they work without one.
    func follow(keyHolds: AsyncStream<KeyHoldEvent>) async {
        for await event in keyHolds { holdKeys(event) }
    }

    func apply(_ order: TapOrder) {
        release(pipeline.reset(), endingEverything: !order.install)
        pipeline.replaceRules(order.rules)
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
        removeOverlay()
        updateOverlay()
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
        frames?.invalidate()
        if let ended = animator.stop() { post(ended) }
        CFMachPortInvalidate(port)
        (self.port, self.source, self.watchdog, frames) = (nil, nil, nil, nil)
        release(pipeline.reset(), endingEverything: true)
        removeOverlay()
        signals.yield(.removed)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenable()
            return Unmanaged.passUnretained(event)
        default:
            let verdict = pipeline.process(type, event)
            updateCursor()
            switch verdict {
            case .pass:
                return Unmanaged.passUnretained(event)
            case .drop:
                return nil
            case .scroll(let tick):
                let now = Self.uptime()
                animator.tick(tick, at: now)
                guard keepFrames(near: event.location, now: now) else {
                    if let ended = animator.stop() { post(ended) }
                    return Unmanaged.passUnretained(event)
                }
                return nil
            case .replay(let press, let release):
                press.post(tap: .cghidEventTap)
                release.post(tap: .cghidEventTap)
                return nil
            case .perform(let action):
                actions.yield(action)
                return nil
            case .holdScroll(let scroll):
                holdScrolled(scroll, at: event.location)
                return nil
            case .keys(let hold):
                holdKeys(hold)
                return nil
            case .heard(let id, let press):
                signals.yield(.heard(id, press))
                return nil
            }
        }
    }

    /// `location` is where the pointer is, or nil to ask, which only a display link that has to start needs.
    private func holdScrolled(_ event: HoldScrollEvent, at location: CGPoint?) {
        let now = Self.uptime()
        holdScroll.receive(event, at: now)
        switch event {
        case .began: handScrolling = true
        case .ended: handScrolling = false
        case .moved: break
        }
        updateCursor()
        guard holdScroll.wantsFrames else { return }
        if !keepFrames(near: location ?? CGEvent(source: nil)?.location ?? .zero, now: now) { endHoldScroll() }
    }

    /// The pointer stays put from the press of a plain button that scrolls until its release, and while an HID++
    /// control scrolls, whether or not the device keeps reporting movement to macOS. `force` frees it even if it
    /// should be free already, for a tap that stops or lost events.
    private func updateCursor(force: Bool = false) {
        let frozen = pipeline.holdsPointer || handScrolling
        guard frozen != cursorFrozen || force else { return }
        cursorFrozen = frozen
        _ = CGAssociateMouseAndMouseCursorPosition(frozen ? 0 : 1)
    }

    private func endHoldScroll() {
        if let ended = holdScroll.stop() { post(ended) }
        handScrolling = false
        updateCursor()
    }

    /// A button the pipeline forgot while it was down. A press held back from apps goes to them, its scroll ends and
    /// its keys go up. `endingEverything` also ends a scroll an HID++ control drives and lets go of every held key,
    /// for a tap that stops or lost events.
    private func release(_ release: ButtonStage.Release, endingEverything: Bool) {
        if release.endsScroll || endingEverything { endHoldScroll() }
        updateCursor(force: endingEverything)
        release.press?.post(tap: .cghidEventTap)
        if endingEverything {
            post(heldKeys.releaseAll(flags: CGEventSource.flagsState(.combinedSessionState)))
            updateOverlay()
        } else if let holder = release.letsGo {
            holdKeys(.release(holder))
        }
    }

    /// At the HID tap, so apps see the keys go down and up as a keyboard's would.
    private func holdKeys(_ event: KeyHoldEvent) {
        post(heldKeys.receive(event, flags: CGEventSource.flagsState(.combinedSessionState)))
        updateOverlay()
    }

    /// A tap that fails to install leaves held modifiers to the posted modifier changes alone.
    private func updateOverlay() {
        let holding = !heldKeys.flags.isEmpty
        if holding, overlay == nil,
            let port = CGEvent.tapCreate(
                tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: HeldKeys.overlayInterests.reduce(0) { $0 | (1 << CGEventMask($1.rawValue)) },
                callback: overlayCallback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        {
            if let source = CFMachPortCreateRunLoopSource(nil, port, 0) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                overlay = (port, source)
            } else {
                CFMachPortInvalidate(port)
            }
        }
        if let overlay { CGEvent.tapEnable(tap: overlay.port, enable: holding) }
    }

    private func removeOverlay() {
        guard let overlay else { return }
        CGEvent.tapEnable(tap: overlay.port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), overlay.source, .commonModes)
        CFMachPortInvalidate(overlay.port)
        self.overlay = nil
    }

    /// macOS disables a tap that answers slowly, and this one is wanted again while modifiers are held.
    fileprivate func overlaid(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput: updateOverlay()
        default: heldKeys.overlay(event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func post(_ keys: [CGEvent]) {
        for key in keys { key.post(tap: .cghidEventTap) }
    }

    /// Keeps the display link running for an animator that wants frames. A link that has not fired for `stalled`
    /// lost its display, so it is rebuilt. False when there is no display to follow.
    private func keepFrames(near location: @autoclosure () -> CGPoint, now: Double) -> Bool {
        let running = frames.map { !$0.isPaused } ?? false
        if running, now - lastFrame <= Self.stalled { return true }
        guard runFrames(at: location(), renew: running) else { return false }
        lastFrame = now
        return true
    }

    /// Frames follow the display under the pointer, whose refresh rate the scrolled window draws at. False when there
    /// is no display to follow.
    private func runFrames(at location: CGPoint, renew: Bool) -> Bool {
        var display = CGDirectDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(location, 1, &display, &count)
        if renew || frames == nil || (count > 0 && display != framesDisplay) {
            frames?.invalidate()
            frames = nil
            let screens = NSScreen.screens
            guard let screen = screens.first(where: { $0.displayID == display }) ?? screens.first else { return false }
            let link = screen.displayLink(target: FrameTarget(host: self), selector: #selector(FrameTarget.frame(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .current, forMode: .common)
            (frames, framesDisplay) = (link, screen.displayID)
        }
        frames?.isPaused = false
        return true
    }

    /// `time` is when the frame reaches the screen, on the same clock as `uptime()`.
    fileprivate func glide(at time: Double) {
        lastFrame = Self.uptime()
        if let frame = animator.frame(at: time) { post(frame) }
        if let frame = holdScroll.frame(at: time) { post(frame) }
        if animator.isIdle, !holdScroll.wantsFrames { frames?.isPaused = true }
    }

    /// A fresh event per frame, because CG derives the line, fixed-point and point deltas from one another, so a
    /// reused event cannot be set to a new delta safely (measured). The fixed-point field, in lines of 10 points,
    /// reaches only `NSEvent.deltaY`, but it can carry the fraction.
    private func post(_ frame: ScrollFrame) {
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: wholePoints.take(frame), wheel2: 0,
                wheel3: 0)
        else { return }
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: frame.points / 10)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(frame.phase.rawValue))
        event.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker)
        event.post(tap: .cgSessionEventTap)
    }

    /// Both axes, with a trackpad's scroll phases while the hand moves and its momentum phases while it glides.
    private func post(_ frame: HoldScrollFrame) {
        let restart = frame.phase == .began
        let dy = holdPoints.dy.take(frame.dy, restart: restart)
        let dx = holdPoints.dx.take(frame.dx, restart: restart)
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        else { return }
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: frame.dy / 10)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: frame.dx / 10)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(frame.phase.scrollPhase?.rawValue ?? 0))
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(frame.phase.momentumPhase.rawValue))
        event.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker)
        event.post(tap: .cgSessionEventTap)
    }

    private static func uptime() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000 }

    /// macOS disables a tap that answers slowly, and a key-up may have been lost while it was off.
    private func reenable() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        release(pipeline.reset(), endingEverything: true)
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

nonisolated private func overlayCallback(
    _ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let host = Unmanaged<TapHost>.fromOpaque(refcon).takeUnretainedValue()
    nonisolated(unsafe) let event = event
    return TapActor.assumeIsolated { host.overlaid(type, event) }
}

/// A display link calls an Objective-C method, so this hands each frame to the host.
private final class FrameTarget: NSObject {
    private unowned let host: TapHost

    init(host: TapHost) { self.host = host }

    @objc func frame(_ link: CADisplayLink) {
        let time = link.targetTimestamp
        let host = host
        TapActor.assumeIsolated { host.glide(at: time) }
    }
}

extension NSScreen {
    fileprivate var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

nonisolated private func tapWatchdog(_ timer: CFRunLoopTimer?, _ info: UnsafeMutableRawPointer?) {
    guard let info else { return }
    let host = Unmanaged<TapHost>.fromOpaque(info).takeUnretainedValue()
    TapActor.assumeIsolated { host.checkHealth() }
}

/// The HID event service that produced the event, and its wheel detents. Private API, as LinearMouse uses it.
nonisolated private func eventOrigin(_ event: CGEvent) -> HIDOrigin? {
    guard let hid = CGEventCopyIOHIDEvent(event)?.takeRetainedValue() else { return nil }
    return HIDOrigin(
        sender: SenderID(rawValue: IOHIDEventGetSenderID(hid)), wheelDetents: IOHIDEventGetFloatValue(hid, scrollY))
}

/// kIOHIDEventFieldScrollY: the scroll event type, 6, shifted into the high half, then the Y axis.
nonisolated private let scrollY: UInt32 = 0x60001

@_silgen_name("CGEventCopyIOHIDEvent")
nonisolated private func CGEventCopyIOHIDEvent(_ event: CGEvent) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetSenderID")
nonisolated private func IOHIDEventGetSenderID(_ event: CFTypeRef) -> UInt64

@_silgen_name("IOHIDEventGetFloatValue")
nonisolated private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: UInt32) -> Double
