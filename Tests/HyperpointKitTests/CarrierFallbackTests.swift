@testable import HyperpointKit
import Testing

private let f13 = Carrier.f13.keyCode
private let t = KeyCode(name: "t")!
private let r = KeyCode(name: "r")!
private let optShiftS = Action.shortcut(Chord(key: KeyCode(name: "s")!, modifiers: [.option, .shift]))
private let all = CarrierFallback.controlKeys

@Suite struct CarrierFallbackTests {
    var fallback = CarrierFallback()
    var keysDown: Set<KeyCode> = []

    init() {
        _ = fallback.replace(CarrierPlan(carriers: [f13: .press(optShiftS)], hyper: true))
    }

    mutating func check(secureInput: Bool) -> [CarrierFallback.Effect] {
        let down = keysDown
        return fallback.check(secureInput: secureInput) { down.contains($0) }
    }

    @Test mutating func secureInputTakesEveryKeyWithControlUntilItEnds() {
        #expect(check(secureInput: false) == [])
        #expect(check(secureInput: true) == [.take(all)])
        #expect(all.contains(t) && all.contains(KeyCode(name: "space")!) && all.contains(KeyCode(name: "f5")!))
        #expect(all.contains(Carrier.f16.keyCode), "F13 to F20 have hyper in the tap too")
        #expect(!all.contains(KeyCode(name: "capsLock")!), "Caps Lock is hyper's own key")
        #expect(check(secureInput: true) == [], "nothing changes while it stays on")
        #expect(check(secureInput: false) == [.take([])])
    }

    @Test mutating func aKeyWithRightControlGoesOnWithHyper() {
        _ = check(secureInput: true)
        keysDown = [t]
        #expect(fallback.controlKeyPressed(t, rightControl: true) == [.hyper(t, down: true)])
        #expect(fallback.controlKeyPressed(t, rightControl: true) == [], "a repeat sends nothing")
        #expect(check(secureInput: true) == [])
        #expect(fallback.controlKeyReleased(t) == [.hyper(t, down: false)])
        #expect(fallback.controlKeyReleased(t) == [])
    }

    @Test mutating func aKeyWithTheOtherControlGoesBackToTheAppUntilItIsUp() {
        _ = check(secureInput: true)
        keysDown = [t]
        #expect(fallback.controlKeyPressed(t, rightControl: false) == [.take(all.subtracting([t])), .passBack(t)])
        #expect(check(secureInput: true) == [], "its hotkey stays given back while it is down")
        keysDown = []
        #expect(check(secureInput: true) == [.take(all)])
    }

    @Test mutating func aLostReleaseGoesUpWithHyper() {
        _ = check(secureInput: true)
        keysDown = [t]
        _ = fallback.controlKeyPressed(t, rightControl: true)
        keysDown = []
        #expect(check(secureInput: true) == [.hyper(t, down: false)], "Right Control let go first, so ⌃T never went up")
        #expect(fallback.controlKeyReleased(t) == [])
    }

    @Test mutating func keysStayTakenAfterSecureInputUntilTheLastHyperKeyIsUp() {
        _ = check(secureInput: true)
        keysDown = [t]
        _ = fallback.controlKeyPressed(t, rightControl: true)
        #expect(check(secureInput: false) == [], "the release of ⌃T still has to come back as a hotkey")
        keysDown = []
        #expect(check(secureInput: false) == [.hyper(t, down: false), .take([])])
    }

    @Test mutating func keysNotTakenAreNotSentOn() {
        #expect(fallback.controlKeyPressed(t, rightControl: true) == [])
    }

    @Test mutating func withoutHyperNoKeyIsTaken() {
        _ = fallback.replace(CarrierPlan(carriers: [f13: .press(optShiftS)], hyper: false))
        #expect(check(secureInput: true) == [])
    }

    @Test mutating func newPlansLetGoOfEverything() {
        _ = check(secureInput: true)
        keysDown = [t, r]
        _ = fallback.controlKeyPressed(t, rightControl: true)
        _ = fallback.controlKeyPressed(r, rightControl: true)
        #expect(fallback.replace(.none) == [.hyper(r, down: false), .hyper(t, down: false), .take([])])
        #expect(check(secureInput: true) == [])
    }

    @Test mutating func aPressCarrierPerformsItsAction() {
        #expect(fallback.carrierPressed(f13) == [.perform(optShiftS)])
        #expect(fallback.carrierPressed(t) == [])
    }

    @Test func onlyAShortcutWithoutCommandOrControlOnACharacterKeyTypesACharacter() {
        #expect(optShiftS.typesCharacter)
        #expect(Action.shortcut(Chord(key: KeyCode(name: "slash")!, modifiers: [.shift])).typesCharacter)
        #expect(!Action.shortcut(Chord(key: KeyCode(name: "s")!, modifiers: [.command, .shift])).typesCharacter)
        #expect(!Action.shortcut(Chord(key: KeyCode(name: "s")!, modifiers: [.control])).typesCharacter)
        #expect(!Action.shortcut(Chord(key: KeyCode(name: "space")!, modifiers: [.option])).typesCharacter)
        #expect(!Action.shortcut(Chord(key: KeyCode(name: "f5")!, modifiers: [])).typesCharacter)
        #expect(!Action.modifier(.rightOption).typesCharacter)
    }
}
