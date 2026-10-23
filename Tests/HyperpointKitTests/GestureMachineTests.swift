@testable import HyperpointKit
import Testing

private func plan(_ fire: GestureFire) -> GesturePlan {
    GesturePlan(
        fire: fire, distance: 100, click: .system(.missionControl),
        swipes: [.down: .system(.appExpose), .left: .system(.spaceLeft), .right: .system(.spaceRight)])
}

/// The thirteen traces of the gesture prototype, then cancel.
@Suite struct GestureMachineTests {
    @Test(arguments: [GestureFire.pastDistance, .onRelease])
    func movementBelowTheDistanceIsAClick(_ fire: GestureFire) {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(fire)))
        _ = machine.step(.move(dx: 10, dy: -8))
        #expect(machine.step(.release) == .system(.missionControl))
    }

    @Test func pastDistanceFiresOnTheCrossingMoveOnly() {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(.pastDistance)))
        #expect(machine.step(.move(dx: 0, dy: 60)) == nil, "below the distance nothing fires")
        #expect(machine.step(.move(dx: 0, dy: 60)) == .system(.appExpose), "the crossing move fires")
        #expect(machine.step(.move(dx: 0, dy: 300)) == nil, "later moves are silent")
        #expect(machine.step(.release) == nil, "the release after a fire is silent")
    }

    @Test func onReleaseDecidesAtRelease() {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(.onRelease)))
        #expect(machine.step(.move(dx: -150, dy: 5)) == nil, "silent while held")
        #expect(machine.step(.release) == .system(.spaceLeft))
    }

    @Test func aSwipeWithNoRuleIsConsumed() {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(.pastDistance)))
        #expect(machine.step(.move(dx: 0, dy: -200)) == nil, "up has no rule")
        #expect(machine.step(.release) == nil, "and its release is not a click")
    }

    @Test func aPressWhileTrackingStartsOver() {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(.onRelease)))
        _ = machine.step(.move(dx: 500, dy: 0))
        _ = machine.step(.press(plan(.onRelease)))
        #expect(machine.step(.release) == .system(.missionControl), "the lost release drops the old travel")
    }

    @Test func thePlanIsCapturedAtPress() {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(.onRelease)))
        #expect(machine.step(.move(dx: 0, dy: 500)) == nil, "the press-time mode holds, so nothing fires mid-hold")
        #expect(machine.step(.release) == .system(.appExpose))
    }

    @Test func aPathThatTurnsBackDiffersByMode() {
        var past = GestureMachine()
        _ = past.step(.press(plan(.pastDistance)))
        #expect(past.step(.move(dx: 200, dy: 0)) == .system(.spaceRight))
        #expect(past.step(.move(dx: -300, dy: 0)) == nil)

        var release = GestureMachine()
        _ = release.step(.press(plan(.onRelease)))
        _ = release.step(.move(dx: 200, dy: 0))
        _ = release.step(.move(dx: -300, dy: 0))
        #expect(release.step(.release) == .system(.spaceLeft))
    }

    @Test(arguments: [GestureFire.pastDistance, .onRelease])
    func cancelFiresNothing(_ fire: GestureFire) {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(fire)))
        _ = machine.step(.move(dx: 0, dy: 40))
        #expect(machine.step(.cancel) == nil)
        #expect(machine.step(.move(dx: 0, dy: 400)) == nil, "moves after cancel are ignored")
        #expect(machine.step(.release) == nil, "a release after cancel is not a click")
    }
}
