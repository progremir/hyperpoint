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
        rules: Intent.compile(.default, paused: false, tapAvailable: true, present: thisMac).tap, sender: { _ in nil })

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
        pipeline.replaceRulesAndForgetHeldKeys(Intent.compile(.default, paused: false, tapAvailable: true, present: thisMac).tap)
        let rDown = key(r, down: true)
        _ = pipeline.process(.keyDown, rDown)
        #expect(rDown.flags.isDisjoint(with: hyperFlags))
    }

    @Test mutating func withoutRulesF18IsAnOrdinaryKey() {
        pipeline.replaceRulesAndForgetHeldKeys(.empty)
        let down = key(f18, down: true)
        #expect(pipeline.process(.keyDown, down) == .pass)
        #expect(down.type == .keyDown && keyCode(down) == Int64(f18))
        #expect(down.flags.isDisjoint(with: hyperFlags))
    }

    @Test func theTapListensForKeysAndScrolls() {
        for type in [CGEventType.keyDown, .keyUp, .scrollWheel] {
            #expect(TapPipeline.mask & (1 << CGEventMask(type.rawValue)) != 0, "\(type.rawValue)")
        }
    }
}

private let mxSender = SenderID(rawValue: 0x1_0003_7032)
private let trackpadSender = SenderID(rawValue: 0x1_0000_0D10)
private let smooth = Config.default.devices[0].scrolling!.smooth!

private func wheel(_ lines: Int32, horizontal: Int32 = 0, marked: Bool = false) -> CGEvent {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: lines, wheel2: horizontal, wheel3: 0)!
    if marked { event.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker) }
    return event
}

@Suite struct ScrollStageTests {
    let rules = Intent.compile(
        .default, paused: false, tapAvailable: true,
        present: [present(3, Bags.mxMaster3, services: [mxSender.rawValue])]
    ).tap

    func pipeline(_ sender: SenderID?) -> TapPipeline { TapPipeline(rules: rules, sender: { _ in sender }) }

    @Test func aWheelTickFromASmoothSenderIsTakenForTheAnimator() {
        var pipeline = pipeline(mxSender)
        #expect(pipeline.process(.scrollWheel, wheel(1)) == .scroll(ScrollTick(sign: .positive, settings: smooth)))
        #expect(pipeline.process(.scrollWheel, wheel(-3)) == .scroll(ScrollTick(sign: .negative, settings: smooth)))
    }

    @Test func continuousScrollsPass() {
        var pipeline = pipeline(mxSender)
        let continuous = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 12, wheel2: 0, wheel3: 0)!
        #expect(pipeline.process(.scrollWheel, continuous) == .pass)
    }

    @Test func horizontalScrollsPass() {
        var pipeline = pipeline(mxSender)
        #expect(pipeline.process(.scrollWheel, wheel(0, horizontal: 1)) == .pass, "the thumb wheel")
        #expect(pipeline.process(.scrollWheel, wheel(1, horizontal: -1)) == .pass, "a diagonal keeps both axes")
    }

    @Test func otherSendersPass() {
        var trackpad = pipeline(trackpadSender)
        #expect(trackpad.process(.scrollWheel, wheel(1)) == .pass)
        var unattributed = pipeline(nil)
        #expect(unattributed.process(.scrollWheel, wheel(1)) == .pass)
    }

    @Test func hyperpointsOwnScrollsPass() {
        var pipeline = pipeline(mxSender)
        #expect(pipeline.process(.scrollWheel, wheel(1, marked: true)) == .pass)
    }

    @Test func aScrollWithAModifierHeldPasses() {
        var pipeline = pipeline(mxSender)
        for flags in [CGEventFlags.maskShift, .maskCommand, .maskControl, .maskAlternate] {
            let event = wheel(1)
            event.flags = flags
            #expect(pipeline.process(.scrollWheel, event) == .pass, "\(flags.rawValue)")
        }
    }

    @Test func newRulesApplyFromTheNextTick() {
        var pipeline = pipeline(mxSender)
        var faster = rules
        faster.smoothScroll[mxSender]?.speed = 90
        pipeline.replaceRulesAndForgetHeldKeys(faster)
        guard case .scroll(let tick) = pipeline.process(.scrollWheel, wheel(1)) else {
            Issue.record("the tick is taken")
            return
        }
        #expect(tick.settings.speed == 90)
    }
}
