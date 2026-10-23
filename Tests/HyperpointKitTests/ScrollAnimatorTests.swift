import CoreGraphics
@testable import HyperpointKit
import Testing

private let frameRate = 120.0
private let smooth = Config.default.devices[0].scrolling!.smooth!

private struct Glide {
    var frames: [(time: Double, frame: ScrollFrame)]
    var idleAtEnd: Bool

    var distance: Int { frames.reduce(0) { $0 + Int($1.frame.points) } }
    func distance(from start: Double, to stop: Double) -> Int {
        frames.filter { $0.time >= start && $0.time < stop }.reduce(0) { $0 + Int($1.frame.points) }
    }
    var lastMovingFrame: Double { frames.last { $0.frame.points != 0 }?.time ?? 0 }
}

/// Drives the animator at 120 Hz with a fake clock. Ticks land between frames.
private func glide(
    _ ticks: [(time: Double, sign: ScrollTick.Sign)], _ settings: SmoothScroll = smooth, seconds: Double = 3
) -> Glide {
    var animator = ScrollAnimator()
    var pending = ticks[...]
    var frames: [(Double, ScrollFrame)] = []
    for index in 0...Int(seconds * frameRate) {
        let now = Double(index) / frameRate
        while let next = pending.first, next.time <= now {
            animator.tick(ScrollTick(sign: next.sign, settings: settings), at: next.time)
            pending.removeFirst()
        }
        if let frame = animator.frame(at: now) { frames.append((now, frame)) }
    }
    return Glide(frames: frames, idleAtEnd: animator.isIdle)
}

private func burst(_ count: Int, perSecond rate: Double, from start: Double = 0.0005, _ sign: ScrollTick.Sign = .positive)
    -> [(time: Double, sign: ScrollTick.Sign)]
{
    (0..<count).map { (start + Double($0) / rate, sign) }
}

private func with(_ change: (inout SmoothScroll) -> Void) -> SmoothScroll {
    var settings = smooth
    change(&settings)
    return settings
}

private func perTickInSteadyStream(_ rate: Double, _ settings: SmoothScroll) -> Double {
    let stream = glide(burst(Int(5 * rate), perSecond: rate), settings, seconds: 6)
    return Double(stream.distance(from: 1, to: 3)) / (2 * rate)
}

@Suite struct ScrollAnimatorTests {
    @Test func aTickAfterIdleGoesFartherThanAPlainNotch() {
        let notch = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
        let plainNotch = Int(notch.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))

        let single = glide(burst(1, perSecond: 1))

        #expect(single.distance > 2 * plainNotch)
        #expect(abs(single.distance - Int(smooth.speed * smooth.startBoost)) <= 1, "it scrolls startBoost × speed")
        #expect(single.frames.first?.frame.phase == .began)
        #expect(single.frames.last?.frame == ScrollFrame(points: 0, phase: .ended))
        #expect(single.frames.dropFirst().dropLast().allSatisfy { $0.frame.phase == .changed && $0.frame.points > 0 })
        #expect(single.idleAtEnd)
    }

    @Test func aFastBurstAcceleratesWhenAccelerationIsOn() {
        let fast = burst(20, perSecond: 60)
        let accelerated = glide(fast).distance
        let flat = glide(fast, with { $0.acceleration = nil }).distance
        #expect(accelerated > 2 * flat)
        #expect(glide(burst(20, perSecond: 60)).distance > glide(burst(20, perSecond: 10)).distance)
    }

    @Test func aSteadyStreamScrollsSpeedPerTickWhateverTheGlide() {
        for (duration, brake) in [(4.0, 1.0), (4.0, 4.0), (10.0, 2.0)] {
            let settings = with {
                $0.duration = duration
                $0.brake = brake
                $0.acceleration = nil
                $0.startBoost = 1
            }
            let stream = glide(burst(40, perSecond: 10), settings, seconds: 6)
            let perTick = Double(stream.distance(from: 1, to: 3)) / 20
            #expect(abs(perTick - settings.speed) < 0.1 * settings.speed, "duration \(duration), brake \(brake)")
        }
    }

    @Test func accelerationGainRisesLinearlyWithTickRate() {
        let settings = with {
            $0.startBoost = 1
            $0.acceleration = Acceleration(from: 4, to: 40, max: 3)
        }
        let expected: [(rate: Double, gain: Double)] = [(3, 1), (4, 1), (13, 1.5), (22, 2), (31, 2.5), (40, 3), (80, 3)]
        for (rate, gain) in expected {
            let perTick = perTickInSteadyStream(rate, settings)
            #expect(abs(perTick / (settings.speed * gain) - 1) < 0.05, "\(rate) ticks/s scroll \(perTick) per tick")
        }
    }

    @Test func withoutAccelerationEveryRateScrollsSpeedPerTick() {
        let settings = with {
            $0.startBoost = 1
            $0.acceleration = nil
        }
        for rate in [3.0, 22, 80] {
            let perTick = perTickInSteadyStream(rate, settings)
            #expect(abs(perTick / settings.speed - 1) < 0.05, "\(rate) ticks/s scroll \(perTick) per tick")
        }
    }

    @Test func theGlideStopsWithinDurationAfterTheLastTick() {
        for duration in [4.0, 8.0] {
            let settings = with { $0.duration = duration }
            let ticks = burst(10, perSecond: 30)
            let lastTick = ticks.last!.time
            let length = duration / 10
            let run = glide(ticks, settings)

            #expect(run.lastMovingFrame <= lastTick + length + 1 / frameRate)
            #expect(run.lastMovingFrame > lastTick + length / 2, "it glides on after the last tick")
            #expect(run.frames.last?.frame.phase == .ended)
            #expect(run.idleAtEnd)
            let firstHalf = run.distance(from: lastTick, to: lastTick + length / 2)
            let secondHalf = run.distance(from: lastTick + length / 2, to: lastTick + length + 1)
            #expect(firstHalf > 3 * secondHalf, "it decays")
        }
    }

    @Test func brakeFrontLoadsTheStop() {
        func shareOfFirstQuarter(_ brake: Double) -> Double {
            let run = glide(burst(1, perSecond: 1), with { $0.brake = brake })
            return Double(run.distance(from: 0, to: 0.1)) / Double(run.distance)
        }
        #expect(shareOfFirstQuarter(1) < shareOfFirstQuarter(2))
        #expect(shareOfFirstQuarter(2) < shareOfFirstQuarter(4))
    }

    @Test func aTickTheOtherWayCancelsTheGlideAtOnce() throws {
        let up = burst(10, perSecond: 30)
        let reversal = up.last!.time + 0.05
        let run = glide(up + [(reversal, .negative)])

        let after = run.frames.filter { $0.time >= reversal }
        let first = try #require(after.first)
        #expect(first.frame == ScrollFrame(points: 0, phase: .ended), "the glide ends on the next frame")
        #expect(first.time < reversal + 1 / frameRate)
        #expect(after.dropFirst().first?.frame.phase == .began)
        #expect(after.allSatisfy { $0.frame.points <= 0 }, "nothing moves the old way after the reversal")
        #expect(after.reduce(0) { $0 + Int($1.frame.points) } <= -Int(smooth.speed), "the new tick scrolls the other way")
    }

    @Test func distanceIsFiniteAndGrowsWithSpeed() {
        let distances = [10.0, 20, 40, 80].map { speed in glide(burst(15, perSecond: 40), with { $0.speed = speed }) }
        #expect(distances.allSatisfy { $0.idleAtEnd }, "every glide ends")
        #expect(zip(distances, distances.dropFirst()).allSatisfy { $0.distance < $1.distance })
    }

    @Test func easeInStartsAnIsolatedTickSlowerWithoutChangingItsDistance() throws {
        let flat = with {
            $0.startBoost = 1
            $0.brake = 1
        }
        let abrupt = glide(burst(1, perSecond: 1), flat)
        let firstAbrupt = try #require(abrupt.frames.first { $0.frame.points != 0 })
        for easeIn in [60.0, 300] {
            let eased = glide(burst(1, perSecond: 1), with { $0 = flat; $0.easeIn = easeIn })
            let firstEased = try #require(eased.frames.first { $0.frame.points != 0 })
            #expect(eased.distance(from: 0, to: firstAbrupt.time + 0.001) < Int(firstAbrupt.frame.points), "\(easeIn) ms")
            #expect(firstEased.time >= firstAbrupt.time)
            #expect(abs(eased.distance - Int(flat.speed)) <= 1, "\(easeIn) ms still scrolls speed × startBoost")
            #expect(eased.lastMovingFrame <= 0.0005 + (easeIn / 1000 + flat.duration / 10) + 1 / frameRate)
            #expect(eased.lastMovingFrame > 0.0005 + flat.duration / 10, "the ease-in lengthens the glide")
            #expect(eased.idleAtEnd)
        }
        let boosted = glide(burst(1, perSecond: 1), with { $0.easeIn = 300 })
        #expect(abs(boosted.distance - Int(smooth.speed * smooth.startBoost)) <= 1)
    }

    @Test func easeInLeavesASteadyStreamAlone() {
        for accelerated in [false, true] {
            let settings = with {
                $0.startBoost = 1
                if !accelerated { $0.acceleration = nil }
            }
            for rate in [5.0, 30] {
                let plain = perTickInSteadyStream(rate, settings)
                let eased = perTickInSteadyStream(rate, with { $0 = settings; $0.easeIn = 300 })
                #expect(abs(eased / plain - 1) < 0.01, "\(rate) ticks/s, acceleration \(accelerated)")
            }
        }
    }

    @Test func ticksDuringTheEaseInKeepTheFirstTicksDistance() {
        let settings = with {
            $0.easeIn = 300
            $0.acceleration = nil
            $0.startBoost = 1
        }
        let two = glide([(0.0005, .positive), (0.1005, .positive)], settings)
        let single = glide(burst(1, perSecond: 1), settings)
        #expect(two.distance > single.distance + Int(settings.speed) / 2, "the second tick adds to the first")
        #expect(two.frames.dropFirst().dropLast().allSatisfy { $0.frame.phase == .changed && $0.frame.points > 0 })
    }

    @Test func easeInOfZeroPostsTheFramesItAlwaysHas() {
        let isolated: [Int32] = [
            4, 5, 4, 5, 4, 4, 3, 4, 3, 4, 3, 3, 2, 3, 2, 3, 2, 2, 2, 2, 1, 2, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,
        ]
        let burstThenReversal: [Int32] = [
            4, 5, 4, 5, 4, 8, 8, 7, 7, 9, 10, 10, 10, 9, 11, 12, 12, 11, 11, 14, 14, 13, 13, 12, 15, 16, 14, 14, 13, 13,
            12, 11, 11, 11, 9, 10, 9, 8, 8, 7, 7, 7, 6, 5, 6, 5, 4, 0, -4, -5, -5, -4, -4, -4, -4, -3, -4, -3, -3, -3, -2,
            -3, -3, -2, -2, -2, -2, -2, -1, -2, -1, -1, -2, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0,
        ]
        #expect(smooth.easeIn == 0)
        #expect(glide(burst(1, perSecond: 1)).frames.map(\.frame.points) == isolated)
        let ticks = burst(6, perSecond: 25) + [(0.4, .negative)]
        #expect(glide(ticks).frames.map(\.frame.points) == burstThenReversal)
    }

    @Test func stopEndsAnOpenGestureOnce() {
        var animator = ScrollAnimator()
        #expect(animator.stop() == nil, "nothing to end")
        animator.tick(ScrollTick(sign: .positive, settings: smooth), at: 0)
        _ = animator.frame(at: 1 / frameRate)
        #expect(animator.stop() == ScrollFrame(points: 0, phase: .ended))
        #expect(animator.isIdle)
        #expect(animator.frame(at: 2 / frameRate) == nil)
    }
}
