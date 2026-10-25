import Foundation
@testable import HyperpointKit
import Testing

/// Replays wheel steps recorded by `verify.sh record wheel` through the real animator, so a scroll setting can be
/// judged on the user's own hand without installing the app. Run through `verify.sh replay`, which sets these:
/// - `HYPERPOINT_REPLAY_WHEEL`: one or more recordings, separated by colons.
/// - `HYPERPOINT_REPLAY_CONFIG`: the config whose smooth scrolling is the baseline.
/// - `HYPERPOINT_REPLAY_DEVICE`: part of the device profile's name, `MX` when unset.
/// - `HYPERPOINT_REPLAY_VARIANTS`: changes to try against the baseline, such as `duration=2 duration=3,easeIn=30`.
/// - `HYPERPOINT_REPLAY_HZ`: the display's refresh rate, 60 when unset.
/// - `HYPERPOINT_REPLAY_OUT`: where to write every frame as JSON.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HYPERPOINT_REPLAY_WHEEL"] != nil))
struct ScrollReplay {
    private let env = ProcessInfo.processInfo.environment

    @Test func replay() throws {
        let config = try ConfigCodec.decode(Data(contentsOf: URL(fileURLWithPath: env["HYPERPOINT_REPLAY_CONFIG"]!)))
        let wanted = env["HYPERPOINT_REPLAY_DEVICE"] ?? "MX"
        let profile = try #require(config.devices.first { $0.name.contains(wanted) && $0.scrolling?.smooth != nil })
        let baseline = profile.scrolling!.smooth!
        let hertz = Double(env["HYPERPOINT_REPLAY_HZ"] ?? "60")!
        let variants = try [("as configured", baseline)]
            + (env["HYPERPOINT_REPLAY_VARIANTS"] ?? "").split(separator: " ").map { (String($0), try changed(baseline, by: $0)) }
        print("device \(profile.name), \(Int(hertz)) Hz; swing is the median fastest/slowest frame between two notches, lag the median time to half a notch")
        var recordings: [[String: Any]] = []
        for path in env["HYPERPOINT_REPLAY_WHEEL"]!.split(separator: ":").map(String.init) {
            let steps = try wheelSteps(path)
            print("\n\(path): \(steps.count) events over \(String(format: "%.1f", steps.last!.time - steps[0].time)) s")
            var runs: [[String: Any]] = []
            for (label, settings) in variants {
                let run = Replay(steps: steps, settings: settings, hertz: hertz)
                print("  " + label.padding(toLength: 24, withPad: " ", startingAt: 0) + String(
                    format: "stops=%3d still=%5.1f s  swing=%5.1fx  lag=%4.0f ms", run.stops, run.still, run.swing, run.lag * 1000))
                runs.append(["label": label, "duration": settings.duration, "brake": settings.brake, "easeIn": settings.easeIn,
                             "stops": run.stops, "still": run.still, "swing": run.swing, "lagMs": run.lag * 1000, "points": run.points,
                             "distances": run.distances])
            }
            recordings.append(["path": path, "steps": steps.map { $0.time - steps[0].time + 0.01 }, "runs": runs])
        }
        if let out = env["HYPERPOINT_REPLAY_OUT"] {
            let json = try JSONSerialization.data(withJSONObject: ["device": profile.name, "hz": hertz, "recordings": recordings])
            try json.write(to: URL(fileURLWithPath: out))
        }
    }

    private func changed(_ settings: SmoothScroll, by spec: Substring) throws -> SmoothScroll {
        var settings = settings
        for pair in spec.split(separator: ",") {
            let parts = pair.split(separator: "=")
            let value = try #require(parts.count == 2 ? Double(parts[1]) : nil, "\(pair) is not key=number")
            switch parts[0] {
            case "duration": settings.duration = value
            case "brake": settings.brake = value
            case "easeIn": settings.easeIn = value
            default: Issue.record("\(parts[0]) is not duration, brake or easeIn")
            }
        }
        return settings
    }

    private func wheelSteps(_ path: String) throws -> [(time: Double, steps: Int)] {
        try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").compactMap { line in
            guard line.contains(" sender="), let raw = line.split(separator: " ").first(where: { $0.hasPrefix("raw=") }) else {
                return nil
            }
            return (Double(line.prefix { $0 != " " })! / 1000, max(1, Int(Double(raw.dropFirst(4))!.rounded())))
        }
    }
}

/// One recording through the animator on a display clock, as the app posts it: whole points per frame.
private struct Replay {
    var points: [Int] = []
    /// How far each step should take the page, from the curve at the spin rate when it arrived.
    var distances: [Double] = []
    var stops = 0
    var still = 0.0
    var swing = 0.0
    var lag = 0.0

    init(steps: [(time: Double, steps: Int)], settings: SmoothScroll, hertz: Double) {
        var animator = ScrollAnimator()
        var whole = WholePoints()
        var rate = SpinRate()
        let start = steps[0].time - 0.01
        var pending = steps[...]
        var exact: [Double] = []
        var halves: [(time: Double, mark: Double)] = []
        var delays: [Double] = []
        var stepped = 0.0, posted = 0.0
        for index in 0..<Int((steps.last!.time - start + 1.5) * hertz) {
            let now = start + Double(index) / hertz
            while let step = pending.first, step.time <= now {
                animator.tick(ScrollTick(sign: .positive, steps: step.steps, settings: settings), at: step.time)
                let curve = settings.curve
                let distance = Double(step.steps) * curve.distancePerStep(at: rate.record(step.steps, at: step.time, slowest: curve.slowest))
                distances.append(distance)
                halves.append((step.time, stepped + distance / 2))
                stepped += distance
                pending.removeFirst()
            }
            let frame = animator.frame(at: now)
            let move = frame?.points ?? 0
            posted += move
            exact.append(move * hertz)
            points.append(frame.map { Int(whole.take($0)) } ?? 0)
            while let half = halves.first, posted >= half.mark - 1e-6 {
                delays.append(now - half.time)
                halves.removeFirst()
            }
        }
        var swings: [Double] = []
        for (from, to) in zip(steps, steps.dropFirst()) where to.time - from.time < 1 {
            let first = Int(((from.time - start) * hertz).rounded(.up)) + 1
            let last = min(Int(((to.time - start) * hertz).rounded(.down)), exact.count - 1)
            guard first <= last else { continue }
            let between = exact[first...last]
            let idle = between.filter { $0 < 1e-9 }.count
            if idle > 0 { (stops, still) = (stops + 1, still + Double(idle) / hertz) }
            let moving = between.filter { $0 >= 1e-9 }
            if let fastest = moving.max(), let slowest = moving.min() { swings.append(fastest / slowest) }
        }
        swing = swings.sorted()[swings.count / 2]
        lag = delays.sorted()[delays.count / 2]
    }
}
