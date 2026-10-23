import CoreGraphics
@testable import HyperpointKit
import Testing

private let smooth = SmoothScroll.default

private struct Step {
    var time: Double
    var sign = ScrollTick.Sign.positive
    var detents = 1
}

private struct Run {
    var frames: [(time: Double, frame: ScrollFrame)]
    var idleAtEnd: Bool

    var distance: Double { frames.reduce(0) { $0 + $1.frame.points } }
    func distance(from start: Double, to stop: Double) -> Double {
        frames.filter { $0.time >= start && $0.time < stop }.reduce(0) { $0 + $1.frame.points }
    }
    var moving: [(time: Double, frame: ScrollFrame)] { frames.filter { $0.frame.phase != .ended } }
}

/// Drives the animator with a fake display clock. Steps land between frames.
private func run(_ steps: [Step], _ settings: SmoothScroll = smooth, seconds: Double = 3, hertz: Double = 120) -> Run {
    var animator = ScrollAnimator()
    var pending = steps[...]
    var frames: [(Double, ScrollFrame)] = []
    for index in 0...Int(seconds * hertz) {
        let now = Double(index) / hertz
        while let next = pending.first, next.time <= now {
            animator.tick(ScrollTick(sign: next.sign, steps: next.detents, settings: settings), at: next.time)
            pending.removeFirst()
        }
        if let frame = animator.frame(at: now) { frames.append((now, frame)) }
    }
    return Run(frames: frames, idleAtEnd: animator.isIdle)
}

private func spin(_ count: Int, perSecond rate: Double, from start: Double = 0.0005, detents: Int = 1) -> [Step] {
    (0..<count).map { Step(time: start + Double($0) / rate, detents: detents) }
}

private func with(_ change: (inout SmoothScroll) -> Void) -> SmoothScroll {
    var settings = smooth
    change(&settings)
    return settings
}

private func speedInSteadySpin(_ rate: Double, _ settings: SmoothScroll = smooth, detents: Int = 1) -> Double {
    let events = rate / Double(detents)
    let stream = run(spin(Int(6 * events), perSecond: events, detents: detents), settings, seconds: 7)
    return stream.distance(from: 2, to: 5) / 3
}

@Suite struct ScrollAnimatorTests {
    @Test func aSingleStepGoesTheCurvesDistanceAtTheSlowestRate() {
        let single = run(spin(1, perSecond: 1))
        let curve = smooth.curve
        #expect(abs(single.distance - curve.pointsPerSecond(at: curve.slowest) / curve.slowest) < 1e-9)
        #expect(single.frames.first?.frame.phase == .began)
        #expect(single.frames.last?.frame == ScrollFrame(points: 0, phase: .ended))
        #expect(single.moving.dropFirst().allSatisfy { $0.frame.phase == .changed && $0.frame.points > 0 })
        #expect(single.idleAtEnd)
    }

    @Test func aStepFromRestStartsNearStillAndNeverJumps() {
        let single = run(spin(1, perSecond: 1))
        let speeds = single.moving.map(\.frame.points)
        let peak = speeds.max()!
        #expect(speeds[0] < 0.05 * peak, "the first frame barely moves")
        #expect(zip(speeds, speeds.dropFirst()).allSatisfy { abs($1 - $0) < 0.3 * peak }, "speed changes by small steps")

        let abrupt = run(spin(1, perSecond: 1), with { $0.easeIn = 0 }).moving.map(\.frame.points)
        #expect(abrupt[0] > 0.9 * abrupt.max()!, "without the ease-in the first frame moves at full speed")
    }

    @Test(arguments: [4.0, 10, 16, 36])
    func aSteadySpinScrollsAtTheCurvesSpeed(_ rate: Double) {
        for settings in [smooth, with { $0.brake = 1 }, with { $0.duration = 10; $0.easeIn = 300 }] {
            let speed = speedInSteadySpin(rate, settings)
            let expected = settings.curve.pointsPerSecond(at: rate)
            #expect(abs(speed / expected - 1) < 0.03, "\(rate) steps/s scroll \(speed) pt/s, not \(expected)")
        }
    }

    @Test func aFlickCountsEveryDetentInAnEvent() {
        #expect(abs(speedInSteadySpin(40, detents: 2) / speedInSteadySpin(40) - 1) < 0.03)
        let curve = smooth.curve
        let three = run([Step(time: 0.0005, detents: 3)])
        #expect(abs(three.distance - 3 * curve.distancePerStep(at: curve.slowest)) < 1e-9)
    }

    @Test func framesCarryTheFractionAndAddUpToTheDistance() throws {
        let sixtyPerStep = try SpeedCurve([
            .init(stepsPerSecond: 1, pointsPerSecond: 60), .init(stepsPerSecond: 150, pointsPerSecond: 9000),
        ])
        let stream = run(spin(8, perSecond: 15), with { $0.curve = sixtyPerStep })
        #expect(stream.moving.contains { $0.frame.points != $0.frame.points.rounded() }, "frames are not whole points")
        #expect(abs(stream.distance - 8 * 60) < 1e-9)
    }

    @Test(arguments: [60.0, 120])
    func theGlideEndsAtAnEvenCadenceInsteadOfTrickling(_ hertz: Double) {
        let cases = [(spin(1, perSecond: 1), smooth), (spin(12, perSecond: 30), with { $0.brake = 1 }), (spin(1, perSecond: 1), with { $0.brake = 6 })]
        for (steps, settings) in cases {
            let glide = run(steps, settings, hertz: hertz)
            var whole = WholePoints()
            let posted = glide.frames.map { whole.take($0.frame) }
            let moving = posted.drop { $0 == 0 }.dropLast()
            #expect(!moving.isEmpty)
            let gaps = zip(moving, moving.dropFirst()).filter { $0 == 0 && $1 == 0 }
            #expect(gaps.isEmpty, "\(hertz) Hz: whole points \(posted)")
            let tail = glide.moving.suffix(4).dropLast().map(\.frame.points)
            #expect(tail.allSatisfy { $0 >= ScrollAnimator.stoppingSpeed / hertz - 1e-9 }, "the last frames keep the stopping speed")
            #expect(glide.frames.last?.frame.phase == .ended)
        }
    }

    @Test func theGlideStopsWithinTheEaseInAndDurationAfterTheLastStep() {
        for duration in [4.0, 8.0] {
            let settings = with { $0.duration = duration }
            let steps = spin(10, perSecond: 30)
            let last = steps.last!.time
            let glide = run(steps, settings)
            let length = settings.easeIn / 1000 + duration / 10
            #expect(glide.moving.last!.time <= last + length + 1.0 / 120)
            #expect(glide.moving.last!.time > last + length / 2, "it glides on after the last step")
            #expect(glide.idleAtEnd)
        }
    }

    @Test func brakeFrontLoadsTheStop() {
        func shareOfFirstTenth(_ brake: Double) -> Double {
            let glide = run(spin(1, perSecond: 1), with { $0.brake = brake })
            return glide.distance(from: 0, to: 0.1) / glide.distance
        }
        #expect(shareOfFirstTenth(1) < shareOfFirstTenth(2))
        #expect(shareOfFirstTenth(2) < shareOfFirstTenth(4))
    }

    @Test func aStepTheOtherWayEndsTheGlideAtOnce() throws {
        let up = spin(10, perSecond: 30)
        let reversal = up.last!.time + 0.05
        let glide = run(up + [Step(time: reversal, sign: .negative)])

        let after = glide.frames.filter { $0.time >= reversal }
        let first = try #require(after.first)
        #expect(first.frame == ScrollFrame(points: 0, phase: .ended), "the glide ends on the next frame")
        #expect(after.dropFirst().first?.frame.phase == .began)
        #expect(after.allSatisfy { $0.frame.points <= 0 }, "nothing moves the old way after the reversal")
        let back = after.reduce(0) { $0 + $1.frame.points }
        #expect(abs(back + smooth.curve.distancePerStep(at: smooth.curve.slowest)) < 1e-9, "a fresh step the other way")
    }

    @Test func theDisplaysRefreshRateChangesNoDistance() {
        let steps = spin(20, perSecond: 12)
        let at60 = run(steps, hertz: 60)
        let at120 = run(steps, hertz: 120)
        #expect(abs(at60.distance - at120.distance) < 1e-9)
        #expect(abs(at60.distance(from: 0.5, to: 1.5) / at120.distance(from: 0.5, to: 1.5) - 1) < 0.02)
    }

    @Test func aSettingsChangeAppliesFromTheNextStep() {
        let faster = with {
            $0.curve = try! SpeedCurve([.init(stepsPerSecond: 1, pointsPerSecond: 100), .init(stepsPerSecond: 150, pointsPerSecond: 15_000)])
        }
        var animator = ScrollAnimator()
        animator.tick(ScrollTick(sign: .positive, steps: 1, settings: smooth), at: 0)
        animator.tick(ScrollTick(sign: .positive, steps: 1, settings: faster), at: 2)
        var total = 0.0
        for index in 1...600 { total += animator.frame(at: Double(index) / 120)?.points ?? 0 }
        #expect(abs(total - 140) < 1e-9, "40 points, then 100")
    }

    @Test func stopEndsAnOpenGestureOnce() {
        var animator = ScrollAnimator()
        #expect(animator.stop() == nil, "nothing to end")
        animator.tick(ScrollTick(sign: .positive, steps: 1, settings: smooth), at: 0)
        _ = animator.frame(at: 1.0 / 120)
        #expect(animator.stop() == ScrollFrame(points: 0, phase: .ended))
        #expect(animator.isIdle)
        #expect(animator.frame(at: 2.0 / 120) == nil)
    }
}

@Suite struct SpinRateTests {
    @Test func aStepAfterAPauseCountsAsTheSlowestRate() {
        var rate = SpinRate()
        #expect(rate.record(1, at: 10, slowest: 1) == 1)
        #expect(rate.record(1, at: 12, slowest: 1) == 1, "two seconds apart is slower than the slowest point")
        #expect(abs(rate.record(1, at: 12.1, slowest: 1) - 10) < 1e-9, "the first interval sets the rate")
    }

    @Test func theRateFollowsTheLastFewIntervals() {
        var rate = SpinRate()
        var time = 0.0
        _ = rate.record(1, at: time, slowest: 1)
        for _ in 0..<10 {
            time += 0.1
            _ = rate.record(1, at: time, slowest: 1)
        }
        time += 1.0 / 40
        let first = rate.record(1, at: time, slowest: 1)
        #expect(first > 10 && first < 30, "one fast step moves the rate only part of the way")
        var latest = first
        for _ in 0..<7 {
            time += 1.0 / 40
            latest = rate.record(1, at: time, slowest: 1)
        }
        #expect(abs(latest - 40) < 1, "eight steps at 40 per second bring it to about 40")
        time += 1.0 / 20
        #expect(rate.record(2, at: time, slowest: 1) > 30, "two detents in one event count as two steps")
    }
}

@Suite struct WholePointsTests {
    @Test func wholePointsTrackTheExactTotalWithinHalfAPoint() {
        var whole = WholePoints()
        var exact = 0.0
        var posted: Int32 = 0
        let frames = [ScrollFrame(points: 0.3, phase: .began)] + (0..<200).map { ScrollFrame(points: 2.7 + sin(Double($0)) * 0.4, phase: .changed) }
        for frame in frames {
            exact += frame.points
            posted += whole.take(frame)
            #expect(abs(Double(posted) - exact) <= 0.5)
        }
    }

    @Test func aSteadyGlidePostsEvenWholePoints() {
        var whole = WholePoints()
        _ = whole.take(ScrollFrame(points: 2.7, phase: .began))
        let posted = (0..<100).map { _ in whole.take(ScrollFrame(points: 2.7, phase: .changed)) }
        #expect(Set(posted) == [2, 3], "never 4 next to 2")
    }

    @Test func aNewGestureStartsFromZero() {
        var whole = WholePoints()
        _ = whole.take(ScrollFrame(points: 0.4, phase: .began))
        #expect(whole.take(ScrollFrame(points: 0, phase: .ended)) == 0)
        #expect(whole.take(ScrollFrame(points: 0.4, phase: .began)) == 0, "the last gesture's fraction does not carry")
    }
}
