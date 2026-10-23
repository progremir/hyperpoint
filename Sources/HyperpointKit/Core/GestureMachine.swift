struct GestureMachine: Sendable {
    enum Input: Sendable {
        case press(GesturePlan)
        /// In the control's own unit: sensor counts for HID++ raw movement, points for pointer drags.
        case move(dx: Double, dy: Double)
        case release
        case cancel
    }

    enum Output: Equatable, Sendable {
        /// A release before the movement reached the distance, with the plan's click action if it has one.
        case click(Action?)
        case perform(Action)
        case scroll(HoldScrollEvent)
    }

    private enum State: Sendable {
        case idle
        case tracking(GesturePlan, dx: Double, dy: Double)
        case consumed
        case scrolling(HoldScrollPlan)
    }

    private var state = State.idle

    mutating func step(_ input: Input) -> Output? {
        switch (state, input) {
        case (.scrolling, .press(let plan)):
            state = .tracking(plan, dx: 0, dy: 0)
            return .scroll(.ended)
        case (.scrolling, .cancel), (.scrolling, .release):
            state = .idle
            return .scroll(.ended)
        case (_, .press(let plan)):
            state = .tracking(plan, dx: 0, dy: 0)
            return nil
        case (_, .cancel):
            state = .idle
            return nil
        case (.tracking(let plan, let x, let y), .move(let dx, let dy)):
            let (x, y) = (x + dx, y + dy)
            switch plan.moves {
            case .scroll(let scroll) where max(abs(x), abs(y)) >= plan.distance:
                state = .scrolling(scroll)
                return .scroll(.began(scroll))
            case .swipes(let swipes, .pastDistance):
                if let direction = Self.direction(x, y, distance: plan.distance) {
                    state = .consumed
                    return swipes[direction].map(Output.perform)
                }
            case .swipes(_, .onRelease), .scroll:
                break
            }
            state = .tracking(plan, dx: x, dy: y)
            return nil
        case (.tracking(let plan, let x, let y), .release):
            state = .idle
            if case .swipes(let swipes, _) = plan.moves, let direction = Self.direction(x, y, distance: plan.distance) {
                return swipes[direction].map(Output.perform)
            }
            return .click(plan.click)
        case (.scrolling(let scroll), .move(let dx, let dy)):
            return .scroll(.moved(dx: dx * scroll.gain, dy: dy * scroll.gain))
        case (.consumed, .release):
            state = .idle
            return nil
        case (.idle, .move), (.idle, .release), (.consumed, .move):
            return nil
        }
    }

    static func direction(_ dx: Double, _ dy: Double, distance: Double) -> Direction? {
        guard max(abs(dx), abs(dy)) >= distance else { return nil }
        return abs(dx) >= abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
    }
}

struct GesturePlan: Equatable, Sendable {
    /// Movement past this, in the control's own unit, makes the hold a swipe or a scroll instead of a click.
    var distance: Double
    var click: Action?
    var moves: GestureMoves
}

/// What moving past the distance does. One control cannot do both, because both read the same movement.
enum GestureMoves: Equatable, Sendable {
    case swipes([Direction: Action], fire: GestureFire)
    case scroll(HoldScrollPlan)
}
