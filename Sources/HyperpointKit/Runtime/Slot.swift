import Foundation

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
    /// The mapping dies with its service, but a service can outlive a crashed
    /// Hyperpoint, so a new slot first reads what the service holds.
    private(set) var written: KeyMapSetup?
    private var surveyed = false

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

    func close() {
        retry?.cancel()
        worker?.cancel()
    }

    private func drain() async {
        while !Task.isCancelled, let job = scheduler.nextJob() {
            retry?.cancel()
            if !surveyed {
                do {
                    written = KeyMapSetup.recovered(from: try await KeyMapWriter.read(matching: matching))
                    surveyed = true
                } catch {
                    journal.note("survey \(device.id) \(device.name) failed: \(error)")
                    failed(error)
                    changed()
                    continue
                }
            }
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
                journal.applied(device, job: job, wrote: target, failure: error)
                failed(error)
            }
            changed()
        }
    }

    private func failed(_ error: KeyMapError) {
        phase = .failed(error)
        if let delay = scheduler.finished(failed: true) {
            retry = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.invalidate(.retry)
            }
        }
    }
}
