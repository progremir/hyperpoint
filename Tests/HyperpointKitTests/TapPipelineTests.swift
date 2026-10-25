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
        rules: Intent.compile(.example, paused: false, tapAvailable: true, present: thisMac).tap, origin: { _ in nil })

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
        pipeline.replaceRulesAndForgetHeldKeys(Intent.compile(.example, paused: false, tapAvailable: true, present: thisMac).tap)
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

    @Test func theMouseReturnCarrierSendsItsShortcutOncePerPress() {
        let f13: CGKeyCode = 105
        let mouse = present(6, Bags.mouse24GKeys)
        var pipeline = TapPipeline(
            rules: Intent.compile(.example, paused: false, tapAvailable: true, present: [mouse]).tap, origin: { _ in nil })
        let optShiftS = Action.shortcut(Chord(key: KeyCode(name: "s")!, modifiers: [.option, .shift]))
        #expect(pipeline.process(.keyDown, key(f13, down: true)) == .perform(optShiftS))
        let repeated = key(f13, down: true)
        repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(pipeline.process(.keyDown, repeated) == .drop, "holding Return does not repeat the shortcut")
        #expect(pipeline.process(.keyUp, key(f13, down: false)) == .drop)
        #expect(pipeline.process(.keyDown, key(f13, down: true)) == .perform(optShiftS), "the next press sends it again")

        let rDown = key(r, down: true)
        #expect(pipeline.process(.keyDown, rDown) == .pass)
        #expect(rDown.flags.isDisjoint(with: hyperFlags), "a click carrier holds no modifiers")
    }

    @Test func theTapListensForKeysAndScrolls() {
        for type in [CGEventType.keyDown, .keyUp, .scrollWheel] {
            #expect(TapPipeline.mask & (1 << CGEventMask(type.rawValue)) != 0, "\(type.rawValue)")
        }
    }
}

private let mxSender = SenderID(rawValue: 0x1_0003_7032)
private let trackpadSender = SenderID(rawValue: 0x1_0000_0D10)
private let smooth = Config.example.devices[0].scrolling!.smooth!

private func wheel(_ lines: Int32, horizontal: Int32 = 0, marked: Bool = false) -> CGEvent {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: lines, wheel2: horizontal, wheel3: 0)!
    if marked { event.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker) }
    return event
}

@Suite struct ScrollStageTests {
    let rules = Intent.compile(
        .example, paused: false, tapAvailable: true,
        present: [present(3, Bags.mxMaster3, services: [mxSender.rawValue])]
    ).tap

    func pipeline(_ sender: SenderID?, detents: Double = 1) -> TapPipeline {
        TapPipeline(rules: rules, origin: { _ in sender.map { HIDOrigin(sender: $0, wheelDetents: detents) } })
    }

    @Test func aWheelStepFromASmoothSenderIsTakenForTheAnimator() {
        var pipeline = pipeline(mxSender)
        #expect(pipeline.process(.scrollWheel, wheel(1)) == .scroll(ScrollTick(sign: .positive, steps: 1, settings: smooth)))
        #expect(
            pipeline.process(.scrollWheel, wheel(-3)) == .scroll(ScrollTick(sign: .negative, steps: 1, settings: smooth)),
            "macOS's accelerated line delta is not the step count")
    }

    @Test func theStepsAreTheWheelsDetents() {
        var flick = pipeline(mxSender, detents: -3)
        #expect(flick.process(.scrollWheel, wheel(-13)) == .scroll(ScrollTick(sign: .negative, steps: 3, settings: smooth)))
        var unknown = pipeline(mxSender, detents: 0)
        #expect(unknown.process(.scrollWheel, wheel(2)) == .scroll(ScrollTick(sign: .positive, steps: 1, settings: smooth)))
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

    @Test func newRulesApplyFromTheNextStep() {
        var pipeline = pipeline(mxSender)
        var faster = rules
        faster.smoothScroll[mxSender]?.duration = 9
        pipeline.replaceRulesAndForgetHeldKeys(faster)
        guard case .scroll(let tick) = pipeline.process(.scrollWheel, wheel(1)) else {
            Issue.record("the tick is taken")
            return
        }
        #expect(tick.settings.duration == 9)
    }
}

private let shotAction = Action.shortcut(Chord(key: KeyCode(name: "4")!, modifiers: [.shift, .command]))

private func mouse(
    _ type: CGEventType, button: Int, dx: Double = 0, dy: Double = 0, at location: CGPoint = CGPoint(x: 400, y: 300),
    marked: Bool = false
) -> CGEvent {
    let event = CGEvent(
        mouseEventSource: nil, mouseType: type, mouseCursorPosition: location,
        mouseButton: CGMouseButton(rawValue: UInt32(button))!)!
    event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
    event.setDoubleValueField(.mouseEventDeltaX, value: dx)
    event.setDoubleValueField(.mouseEventDeltaY, value: dy)
    if marked { event.setIntegerValueField(.eventSourceUserData, value: TapPipeline.syntheticMarker) }
    return event
}

private func isMarked(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == TapPipeline.syntheticMarker
}

@Suite struct ButtonStageTests {
    let rightScroll = HoldScrollPlan(.default, glide: .default, pointsPerUnit: 1)
    var rules: TapRules {
        var config = Config.example
        config.devices[0].rules = [
            Rule(control: .button(1), trigger: .holdMove(nil), action: .scroll),
            Rule(control: .button(3), trigger: .click, action: .system(.spaceLeft)),
            Rule(control: .button(3), trigger: .holdMove(nil), action: .scroll),
            Rule(control: .button(4), trigger: .click, action: shotAction),
        ]
        return Intent.compile(
            config, paused: false, tapAvailable: true, present: [present(3, Bags.mxMaster3, services: [mxSender.rawValue])]
        ).tap
    }
    var distance: Double { 120 * HoldScrollPlan.pointsPerCount }

    func pipeline(_ sender: SenderID? = mxSender) -> TapPipeline {
        TapPipeline(rules: rules, origin: { _ in sender.map { HIDOrigin(sender: $0, wheelDetents: 0) } })
    }

    @Test func aShortRightPressReplaysTheClickMarked() throws {
        var pipeline = pipeline()
        #expect(pipeline.process(.rightMouseDown, mouse(.rightMouseDown, button: 1)) == .drop, "the press waits")
        #expect(pipeline.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dx: 3, dy: -2)) == .drop)
        guard case .replay(let press, let release) = pipeline.process(.rightMouseUp, mouse(.rightMouseUp, button: 1)) else {
            Issue.record("the click is replayed")
            return
        }
        #expect(press.type == .rightMouseDown && release.type == .rightMouseUp)
        #expect(press.getIntegerValueField(.mouseEventButtonNumber) == 1)
        #expect(isMarked(press) && isMarked(release))
        #expect(pipeline.process(press.type, press) == .pass, "the replay passes the tap untouched")
        #expect(pipeline.process(release.type, release) == .pass)
    }

    @Test func aScrollingButtonHoldsThePointerFromItsPress() {
        var pipeline = pipeline()
        #expect(!pipeline.holdsPointer)
        _ = pipeline.process(.rightMouseDown, mouse(.rightMouseDown, button: 1))
        #expect(pipeline.holdsPointer, "frozen at the press, before any movement")
        _ = pipeline.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dy: distance - 1))
        #expect(pipeline.holdsPointer, "still frozen below the distance")
        _ = pipeline.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dy: 2))
        #expect(pipeline.holdsPointer, "and while it scrolls")
        _ = pipeline.process(.rightMouseUp, mouse(.rightMouseUp, button: 1))
        #expect(!pipeline.holdsPointer, "free from the release")

        _ = pipeline.process(.otherMouseDown, mouse(.otherMouseDown, button: 4))
        #expect(!pipeline.holdsPointer, "a click-only button leaves the pointer free")
    }

    @Test func aShortPressReplaysAtThePressLocation() {
        var pipeline = pipeline()
        let pressed = CGPoint(x: 120, y: 80)
        _ = pipeline.process(.rightMouseDown, mouse(.rightMouseDown, button: 1, at: pressed))
        _ = pipeline.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dx: 5, dy: 5, at: pressed))
        let up = mouse(.rightMouseUp, button: 1, at: CGPoint(x: 125, y: 85))
        guard case .replay(let press, let release) = pipeline.process(.rightMouseUp, up) else {
            Issue.record("the click is replayed")
            return
        }
        #expect(press.location == pressed && release.location == pressed)
        #expect(!pipeline.holdsPointer, "the pointer is free before the replay reaches apps")
    }

    @Test func aDragPastTheDistanceScrollsAndAppsSeeNoDrag() {
        var pipeline = pipeline()
        _ = pipeline.process(.rightMouseDown, mouse(.rightMouseDown, button: 1))
        #expect(pipeline.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dy: distance - 1)) == .drop)
        #expect(
            pipeline.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dx: 1, dy: 2))
                == .holdScroll(.began(rightScroll)))
        #expect(
            pipeline.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dx: -4, dy: 7))
                == .holdScroll(.moved(dx: -4, dy: 7)), "at speed 1 the page moves as far as the pointer would")
        #expect(pipeline.process(.rightMouseUp, mouse(.rightMouseUp, button: 1)) == .holdScroll(.ended))
        #expect(pipeline.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dy: 5)) == .pass, "released")
    }

    @Test func aShortPressOfAButtonWithAClickRulePerformsIt() {
        var pipeline = pipeline()
        #expect(pipeline.process(.otherMouseDown, mouse(.otherMouseDown, button: 3)) == .drop)
        #expect(pipeline.process(.otherMouseUp, mouse(.otherMouseUp, button: 3)) == .perform(.system(.spaceLeft)))
    }

    @Test func aClickOnlyButtonActsOnPressAndHidesTheRest() {
        var pipeline = pipeline()
        #expect(pipeline.process(.otherMouseDown, mouse(.otherMouseDown, button: 4)) == .perform(shotAction))
        #expect(pipeline.process(.otherMouseDragged, mouse(.otherMouseDragged, button: 4, dx: 500)) == .drop)
        #expect(pipeline.process(.otherMouseUp, mouse(.otherMouseUp, button: 4)) == .drop)
    }

    @Test func otherSendersButtonsAndMarkedEventsPass() {
        var trackpad = pipeline(trackpadSender)
        #expect(trackpad.process(.rightMouseDown, mouse(.rightMouseDown, button: 1)) == .pass)
        var unattributed = pipeline(nil)
        #expect(unattributed.process(.rightMouseDown, mouse(.rightMouseDown, button: 1)) == .pass)
        var mx = pipeline()
        #expect(mx.process(.otherMouseDown, mouse(.otherMouseDown, button: 2)) == .pass, "the middle button has no rule")
        #expect(mx.process(.otherMouseUp, mouse(.otherMouseUp, button: 2)) == .pass)
        #expect(mx.process(.rightMouseDown, mouse(.rightMouseDown, button: 1, marked: true)) == .pass)
        #expect(mx.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dy: 500)) == .pass, "nothing is held")
    }

    @Test func aSecondButtonWhileOneIsHeldPasses() {
        var pipeline = pipeline()
        _ = pipeline.process(.rightMouseDown, mouse(.rightMouseDown, button: 1))
        #expect(pipeline.process(.otherMouseDown, mouse(.otherMouseDown, button: 3)) == .pass)
        #expect(pipeline.process(.otherMouseUp, mouse(.otherMouseUp, button: 3)) == .pass)
        guard case .replay = pipeline.process(.rightMouseUp, mouse(.rightMouseUp, button: 1)) else {
            Issue.record("the held button still clicks")
            return
        }
    }

    @Test func resetHandsAHeldPressToAppsAndEndsAScroll() throws {
        var held = pipeline()
        _ = held.process(.rightMouseDown, mouse(.rightMouseDown, button: 1))
        let release = held.reset()
        #expect(!held.holdsPointer, "a reset frees the pointer held since the press")
        let press = try #require(release.press, "the held press goes to apps")
        #expect(press.type == .rightMouseDown && isMarked(press) && !release.endsScroll)
        #expect(held.process(.rightMouseUp, mouse(.rightMouseUp, button: 1)) == .pass, "so its release passes too")

        var scrolling = pipeline()
        _ = scrolling.process(.rightMouseDown, mouse(.rightMouseDown, button: 1))
        _ = scrolling.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dx: distance))
        #expect(scrolling.reset() == ButtonStage.Release(press: nil, endsScroll: true), "the host frees the pointer")
        #expect(!scrolling.holdsPointer)
        #expect(scrolling.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dy: 9)) == .pass)

        var idle = pipeline()
        #expect(idle.reset() == ButtonStage.Release(press: nil, endsScroll: false))
    }

    @Test func aLostReleaseEndsTheScrollOnTheNextPress() {
        var pipeline = pipeline()
        _ = pipeline.process(.rightMouseDown, mouse(.rightMouseDown, button: 1))
        _ = pipeline.process(.rightMouseDragged, mouse(.rightMouseDragged, button: 1, dx: distance))
        #expect(pipeline.process(.rightMouseDown, mouse(.rightMouseDown, button: 1)) == .holdScroll(.ended))
    }

    @Test func theTapListensForRightAndOtherButtons() {
        for type in ButtonStage.interests {
            #expect(TapPipeline.mask & (1 << CGEventMask(type.rawValue)) != 0, "\(type.rawValue)")
        }
        #expect(TapPipeline.mask & (1 << CGEventMask(CGEventType.leftMouseDown.rawValue)) == 0, "the left button is left alone")
    }
}
