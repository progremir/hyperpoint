import Carbon.HIToolbox
import CoreGraphics
import os

/// Carbon hotkeys that do `CarrierFallback`'s work. In secure input macOS shows event taps no keys, but it still
/// matches hotkeys, and only for the keys a tap left alone (measured). Carbon delivers hotkeys on the main thread.
@MainActor
public final class CarrierHotkeys {
    /// Set in a carrier's hotkey id, clear in a Control key's.
    private static let carrierBit: UInt32 = 1 << 16
    /// How soon the Control keys are taken once secure input starts, and how soon a lost release is noticed.
    private static let checkEvery: Duration = .milliseconds(100)

    private let performer: ActionPerformer
    private var fallback = CarrierFallback()
    private var carrierHotkeys: [EventHotKeyRef] = []
    private var controlHotkeys: [KeyCode: EventHotKeyRef] = [:]
    private var checks: Task<Void, Never>?
    private let log = Logger(subsystem: "dev.emir.hyperpoint", category: "keys")

    public init(performer: ActionPerformer) { self.performer = performer }

    public func follow(_ engine: Engine) async {
        var kinds = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(), hotKeyHandler, kinds.count, &kinds, Unmanaged.passUnretained(self).toOpaque(),
            nil)
        guard status == noErr else {
            log.error("hotkey handler not installed: \(status)")
            return
        }
        for await plan in engine.carrierPlans where plan != fallback.plan { replace(plan) }
    }

    private func replace(_ plan: CarrierPlan) {
        apply(fallback.replace(plan))
        for hotkey in carrierHotkeys { UnregisterEventHotKey(hotkey) }
        carrierHotkeys = plan.carriers.compactMap { code, meaning in
            guard case .press = meaning else { return nil }
            return register(code, modifiers: 0, id: Self.carrierBit | UInt32(code.rawValue))
        }
        checks?.cancel()
        checks =
            plan.hyper
            ? Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.checkEvery)
                    self?.check()
                }
            } : nil
    }

    private func check() {
        apply(
            fallback.check(secureInput: IsSecureEventInputEnabled()) {
                CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0.rawValue))
            })
    }

    fileprivate func fired(_ id: UInt32, pressed: Bool) {
        let code = KeyCode(rawValue: UInt16(truncatingIfNeeded: id))
        if id & Self.carrierBit != 0 {
            guard pressed else { return }
            log.notice("carrier \(code.rawValue) got past the tap, as in secure input")
            apply(fallback.carrierPressed(code))
        } else if pressed {
            // The flags of the key that fired, from the hardware (measured).
            let flags = CGEventSource.flagsState(.hidSystemState).rawValue
            apply(fallback.controlKeyPressed(code, rightControl: flags & HeldModifier.rightControl.deviceFlag != 0))
        } else {
            apply(fallback.controlKeyReleased(code))
        }
    }

    private func apply(_ effects: [CarrierFallback.Effect]) {
        for effect in effects {
            switch effect {
            case .perform(let action):
                if action.typesCharacter, IsSecureEventInputEnabled() {
                    log.notice("a shortcut that types a character is not sent in secure input")
                } else {
                    performer.perform(action)
                }
            case .take(let keys):
                take(keys)
            case .hyper(let code, down: true):
                log.notice("hyper with key \(code.rawValue) sent on past secure input")
                post(code, down: true, flags: Modifiers.hyper.cgFlags)
            case .hyper(let code, down: false):
                // The press already reached the hotkey. A release with hyper that lands after Right Control's would
                // leave the system's modifier state reading hyper (measured).
                post(code, down: false, flags: [])
            case .passBack(let code):
                // The hotkey matches Control alone, and the system's modifier state may still read what this
                // posted last, so the press goes back as it must have come.
                log.notice("control with key \(code.rawValue) given back to the app")
                post(code, down: true, flags: HeldModifier.leftControl.flags)
            }
        }
    }

    /// Registering every key takes about a millisecond (measured), well before the key a hand presses next.
    private func take(_ keys: Set<KeyCode>) {
        let before = controlHotkeys.count
        for (code, hotkey) in controlHotkeys where !keys.contains(code) {
            UnregisterEventHotKey(hotkey)
            controlHotkeys[code] = nil
        }
        for code in keys where controlHotkeys[code] == nil {
            controlHotkeys[code] = register(code, modifiers: UInt32(controlKey), id: UInt32(code.rawValue))
        }
        if before == 0 || controlHotkeys.isEmpty {
            log.notice("Control keys taken for hyper: \(self.controlHotkeys.count)")
        }
    }

    private func register(_ code: KeyCode, modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
        var hotkey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(code.rawValue), modifiers, EventHotKeyID(signature: hotKeySignature, id: id),
            GetApplicationEventTarget(), 0, &hotkey)
        if status != noErr { log.error("hotkey for key \(code.rawValue) not registered: \(status)") }
        return hotkey
    }

    /// At the HID tap, marked, as `ActionPerformer` posts a shortcut. A new event already has the flags its key
    /// always carries, such as Fn on F-keys and arrows, and a hotkey on such a key does not match without them
    /// (measured). A source gives each new event the flags of the last one posted from it, Fn and modifiers alike
    /// (measured), so every event gets a new source.
    private func post(_ code: KeyCode, down: Bool, flags: CGEventFlags) {
        guard
            let event = CGEvent(
                keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: CGKeyCode(code.rawValue),
                keyDown: down)
        else { return }
        event.flags.formUnion(flags)
        event.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }
}

nonisolated private let hotKeySignature: OSType = 0x4879_704B  // "HypK"

nonisolated private func hotKeyHandler(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr, id.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let hotkeys = Unmanaged<CarrierHotkeys>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotkeys.fired(id.id, pressed: pressed) }
    return noErr
}
