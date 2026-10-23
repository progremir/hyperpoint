import Foundation
import HyperpointKit

/// Maps a slider's position, 0 to 1, to a value and back. A logarithmic curve gives small values the same room as
/// large ones, so 40 points sits mid-slider on a 1 to 500 range instead of near its left end.
struct SliderScale: Equatable {
    enum Curve: Equatable {
        case linear
        case logarithmic
    }

    var bounds: ClosedRange<Double>
    var step: Double
    var curve: Curve

    /// The value at `position`, rounded to the step, so a drag never writes 41.3782 to the file.
    func value(at position: Double) -> Double {
        let position = min(max(position, 0), 1)
        let low = bounds.lowerBound
        let high = bounds.upperBound
        let raw =
            switch curve {
            case .linear: low + position * (high - low)
            case .logarithmic: (low + shift) * pow((high + shift) / (low + shift), position) - shift
            }
        let rounded = step < 1 ? (raw / step).rounded() / (1 / step) : (raw / step).rounded() * step
        return min(max(rounded, low), high)
    }

    func position(of value: Double) -> Double {
        let low = bounds.lowerBound
        let high = bounds.upperBound
        guard high > low else { return 0 }
        let value = min(max(value, low), high)
        return switch curve {
        case .linear: (value - low) / (high - low)
        case .logarithmic: log((value + shift) / (low + shift)) / log((high + shift) / (low + shift))
        }
    }

    /// A logarithm needs a range above zero, so a range that starts at zero or below is shifted to start at one.
    private var shift: Double { bounds.lowerBound > 0 ? 0 : 1 - bounds.lowerBound }

    /// The same scale, widened to include `value`, so a value from a hand edit never snaps when shown.
    func including(_ value: Double) -> SliderScale {
        var scale = self
        scale.bounds = min(bounds.lowerBound, value)...max(bounds.upperBound, value)
        return scale
    }
}

enum KnobUnit: Equatable {
    case points
    case multiple
    /// Stored in tenths of a second and shown in seconds.
    case tenthsOfASecond
    case milliseconds
    case stepsPerSecond
    case counts
    case none

    func format(_ value: Double, locale: Locale = .current) -> String {
        let number = { (value: Double, fraction: ClosedRange<Int>) in
            value.formatted(.number.locale(locale).precision(.fractionLength(fraction)))
        }
        return switch self {
        case .points: "\(number(value, 0...0)) points"
        case .multiple: "\(number(value, 0...1))×"
        case .tenthsOfASecond: "\(number(value / 10, 1...1)) s"
        case .milliseconds: "\(number(value, 0...0)) ms"
        case .stepsPerSecond: "\(number(value, 0...0)) steps/s"
        case .counts: "\(number(value, 0...0)) counts"
        case .none: number(value, 0...1)
        }
    }
}

/// One smooth-scrolling setting as the window shows it: plain words, a unit, and a slider over values the parser
/// accepts.
enum SmoothKnob: String, CaseIterable, Sendable {
    case speed, startBoost, easeIn, duration, brake, accelerationFrom, accelerationTo, accelerationMax

    static let glide: [SmoothKnob] = [.speed, .startBoost, .easeIn, .duration, .brake]
    static let acceleration: [SmoothKnob] = [.accelerationFrom, .accelerationTo, .accelerationMax]

    var title: String {
        switch self {
        case .speed: "Distance per wheel step"
        case .startBoost: "Extra push on the first step"
        case .easeIn: "Ease into the first step"
        case .duration: "Glide after you stop"
        case .brake: "How hard the glide stops"
        case .accelerationFrom: "Starts speeding up at"
        case .accelerationTo: "Full speed-up at"
        case .accelerationMax: "Up to"
        }
    }

    var detail: String {
        switch self {
        case .speed: "How far one wheel step scrolls while you keep spinning, in points."
        case .startBoost: "How much farther the first step goes when the page is still, as a multiple of the distance per step."
        case .easeIn: "How long the first step takes to reach full speed, in milliseconds. At 0 it starts at full speed."
        case .duration: "How long the page keeps moving after the last wheel step, in seconds."
        case .brake: "At 1 the glide slows evenly. Higher values slow hard at first, then coast to a soft stop."
        case .accelerationFrom: "Spin faster than this many wheel steps per second and each step goes farther."
        case .accelerationTo: "At this many wheel steps per second, each step gets the full extra distance."
        case .accelerationMax: "The most a fast spin multiplies the distance of each step."
        }
    }

    var unit: KnobUnit {
        switch self {
        case .speed: .points
        case .startBoost, .accelerationMax: .multiple
        case .easeIn: .milliseconds
        case .duration: .tenthsOfASecond
        case .brake: .none
        case .accelerationFrom, .accelerationTo: .stepsPerSecond
        }
    }

    /// The key under `scrolling.smooth` in the file, for the log.
    var key: String {
        switch self {
        case .accelerationFrom: "acceleration.from"
        case .accelerationTo: "acceleration.to"
        case .accelerationMax: "acceleration.max"
        default: rawValue
        }
    }

    /// The parser only bounds `from` below and `to` by `from`, so the slider stops at a fast spin's rate.
    static let fastestSpin = 200.0

    func scale(in smooth: SmoothScroll) -> SliderScale {
        let acceleration = smooth.acceleration ?? .default
        let scale =
            switch self {
            case .speed: SliderScale(bounds: SmoothScroll.speedRange, step: 1, curve: .logarithmic)
            case .startBoost: SliderScale(bounds: SmoothScroll.startBoostRange, step: 0.1, curve: .logarithmic)
            case .easeIn: SliderScale(bounds: SmoothScroll.easeInRange, step: 10, curve: .linear)
            case .duration: SliderScale(bounds: SmoothScroll.durationRange, step: 1, curve: .logarithmic)
            case .brake: SliderScale(bounds: SmoothScroll.brakeRange, step: 0.1, curve: .logarithmic)
            case .accelerationFrom:
                SliderScale(bounds: 0...max(0, acceleration.to - 1), step: 1, curve: .logarithmic)
            case .accelerationTo:
                SliderScale(
                    bounds: (acceleration.from + 1)...max(acceleration.from + 1, Self.fastestSpin), step: 1,
                    curve: .logarithmic)
            case .accelerationMax: SliderScale(bounds: 1...10, step: 0.1, curve: .logarithmic)
            }
        return scale.including(value(in: smooth))
    }

    func value(in smooth: SmoothScroll) -> Double {
        let acceleration = smooth.acceleration ?? .default
        return switch self {
        case .speed: smooth.speed
        case .startBoost: smooth.startBoost
        case .easeIn: smooth.easeIn
        case .duration: smooth.duration
        case .brake: smooth.brake
        case .accelerationFrom: acceleration.from
        case .accelerationTo: acceleration.to
        case .accelerationMax: acceleration.max
        }
    }

    /// An acceleration knob changes nothing while acceleration is off.
    func setting(_ value: Double, in smooth: SmoothScroll) -> SmoothScroll {
        var smooth = smooth
        switch self {
        case .speed: smooth.speed = value
        case .startBoost: smooth.startBoost = value
        case .easeIn: smooth.easeIn = value
        case .duration: smooth.duration = value
        case .brake: smooth.brake = value
        case .accelerationFrom: smooth.acceleration?.from = value
        case .accelerationTo: smooth.acceleration?.to = value
        case .accelerationMax: smooth.acceleration?.max = value
        }
        return smooth
    }
}

enum GestureKnob {
    static let title = "Distance before a swipe"
    static let detail = "How far you move while holding the button before a hold-and-move rule fires, in mouse sensor counts."
    static let unit = KnobUnit.counts

    static func scale(for distance: Int) -> SliderScale {
        let range = GestureSettings.distanceRange
        return SliderScale(bounds: Double(range.lowerBound)...Double(range.upperBound), step: 10, curve: .logarithmic)
            .including(Double(distance))
    }
}
