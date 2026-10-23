/// The apply is the same for every reason. The reason is for the journal.
enum ApplyReason: String, Hashable, Sendable {
    case launch
    case connected
    case configChanged
    case permissionChanged
    case pauseChanged
    case manual
    case quit
    case retry
}

/// One device's apply bookkeeping as a value. A device has one writer, and triggers that arrive during an apply
/// collapse into exactly one follow-up.
struct ApplyScheduler: Sendable {
    struct Job: Equatable, Sendable {
        var reasons: Set<ApplyReason>
        var attempt: Int
    }

    private(set) var running = false
    private var queued: Set<ApplyReason> = []
    private var failures = 0

    /// True when the caller must start the worker. False when a worker is running and will pick the reason up.
    mutating func request(_ reason: ApplyReason) -> Bool {
        queued.insert(reason)
        if reason != .retry { failures = 0 }
        guard !running else { return false }
        running = true
        return true
    }

    mutating func nextJob() -> Job? {
        guard !queued.isEmpty else {
            running = false
            return nil
        }
        defer { queued = [] }
        return Job(reasons: queued, attempt: failures + 1)
    }

    /// The delay before a retry, or nil when there is nothing to retry.
    mutating func finished(failed: Bool) -> Duration? {
        guard failed else {
            failures = 0
            return nil
        }
        failures += 1
        return RetryPolicy.delay(afterFailures: failures)
    }
}

enum RetryPolicy {
    /// A service can lag its device by a moment after a connect, so retry quickly and then back off. After the
    /// last delay the slot waits for the next trigger.
    static let delays: [Duration] = [.milliseconds(300), .seconds(1), .seconds(2), .seconds(4), .seconds(8)]

    static func delay(afterFailures failures: Int) -> Duration? {
        delays.indices.contains(failures - 1) ? delays[failures - 1] : nil
    }
}
