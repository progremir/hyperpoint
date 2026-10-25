@testable import HyperpointKit
import Testing

struct Bench {
    var link = HIDPPLink()
    var fake = FakeHIDPPDevice()
    var now = ContinuousClock.now
    var events: [HIDPPEvent] = []
    var delayReply: (([UInt8]) -> Bool)?
    private var inbox: [[UInt8]] = []
    private var late: [[UInt8]] = []

    mutating func request(_ reason: ApplyReason, _ plan: HIDPPSetup?) {
        absorb(link.request(reason, plan: plan, now: now))
    }

    mutating func deliver(_ report: [UInt8]) {
        absorb(report.withUnsafeBufferPointer { link.receive($0, now: now) })
    }

    mutating func turnWheel(_ rotation: Int16) {
        for report in fake.turned(rotation) { deliver(report) }
    }

    mutating func settle(until done: (Bench) -> Bool = { _ in false }) {
        for _ in 0..<10_000 {
            if done(self) { return }
            if !inbox.isEmpty {
                deliver(inbox.removeFirst())
            } else if let deadline = link.deadline {
                now = max(now, deadline)
                inbox = late + inbox
                late = []
                absorb(link.tick(now: now))
            } else {
                return
            }
        }
        Issue.record("the link never settled")
    }

    var outcomes: [HIDPPOutcome] {
        events.compactMap { if case .applyFinished(_, let outcome) = $0 { outcome } else { nil } }
    }

    var lastJob: ApplyScheduler.Job? {
        events.reversed().lazy.compactMap { if case .applyFinished(let job, _) = $0 { job } else { nil } }.first
    }

    var performed: [Action] { events.compactMap { if case .perform(let action) = $0 { action } else { nil } } }

    var scrolls: [HoldScrollEvent] { events.compactMap { if case .holdScroll(let event) = $0 { event } else { nil } } }

    var heard: [ListenPress] { events.compactMap { if case .heard(let press) = $0 { press } else { nil } } }

    mutating func clearEvents() { events = [] }

    private mutating func absorb(_ out: HIDPPOutput) {
        events += out.events
        for request in out.reports {
            guard let reply = fake.answer(request) else { continue }
            if let delay = delayReply, delay(request) {
                delayReply = nil
                late.append(reply)
            } else {
                inbox.append(reply)
            }
        }
    }
}

private let mx = discovered(thisMac[2])

private func plan(_ config: Config = .example) -> HIDPPSetup {
    Intent.compile(config, paused: false, tapAvailable: true, present: [mx]).setup(for: mx.id).hidpp!
}

private var scrollingTop: HIDPPSetup {
    var config = Config.example
    config.devices[0].rules?.append(Rule(control: .hidpp(topButton), trigger: .holdMove(nil), action: .scroll))
    return plan(config)
}

private func plan(fire: GestureFire) -> HIDPPSetup {
    var config = Config.example
    config.devices[0].gestures = GestureSettings(fire: fire, distance: 120)
    return plan(config)
}

private func listening(over setup: HIDPPSetup?) -> HIDPPSetup { .listening(over: setup, thumbWheel: true) }

private let setUp: [UInt16: UInt8] = [0xC3: 0x11, 0xC4: 0x01]
/// Every divertable MX control, diverted without raw movement.
private let listeningControls: [UInt16: UInt8] = [0x52: 0x01, 0x53: 0x01, 0x56: 0x01, 0xC3: 0x01, 0xC4: 0x01]
private let shot = Action.shortcut(Chord(key: KeyCode(name: "4")!, modifiers: [.shift, .command]))

private func connected(_ setup: HIDPPSetup? = plan()) -> Bench {
    var bench = Bench()
    bench.request(.connected, setup)
    bench.settle()
    bench.clearEvents()
    return bench
}

@Suite struct HIDPPLinkTests {
    @Test func connectConvergesFromTheBetterMouseState() {
        var bench = Bench()
        bench.request(.connected, plan())
        bench.settle()
        #expect(bench.fake.diverted == setUp)
        #expect(!bench.fake.wheelDiverted && bench.fake.wheelInverted)
        #expect(bench.events.contains(.discovered(measuredMXCapabilities)))
        #expect(bench.outcomes == [.applied])
        #expect(!bench.link.isApplying && bench.link.deadline == nil)
    }

    @Test func aLaterApplyDoesNotDiscoverAgain() {
        var bench = connected()
        bench.fake.forget()
        bench.request(.manual, plan())
        bench.settle()
        #expect(bench.fake.diverted == setUp)
        #expect(!bench.events.contains { if case .discovered = $0 { true } else { false } })
    }

    @Test(arguments: [0, 2])
    func nothingToWriteReadsTheControlsAndLeavesTheFirmware(dropped: Int) {
        var bench = Bench()
        bench.fake.unanswered = dropped
        bench.request(.connected, nil)
        bench.settle()
        #expect(bench.link.capabilities == measuredMXCapabilities)
        #expect(bench.events.contains(.discovered(measuredMXCapabilities)))
        #expect(bench.outcomes.last == .applied)
        #expect(bench.fake.writes == 0)
        #expect(bench.fake.diverted == [0xC3: 0x01, 0xC4: 0x01], "BetterMouse's diverts stay")
        #expect(bench.fake.wheelDiverted && !bench.fake.wheelInverted)
    }

    @Test func aLinkWithNothingToWriteIsQuietOnceItKnowsTheControls() {
        var bench = connected(nil)
        bench.deliver(bench.fake.askedToReconfigure())
        bench.request(.manual, nil)
        bench.settle()
        bench.deliver(bench.fake.held(0xC3))
        bench.deliver(bench.fake.held())
        #expect(bench.events.isEmpty, "no apply runs and a still-diverted press performs nothing")
        #expect(bench.fake.writes == 0)
        #expect(!bench.link.isApplying && bench.link.deadline == nil)
    }

    @Test func aRuleAddedAfterReadingWritesWithoutReadingAgain() {
        var bench = connected(nil)
        bench.request(.configChanged, plan())
        bench.settle()
        #expect(bench.fake.diverted == setUp)
        #expect(!bench.fake.wheelDiverted && bench.fake.wheelInverted)
        #expect(bench.outcomes == [.applied])
        #expect(!bench.events.contains { if case .discovered = $0 { true } else { false } })
    }

    @Test func droppedFirstRequestsAreAskedAgain() {
        var bench = Bench()
        bench.fake.unanswered = 2
        bench.request(.connected, plan())
        bench.settle()
        #expect(bench.fake.diverted == setUp)
        #expect(bench.outcomes == [.applied])
    }

    @Test func aSlowFirstReplyStillConverges() {
        var bench = Bench()
        bench.delayReply = { _ in true }
        bench.request(.connected, plan())
        bench.settle()
        #expect(bench.fake.diverted == setUp)
        #expect(!bench.fake.wheelDiverted && bench.fake.wheelInverted)
        #expect(bench.outcomes.last == .applied)
        #expect(bench.link.capabilities == measuredMXCapabilities, "a crossed reply never becomes a capability")
    }

    @Test func aLateReadBackIsNotTakenForTheNextControl() {
        var bench = Bench()
        bench.delayReply = { $0[2] == 0x08 && $0[3] >> 4 == 2 && $0[5] == 0xC3 }
        bench.request(.connected, plan())
        bench.settle()
        #expect(bench.outcomes == [.applied], "0xC3's late read-back does not fail 0xC4's")
        #expect(bench.fake.diverted == setUp)
    }

    @Test func aSilentDeviceFailsThenStopsRetrying() {
        var bench = Bench()
        bench.fake.unanswered = .max
        bench.request(.connected, plan())
        bench.settle()
        #expect(bench.outcomes.count == RetryPolicy.delays.count + 1, "one run, then one per backoff delay")
        #expect(bench.outcomes.allSatisfy { if case .failed(.timedOut) = $0 { true } else { false } })
        #expect(bench.fake.diverted == [0xC3: 0x01, 0xC4: 0x01], "nothing was written")
        #expect(bench.link.deadline == nil)
    }

    @Test func aReconfigureRequestMidApplyConverges() {
        var bench = Bench()
        bench.request(.connected, plan())
        bench.settle { $0.fake.writes == 2 }
        bench.fake.forget()
        bench.deliver(bench.fake.askedToReconfigure())
        bench.settle()
        #expect(bench.fake.diverted == setUp)
        #expect(!bench.fake.wheelDiverted && bench.fake.wheelInverted)
        #expect(bench.outcomes.last == .applied)
        #expect(bench.lastJob?.reasons.contains(.deviceAsked) == true)
    }

    @Test func aReconfigureRequestAfterSleepReapplies() {
        var bench = connected()
        bench.fake.forget()
        bench.deliver(bench.fake.askedToReconfigure())
        bench.settle()
        #expect(bench.fake.diverted == setUp)
        #expect(bench.lastJob?.reasons == [.deviceAsked])
    }

    @Test func aStatusWithoutTheReconfigureFlagIsIgnored() {
        var bench = connected()
        bench.fake.forget()
        bench.deliver(bench.fake.notification(0x1D4B, event: 0, [0x01, 0x00, 0x00]))
        bench.settle()
        #expect(bench.outcomes.isEmpty)
    }

    @Test func aPlanChangeMidApplyQueuesOneRerun() {
        var config = Config.example
        config.devices[0].rules = config.devices[0].rules?.filter { $0.control != .hidpp(topButton) && $0.control != .thumbWheel }
        var bench = Bench()
        bench.request(.connected, plan())
        bench.settle { $0.fake.writes == 2 }
        bench.request(.configChanged, plan(config))
        bench.request(.manual, plan(config))
        bench.settle()
        #expect(bench.fake.diverted == [0xC3: 0x11])
        #expect(!bench.fake.wheelInverted)
        #expect(bench.outcomes == [.applied, .applied], "the triggers collapse into one rerun")
        #expect(bench.lastJob?.reasons == [.configChanged, .manual])
    }

    @Test(arguments: [false, true])
    func pauseReturnsEveryControlToNative(whileListening: Bool) {
        var bench = connected(whileListening ? listening(over: plan()) : plan())
        bench.request(.pauseChanged, .native)
        bench.settle()
        #expect(bench.fake.diverted == [:])
        #expect(!bench.fake.wheelDiverted && !bench.fake.wheelInverted)
        #expect(bench.outcomes == [.applied])
    }

    @Test func anotherAppWritingTheSameControlIsAMismatch() {
        var bench = Bench()
        bench.request(.connected, plan())
        bench.settle { $0.fake.writes == 6 }
        bench.fake.reporting[0xC3] = 0x01
        bench.settle { $0.outcomes.count == 1 }
        guard case .failed(.mismatch(.checkReporting(gestureButton, _))) = bench.outcomes.first else {
            Issue.record("a read-back mismatch on 0xC3, got \(bench.outcomes)")
            return
        }
        bench.settle()
        #expect(bench.fake.diverted == setUp, "the retry puts it back")
    }

    @Test func aGestureButtonClickPerformsMissionControl() {
        var bench = connected()
        bench.deliver(bench.fake.held(0xC3))
        #expect(bench.performed.isEmpty, "the press waits for the gesture")
        bench.deliver(bench.fake.held())
        #expect(bench.performed == [.system(.missionControl)])
    }

    @Test(arguments: [GestureFire.pastDistance, .onRelease])
    func holdMoveDownPerformsAppExpose(_ fire: GestureFire) {
        var bench = connected(plan(fire: fire))
        bench.deliver(bench.fake.held(0xC3))
        bench.deliver(bench.fake.rawXY(dx: 4, dy: 70))
        bench.deliver(bench.fake.rawXY(dx: -2, dy: 70))
        #expect(bench.performed == (fire == .pastDistance ? [.system(.appExpose)] : []))
        bench.deliver(bench.fake.held())
        #expect(bench.performed == [.system(.appExpose)], "exactly once, and the release is not a click")
    }

    @Test func theTopButtonFiresOnPress() {
        var bench = connected()
        bench.deliver(bench.fake.held(0xC4))
        #expect(bench.performed == [shot])
        bench.deliver(bench.fake.held())
        #expect(bench.performed.count == 1)
    }

    @Test func aScrollRuleDivertsTheTopButtonWithRawMovement() {
        let bench = connected(scrollingTop)
        #expect(bench.fake.diverted == [0xC3: 0x11, 0xC4: 0x11])
    }

    @Test func aQuickPressOfAScrollingButtonIsItsClickOnRelease() {
        var bench = connected(scrollingTop)
        bench.deliver(bench.fake.held(0xC4))
        bench.deliver(bench.fake.rawXY(dx: 30, dy: -40))
        #expect(bench.performed.isEmpty, "the press waits to see whether the hand scrolls")
        bench.deliver(bench.fake.held())
        #expect(bench.performed == [shot])
        #expect(bench.scrolls.isEmpty)
    }

    @Test func holdingAndMovingTheTopButtonScrolls() {
        var bench = connected(scrollingTop)
        let k = HoldScrollPlan.pointsPerCount
        bench.deliver(bench.fake.held(0xC4))
        bench.deliver(bench.fake.rawXY(dx: 0, dy: 80))
        bench.deliver(bench.fake.rawXY(dx: 5, dy: 60))
        bench.deliver(bench.fake.rawXY(dx: -3, dy: 20))
        bench.deliver(bench.fake.held())
        #expect(
            bench.scrolls == [
                .began(HoldScrollPlan(.default, glide: .default, pointsPerUnit: k)),
                .moved(dx: -3 * k, dy: 20 * k), .ended,
            ], "past 120 counts the page follows the hand")
        #expect(bench.performed.isEmpty, "a scroll is not a click")
    }

    @Test func aScrollEndsWhenAnApplyOrCloseInterruptsIt() {
        var applied = connected(scrollingTop)
        applied.deliver(applied.fake.held(0xC4))
        applied.deliver(applied.fake.rawXY(dx: 200, dy: 0))
        applied.request(.manual, scrollingTop)
        #expect(applied.scrolls.last == .ended, "an apply mid-scroll ends it")

        var closed = connected(scrollingTop)
        closed.deliver(closed.fake.held(0xC4))
        closed.deliver(closed.fake.rawXY(dx: 200, dy: 0))
        #expect(closed.link.close().events == [.holdScroll(.ended)], "a device going away ends it")
        var idle = connected(scrollingTop)
        #expect(idle.link.close().events.isEmpty, "closing an idle link ends nothing")
    }

    @Test func anApplyCancelsAGestureInFlight() {
        var bench = connected()
        bench.deliver(bench.fake.held(0xC3))
        bench.request(.manual, plan())
        bench.settle()
        bench.deliver(bench.fake.held())
        #expect(bench.performed.isEmpty)
    }

    @Test func aListeningPlanDivertsEveryControlWithoutRawMovement() {
        var bench = connected()
        bench.request(.manual, listening(over: plan()))
        bench.settle()
        #expect(bench.fake.diverted == listeningControls)
        #expect(bench.fake.wheelDiverted, "a turn is reported instead of scrolling")
        #expect(bench.fake.wheelInverted, "the wheel keeps the profile's direction")
        #expect(bench.outcomes == [.applied])
    }

    @Test func aListenedPressIsHeardAndDoesNothingElse() {
        var bench = connected(listening(over: plan()))
        bench.deliver(bench.fake.held(0xC3))
        bench.deliver(bench.fake.rawXY(dx: 0, dy: 300))
        bench.deliver(bench.fake.held())
        bench.deliver(bench.fake.held(0xC4))
        bench.deliver(bench.fake.held())
        #expect(
            bench.events == [.heard(.hidpp(gestureButton)), .heard(.hidpp(topButton))], "no gesture, click or shortcut")
    }

    @Test func aListenedTurnIsHeardOnce() {
        var bench = connected(listening(over: plan()))
        bench.turnWheel(3)
        #expect(bench.events == [.heard(.thumbWheel)], "the stop after it is not a second turn")
    }

    @Test func aTurnRightAfterTheListenIsNotHeard() {
        var bench = connected(listening(over: plan()))
        bench.request(.manual, plan())
        bench.clearEvents()
        bench.turnWheel(3)
        #expect(bench.fake.wheelDiverted, "the write that gives the wheel back has not landed")
        #expect(bench.events.isEmpty)
    }

    @Test func aWheelThatLostItsDivertIsAMismatch() {
        var bench = Bench()
        bench.request(.connected, listening(over: plan()))
        bench.settle { $0.fake.writes == 6 }
        bench.fake.wheelDiverted = false
        bench.settle { $0.outcomes.count == 1 }
        #expect(
            bench.outcomes.first
                == .failed(.mismatch(.checkThumbWheel(ThumbWheelReporting(diverted: true, inverted: true)))))
    }

    @Test func theRealPlanComesBackAfterAListen() {
        var bench = connected(listening(over: plan()))
        bench.request(.manual, plan())
        bench.settle()
        #expect(bench.fake.diverted == setUp)
        #expect(!bench.fake.wheelDiverted && bench.fake.wheelInverted)
    }

    @Test func aMouseWithoutHIDPPRulesIsNativeAfterAListen() {
        var bench = connected(nil)
        bench.request(.manual, listening(over: nil))
        bench.settle()
        #expect(bench.fake.diverted == listeningControls, "BetterMouse's diverts are replaced too")
        bench.request(.manual, .native)
        bench.settle()
        #expect(bench.fake.diverted == [:])
        #expect(!bench.fake.wheelDiverted && !bench.fake.wheelInverted)
    }

    @Test func aPressRightAfterTheListenFollowsTheRules() {
        var bench = connected(listening(over: plan()))
        bench.request(.manual, plan())
        bench.deliver(bench.fake.held(0xC3))
        bench.deliver(bench.fake.held())
        #expect(bench.heard.isEmpty)
        #expect(bench.performed == [.system(.missionControl)], "before the writes land")
    }

    @Test func aListenLeavesTheLeftButtonAloneOnAMouseThatCanDivertIt() {
        var bench = Bench()
        bench.fake.controls[0].flags = 0x31
        bench.request(.connected, listening(over: nil))
        bench.settle()
        #expect(bench.link.capabilities?.control(HIDPPSetup.leftButton)?.divertable == true)
        #expect(bench.fake.diverted[0x50] == nil)
        bench.clearEvents()
        bench.deliver(bench.fake.held(0x50))
        bench.deliver(bench.fake.held())
        #expect(bench.events.isEmpty)
    }

    @Test func pressesFollowTheNewestPlan() {
        var bench = connected()
        bench.request(.pauseChanged, .native)
        bench.deliver(bench.fake.held(0xC4))
        bench.deliver(bench.fake.held())
        #expect(bench.performed.isEmpty, "a paused device fires nothing even before the writes land")
    }
}
