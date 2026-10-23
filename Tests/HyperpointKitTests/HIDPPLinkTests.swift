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

    mutating func request(_ reason: ApplyReason, _ plan: HIDPPSetup) {
        absorb(link.request(reason, plan: plan, now: now))
    }

    mutating func deliver(_ report: [UInt8]) {
        absorb(report.withUnsafeBufferPointer { link.receive($0, now: now) })
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

private func plan(_ config: Config = .default) -> HIDPPSetup {
    Intent.compile(config, paused: false, tapAvailable: true, present: [mx]).setup(for: mx.id).hidpp!
}

private func plan(fire: GestureFire) -> HIDPPSetup {
    var config = Config.default
    config.devices[0].gestures = GestureSettings(fire: fire, distance: 120)
    return plan(config)
}

private let setUp: [UInt16: UInt8] = [0xC3: 0x11, 0xC4: 0x01]

private func connected(_ setup: HIDPPSetup = plan()) -> Bench {
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
        var config = Config.default
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

    @Test func pauseReturnsEveryControlToNative() {
        var bench = connected()
        bench.request(.pauseChanged, .native)
        bench.settle()
        #expect(bench.fake.diverted == [:])
        #expect(!bench.fake.wheelDiverted && !bench.fake.wheelInverted)
        #expect(bench.outcomes == [.applied])
    }

    @Test func anotherAppWritingTheSameControlIsAMismatch() {
        var bench = Bench()
        bench.request(.connected, plan())
        bench.settle { $0.fake.writes == 7 }
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
        #expect(bench.performed == [.shortcut(Chord(key: KeyCode(name: "4")!, modifiers: [.shift, .command]))])
        bench.deliver(bench.fake.held())
        #expect(bench.performed.count == 1)
    }

    @Test func anApplyCancelsAGestureInFlight() {
        var bench = connected()
        bench.deliver(bench.fake.held(0xC3))
        bench.request(.manual, plan())
        bench.settle()
        bench.deliver(bench.fake.held())
        #expect(bench.performed.isEmpty)
    }

    @Test func pressesFollowTheNewestPlan() {
        var bench = connected()
        bench.request(.pauseChanged, .native)
        bench.deliver(bench.fake.held(0xC4))
        bench.deliver(bench.fake.held())
        #expect(bench.performed.isEmpty, "a paused device fires nothing even before the writes land")
    }
}
