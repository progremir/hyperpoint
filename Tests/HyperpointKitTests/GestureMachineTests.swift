@testable import HyperpointKit
import Testing

private func plan(_ fire: GestureFire) -> GesturePlan {
    GesturePlan(
        distance: 100, click: .system(.missionControl),
        moves: .swipes([.down: .system(.appExpose), .left: .system(.spaceLeft), .right: .system(.spaceRight)], fire: fire))
}

private func scrolling(_ direction: HoldScrollDirection = .grab, click: Action? = nil) -> GesturePlan {
    GesturePlan(
        distance: 100, click: click,
        moves: .scroll(
            HoldScrollPlan(HoldToScroll(speed: 1.5, direction: direction, momentum: true), glide: .default, pointsPerUnit: 2)))
}

private let shot = Action.shortcut(Chord(key: KeyCode(name: "4")!, modifiers: [.shift, .command]))

@Suite struct GestureMachineTests {
    @Test(arguments: [GestureFire.pastDistance, .onRelease])
    func movementBelowTheDistanceIsAClick(_ fire: GestureFire) {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(fire)))
        _ = machine.step(.move(dx: 10, dy: -8))
        #expect(machine.step(.release) == .click(.system(.missionControl)))
    }

    @Test func pastDistanceFiresOnTheCrossingMoveOnly() {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(.pastDistance)))
        #expect(machine.step(.move(dx: 0, dy: 60)) == nil, "below the distance nothing fires")
        #expect(machine.step(.move(dx: 0, dy: 60)) == .perform(.system(.appExpose)), "the crossing move fires")
        #expect(machine.step(.move(dx: 0, dy: 300)) == nil, "later moves are silent")
        #expect(machine.step(.release) == nil, "the release after a fire is silent")
    }

    @Test func onReleaseDecidesAtRelease() {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(.onRelease)))
        #expect(machine.step(.move(dx: -150, dy: 5)) == nil, "silent while held")
        #expect(machine.step(.release) == .perform(.system(.spaceLeft)))
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
        #expect(machine.step(.release) == .click(.system(.missionControl)), "the lost release drops the old travel")
    }

    @Test func thePlanIsCapturedAtPress() {
        var machine = GestureMachine()
        _ = machine.step(.press(plan(.onRelease)))
        #expect(machine.step(.move(dx: 0, dy: 500)) == nil, "the press-time mode holds, so nothing fires mid-hold")
        #expect(machine.step(.release) == .perform(.system(.appExpose)))
    }

    @Test func aPathThatTurnsBackDiffersByMode() {
        var past = GestureMachine()
        _ = past.step(.press(plan(.pastDistance)))
        #expect(past.step(.move(dx: 200, dy: 0)) == .perform(.system(.spaceRight)))
        #expect(past.step(.move(dx: -300, dy: 0)) == nil)

        var release = GestureMachine()
        _ = release.step(.press(plan(.onRelease)))
        _ = release.step(.move(dx: 200, dy: 0))
        _ = release.step(.move(dx: -300, dy: 0))
        #expect(release.step(.release) == .perform(.system(.spaceLeft)))
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

@Suite struct HoldToScrollGestureTests {
    @Test func aShortHoldIsTheClickRuleOrAPlainClick() {
        var withRule = GestureMachine()
        _ = withRule.step(.press(scrolling(click: shot)))
        _ = withRule.step(.move(dx: 60, dy: -70))
        #expect(withRule.step(.release) == .click(shot))

        var plain = GestureMachine()
        _ = plain.step(.press(scrolling()))
        _ = plain.step(.move(dx: 99, dy: 0))
        #expect(plain.step(.release) == .click(nil), "a button with no click rule is still a click")
    }

    @Test func pastTheDistanceTheHandScrollsUntilRelease() throws {
        var machine = GestureMachine()
        let plan = scrolling(click: shot)
        guard case .scroll(let scroll) = plan.moves else { throw Failure() }
        _ = machine.step(.press(plan))
        #expect(machine.step(.move(dx: 0, dy: 60)) == nil)
        #expect(machine.step(.move(dx: 10, dy: 50)) == .scroll(.began(scroll)), "the move that reaches 100 begins")
        #expect(machine.step(.move(dx: 4, dy: -2)) == .scroll(.moved(dx: 12, dy: -6)), "1.5 × 2 points per unit")
        #expect(machine.step(.move(dx: 0, dy: 10)) == .scroll(.moved(dx: 0, dy: 30)))
        #expect(machine.step(.release) == .scroll(.ended), "the release ends the scroll and is not a click")
        #expect(machine.step(.move(dx: 0, dy: 10)) == nil, "moves after the release do nothing")
    }

    @Test func theDirectionSettingFlipsTheSign() {
        func firstScroll(_ direction: HoldScrollDirection) -> GestureMachine.Output? {
            var machine = GestureMachine()
            _ = machine.step(.press(scrolling(direction)))
            _ = machine.step(.move(dx: 0, dy: 120))
            return machine.step(.move(dx: 2, dy: 5))
        }
        #expect(firstScroll(.grab) == .scroll(.moved(dx: 6, dy: 15)), "grabbing moves the page with the hand")
        #expect(firstScroll(.wheel) == .scroll(.moved(dx: -6, dy: -15)), "the wheel way scrolls against it")
    }

    @Test func anInterruptedScrollStillEnds() {
        var cancelled = GestureMachine()
        _ = cancelled.step(.press(scrolling()))
        _ = cancelled.step(.move(dx: -150, dy: 0))
        #expect(cancelled.step(.cancel) == .scroll(.ended), "an apply mid-scroll ends it")
        #expect(cancelled.step(.release) == nil)

        var repressed = GestureMachine()
        _ = repressed.step(.press(scrolling()))
        _ = repressed.step(.move(dx: -150, dy: 0))
        #expect(repressed.step(.press(scrolling(click: shot))) == .scroll(.ended), "a press after a lost release ends it")
        #expect(repressed.step(.release) == .click(shot), "and tracks the new press")
    }
}

private struct Failure: Error {}
