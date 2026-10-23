import Foundation
import HyperpointKit
import Testing

private func curve(_ pairs: [(Double, Double)]) throws -> SpeedCurve {
    try SpeedCurve(pairs.map { SpeedCurve.Point(stepsPerSecond: $0, pointsPerSecond: $1) })
}

private func problem(_ pairs: [(Double, Double)]) -> SpeedCurve.Problem? {
    SpeedCurve.problem(with: pairs.map { SpeedCurve.Point(stepsPerSecond: $0, pointsPerSecond: $1) })
}

private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 * max(abs(a), abs(b)) }

@Suite struct SpeedCurveTests {
    @Test func itPassesThroughItsPoints() throws {
        let speeds = try curve([(1, 40), (5, 250), (15, 900)])
        #expect(close(speeds.pointsPerSecond(at: 1), 40))
        #expect(close(speeds.pointsPerSecond(at: 5), 250))
        #expect(close(speeds.pointsPerSecond(at: 15), 900))
    }

    @Test func betweenPointsItIsAStraightLineOnLogLogAxes() throws {
        let speeds = try curve([(2, 100), (8, 1600)])
        #expect(close(speeds.pointsPerSecond(at: 4), 400), "halfway on a log axis is the geometric mean")
        #expect(close(speeds.pointsPerSecond(at: 2 * pow(4, 0.25)), 100 * pow(16, 0.25)))
    }

    @Test func aFixedDistancePerStepStaysExactBetweenPoints() throws {
        let sixtyPerStep = try curve([(1, 60), (150, 9000)])
        for rate in [1.0, 2, 7.5, 37, 100, 150] {
            #expect(close(sixtyPerStep.distancePerStep(at: rate), 60), "\(rate) steps/s")
        }
    }

    @Test func beyondTheEndsTheSpeedIsFlat() throws {
        let speeds = try curve([(2, 100), (40, 2800)])
        #expect(speeds.pointsPerSecond(at: 60) == 2800)
        #expect(speeds.pointsPerSecond(at: 1000) == 2800)
        #expect(speeds.pointsPerSecond(at: 1) == 100)
        #expect(close(speeds.distancePerStep(at: 80), 35), "a faster spin past the end keeps the top speed")
        #expect(speeds.distancePerStep(at: 0.5) == 50, "a step slower than the first point goes as far as one at it")
        #expect(speeds.distancePerStep(at: 0.5) == speeds.distancePerStep(at: speeds.slowest))
    }

    @Test func theDefaultStartsGentleAndGoesFartherPerStepTheFasterYouSpin() {
        let speeds = SpeedCurve.default
        #expect(speeds.distancePerStep(at: speeds.slowest) == 40)
        let rates = stride(from: 1.0, through: speeds.points.last!.stepsPerSecond, by: 0.5).map { $0 }
        let distances = rates.map(speeds.distancePerStep)
        #expect(zip(distances, distances.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 }, "up to the last point, distance per step never falls")
        #expect(distances.max()! < 2 * distances.min()!, "speed grows close to linearly with the spin")
    }

    @Test func aCurveNeedsTwoPointsInOrderWithSpeedsThatNeverFall() {
        #expect(problem([(1, 40)]) != nil)
        #expect(problem([(1, 40)])?.index == nil, "the whole list is at fault")
        #expect(problem([(5, 40), (5, 80)])?.index == 1)
        #expect(problem([(5, 40), (5, 80)])?.key == "stepsPerSecond")
        #expect(problem([(5, 40), (2, 80)])?.key == "stepsPerSecond")
        #expect(problem([(1, 80), (5, 40)])?.index == 1)
        #expect(problem([(1, 80), (5, 40)])?.key == "pointsPerSecond")
        #expect(problem([(1, 80), (5, 80)]) == nil, "a flat stretch is allowed")
    }

    @Test func pointsStayInsideTheGraphsRange() {
        #expect(problem([(0.5, 40), (5, 80)])?.index == 0)
        #expect(problem([(0.5, 40), (5, 80)])?.key == "stepsPerSecond")
        #expect(problem([(1, 40), (151, 80)])?.index == 1)
        #expect(problem([(1, 5), (5, 80)])?.key == "pointsPerSecond")
        #expect(problem([(1, 40), (5, 30_001)])?.key == "pointsPerSecond")
        #expect(problem([(1, 10), (150, 30_000)]) == nil)
    }

    @Test func itDecodesAsAListOfPointsAndNamesTheBadOne() throws {
        let json = #"[{"stepsPerSecond": 1, "pointsPerSecond": 40}, {"stepsPerSecond": 10, "pointsPerSecond": 900}]"#
        let decoded = try JSONDecoder().decode(SpeedCurve.self, from: Data(json.utf8))
        #expect(decoded == (try curve([(1, 40), (10, 900)])))
        #expect(try JSONDecoder().decode(SpeedCurve.self, from: JSONEncoder().encode(SpeedCurve.default)) == .default)

        let falling = #"[{"stepsPerSecond": 1, "pointsPerSecond": 40}, {"stepsPerSecond": 10, "pointsPerSecond": 30}]"#
        #expect {
            try JSONDecoder().decode(SpeedCurve.self, from: Data(falling.utf8))
        } throws: { error in
            guard case DecodingError.dataCorrupted(let context) = error else { return false }
            return context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue } == ["1", "pointsPerSecond"]
        }
    }
}
