/// A gesture control as a pure machine with no clock. The plan is captured at press, so a config edit cannot change
/// a gesture in flight.
///
/// `pastDistance` fires on the move that makes net travel reach `distance`. `onRelease` decides at release. The
/// two differ on a path that turns back: right 200 then left 300 fires right in the first mode and left in the
/// second.
struct GestureMachine: Sendable {
    enum Input: Sendable {
        case press(GesturePlan)
        case move(dx: Int, dy: Int)
        case release
        /// Device removal and every apply. Fires nothing.
        case cancel
    }

    private enum State: Sendable {
        case idle
        case tracking(GesturePlan, dx: Int, dy: Int)
        /// This hold fired, or crossed `distance` toward a direction with no rule. Its release is not a click.
        case consumed
    }

    private var state = State.idle

    mutating func step(_ input: Input) -> Action? {
        switch (state, input) {
        case (_, .press(let plan)):
            // A press while tracking means the release was lost, so the old hold is dropped.
            state = .tracking(plan, dx: 0, dy: 0)
            return nil
        case (_, .cancel):
            state = .idle
            return nil
        case (.tracking(let plan, let x, let y), .move(let dx, let dy)):
            let (x, y) = (x + dx, y + dy)
            if plan.fire == .pastDistance, let direction = Self.direction(x, y, distance: plan.distance) {
                state = .consumed
                return plan.swipes[direction]
            }
            state = .tracking(plan, dx: x, dy: y)
            return nil
        case (.tracking(let plan, let x, let y), .release):
            state = .idle
            guard let direction = Self.direction(x, y, distance: plan.distance) else { return plan.click }
            return plan.swipes[direction]
        case (.consumed, .release):
            state = .idle
            return nil
        case (.idle, .move), (.idle, .release), (.consumed, .move):
            return nil
        }
    }

    /// The dominant axis of net travel once it reaches `distance`. Positive dy is down. A tie goes to the
    /// horizontal axis, because switching Spaces is the common swipe.
    static func direction(_ dx: Int, _ dy: Int, distance: Int) -> Direction? {
        guard max(abs(dx), abs(dy)) >= distance else { return nil }
        return abs(dx) >= abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
    }
}

struct GesturePlan: Equatable, Sendable {
    var fire: GestureFire
    /// Net movement in sensor counts.
    var distance: Int
    var click: Action?
    var swipes: [Direction: Action]
}
