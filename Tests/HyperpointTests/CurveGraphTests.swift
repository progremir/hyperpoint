import Foundation
import HyperpointKit
import Testing

@testable import Hyperpoint

private let graph = CurveGraph(size: CGSize(width: 600, height: 300))
private let english = Locale(identifier: "en_US")

private func curve(_ pairs: [(Double, Double)]) throws -> SpeedCurve {
    try SpeedCurve(pairs.map { SpeedCurve.Point(stepsPerSecond: $0, pointsPerSecond: $1) })
}

private func valid(_ curve: SpeedCurve) -> Bool { SpeedCurve.problem(with: curve.points) == nil }

@Suite struct CurveGraphTests {
    @Test func theAxesSpanTheRangesALogStepApart() {
        #expect(graph.x(1) == 0)
        #expect(abs(graph.x(150) - 600) < 1e-9)
        #expect(abs(graph.y(10) - 300) < 1e-9, "slow speeds at the bottom")
        #expect(abs(graph.y(30_000)) < 1e-9)
        #expect(abs((graph.x(10) - graph.x(1)) - (graph.x(100) - graph.x(10))) < 1e-9, "each tenfold step is as wide")
        let point = SpeedCurve.Point(stepsPerSecond: 15, pointsPerSecond: 900)
        let back = graph.point(at: graph.position(of: point))
        #expect(abs(back.stepsPerSecond - 15) < 1e-9 && abs(back.pointsPerSecond - 900) < 1e-6)
    }

    @Test func aPointIsFoundNearWhereItIsDrawn() {
        let position = graph.position(of: SpeedCurve.default.points[2])
        #expect(graph.pointIndex(near: CGPoint(x: position.x + 4, y: position.y - 3), in: .default) == 2)
        #expect(graph.pointIndex(near: CGPoint(x: position.x + 40, y: position.y), in: .default) == nil)
    }

    @Test func draggingAnywhereLeavesAValidCurve() {
        for index in SpeedCurve.default.points.indices {
            for x in stride(from: -50.0, through: 650, by: 25) {
                for y in stride(from: -50.0, through: 350, by: 25) {
                    let dragged = CurveGraph.dragging(.default, point: index, to: graph.point(at: CGPoint(x: x, y: y)))
                    #expect(valid(dragged), "point \(index) to (\(x), \(y))")
                    let others = dragged.points.indices.filter { $0 != index }
                    #expect(others.allSatisfy { dragged.points[$0] == SpeedCurve.default.points[$0] }, "only the dragged point moves")
                }
            }
        }
    }

    @Test func aDragGoesWhereThePointerIsBetweenTheNeighbours() {
        let dragged = CurveGraph.dragging(.default, point: 2, to: SpeedCurve.Point(stepsPerSecond: 10, pointsPerSecond: 600))
        #expect(dragged.points[2] == SpeedCurve.Point(stepsPerSecond: 10, pointsPerSecond: 600))
    }

    @Test func aDragStopsAtItsNeighbours() {
        let points = SpeedCurve.default.points
        let up = CurveGraph.dragging(.default, point: 2, to: SpeedCurve.Point(stepsPerSecond: 15, pointsPerSecond: 20_000))
        #expect(up.points[2].pointsPerSecond == points[3].pointsPerSecond, "no faster than the next point")
        let down = CurveGraph.dragging(.default, point: 2, to: SpeedCurve.Point(stepsPerSecond: 15, pointsPerSecond: 10))
        #expect(down.points[2].pointsPerSecond == points[1].pointsPerSecond, "no slower than the point before")
        let left = CurveGraph.dragging(.default, point: 2, to: SpeedCurve.Point(stepsPerSecond: 2, pointsPerSecond: 900))
        #expect(left.points[2].stepsPerSecond > points[1].stepsPerSecond)
        let right = CurveGraph.dragging(.default, point: 4, to: SpeedCurve.Point(stepsPerSecond: 400, pointsPerSecond: 9000))
        #expect(right.points[4].stepsPerSecond == 150)
    }

    @Test func draggedValuesRoundForTheFile() {
        let dragged = CurveGraph.dragging(.default, point: 2, to: SpeedCurve.Point(stepsPerSecond: 13.4567, pointsPerSecond: 812.345))
        #expect(dragged.points[2] == SpeedCurve.Point(stepsPerSecond: 13, pointsPerSecond: 812))
        let slow = CurveGraph.dragging(.default, point: 0, to: SpeedCurve.Point(stepsPerSecond: 1.2345, pointsPerSecond: 37.6))
        #expect(slow.points[0] == SpeedCurve.Point(stepsPerSecond: 1.2, pointsPerSecond: 38))
    }

    @Test func aPointAddedOnTheLineKeepsTheCurve() throws {
        let added = try #require(CurveGraph.adding(.default, at: 9))
        #expect(added.points.count == SpeedCurve.default.points.count + 1)
        #expect(added.points.contains { $0.stepsPerSecond == 9 })
        #expect(valid(added))
        for rate in [2.0, 9, 12, 30, 100] {
            #expect(abs(added.pointsPerSecond(at: rate) / SpeedCurve.default.pointsPerSecond(at: rate) - 1) < 0.01)
        }
        #expect(CurveGraph.adding(.default, at: 15.5) == nil, "too close to the point at 15")
    }

    @Test func aCurveKeepsTwoPointsAndAtMostTen() throws {
        let two = try curve([(1, 40), (150, 9000)])
        #expect(CurveGraph.removing(two, point: 0) == nil)
        #expect(CurveGraph.removing(.default, point: 2)?.points.count == 4)
        var many = two
        for rate in [2.0, 3, 5, 8, 12, 20, 35, 60, 100] { many = CurveGraph.adding(many, at: rate) ?? many }
        #expect(many.points.count == CurveGraph.mostPoints)
    }

    @Test func theReadoutGivesSpeedAndDistancePerStep() throws {
        let tenfold = try curve([(1, 40), (10, 900), (100, 9000)])
        #expect(CurveGraph.readout(tenfold, at: 10, locale: english) == "at 10 steps/s: 900 pt/s, 90 pt per step")
        #expect(CurveGraph.readout(.default, at: 1, locale: english) == "at 1 steps/s: 40 pt/s, 40 pt per step")
        #expect(CurveGraph.readout(tenfold, at: 100, locale: english) == "at 100 steps/s: 9,000 pt/s, 90 pt per step")
    }

    @Test func theMeasuredBandsSitInsideTheAxis() {
        for band in CurveGraph.bands {
            #expect(CurveGraph.rates.contains(band.rates.lowerBound) && CurveGraph.rates.contains(band.rates.upperBound))
        }
    }
}
