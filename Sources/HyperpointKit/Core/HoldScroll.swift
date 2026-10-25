import CoreGraphics
import Foundation

/// What one held button does to the page while it scrolls, captured at press like every gesture plan.
struct HoldScrollPlan: Equatable, Sendable {
    /// Screen points per MX Master 3 sensor count, so that at speed 1 the page moves about as far as the pointer
    /// would have. macOS accelerates the pointer from 0.25 points per count for a slow hand to 0.95 for a fast one,
    /// and this is its median over drag speeds (measured, the architecture doc's Appendix A).
    static let pointsPerCount = 0.4

    /// Page points per unit of the control's movement, negative where the page moves against the hand.
    var gain: Double
    /// The release glide, or nil without momentum.
    var momentum: Glide?

    /// `pointsPerUnit` turns the control's movement into points. It is `pointsPerCount` for HID++ raw movement and
    /// 1 for pointer drags, which are points already.
    init(_ settings: HoldToScroll, glide: SmoothScroll, pointsPerUnit: Double) {
        let sign: Double = settings.direction == .grab ? 1 : -1
        gain = sign * settings.speed * pointsPerUnit
        momentum = settings.momentum ? Glide(seconds: glide.duration / 10, brake: glide.brake) : nil
    }
}

/// The glide's decay, (1 - t / seconds) ^ brake, the same one a wheel step's glide uses.
struct Glide: Equatable, Sendable {
    var seconds: Double
    var brake: Double
}

/// Between a gesture recognizer and the animator that posts the scroll events. Deltas are page points in the
/// posted scroll's sign, so positive moves the content down or right.
enum HoldScrollEvent: Equatable, Sendable {
    case began(HoldScrollPlan)
    case moved(dx: Double, dy: Double)
    case ended
}

/// A trackpad's scroll phases while the hand moves, then its momentum phases while the page glides.
enum HoldScrollPhase: Equatable, Sendable {
    case began, changed, ended
    case momentumBegan, momentum, momentumEnded
}

struct HoldScrollFrame: Equatable, Sendable {
    var dx: Double
    var dy: Double
    var phase: HoldScrollPhase
}

extension HoldScrollPhase {
    /// Nil on momentum frames, which carry no scroll phase.
    var scrollPhase: CGScrollPhase? {
        switch self {
        case .began: .began
        case .changed: .changed
        case .ended: .ended
        case .momentumBegan, .momentum, .momentumEnded: nil
        }
    }

    var momentumPhase: CGMomentumScrollPhase {
        switch self {
        case .began, .changed, .ended: .none
        case .momentumBegan: .begin
        case .momentum: .continuous
        case .momentumEnded: .end
        }
    }
}

/// Posts a held button's scrolling the way a trackpad does. The hand's movement goes out once per display frame with
/// the scroll phases began, changed and ended, and on release a momentum glide follows with the momentum phases. The
/// glide starts at the hand's speed over the last few tens of milliseconds and decays like a wheel step's glide. Time
/// is passed in, in seconds.
struct HoldScrollAnimator {
    /// How far back the release speed looks, in seconds. Movement this old counts for about a third.
    static let smoothing = 0.04
    /// A release slower than this, in points per second, does not glide.
    static let slowestFling = 150.0

    private enum Hold: Equatable {
        case idle
        case following
        /// The button is up. The movement not yet posted goes first, then the ended frame, then the glide.
        case releasing(Fling?)
        case gliding(Fling)
    }

    struct Fling: Equatable {
        var dx: Double
        var dy: Double
        var distance: Double
        var shape: PulseShape
        var start = 0.0
        var posted = 0.0
        var lastFrame = 0.0
    }

    private enum Owed: Equatable {
        case ended
        case momentumEnded
    }

    private var hold = Hold.idle
    /// Whether the current gesture or glide has posted its first frame.
    private var begun = false
    /// An end frame that an interrupted gesture or glide still owes, posted before anything else.
    private var owed: Owed?
    private var plan: HoldScrollPlan?
    private var pending = (dx: 0.0, dy: 0.0)
    /// Movement and the time it took, both weighted by how recent they are. Their ratio is the hand's speed, exact
    /// for a steady hand however often the device reports.
    private var trail = (dx: 0.0, dy: 0.0, seconds: 0.0)
    private var lastMove = 0.0

    var isIdle: Bool { hold == .idle && owed == nil }

    /// False while the hand holds still, so the display link can pause until it moves again.
    var wantsFrames: Bool {
        switch hold {
        case .idle: owed != nil
        case .following: owed != nil || pending != (0, 0)
        case .releasing, .gliding: true
        }
    }

    mutating func receive(_ event: HoldScrollEvent, at now: Double) {
        switch (event, hold) {
        case (.began(let plan), _):
            if begun {
                switch hold {
                case .following, .releasing: owed = .ended
                case .gliding: owed = .momentumEnded
                case .idle: break
                }
            }
            self.plan = plan
            hold = .following
            begun = false
            pending = (0, 0)
            trail = (0, 0, 0)
            lastMove = now
        case (.moved(let dx, let dy), .following):
            pending.dx += dx
            pending.dy += dy
            let gap = max(0, now - lastMove)
            let keep = exp(-gap / Self.smoothing)
            trail = (trail.dx * keep + dx, trail.dy * keep + dy, trail.seconds * keep + gap)
            lastMove = now
        case (.ended, .following):
            guard begun || pending != (0, 0) else {
                hold = .idle
                return
            }
            hold = .releasing(fling(at: now))
        case (.moved, _), (.ended, _):
            break
        }
    }

    mutating func frame(at now: Double) -> HoldScrollFrame? {
        if let owed {
            self.owed = nil
            return HoldScrollFrame(dx: 0, dy: 0, phase: owed == .ended ? .ended : .momentumEnded)
        }
        switch hold {
        case .idle:
            return nil
        case .following:
            return flush()
        case .releasing(let fling):
            if let moved = flush() { return moved }
            if var fling {
                (fling.start, fling.lastFrame) = (now, now)
                hold = .gliding(fling)
            } else {
                hold = .idle
            }
            begun = false
            return HoldScrollFrame(dx: 0, dy: 0, phase: .ended)
        case .gliding(var fling):
            let travelled = fling.distance * fling.shape.share(after: now - fling.start)
            let slowest = ScrollAnimator.stoppingSpeed * (now - fling.lastFrame)
            let move = min(max(travelled - fling.posted, slowest, 0), fling.distance - fling.posted)
            fling.posted += move
            fling.lastFrame = now
            let frame = HoldScrollFrame(dx: move * fling.dx, dy: move * fling.dy, phase: begun ? .momentum : .momentumBegan)
            begun = true
            if fling.distance - fling.posted < 1e-9 {
                hold = .idle
                owed = .momentumEnded
                begun = false
            } else {
                hold = .gliding(fling)
            }
            return frame
        }
    }

    /// Ends whatever is posted at once, for a hold that is going away with no release.
    mutating func stop() -> HoldScrollFrame? {
        defer {
            (hold, begun, owed, pending) = (.idle, false, nil, (0, 0))
        }
        if let owed { return HoldScrollFrame(dx: 0, dy: 0, phase: owed == .ended ? .ended : .momentumEnded) }
        guard begun else { return nil }
        switch hold {
        case .following, .releasing: return HoldScrollFrame(dx: 0, dy: 0, phase: .ended)
        case .gliding: return HoldScrollFrame(dx: 0, dy: 0, phase: .momentumEnded)
        case .idle: return nil
        }
    }

    private mutating func flush() -> HoldScrollFrame? {
        guard pending != (0, 0) else { return nil }
        defer {
            pending = (0, 0)
            begun = true
        }
        return HoldScrollFrame(dx: pending.dx, dy: pending.dy, phase: begun ? .changed : .began)
    }

    /// A glide that starts at the hand's speed and travels speed × seconds / (brake + 1), as a wheel step's glide
    /// with no ease-in does.
    private func fling(at now: Double) -> Fling? {
        let gap = max(0, now - lastMove)
        let keep = exp(-gap / Self.smoothing)
        let seconds = trail.seconds * keep + gap
        guard let glide = plan?.momentum, seconds > 0 else { return nil }
        let velocity = (dx: trail.dx * keep / seconds, dy: trail.dy * keep / seconds)
        let speed = (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot()
        guard speed >= Self.slowestFling else { return nil }
        return Fling(
            dx: velocity.dx / speed, dy: velocity.dy / speed, distance: speed * glide.seconds / (glide.brake + 1),
            shape: PulseShape(easeIn: 0, decay: glide.seconds, brake: glide.brake))
    }
}
