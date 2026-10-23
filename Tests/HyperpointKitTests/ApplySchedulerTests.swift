@testable import HyperpointKit
import Testing

@Suite struct ApplySchedulerTests {
    @Test func triggersDuringAnApplyCollapseIntoOneFollowUp() {
        var scheduler = ApplyScheduler()
        let first = scheduler.request(.connected)
        #expect(first, "the first trigger starts a worker")
        let job = scheduler.nextJob()
        #expect(job == .init(reasons: [.connected], attempt: 1))

        let duringApply = [scheduler.request(.configChanged), scheduler.request(.manual), scheduler.request(.configChanged)]
        #expect(duringApply == [false, false, false], "a running worker picks the triggers up")
        let delay = scheduler.finished(failed: false)
        #expect(delay == nil)

        let followUp = scheduler.nextJob()
        #expect(followUp == .init(reasons: [.configChanged, .manual], attempt: 1))
        _ = scheduler.finished(failed: false)
        let idle = scheduler.nextJob()
        #expect(idle == nil, "the worker exits when nothing is queued")
        let restart = scheduler.request(.manual)
        #expect(restart, "a trigger after that starts a new worker")
    }

    @Test func failuresBackOffThenStop() {
        var scheduler = ApplyScheduler()
        _ = scheduler.request(.connected)
        var delays: [Duration] = []
        var attempts: [Int] = []
        while let job = scheduler.nextJob() {
            attempts.append(job.attempt)
            if let delay = scheduler.finished(failed: true) {
                delays.append(delay)
                _ = scheduler.request(.retry)
            }
        }
        #expect(delays == [.milliseconds(300), .seconds(1), .seconds(2), .seconds(4), .seconds(8)])
        #expect(attempts == [1, 2, 3, 4, 5, 6])
    }

    @Test func aFreshTriggerRestartsTheAttemptCount() {
        var scheduler = ApplyScheduler()
        _ = scheduler.request(.connected)
        _ = scheduler.nextJob()
        _ = scheduler.finished(failed: true)
        _ = scheduler.request(.retry)
        let retry = scheduler.nextJob()
        #expect(retry?.attempt == 2)
        _ = scheduler.finished(failed: true)
        _ = scheduler.request(.manual)
        let fresh = scheduler.nextJob()
        #expect(fresh == .init(reasons: [.manual], attempt: 1))
        let delay = scheduler.finished(failed: true)
        #expect(delay == .milliseconds(300), "the backoff starts over too")
    }
}
