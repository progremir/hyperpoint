import CoreGraphics
@testable import HyperpointKit
import Testing

private let f18: CGKeyCode = 79
private let r: CGKeyCode = 15
private let hyperFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

private func key(_ code: CGKeyCode, down: Bool, marked: Bool = false) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    if marked { event.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker) }
    return event
}

private func keyCode(_ event: CGEvent) -> Int64 { event.getIntegerValueField(.keyboardEventKeycode) }

@Suite struct TapPipelineTests {
    var pipeline = TapPipeline(
        rules: Intent.compile(.default, paused: false, tapAvailable: true, present: thisMac).tap)

    @Test mutating func hyperHeldIsAModifierChangeAndKeysCarryIt() {
        let down = key(f18, down: true)
        #expect(pipeline.process(.keyDown, down) == .pass)
        #expect(down.type == .flagsChanged)
        #expect(keyCode(down) == 55)
        #expect(down.flags.isSuperset(of: hyperFlags))

        let rDown = key(r, down: true)
        #expect(pipeline.process(.keyDown, rDown) == .pass)
        #expect(rDown.type == .keyDown && keyCode(rDown) == Int64(r))
        #expect(rDown.flags.isSuperset(of: hyperFlags))

        let rUp = key(r, down: false)
        #expect(pipeline.process(.keyUp, rUp) == .pass)
        #expect(rUp.flags.isSuperset(of: hyperFlags))

        let up = key(f18, down: false)
        up.flags = hyperFlags.union(.maskAlphaShift)
        #expect(pipeline.process(.keyUp, up) == .pass)
        #expect(up.type == .flagsChanged)
        #expect(up.flags.isDisjoint(with: hyperFlags), "the release clears the hyper modifiers")
        #expect(up.flags.contains(.maskAlphaShift), "the release keeps modifiers hyper does not own")

        let after = key(r, down: true)
        #expect(pipeline.process(.keyDown, after) == .pass)
        #expect(after.flags.isDisjoint(with: hyperFlags), "keys after release are plain")
    }

    @Test mutating func carrierModifierChangesNeverMarkFnHeld() {
        let down = key(f18, down: true)
        down.flags = .maskSecondaryFn
        #expect(pipeline.process(.keyDown, down) == .pass)
        #expect(down.type == .flagsChanged && down.flags.isSuperset(of: hyperFlags))
        #expect(!down.flags.contains(.maskSecondaryFn), "the press does not mark Fn held")

        let up = key(f18, down: false)
        up.flags = hyperFlags.union(.maskSecondaryFn)
        #expect(pipeline.process(.keyUp, up) == .pass)
        #expect(up.type == .flagsChanged && up.flags.isDisjoint(with: hyperFlags))
        #expect(!up.flags.contains(.maskSecondaryFn), "the release does not leave Fn held")
    }

    @Test mutating func keysUnderHyperKeepTheirOwnFn() {
        _ = pipeline.process(.keyDown, key(f18, down: true))

        let f5: CGKeyCode = 96
        let fKey = key(f5, down: true)
        fKey.flags = .maskSecondaryFn
        #expect(pipeline.process(.keyDown, fKey) == .pass)
        #expect(fKey.type == .keyDown && keyCode(fKey) == Int64(f5))
        #expect(fKey.flags.isSuperset(of: hyperFlags.union(.maskSecondaryFn)), "an F-key keeps Fn and gains hyper")

        let rDown = key(r, down: true)
        #expect(pipeline.process(.keyDown, rDown) == .pass)
        #expect(!rDown.flags.contains(.maskSecondaryFn), "a key without Fn does not gain it")
    }

    @Test mutating func autoRepeatOfTheHeldCarrierIsDropped() {
        _ = pipeline.process(.keyDown, key(f18, down: true))
        let repeated = pipeline.process(.keyDown, key(f18, down: true))
        #expect(repeated == .drop)
    }

    @Test mutating func markedEventsPassUntouched() {
        let marked = key(f18, down: true, marked: true)
        #expect(pipeline.process(.keyDown, marked) == .pass)
        #expect(marked.type == .keyDown && keyCode(marked) == Int64(f18))
        #expect(marked.flags.isDisjoint(with: hyperFlags))

        let rDown = key(r, down: true)
        _ = pipeline.process(.keyDown, rDown)
        #expect(rDown.flags.isDisjoint(with: hyperFlags), "a marked carrier does not hold hyper")

        _ = pipeline.process(.keyDown, key(f18, down: true))
        let markedR = key(r, down: true, marked: true)
        _ = pipeline.process(.keyDown, markedR)
        #expect(markedR.flags.isDisjoint(with: hyperFlags), "marked keys get no overlay while hyper is held")
    }

    @Test mutating func resetForgetsHeldHyper() {
        _ = pipeline.process(.keyDown, key(f18, down: true))
        pipeline.reset()

        let rDown = key(r, down: true)
        _ = pipeline.process(.keyDown, rDown)
        #expect(rDown.flags.isDisjoint(with: hyperFlags))

        let lateUp = key(f18, down: false)
        lateUp.flags = hyperFlags
        #expect(pipeline.process(.keyUp, lateUp) == .pass)
        #expect(lateUp.type == .flagsChanged && lateUp.flags.isDisjoint(with: hyperFlags), "a late key-up still clears")

        let again = key(f18, down: true)
        #expect(pipeline.process(.keyDown, again) == .pass, "hyper can be pressed again after a reset")
        #expect(again.flags.isSuperset(of: hyperFlags))
    }

    @Test mutating func newRulesForgetHeldHyper() {
        _ = pipeline.process(.keyDown, key(f18, down: true))
        pipeline.apply(Intent.compile(.default, paused: false, tapAvailable: true, present: thisMac).tap)
        let rDown = key(r, down: true)
        _ = pipeline.process(.keyDown, rDown)
        #expect(rDown.flags.isDisjoint(with: hyperFlags))
    }

    @Test mutating func withoutRulesF18IsAnOrdinaryKey() {
        pipeline.apply(.empty)
        let down = key(f18, down: true)
        #expect(pipeline.process(.keyDown, down) == .pass)
        #expect(down.type == .keyDown && keyCode(down) == Int64(f18))
        #expect(down.flags.isDisjoint(with: hyperFlags))
    }

    @Test func theTapListensForKeys() {
        #expect(TapPipeline.mask & (1 << CGEventMask(CGEventType.keyDown.rawValue)) != 0)
        #expect(TapPipeline.mask & (1 << CGEventMask(CGEventType.keyUp.rawValue)) != 0)
    }
}
