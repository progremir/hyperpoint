import Foundation
import HyperpointKit

/// Maps a slider's position, 0 to 1, to a value and back. A logarithmic curve gives small values the same room as
/// large ones, so a 0.4 s glide sits near mid-slider on a 0.1 to 2 s range instead of near its left end.
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
}

enum KnobUnit: Equatable {
    /// Stored in tenths of a second and shown in seconds.
    case tenthsOfASecond
    case milliseconds
    case counts
    /// A multiplier, shown as 1.25×.
    case times
    case none

    func format(_ value: Double, locale: Locale = .current) -> String {
        let number = { (value: Double, fraction: ClosedRange<Int>) in
            value.formatted(.number.locale(locale).precision(.fractionLength(fraction)))
        }
        return switch self {
        case .tenthsOfASecond: "\(number(value / 10, 1...1)) s"
        case .milliseconds: "\(number(value, 0...0)) ms"
        case .counts: "\(number(value, 0...0)) counts"
        case .times: "\(number(value, 1...2))×"
        case .none: number(value, 0...1)
        }
    }
}

/// One glide setting as the window shows it: plain words, a unit, and a slider over values the parser accepts.
enum SmoothKnob: String, CaseIterable, Sendable {
    case duration, brake, easeIn

    var title: String {
        switch self {
        case .duration: "Glide after you stop"
        case .brake: "How hard the glide stops"
        case .easeIn: "Ease into each step"
        }
    }

    var detail: String {
        switch self {
        case .duration: "How long the page keeps moving after the last wheel step, in seconds."
        case .brake: "At 1 the glide slows evenly. Higher values slow hard at first, then coast to a soft stop."
        case .easeIn:
            "How long a wheel step takes to reach full speed, in milliseconds, so the page never jumps from rest. At 0 a step starts at full speed."
        }
    }

    var unit: KnobUnit {
        switch self {
        case .duration: .tenthsOfASecond
        case .brake: .none
        case .easeIn: .milliseconds
        }
    }

    /// The key under `scrolling.smooth` in the file, for the log.
    var key: String { rawValue }

    var scale: SliderScale {
        switch self {
        case .duration: SliderScale(bounds: SmoothScroll.durationRange, step: 1, curve: .logarithmic)
        case .brake: SliderScale(bounds: SmoothScroll.brakeRange, step: 0.1, curve: .logarithmic)
        case .easeIn: SliderScale(bounds: SmoothScroll.easeInRange, step: 10, curve: .linear)
        }
    }

    func value(in smooth: SmoothScroll) -> Double {
        switch self {
        case .duration: smooth.duration
        case .brake: smooth.brake
        case .easeIn: smooth.easeIn
        }
    }

    func setting(_ value: Double, in smooth: SmoothScroll) -> SmoothScroll {
        var smooth = smooth
        switch self {
        case .duration: smooth.duration = value
        case .brake: smooth.brake = value
        case .easeIn: smooth.easeIn = value
        }
        return smooth
    }
}

enum HoldScrollKnob {
    static let title = "Scroll speed"
    static let detail = "How far the page moves for how far you move the mouse. At 1× it follows your hand."
    static let unit = KnobUnit.times
    static let scale = SliderScale(bounds: HoldToScroll.speedRange, step: 0.05, curve: .logarithmic)
}

enum GestureKnob {
    static let title = "Distance before a swipe"
    static let detail = "How far you move while holding the button before a hold-and-move rule fires, in mouse sensor counts."
    static let unit = KnobUnit.counts

    static let scale = SliderScale(
        bounds: Double(GestureSettings.distanceRange.lowerBound)...Double(GestureSettings.distanceRange.upperBound),
        step: 10, curve: .logarithmic)
}
