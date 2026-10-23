import Foundation

/// How fast the page scrolls for how fast the wheel spins. Points are joined by straight lines on log-log axes, so
/// each segment is a power law, and a fixed distance per step stays exact between points. Beyond the ends the speed
/// stays flat.
public struct SpeedCurve: Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public var stepsPerSecond: Double
        public var pointsPerSecond: Double

        public init(stepsPerSecond: Double, pointsPerSecond: Double) {
            self.stepsPerSecond = stepsPerSecond
            self.pointsPerSecond = pointsPerSecond
        }
    }

    /// Why a list of points is not a curve. `index` and `key` name the point and field, when there is one.
    public struct Problem: Error, Equatable, Sendable {
        public var index: Int?
        public var key: String?
        public var message: String
    }

    /// At least two, spin rates strictly increasing, speeds never falling.
    public let points: [Point]

    public static let stepsPerSecondRange: ClosedRange<Double> = 1...150
    public static let pointsPerSecondRange: ClosedRange<Double> = 10...30_000

    /// From the MX wheel's measured rates: a single step scrolls 40 points, and each step goes a little farther the
    /// faster the wheel spins, 60 points at 15 steps per second and 75 at 120.
    public static let `default` = SpeedCurve(checked: [(1, 40), (5, 250), (15, 900), (40, 2800), (120, 9000)])

    public init(_ points: [Point]) throws(Problem) {
        if let problem = Self.problem(with: points) { throw problem }
        self.points = points
    }

    init(checked pairs: [(Double, Double)]) {
        points = pairs.map { Point(stepsPerSecond: $0, pointsPerSecond: $1) }
        precondition(Self.problem(with: points) == nil, "\(pairs) is not a curve")
    }

    public static func problem(with points: [Point]) -> Problem? {
        guard points.count >= 2 else { return Problem(message: "needs at least 2 points") }
        let rates = stepsPerSecondRange
        let speeds = pointsPerSecondRange
        for (index, point) in points.enumerated() {
            if !rates.contains(point.stepsPerSecond) {
                return Problem(index: index, key: "stepsPerSecond", message: Self.between(rates))
            }
            if !speeds.contains(point.pointsPerSecond) {
                return Problem(index: index, key: "pointsPerSecond", message: Self.between(speeds))
            }
            guard index > 0 else { continue }
            if point.stepsPerSecond <= points[index - 1].stepsPerSecond {
                return Problem(index: index, key: "stepsPerSecond", message: "must be more than the point before")
            }
            if point.pointsPerSecond < points[index - 1].pointsPerSecond {
                return Problem(index: index, key: "pointsPerSecond", message: "must be at least the point before")
            }
        }
        return nil
    }

    private static func between(_ range: ClosedRange<Double>) -> String {
        String(format: "must be between %g and %g", range.lowerBound, range.upperBound)
    }

    /// The slowest spin the curve names. A step after a pause counts as this rate.
    public var slowest: Double { points[0].stepsPerSecond }

    public func pointsPerSecond(at rate: Double) -> Double {
        guard let above = points.firstIndex(where: { $0.stepsPerSecond > rate }) else { return points.last!.pointsPerSecond }
        guard above > 0 else { return points[0].pointsPerSecond }
        let low = points[above - 1]
        let high = points[above]
        let along = log(rate / low.stepsPerSecond) / log(high.stepsPerSecond / low.stepsPerSecond)
        return low.pointsPerSecond * pow(high.pointsPerSecond / low.pointsPerSecond, along)
    }

    /// How far one step goes at `rate`, so that steps at that rate scroll at the curve's speed. A step slower than the
    /// first point goes as far as one at the first point, never farther.
    public func distancePerStep(at rate: Double) -> Double {
        let rate = max(rate, slowest)
        return pointsPerSecond(at: rate) / rate
    }
}

extension SpeedCurve: Codable {
    public init(from decoder: any Decoder) throws {
        let points = try decoder.singleValueContainer().decode([Point].self)
        do {
            try self.init(points)
        } catch {
            let path = decoder.codingPath + [error.index.map(PathKey.init(index:)), error.key.map(PathKey.init(key:))].compactMap { $0 }
            throw DecodingError.dataCorrupted(.init(codingPath: path, debugDescription: error.message))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(points)
    }
}

private struct PathKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(key: String) { stringValue = key }
    init(index: Int) {
        stringValue = "\(index)"
        intValue = index
    }
    init?(stringValue: String) { self.init(key: stringValue) }
    init?(intValue: Int) { self.init(index: intValue) }
}
