import AppKit
import Carbon.HIToolbox
import CoreGraphics

// Throwaway probe. Modes: overlay | real | senders | posted | wheel | hold | keys | held.
// overlay, real: posts F18 down, F16 down/up, F18 up at the HID tap. A rewriting tap turns F18 into hyper using
// the chosen strategy. A Carbon hotkey for cmd+ctrl+opt+shift+F16 and a later listen-only tap report what apps see.
// senders: logs the IOHIDEvent sender id of every pointer event for 40 s, grouped every 2 s.
// hold: 45 s of what apps receive while a button scrolls: posted scrolls on both axes with their phases, right and
// other button events, and where the pointer is at each.
// keys[-seconds]: 45 s (or the given seconds) of key events as they enter the HID tap ahead of Hyperpoint's ("in") and as apps receive them ("app"),
// with sender, flags and marker; HID-system modifier changes; and a Carbon hotkey for opt+shift+S counting its fires.
// held[-seconds]: 60 s (or the given seconds) of what a button that holds keys does: key and modifier events and
// right, other and left clicks, as they enter the HID tap ("in") and as apps receive them ("app"), with flags; pointer
// movement apps receive, per 250 ms; HID-system modifier changes; and a Carbon hotkey for ctrl+opt+cmd+H reporting
// each press and release.

@_silgen_name("CGEventCopyIOHIDEvent") func CGEventCopyIOHIDEvent(_ event: CGEvent) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetSenderID") func IOHIDEventGetSenderID(_ event: CFTypeRef) -> UInt64
@_silgen_name("IOHIDEventGetFloatValue") func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: UInt32) -> Double
let wheelStart = DispatchTime.now().uptimeNanoseconds
nonisolated(unsafe) var wheelLines: [String] = []

let arg = ProcessInfo.processInfo.arguments.dropFirst().first ?? "overlay"
let variant = String(arg.split(separator: "-")[0])
let withHotkey = !arg.hasSuffix("-nohotkey")
let marker: Int64 = 0x4859_5052
let hyperFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
let f18: CGKeyCode = 79, f16: CGKeyCode = 106
let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
print("variant=\(variant) accessibilityTrusted=\(trusted)")
fflush(stdout)

nonisolated(unsafe) var hyperHeld = false
nonisolated(unsafe) var hotkeyFired = 0
nonisolated(unsafe) var observed: [String] = []
nonisolated(unsafe) var senderCounts: [String: Int] = [:]

func post(_ code: CGKeyCode, _ down: Bool, flags: CGEventFlags? = nil, marked: Bool = false, type: CGEventType? = nil) {
    let src = CGEventSource(stateID: .hidSystemState)
    let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
    if let type { e.type = type }
    if let flags { e.flags = flags }
    if marked { e.setIntegerValueField(.eventSourceUserData, value: marker) }
    e.post(tap: .cghidEventTap)
}

let modifierKeys: [(CGKeyCode, CGEventFlags)] = [(55, .maskCommand), (59, .maskControl), (58, .maskAlternate), (56, .maskShift)]

func postRealModifiers(down: Bool) {
    var flags: CGEventFlags = down ? [] : hyperFlags
    for (code, flag) in modifierKeys {
        if down { flags.insert(flag) } else { flags.remove(flag) }
        post(code, down, flags: flags, marked: true, type: .flagsChanged)
    }
}

let rewrite: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return Unmanaged.passUnretained(event) }
    if event.getIntegerValueField(.eventSourceUserData) == marker { return Unmanaged.passUnretained(event) }
    let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    if code == f18, type == .keyDown || type == .keyUp {
        let down = type == .keyDown
        if down == hyperHeld { return nil }
        hyperHeld = down
        if variant == "real" { postRealModifiers(down: down) }
        if variant == "flags" {
            event.type = .flagsChanged
            event.setIntegerValueField(.keyboardEventKeycode, value: 55)
            event.flags = down ? event.flags.union(hyperFlags) : event.flags.subtracting(hyperFlags)
            return Unmanaged.passUnretained(event)
        }
        return nil
    }
    if variant == "overlay" || variant == "flags", hyperHeld, type == .keyDown || type == .keyUp {
        event.flags = event.flags.union(hyperFlags)
    }
    return Unmanaged.passUnretained(event)
}

let observe: CGEventTapCallBack = { _, type, event, _ in
    let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    if code == f16, type == .keyDown {
        let ev = event.flags.intersection(hyperFlags) == hyperFlags
        let session = CGEventSource.flagsState(.combinedSessionState).intersection(hyperFlags) == hyperFlags
        let hid = CGEventSource.flagsState(.hidSystemState).intersection(hyperFlags) == hyperFlags
        let ns = NSEvent.modifierFlags.isSuperset(of: [.command, .control, .option, .shift])
        observed.append("eventFlags=\(ev) combinedSessionState=\(session) hidSystemState=\(hid) NSEvent.modifierFlags=\(ns)")
    }
    return Unmanaged.passUnretained(event)
}

let senders: CGEventTapCallBack = { _, type, event, _ in
    guard type.rawValue < 0xFFFF_FFFE else { return Unmanaged.passUnretained(event) }
    var sender = "none"
    if let hid = CGEventCopyIOHIDEvent(event) {
        sender = String(format: "0x%llx", IOHIDEventGetSenderID(hid.takeRetainedValue()))
    }
    let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
    let name = switch type {
    case .scrollWheel: "scroll"
    case .leftMouseDown: "leftDown"
    case .rightMouseDown: "rightDown"
    case .otherMouseDown: "otherDown(\(event.getIntegerValueField(.mouseEventButtonNumber)))"
    case .mouseMoved: "moved"
    default: "type\(type.rawValue)"
    }
    senderCounts["\(name) sender=\(sender) pid=\(pid)", default: 0] += 1
    return Unmanaged.passUnretained(event)
}

/// The four modifiers plus the left and right device bits (NX_DEVICE*KEYMASK), so Right Option shows as itself.
let deviceBits: [(UInt64, String)] = [
    (0x1, "lCtrl"), (0x2, "lShift"), (0x4, "rShift"), (0x8, "lCmd"), (0x10, "rCmd"), (0x20, "lOpt"), (0x40, "rOpt"),
    (0x2000, "rCtrl"),
]
let modifierMask = CGEventFlags(rawValue: deviceBits.reduce(0) { $0 | $1.0 } | hyperFlags.rawValue)

func flagNames(_ flags: CGEventFlags) -> String {
    let names = [(CGEventFlags.maskControl, "ctrl"), (.maskAlternate, "opt"), (.maskShift, "shift"), (.maskCommand, "cmd"),
                 (.maskSecondaryFn, "fn")].filter { flags.contains($0.0) }.map(\.1)
        + deviceBits.filter { flags.rawValue & $0.0 != 0 }.map(\.1)
    return names.isEmpty ? "-" : names.joined(separator: "+")
}

/// S, H, Return, Escape, the modifiers, F13 and F18. Every other key is logged as "other", so typing is not recorded.
let loggedKeys = Set<Int64>([1, 4, 36, 53, 105, 79]).union(54...63)

func keyLine(_ stage: String, _ type: CGEventType, _ event: CGEvent) -> String {
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    var sender: UInt64 = 0
    if let hid = CGEventCopyIOHIDEvent(event) { sender = IOHIDEventGetSenderID(hid.takeRetainedValue()) }
    let name = [CGEventType.keyDown: "down", .keyUp: "up", .flagsChanged: "flags"][type] ?? "type\(type.rawValue)"
    return String(format: "%.1f %@ %@ key=%@ repeat=%lld flags=%@ ours=%d sender=0x%llx",
        Double(DispatchTime.now().uptimeNanoseconds - wheelStart) / 1e6, stage, name,
        loggedKeys.contains(code) ? String(code) : "other", event.getIntegerValueField(.keyboardEventAutorepeat),
        flagNames(event.flags), event.getIntegerValueField(.eventSourceUserData) == marker ? 1 : 0, sender)
}

func mouseLine(_ stage: String, _ type: CGEventType, _ event: CGEvent) -> String {
    let name = [
        CGEventType.leftMouseDown: "leftDown", .leftMouseUp: "leftUp", .rightMouseDown: "rightDown",
        .rightMouseUp: "rightUp", .otherMouseDown: "otherDown", .otherMouseUp: "otherUp",
    ][type] ?? "type\(type.rawValue)"
    var sender: UInt64 = 0
    if let hid = CGEventCopyIOHIDEvent(event) { sender = IOHIDEventGetSenderID(hid.takeRetainedValue()) }
    return String(format: "%.1f %@ %@ button=%lld flags=%@ ours=%d sender=0x%llx", Double(DispatchTime.now().uptimeNanoseconds - wheelStart) / 1e6,
        stage, name, event.getIntegerValueField(.mouseEventButtonNumber), flagNames(event.flags),
        event.getIntegerValueField(.eventSourceUserData) == marker ? 1 : 0, sender)
}

nonisolated(unsafe) var heldMoved = 0
nonisolated(unsafe) var heldDragged = 0

func heldLine(_ stage: String, _ type: CGEventType, _ event: CGEvent) -> String {
    [.keyDown, .keyUp, .flagsChanged].contains(type) ? keyLine(stage, type, event) : mouseLine(stage, type, event)
}

let heldIn: CGEventTapCallBack = { _, type, event, _ in
    if type.rawValue < 0xFFFF_FFFE { wheelLines.append(heldLine("in", type, event)) }
    return Unmanaged.passUnretained(event)
}

let heldApp: CGEventTapCallBack = { _, type, event, _ in
    if type.rawValue < 0xFFFF_FFFE { wheelLines.append(heldLine("app", type, event)) }
    return Unmanaged.passUnretained(event)
}

let heldMovement: CGEventTapCallBack = { _, type, event, _ in
    if type == .mouseMoved { heldMoved += 1 } else if type.rawValue < 0xFFFF_FFFE { heldDragged += 1 }
    return Unmanaged.passUnretained(event)
}

func install(_ tap: CGEventTapLocation, _ place: CGEventTapPlacement, _ options: CGEventTapOptions, _ mask: CGEventMask, _ cb: CGEventTapCallBack) -> Bool {
    guard let port = CGEvent.tapCreate(tap: tap, place: place, options: options, eventsOfInterest: mask, callback: cb, userInfo: nil) else { return false }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    return true
}

func bit(_ t: CGEventType) -> CGEventMask { 1 << CGEventMask(t.rawValue) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if variant == "posted" {
    let posted: CGEventTapCallBack = { _, type, event, _ in
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - wheelStart) / 1e6
        let ours = event.getIntegerValueField(.eventSourceUserData) == marker
        let ns = NSEvent(cgEvent: event)
        wheelLines.append(String(format: "%.1f ours=%d point=%lld fixed=%.4f lines=%lld cont=%lld phase=%lld momentum=%lld nsDeltaY=%.4f precise=%d", ms, ours ? 1 : 0,
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            event.getIntegerValueField(.scrollWheelEventDeltaAxis1), event.getIntegerValueField(.scrollWheelEventIsContinuous),
            event.getIntegerValueField(.scrollWheelEventScrollPhase), event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            ns?.scrollingDeltaY ?? .nan, (ns?.hasPreciseScrollingDeltas ?? false) ? 1 : 0))
        return Unmanaged.passUnretained(event)
    }
    guard install(.cgAnnotatedSessionEventTap, .tailAppendEventTap, .defaultTap, bit(.scrollWheel), posted) else { print("tapCreate failed"); exit(2) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 40) {
        print(wheelLines.joined(separator: "\n"))
        let ours = wheelLines.filter { $0.contains("ours=1") }
        let times = ours.compactMap { Double($0.split(separator: " ")[0]) }
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 < 100 }.sorted()
        if !gaps.isEmpty {
            print(String(format: "summary: %d posted frames, gap ms min %.2f median %.2f p95 %.2f max %.2f", ours.count, gaps.first!,
                gaps[gaps.count / 2], gaps[min(gaps.count - 1, gaps.count * 95 / 100)], gaps.last!))
        }
        func field(_ line: String, _ name: String) -> Int? {
            line.split(separator: " ").first { $0.hasPrefix(name + "=") }.flatMap { Int($0.dropFirst(name.count + 1)) }
        }
        var zeroRuns = 0
        var run = 0
        var moving = false
        for line in ours {
            guard let point = field(line, "point"), let phase = field(line, "phase") else { continue }
            if phase == 1 || phase == 4 { (moving, run) = (false, 0) }
            if phase == 4 { continue }
            if point != 0 {
                if moving && run >= 2 { zeroRuns += 1 }
                (moving, run) = (true, 0)
            } else if moving {
                run += 1
            }
        }
        print("summary: runs of 2+ zero-point frames between moves: \(zeroRuns)")
        fflush(stdout)
        exit(0)
    }
} else if variant == "hold" {
    let hold: CGEventTapCallBack = { _, type, event, _ in
        let ms = Double(DispatchTime.now().uptimeNanoseconds - wheelStart) / 1e6
        let ours = event.getIntegerValueField(.eventSourceUserData) == marker ? 1 : 0
        let cursor = CGEvent(source: nil)?.location ?? .zero
        let at = String(format: "cursor=%.0f,%.0f", cursor.x, cursor.y)
        switch type {
        case .scrollWheel:
            wheelLines.append(String(format: "%.1f scroll ours=%d dy=%lld dx=%lld phase=%lld momentum=%lld %@", ms, ours,
                event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
                event.getIntegerValueField(.scrollWheelEventScrollPhase), event.getIntegerValueField(.scrollWheelEventMomentumPhase), at))
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            let name = [CGEventType.rightMouseDown: "down", .rightMouseUp: "up", .rightMouseDragged: "drag",
                        .otherMouseDown: "down", .otherMouseUp: "up", .otherMouseDragged: "drag"][type]!
            wheelLines.append(String(format: "%.1f button=%lld %@ ours=%d %@", ms,
                event.getIntegerValueField(.mouseEventButtonNumber), name, ours, at))
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
    let mask = bit(.scrollWheel) | bit(.rightMouseDown) | bit(.rightMouseUp) | bit(.rightMouseDragged)
        | bit(.otherMouseDown) | bit(.otherMouseUp) | bit(.otherMouseDragged)
    // Active, passing every event unchanged: a listen-only tap gets no hardware events without Input Monitoring.
    guard install(.cgAnnotatedSessionEventTap, .tailAppendEventTap, .defaultTap, mask, hold) else { print("tapCreate failed"); exit(2) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 45) { print(wheelLines.joined(separator: "\n")); fflush(stdout); exit(0) }
} else if variant == "keys" {
    let mask = bit(.keyDown) | bit(.keyUp) | bit(.flagsChanged)
    let input: CGEventTapCallBack = { _, type, event, _ in
        if type.rawValue < 0xFFFF_FFFE { wheelLines.append(keyLine("in", type, event)) }
        return Unmanaged.passUnretained(event)
    }
    let delivered: CGEventTapCallBack = { _, type, event, _ in
        if type.rawValue < 0xFFFF_FFFE { wheelLines.append(keyLine("app", type, event)) }
        return Unmanaged.passUnretained(event)
    }
    // Installed after Hyperpoint's, so this head tap runs ahead of it. Both pass every event unchanged.
    guard install(.cghidEventTap, .headInsertEventTap, .defaultTap, mask, input),
          install(.cgAnnotatedSessionEventTap, .tailAppendEventTap, .defaultTap, mask, delivered)
    else { print("tapCreate failed"); exit(2) }
    var hotKeyRef: EventHotKeyRef?
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        hotkeyFired += 1
        wheelLines.append(String(format: "%.1f hotkey opt+shift+S fired", Double(DispatchTime.now().uptimeNanoseconds - wheelStart) / 1e6))
        return noErr
    }, 1, &spec, nil, nil)
    let reg = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey | shiftKey), EventHotKeyID(signature: 0x48595052, id: 2),
        GetApplicationEventTarget(), 0, &hotKeyRef)
    print("RegisterEventHotKey opt+shift+S status=\(reg)")
    var lastHID = CGEventFlags()
    Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
        let now = CGEventSource.flagsState(.hidSystemState).intersection(modifierMask)
        guard now != lastHID else { return }
        lastHID = now
        wheelLines.append(String(format: "%.1f hidSystemState flags=%@", Double(DispatchTime.now().uptimeNanoseconds - wheelStart) / 1e6, flagNames(now)))
    }
    // "keys-120" records for 120 s.
    let seconds = arg.split(separator: "-").dropFirst().first.flatMap { Double($0) } ?? 45
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        print(wheelLines.joined(separator: "\n"))
        print("carbonHotkeyFired=\(hotkeyFired)")
        fflush(stdout)
        exit(0)
    }
} else if variant == "held" {
    let clickTypes: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
    let mask = bit(.keyDown) | bit(.keyUp) | bit(.flagsChanged) | clickTypes.reduce(0) { $0 | bit($1) }
    let movementMask = bit(.mouseMoved) | bit(.rightMouseDragged) | bit(.otherMouseDragged)
    // Installed after Hyperpoint's, so the head tap runs ahead of it. Every tap passes every event unchanged.
    guard install(.cghidEventTap, .headInsertEventTap, .defaultTap, mask, heldIn),
          install(.cgAnnotatedSessionEventTap, .tailAppendEventTap, .defaultTap, mask, heldApp),
          install(.cgAnnotatedSessionEventTap, .tailAppendEventTap, .defaultTap, movementMask, heldMovement)
    else { print("tapCreate failed"); exit(2) }
    var hotKeyRef: EventHotKeyRef?
    var specs = [
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
        if pressed { hotkeyFired += 1 }
        wheelLines.append(String(format: "%.1f hotkey ctrl+opt+cmd+H %@", Double(DispatchTime.now().uptimeNanoseconds - wheelStart) / 1e6,
            pressed ? "pressed" : "released"))
        return noErr
    }, 2, &specs, nil, nil)
    let reg = RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x48595052, id: 3),
        GetApplicationEventTarget(), 0, &hotKeyRef)
    print("RegisterEventHotKey ctrl+opt+cmd+H status=\(reg)")
    var lastHID = CGEventFlags()
    Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
        let now = CGEventSource.flagsState(.hidSystemState).intersection(modifierMask)
        guard now != lastHID else { return }
        lastHID = now
        wheelLines.append(String(format: "%.1f hidSystemState flags=%@", Double(DispatchTime.now().uptimeNanoseconds - wheelStart) / 1e6, flagNames(now)))
    }
    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
        guard heldMoved + heldDragged > 0 else { return }
        let cursor = CGEvent(source: nil)?.location ?? .zero
        wheelLines.append(String(format: "%.1f app moved=%d dragged=%d cursor=%.0f,%.0f",
            Double(DispatchTime.now().uptimeNanoseconds - wheelStart) / 1e6, heldMoved, heldDragged, cursor.x, cursor.y))
        (heldMoved, heldDragged) = (0, 0)
    }
    let seconds = arg.split(separator: "-").dropFirst().first.flatMap { Double($0) } ?? 60
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        print(wheelLines.joined(separator: "\n"))
        print("carbonHotkeyPressed=\(hotkeyFired)")
        fflush(stdout)
        exit(0)
    }
} else if variant == "wheel" {
    let wheel: CGEventTapCallBack = { _, type, event, _ in
        guard type == .scrollWheel, event.getIntegerValueField(.eventSourceUserData) != marker else { return Unmanaged.passUnretained(event) }
        var sender: UInt64 = 0
        var raw = Double.nan
        if let hid = CGEventCopyIOHIDEvent(event) {
            let h = hid.takeRetainedValue()
            sender = IOHIDEventGetSenderID(h)
            raw = IOHIDEventGetFloatValue(h, 0x60001)
        }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - wheelStart) / 1e6
        wheelLines.append(String(format: "%.1f sender=0x%llx raw=%.3f lines=%lld fixed=%.3f point=%lld cont=%lld", ms, sender, raw,
            event.getIntegerValueField(.scrollWheelEventDeltaAxis1), event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), event.getIntegerValueField(.scrollWheelEventIsContinuous)))
        return Unmanaged.passUnretained(event)
    }
    guard install(.cghidEventTap, .headInsertEventTap, .defaultTap, bit(.scrollWheel), wheel) else { print("tapCreate failed"); exit(2) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 45) { print(wheelLines.joined(separator: "\n")); fflush(stdout); exit(0) }
} else if variant == "senders" {
    let mask = bit(.scrollWheel) | bit(.leftMouseDown) | bit(.rightMouseDown) | bit(.otherMouseDown) | bit(.mouseMoved)
    guard install(.cghidEventTap, .headInsertEventTap, .defaultTap, mask, senders) else { print("tapCreate failed"); exit(2) }
    let start = Date()
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        let t = Int(Date().timeIntervalSince(start))
        for (k, n) in senderCounts.sorted(by: { $0.key < $1.key }) { print("t=\(t)s \(k) count=\(n)") }
        senderCounts = [:]
        fflush(stdout)
        if t >= 90 { exit(0) }
    }
} else {
    let mask = bit(.keyDown) | bit(.keyUp) | bit(.flagsChanged)
    guard variant == "none" || install(.cghidEventTap, .headInsertEventTap, .defaultTap, mask, rewrite),
          install(.cgAnnotatedSessionEventTap, .tailAppendEventTap, .listenOnly, mask, observe)
    else { print("tapCreate failed"); exit(2) }
    var hotKeyRef: EventHotKeyRef?
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in hotkeyFired += 1; return noErr }, 1, &spec, nil, nil)
    let mods = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    let reg = !withHotkey ? -1 : RegisterEventHotKey(UInt32(f16), mods, EventHotKeyID(signature: 0x48595052, id: 1), GetApplicationEventTarget(), 0, &hotKeyRef)
    print("RegisterEventHotKey status=\(reg)")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        post(f18, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            post(f16, true)
            post(f16, false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                post(f18, false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let after = CGEventSource.flagsState(.combinedSessionState).intersection(hyperFlags)
                    print(observed.isEmpty ? "observer saw no F16 keyDown" : observed.joined(separator: "\n"))
                    print("carbonHotkeyFired=\(hotkeyFired) modifiersStuckAfter=\(!after.isEmpty)")
                    fflush(stdout)
                    exit(0)
                }
            }
        }
    }
}
app.run()
