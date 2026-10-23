import CoreGraphics
import Foundation

struct ScrollTick: Equatable, Sendable {
    enum Sign: Equatable, Sendable {
        case positive
        case negative

        var factor: Double { self == .positive ? 1 : -1 }
    }

    var sign: Sign
    /// Wheel detents in the event. A freely spinning wheel packs up to three into one.
    var steps: Int
    var settings: SmoothScroll
}

struct ScrollFrame: Equatable, Sendable {
    /// Points to scroll, fraction included.
    var points: Double
    var phase: CGScrollPhase
}

/// Turns wheel steps into a glide. Each step starts a pulse of velocity that rises from rest along smoothstep over
/// `easeIn`, then falls as (1 - t / duration) ^ brake. Pulses add up, so a step travels exactly the distance the curve
/// gives it at the current spin rate, and a steady spin scrolls at the curve's speed whatever the glide's shape. Time
/// is passed in, in seconds.
struct ScrollAnimator {
    /// Apps take whole points (measured), so a glide slowing through a few points a second would move by single
    /// points at growing intervals. Once its steps have eased in, a glide never moves slower than this, in points per
    /// second. It finishes at this speed, one point every other frame at 120 Hz, and stops.
    static let stoppingSpeed = 60.0
    /// More pulses than a free spin fits in the longest glide. Past this a step joins the latest pulse.
    private static let capacity = 512

    private enum Gesture: Equatable {
        case idle
        case gliding(began: Bool)
        /// The posted gesture still owes its ended frame. With `next`, the pulses belong to a new gesture that starts
        /// after it.
        case ending(next: Bool)
    }

    private struct Pulse {
        var start: Double
        var distance: Double
    }

    private var gesture = Gesture.idle
    private var sign = ScrollTick.Sign.positive
    private var shape = PulseShape(.default)
    /// In start order, and outside `gesture` so that a step appends in place.
    private var pulses: [Pulse] = []
    private var rate = SpinRate()
    /// Since the gesture began: the distance of pulses that are over, and the distance posted.
    private var finished = 0.0
    private var posted = 0.0
    private var lastFrame = 0.0

    init() { pulses.reserveCapacity(Self.capacity) }

    var isIdle: Bool { gesture == .idle }

    mutating func tick(_ tick: ScrollTick, at now: Double) {
        switch gesture {
        case .gliding where tick.sign == sign, .ending(next: true) where tick.sign == sign:
            add(tick, at: now)
        case .idle, .gliding(began: false):
            restart(tick, at: now)
            gesture = .gliding(began: false)
        case .gliding(began: true), .ending:
            restart(tick, at: now)
            gesture = .ending(next: true)
        }
    }

    mutating func frame(at now: Double) -> ScrollFrame? {
        switch gesture {
        case .idle:
            return nil
        case .ending(let next):
            gesture = next ? .gliding(began: false) : .idle
            return ScrollFrame(points: 0, phase: .ended)
        case .gliding(let began):
            let over = pulses.prefix { now - $0.start >= shape.length }.count
            finished += pulses[..<over].reduce(0) { $0 + $1.distance }
            pulses.removeFirst(over)
            var travelled = finished
            var total = finished
            for pulse in pulses {
                travelled += pulse.distance * shape.share(after: now - pulse.start)
                total += pulse.distance
            }
            let easing = pulses.last.map { now - $0.start < shape.easeIn } ?? false
            let slowest = easing ? 0 : Self.stoppingSpeed * (now - lastFrame)
            let move = min(max(travelled - posted, slowest, 0), total - posted)
            posted += move
            lastFrame = now
            if total - posted < 1e-9 {
                pulses.removeAll(keepingCapacity: true)
                gesture = .ending(next: false)
            } else if move == 0 {
                return nil
            } else {
                gesture = .gliding(began: true)
            }
            return ScrollFrame(points: sign.factor * move, phase: began ? .changed : .began)
        }
    }

    /// Ends the gesture at once, for a tap that is going away.
    mutating func stop() -> ScrollFrame? {
        defer {
            gesture = .idle
            pulses.removeAll(keepingCapacity: true)
        }
        switch gesture {
        case .gliding(began: true), .ending: return ScrollFrame(points: 0, phase: .ended)
        case .idle, .gliding(began: false): return nil
        }
    }

    /// A new gesture. The spin rate carries over unless the wheel turned the other way.
    private mutating func restart(_ tick: ScrollTick, at now: Double) {
        if tick.sign != sign { rate.reset() }
        sign = tick.sign
        shape = PulseShape(tick.settings)
        pulses.removeAll(keepingCapacity: true)
        (finished, posted, lastFrame) = (0, 0, now)
        add(tick, at: now)
    }

    private mutating func add(_ tick: ScrollTick, at now: Double) {
        let curve = tick.settings.curve
        let spin = rate.record(tick.steps, at: now, slowest: curve.slowest)
        let distance = Double(tick.steps) * curve.distancePerStep(at: spin)
        if pulses.count < Self.capacity {
            pulses.append(Pulse(start: now, distance: distance))
        } else {
            pulses[pulses.count - 1].distance += distance
        }
    }
}

/// One step's glide, scaled to a distance of 1: a smoothstep rise over `easeIn`, then a fall as
/// (1 - t / decay) ^ brake.
struct PulseShape {
    let easeIn: Double
    let decay: Double
    let brake: Double
    private let peak: Double

    init(_ settings: SmoothScroll) {
        easeIn = settings.easeIn / 1000
        decay = settings.duration / 10
        brake = settings.brake
        peak = 1 / (easeIn / 2 + decay / (brake + 1))
    }

    var length: Double { easeIn + decay }

    /// The share of its distance a step has travelled `t` seconds after it. Smoothstep, 3u² - 2u³, integrates to
    /// u³ - u⁴ / 2, which is half the ease-in at its end.
    func share(after t: Double) -> Double {
        if t <= 0 { return 0 }
        if t < easeIn {
            let u = t / easeIn
            return peak * easeIn * (u * u * u - u * u * u * u / 2)
        }
        let s = min(1, (t - easeIn) / decay)
        return peak * (easeIn / 2 + decay / (brake + 1) * (1 - pow(1 - s, brake + 1)))
    }
}

/// The wheel's spin rate in steps per second, smoothed over the last few steps.
struct SpinRate {
    /// Each interval moves the estimate halfway, so the last three carry most of it.
    private static let smoothing = 0.5
    private static let shortest = 0.001

    private var last: Double?
    private var interval: Double?

    mutating func reset() { (last, interval) = (nil, nil) }

    /// The rate of `steps` steps arriving at `now`. Steps after a pause longer than a step at `slowest` count as
    /// `slowest`.
    mutating func record(_ steps: Int, at now: Double, slowest: Double) -> Double {
        defer { last = now }
        guard let last, (now - last) / Double(steps) < 1 / slowest else {
            interval = nil
            return slowest
        }
        let each = max((now - last) / Double(steps), Self.shortest)
        let smoothed = interval.map { $0 + Self.smoothing * (each - $0) } ?? each
        interval = smoothed
        return 1 / smoothed
    }
}

/// AppKit reads a posted scroll's precise delta from its integer point field alone (measured), so frames post whole
/// points. Rounding the running total keeps what is posted within half a point of the glide.
struct WholePoints {
    private var exact = 0.0
    private var posted = 0.0

    mutating func take(_ frame: ScrollFrame) -> Int32 {
        if frame.phase == .began { (exact, posted) = (0, 0) }
        exact += frame.points
        let whole = exact.rounded() - posted
        posted += whole
        return Int32(whole)
    }
}
