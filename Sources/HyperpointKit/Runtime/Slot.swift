import Foundation

/// One per present device. Owns what is actually on the device and the one worker that writes to it. The engine
/// owns the desired state, which the worker reads at the moment it writes, so `invalidate` is the only entry.
@HIDActor
final class Slot {
    enum Phase: Equatable {
        case idle
        case applying
        case failed(KeyMapError)
    }

    let device: PresentDevice
    let connectedAt = Date()
    private(set) var phase = Phase.idle
    /// What the last successful write put on the device. The mapping dies with its service, so a new slot starts
    /// knowing nothing of ours is there.
    private(set) var written: KeyMapSetup?

    private let desired: @HIDActor () -> DeviceSetup
    private let changed: @HIDActor () -> Void
    private let journal: Journal
    private let matching: String
    private var scheduler = ApplyScheduler()
    private var worker: Task<Void, Never>?
    private var retry: Task<Void, Never>?

    init(
        device: PresentDevice, journal: Journal, desired: @escaping @HIDActor () -> DeviceSetup,
        changed: @escaping @HIDActor () -> Void
    ) {
        self.device = device
        self.journal = journal
        self.desired = desired
        self.changed = changed
        matching = DeviceMatch(identifying: device.properties).hidutilKeyboardMatching
    }

    var busy: Bool { scheduler.running }

    func invalidate(_ reason: ApplyReason) {
        guard scheduler.request(reason) else { return }
        worker = Task { await drain() }
    }

    /// The device is gone. A write in flight finishes, and nothing starts after it.
    func close() {
        retry?.cancel()
        worker?.cancel()
    }

    private func drain() async {
        while !Task.isCancelled, let job = scheduler.nextJob() {
            retry?.cancel()
            guard let target = KeyMapSetup.pendingWrite(desired: desired().keyMap, written: written) else {
                _ = scheduler.finished(failed: false)
                continue
            }
            phase = .applying
            changed()
            do {
                try await KeyMapWriter.write(target, matching: matching)
                written = target
                phase = .idle
                _ = scheduler.finished(failed: false)
                journal.applied(device, job: job, wrote: target, failure: nil)
            } catch {
                phase = .failed(error)
                journal.applied(device, job: job, wrote: target, failure: error)
                if let delay = scheduler.finished(failed: true) {
                    retry = Task { [weak self] in
                        try? await Task.sleep(for: delay)
                        guard !Task.isCancelled else { return }
                        self?.invalidate(.retry)
                    }
                }
            }
            changed()
        }
    }
}
