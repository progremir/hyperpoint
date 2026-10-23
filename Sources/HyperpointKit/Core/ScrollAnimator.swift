import CoreGraphics
import Foundation

struct ScrollTick: Equatable, Sendable {
    enum Sign: Equatable, Sendable {
        case positive
        case negative

        var factor: Double { self == .positive ? 1 : -1 }
    }

    var sign: Sign
    var settings: SmoothScroll
}

struct ScrollFrame: Equatable, Sendable {
    var points: Int32
    var phase: CGScrollPhase
}

/// Turns wheel ticks into a glide. Each tick adds to the velocity, which then falls as (1 - t / duration) ^ brake
/// and reaches zero `duration` after the last tick. Time is passed in, in seconds.
struct ScrollAnimator {
    private enum State {
        case idle
        case gliding(Glide)
        /// The posted gesture still owes its ended frame. `next` starts a new gesture after it.
        case ending(next: Glide?)
    }

    private var state = State.idle

    var isIdle: Bool {
        if case .idle = state { true } else { false }
    }

    mutating func tick(_ tick: ScrollTick, at now: Double) {
        switch state {
        case .idle:
            state = .gliding(Glide(tick, at: now))
        case .gliding(var glide) where glide.continues(with: tick, at: now):
            glide.add(tick, at: now)
            state = .gliding(glide)
        case .gliding(let glide):
            state = glide.posted ? .ending(next: Glide(tick, at: now)) : .gliding(Glide(tick, at: now))
        case .ending(.some(var next)) where next.continues(with: tick, at: now):
            next.add(tick, at: now)
            state = .ending(next: next)
        case .ending:
            state = .ending(next: Glide(tick, at: now))
        }
    }

    mutating func frame(at now: Double) -> ScrollFrame? {
        switch state {
        case .idle:
            return nil
        case .ending(let next):
            state = next.map(State.gliding) ?? .idle
            return ScrollFrame(points: 0, phase: .ended)
        case .gliding(var glide):
            let points = glide.advance(to: now)
            let finished = now >= glide.end
            guard points != 0 else {
                state = finished ? .idle : .gliding(glide)
                return finished && glide.posted ? ScrollFrame(points: 0, phase: .ended) : nil
            }
            let phase: CGScrollPhase = glide.posted ? .changed : .began
            glide.posted = true
            state = finished ? .ending(next: nil) : .gliding(glide)
            return ScrollFrame(points: points, phase: phase)
        }
    }

    /// Ends the gesture at once, for a tap that is going away.
    mutating func stop() -> ScrollFrame? {
        defer { state = .idle }
        switch state {
        case .gliding(let glide) where glide.posted: return ScrollFrame(points: 0, phase: .ended)
        case .ending: return ScrollFrame(points: 0, phase: .ended)
        case .idle, .gliding: return nil
        }
    }
}

private struct Glide {
    static let minimumInterval = 0.001

    let sign: ScrollTick.Sign
    var settings: SmoothScroll
    var lastTick: Double
    /// Points per second just after `lastTick`.
    var peak: Double
    var postedUntil: Double
    var unposted = 0.0
    var posted = false

    init(_ tick: ScrollTick, at now: Double) {
        sign = tick.sign
        settings = tick.settings
        lastTick = now
        postedUntil = now
        peak = Self.impulse(tick.settings, interval: nil)
    }

    var length: Double { settings.duration / 10 }
    var end: Double { lastTick + length }

    func continues(with tick: ScrollTick, at now: Double) -> Bool { tick.sign == sign && now < end }

    mutating func add(_ tick: ScrollTick, at now: Double) {
        unposted += travelled(from: postedUntil, to: now)
        postedUntil = now
        peak = velocity(at: now) + Self.impulse(tick.settings, interval: now - lastTick)
        settings = tick.settings
        lastTick = now
    }

    /// The whole points to post up to `now`. The fraction waits for the next frame, and the last frame rounds it.
    mutating func advance(to now: Double) -> Int32 {
        let until = min(max(now, postedUntil), end)
        unposted += travelled(from: postedUntil, to: until)
        postedUntil = until
        let whole = now >= end ? unposted.rounded() : unposted.rounded(.down)
        unposted -= whole
        return Int32(sign.factor * whole)
    }

    private func velocity(at time: Double) -> Double {
        let left = 1 - (time - lastTick) / length
        return left > 0 ? peak * pow(left, settings.brake) : 0
    }

    private func travelled(from start: Double, to stop: Double) -> Double {
        func untravelled(_ time: Double) -> Double { pow(min(1, max(0, 1 - (time - lastTick) / length)), settings.brake + 1) }
        return peak * length / (settings.brake + 1) * (untravelled(start) - untravelled(stop))
    }

    /// The velocity one tick adds, chosen so the tick travels `speed` times its multiplier: on its own when no glide
    /// is running, and per tick in a steady stream otherwise, whatever the brake and duration. The start boost fades
    /// as ticks come closer together, so the distance per tick has no step where a glide ends.
    static func impulse(_ settings: SmoothScroll, interval: Double?) -> Double {
        let length = settings.duration / 10
        let brake = settings.brake
        let spacing = interval.map { max($0, minimumInterval) }
        let x = spacing.map { min(1, $0 / length) } ?? 1
        let boost = 1 + (settings.startBoost - 1) * x
        let gain = spacing.flatMap { spacing in settings.acceleration?.gain(ticksPerSecond: 1 / spacing) } ?? 1
        let steady = x < 1 ? (1 - pow(1 - x, brake + 1)) / (1 - pow(1 - x, brake)) : 1
        return settings.speed * boost * gain * (brake + 1) / (length * steady)
    }
}

extension Acceleration {
    func gain(ticksPerSecond rate: Double) -> Double {
        1 + min(1, Swift.max(0, (rate - from) / (to - from))) * (max - 1)
    }
}
