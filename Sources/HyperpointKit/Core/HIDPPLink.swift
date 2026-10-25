struct HIDPPLink: Sendable {
    typealias Instant = ContinuousClock.Instant

    static let replyTimeout: Duration = .seconds(2)
    static let attemptsPerRequest = 3

    private(set) var capabilities: HIDPPCapabilities?
    private var features = FeatureMap()
    /// Nil writes nothing, and the link only learns the controls.
    private var plan: HIDPPSetup?
    private var scheduler = ApplyScheduler()
    private var run: Run?
    private var retryAt: Instant?
    private var held: [CID] = []
    private var gesture = GestureMachine()
    private var gestureControl: CID?

    private struct Run: Sendable {
        let job: ApplyScheduler.Job
        let plan: HIDPPSetup?
        var steps: [HIDPPStep]
        var next = 0
        var inFlight: InFlight?
        var discovery: Discovery?
    }

    private struct Discovery: Sendable {
        var features = FeatureMap()
        var controls: [HIDPPCapabilities.Control] = []

        /// Discovery replies echo nothing, so a late reply to a retried request answers the next request instead.
        /// It then shows up as two features at one index or one control listed twice.
        var isConsistent: Bool {
            let indices = HIDPPFeature.allCases.filter { $0 != .root }.compactMap { features[$0] }
            return Set(indices).count == indices.count && Set(controls.map(\.cid)).count == controls.count
        }
    }

    private struct InFlight: Sendable {
        let step: HIDPPStep
        let featureIndex: UInt8
        var attempts: Int
        var deadline: Instant

        func answers(_ featureIndex: UInt8, _ function: UInt8) -> Bool {
            featureIndex == self.featureIndex && function == step.request.function
        }
    }

    private static let discoverySteps: [HIDPPStep] = [
        .findFeature(.reprogControls), .findFeature(.thumbWheel), .findFeature(.wirelessStatus), .countControls,
    ]

    var isApplying: Bool { scheduler.running }

    var deadline: Instant? {
        switch (run?.inFlight?.deadline, retryAt) {
        case (let reply?, let retry?): min(reply, retry)
        case (let reply, let retry): reply ?? retry
        }
    }

    mutating func request(_ reason: ApplyReason, plan: HIDPPSetup?, now: Instant) -> HIDPPOutput {
        var out = HIDPPOutput()
        self.plan = plan
        request(reason, now: now, into: &out)
        return finished(out)
    }

    mutating func receive(_ report: UnsafeBufferPointer<UInt8>, now: Instant) -> HIDPPOutput {
        var out = HIDPPOutput()
        switch HIDPPInbound(report) {
        case .reply(let featureIndex, let function, let params):
            guard let flight = run?.inFlight, flight.answers(featureIndex, function), flight.step.accepts(params) else {
                break
            }
            run?.inFlight = nil
            replied(flight.step, params, now: now, into: &out)
        case .error(let featureIndex, let function, let code):
            guard let flight = run?.inFlight, flight.answers(featureIndex, function) else { break }
            run?.inFlight = nil
            endRun(.failed(.deviceError(flight.step, code: code)), now: now, into: &out)
        case .notification(let featureIndex, let event):
            guard let feature = features.feature(at: featureIndex),
                let notice = HIDPPNotice(report, feature: feature, event: event)
            else { break }
            handle(notice, now: now, into: &out)
        case .ignored:
            break
        }
        return finished(out)
    }

    /// For a link that is going away. A scroll in progress ends.
    mutating func close() -> HIDPPOutput {
        var out = HIDPPOutput()
        gestureControl = nil
        perform(gesture.step(.cancel), into: &out)
        return out
    }

    mutating func tick(now: Instant) -> HIDPPOutput {
        var out = HIDPPOutput()
        if var flight = run?.inFlight, flight.deadline <= now {
            if flight.attempts < Self.attemptsPerRequest {
                flight.attempts += 1
                flight.deadline = now + Self.replyTimeout
                run?.inFlight = flight
                out.reports.append(flight.step.request.report(featureIndex: flight.featureIndex))
            } else {
                run?.inFlight = nil
                endRun(.failed(.timedOut(flight.step)), now: now, into: &out)
            }
        }
        if let retryAt, retryAt <= now {
            self.retryAt = nil
            request(.retry, now: now, into: &out)
        }
        return finished(out)
    }

    private func finished(_ out: HIDPPOutput) -> HIDPPOutput {
        var out = out
        out.deadline = deadline
        return out
    }

    private mutating func request(_ reason: ApplyReason, now: Instant, into out: inout HIDPPOutput) {
        guard scheduler.request(reason) == .startWorker else { return }
        startNextJob(now: now, into: &out)
    }

    private mutating func startNextJob(now: Instant, into out: inout HIDPPOutput) {
        guard let job = scheduler.nextJob() else { return }
        guard plan != nil || capabilities == nil else {
            // Nothing to write and nothing left to learn.
            _ = scheduler.finished(failed: false)
            return startNextJob(now: now, into: &out)
        }
        retryAt = nil
        perform(gesture.step(.cancel), into: &out)
        if let capabilities {
            run = Run(job: job, plan: plan, steps: Self.applySteps(plan, capabilities))
        } else {
            run = Run(job: job, plan: plan, steps: Self.discoverySteps, discovery: Discovery())
        }
        out.events.append(.applyStarted(job))
        sendNext(now: now, into: &out)
    }

    private static func applySteps(_ plan: HIDPPSetup?, _ capabilities: HIDPPCapabilities) -> [HIDPPStep] {
        guard let plan else { return [] }
        let targets = capabilities.controls.filter(\.divertable).map { ($0.cid, plan.reporting(for: $0)) }
        let wheel = capabilities.thumbWheel ? [plan.thumbWheelInverted] : []
        return targets.map { HIDPPStep.setReporting($0, $1) } + wheel.map { HIDPPStep.setThumbWheel(inverted: $0) }
            + targets.map { HIDPPStep.checkReporting($0, $1) } + wheel.map { HIDPPStep.checkThumbWheel(inverted: $0) }
    }

    private mutating func sendNext(now: Instant, into out: inout HIDPPOutput) {
        while let current = run, current.inFlight == nil {
            guard current.next < current.steps.count else {
                if current.discovery != nil {
                    completeDiscovery(now: now, into: &out)
                    continue
                }
                endRun(.applied, now: now, into: &out)
                return
            }
            let step = current.steps[current.next]
            run?.next += 1
            guard let index = (current.discovery?.features ?? features)[step.request.feature] else { continue }
            run?.inFlight = InFlight(step: step, featureIndex: index, attempts: 1, deadline: now + Self.replyTimeout)
            out.reports.append(step.request.report(featureIndex: index))
            return
        }
    }

    private mutating func completeDiscovery(now: Instant, into out: inout HIDPPOutput) {
        guard let current = run, let discovery = current.discovery else { return }
        guard discovery.isConsistent else { return endRun(.failed(.inconsistentDiscovery), now: now, into: &out) }
        let found = HIDPPCapabilities(controls: discovery.controls, thumbWheel: discovery.features[.thumbWheel] != nil)
        features = discovery.features
        capabilities = found
        run?.discovery = nil
        run?.steps += Self.applySteps(current.plan, found)
        out.events.append(.discovered(found))
    }

    private mutating func replied(_ step: HIDPPStep, _ params: [UInt8], now: Instant, into out: inout HIDPPOutput) {
        switch step {
        case .findFeature(let feature):
            if params[0] != 0 { run?.discovery?.features.record(feature, at: params[0]) }
        case .countControls:
            run?.steps += (0..<params[0]).map(HIDPPStep.describeControl)
        case .describeControl:
            if let control = HIDPPCapabilities.Control(cidInfo: params) { run?.discovery?.controls.append(control) }
        case .setReporting, .setThumbWheel:
            break
        case .checkReporting(_, let expected):
            guard ControlReporting(readFlags: params[2]) == expected else {
                return endRun(.failed(.mismatch(step)), now: now, into: &out)
            }
        case .checkThumbWheel(let inverted):
            guard params[0] & 1 == 0, (params[1] & 1 == 1) == inverted else {
                return endRun(.failed(.mismatch(step)), now: now, into: &out)
            }
        }
        sendNext(now: now, into: &out)
    }

    private mutating func endRun(_ outcome: HIDPPOutcome, now: Instant, into out: inout HIDPPOutput) {
        guard let ended = run else { return }
        run = nil
        out.events.append(.applyFinished(ended.job, outcome))
        if let retryAfter = scheduler.finished(failed: outcome != .applied) { retryAt = now + retryAfter }
        startNextJob(now: now, into: &out)
    }

    private mutating func handle(_ notice: HIDPPNotice, now: Instant, into out: inout HIDPPOutput) {
        switch notice {
        case .heldControls(let current):
            for cid in held where !current.contains(cid) { released(cid, into: &out) }
            for cid in current where !held.contains(cid) { pressed(cid, into: &out) }
            held = current
        case .rawXY(let dx, let dy):
            guard gestureControl != nil else { return }
            perform(gesture.step(.move(dx: Double(dx), dy: Double(dy))), into: &out)
        case .wirelessStatus(let reconfigure):
            if reconfigure { request(.deviceAsked, now: now, into: &out) }
        }
    }

    private mutating func pressed(_ cid: CID, into out: inout HIDPPOutput) {
        if let plan, plan.listening {
            if plan.listens(to: cid) { out.events.append(.heard(cid)) }
            return
        }
        switch plan?.behavior(of: cid) ?? .native {
        case .native:
            break
        case .press(let action):
            out.events.append(.perform(action))
        case .gesture(let gesturePlan):
            gestureControl = cid
            perform(gesture.step(.press(gesturePlan)), into: &out)
        }
    }

    private mutating func released(_ cid: CID, into out: inout HIDPPOutput) {
        guard cid == gestureControl else { return }
        gestureControl = nil
        perform(gesture.step(.release), into: &out)
    }

    private func perform(_ output: GestureMachine.Output?, into out: inout HIDPPOutput) {
        switch output {
        case .click(let action?), .perform(let action): out.events.append(.perform(action))
        case .scroll(let event): out.events.append(.holdScroll(event))
        case .click(nil), nil: break
        }
    }
}

enum HIDPPStep: Equatable, Sendable, CustomStringConvertible {
    case findFeature(HIDPPFeature)
    case countControls
    case describeControl(UInt8)
    case setReporting(CID, ControlReporting)
    case checkReporting(CID, ControlReporting)
    case setThumbWheel(inverted: Bool)
    case checkThumbWheel(inverted: Bool)

    var request: HIDPPRequest {
        switch self {
        case .findFeature(let feature): .getFeature(feature)
        case .countControls: .getControlCount
        case .describeControl(let index): .getControlInfo(index)
        case .setReporting(let cid, let reporting): .setControlReporting(cid, reporting)
        case .checkReporting(let cid, _): .getControlReporting(cid)
        case .setThumbWheel(let inverted): .setThumbWheelReporting(inverted: inverted)
        case .checkThumbWheel: .getThumbWheelReporting
        }
    }

    /// Reporting replies echo the control id. Checking it stops a late reply for one control from answering the
    /// request for the next.
    func accepts(_ params: [UInt8]) -> Bool {
        switch self {
        case .setReporting(let cid, _), .checkReporting(let cid, _):
            UInt16(params[0]) << 8 | UInt16(params[1]) == cid.rawValue
        default:
            true
        }
    }

    var description: String {
        switch self {
        case .findFeature(let feature): "find feature 0x\(String(feature.rawValue, radix: 16, uppercase: true))"
        case .countControls: "count controls"
        case .describeControl(let index): "describe control \(index)"
        case .setReporting(let cid, _): "divert \(cid.hex)"
        case .checkReporting(let cid, _): "read back \(cid.hex)"
        case .setThumbWheel: "set the thumb wheel"
        case .checkThumbWheel: "read back the thumb wheel"
        }
    }
}

struct HIDPPOutput: Equatable, Sendable {
    var reports: [[UInt8]] = []
    var events: [HIDPPEvent] = []
    var deadline: ContinuousClock.Instant?
}

enum HIDPPEvent: Equatable, Sendable {
    case discovered(HIDPPCapabilities)
    case applyStarted(ApplyScheduler.Job)
    case applyFinished(ApplyScheduler.Job, HIDPPOutcome)
    case perform(Action)
    case holdScroll(HoldScrollEvent)
    /// A control pressed while the plan listens. Nothing else happens for it.
    case heard(CID)
}

enum HIDPPOutcome: Equatable, Sendable {
    case applied
    case failed(HIDPPFailure)
}

enum HIDPPFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// No reply after every attempt. Normal right after a Bluetooth connect or while the device sleeps.
    case timedOut(HIDPPStep)
    case deviceError(HIDPPStep, code: UInt8)
    case mismatch(HIDPPStep)
    case inconsistentDiscovery

    var description: String {
        switch self {
        case .timedOut(let step): "no reply to \(step)"
        case .deviceError(let step, let code): "\(step) failed with HID++ error \(code)"
        case .mismatch(let step): "\(step) did not match"
        case .inconsistentDiscovery: "discovery got crossed replies"
        }
    }
}

extension CID {
    var hex: String { "0x" + String(rawValue, radix: 16, uppercase: true) }
}
