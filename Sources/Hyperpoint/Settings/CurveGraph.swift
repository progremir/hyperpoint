import Foundation
import HyperpointKit

/// The speed graph's geometry and edits. Both axes are logarithmic, the same axes the curve is straight on, so the
/// drawn line is exactly what the wheel does. Every edit returns a curve the parser accepts.
struct CurveGraph {
    static let rates = SpeedCurve.stepsPerSecondRange
    static let speeds = SpeedCurve.pointsPerSecondRange
    /// Neighbouring points stay at least this far apart, as a ratio of spin rates, so each stays easy to grab.
    static let closest = 1.08
    static let mostPoints = 10

    /// The MX wheel's spin rates, measured on this Mac.
    static let bands: [(label: String, rates: ClosedRange<Double>)] = [
        ("slow 4–12", 4...12), ("medium 15–17", 15...17), ("fast ~36", 33...40), ("flick ~120", 110...150),
    ]
    static let rateTicks: [Double] = [1, 2, 5, 10, 20, 50, 100, 150]
    static let speedTicks: [Double] = [10, 100, 1000, 10_000]

    var size: CGSize

    func x(_ rate: Double) -> CGFloat { size.width * Self.along(rate, Self.rates) }
    func y(_ speed: Double) -> CGFloat { size.height * (1 - Self.along(speed, Self.speeds)) }
    func position(of point: SpeedCurve.Point) -> CGPoint { CGPoint(x: x(point.stepsPerSecond), y: y(point.pointsPerSecond)) }

    func point(at position: CGPoint) -> SpeedCurve.Point {
        SpeedCurve.Point(
            stepsPerSecond: Self.value(at: position.x / size.width, Self.rates),
            pointsPerSecond: Self.value(at: 1 - position.y / size.height, Self.speeds))
    }

    /// The point within `radius` of `position`, nearest first.
    func pointIndex(near position: CGPoint, in curve: SpeedCurve, radius: CGFloat = 10) -> Int? {
        let distances = curve.points.map { hypot(self.position(of: $0).x - position.x, self.position(of: $0).y - position.y) }
        guard let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }), distances[nearest] <= radius
        else { return nil }
        return nearest
    }

    private static func along(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        log(value / range.lowerBound) / log(range.upperBound / range.lowerBound)
    }

    private static func value(at share: Double, _ range: ClosedRange<Double>) -> Double {
        range.lowerBound * pow(range.upperBound / range.lowerBound, min(max(share, 0), 1))
    }
}

extension CurveGraph {
    /// Point `index` moved as close to `target` as its neighbours allow: its rate stays between theirs, and its speed
    /// no lower than the one before and no higher than the one after. Values round so the file stays readable.
    static func dragging(_ curve: SpeedCurve, point index: Int, to target: SpeedCurve.Point) -> SpeedCurve {
        var points = curve.points
        let before = index > 0 ? points[index - 1] : nil
        let after = index < points.count - 1 ? points[index + 1] : nil
        let lowestRate = before.map { $0.stepsPerSecond * closest } ?? rates.lowerBound
        let highestRate = after.map { $0.stepsPerSecond / closest } ?? rates.upperBound
        let rate =
            lowestRate <= highestRate
            ? rounded(rate: min(max(target.stepsPerSecond, lowestRate), highestRate)) : points[index].stepsPerSecond
        let lowestSpeed = before?.pointsPerSecond ?? speeds.lowerBound
        let highestSpeed = after?.pointsPerSecond ?? speeds.upperBound
        let speed = min(max(rounded(speed: target.pointsPerSecond), lowestSpeed), highestSpeed)
        points[index] = SpeedCurve.Point(stepsPerSecond: rate, pointsPerSecond: speed)
        return (try? SpeedCurve(points)) ?? curve
    }

    /// A new point on the line at `rate`, so the curve is unchanged until it is dragged. Nil when the graph is full or
    /// a point is already that close.
    static func adding(_ curve: SpeedCurve, at rate: Double) -> SpeedCurve? {
        let rate = rounded(rate: min(max(rate, rates.lowerBound), rates.upperBound))
        guard curve.points.count < mostPoints,
            curve.points.allSatisfy({ max($0.stepsPerSecond, rate) / min($0.stepsPerSecond, rate) >= closest })
        else { return nil }
        var points = curve.points
        let index = points.firstIndex { $0.stepsPerSecond > rate } ?? points.endIndex
        let before = index > 0 ? points[index - 1].pointsPerSecond : speeds.lowerBound
        let after = index < points.count ? points[index].pointsPerSecond : speeds.upperBound
        let speed = min(max(rounded(speed: curve.pointsPerSecond(at: rate)), before), after)
        points.insert(SpeedCurve.Point(stepsPerSecond: rate, pointsPerSecond: speed), at: index)
        return try? SpeedCurve(points)
    }

    /// Nil when only two points are left, the fewest a curve has.
    static func removing(_ curve: SpeedCurve, point index: Int) -> SpeedCurve? {
        var points = curve.points
        points.remove(at: index)
        return try? SpeedCurve(points)
    }

    /// Below 10 steps per second to a tenth, above that to a whole step.
    static func rounded(rate: Double) -> Double { rate < 10 ? (rate * 10).rounded() / 10 : rate.rounded() }

    /// To 3 significant digits, and below 100 to a whole point a second.
    static func rounded(speed: Double) -> Double {
        guard speed >= 100 else { return speed.rounded() }
        let unit = pow(10, floor(log10(speed)) - 2)
        return (speed / unit).rounded() * unit
    }
}

extension CurveGraph {
    /// "at 10 steps/s: 900 pt/s, 90 pt per step"
    static func readout(_ curve: SpeedCurve, at rate: Double, locale: Locale = .current) -> String {
        let speed = curve.pointsPerSecond(at: rate)
        let step = curve.distancePerStep(at: rate)
        return "at \(rateText(rate, locale: locale)) steps/s: \(number(speed, locale: locale)) pt/s, \(number(step, locale: locale)) pt per step"
    }

    static func rateText(_ rate: Double, locale: Locale = .current) -> String {
        rate.formatted(.number.locale(locale).precision(.fractionLength(rate < 10 && rate != rate.rounded() ? 1 : 0)))
    }

    static func number(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(value < 10 && value != value.rounded() ? 1 : 0)))
    }
}
