import Foundation
import IOKit.hid

@HIDActor
final class Slot {
    enum Phase: Equatable {
        case idle
        case applying
        case failed(KeyMapError)
    }

    enum HIDPPApply: Equatable {
        case applied
        case failed(String)
        case skipped(String)
    }

    let device: PresentDevice
    let connectedAt = Date()
    private(set) var phase = Phase.idle
    /// The mapping dies with its service, but a service can outlive a crashed
    /// Hyperpoint, so a new slot first reads what the service holds.
    private(set) var ownedOnDevice: KeyMapSetup?
    private var surveyed = false
    private(set) var hidppApplying = false
    private(set) var hidppLast: (outcome: HIDPPApply, at: Date)?

    private let desired: @HIDActor () -> DeviceSetup
    private let changed: @HIDActor () -> Void
    private let discovered: @HIDActor (HIDPPCapabilities) -> Void
    private let perform: @HIDActor (Action) -> Void
    private let holdScroll: @HIDActor (HoldScrollEvent) -> Void
    private let heard: @HIDActor (ListenPress) -> Void
    private let journal: Journal
    private let matching: String
    private let hasKeyMap: Bool
    private let hidppInterface: IOHIDDevice?
    private var session: HIDPPSession?
    private var hidppWrites: HIDPPWrites
    private var scheduler = ApplyScheduler()
    private var worker: Task<Void, Never>?
    private var retry: Task<Void, Never>?

    init(
        device: PresentDevice, hidppInterface: IOHIDDevice?, owesNativeHIDPP: Bool, journal: Journal,
        desired: @escaping @HIDActor () -> DeviceSetup, changed: @escaping @HIDActor () -> Void,
        discovered: @escaping @HIDActor (HIDPPCapabilities) -> Void, perform: @escaping @HIDActor (Action) -> Void,
        holdScroll: @escaping @HIDActor (HoldScrollEvent) -> Void, heard: @escaping @HIDActor (ListenPress) -> Void
    ) {
        self.device = device
        self.hidppInterface = hidppInterface
        hidppWrites = HIDPPWrites(crashMayHaveDiverted: owesNativeHIDPP)
        self.journal = journal
        self.desired = desired
        self.changed = changed
        self.discovered = discovered
        self.perform = perform
        self.holdScroll = holdScroll
        self.heard = heard
        hasKeyMap = device.properties.usagePairs.contains(.keyboard)
        matching = DeviceMatch(identifying: device.properties).hidutilKeyboardMatching
    }

    var busy: Bool { scheduler.running || session?.isApplying == true }

    var reapplied: Bool {
        let wanted = desired()
        let keyMap = wanted.keyMap.routes.isEmpty ? nil : phase == .idle && ownedOnDevice == wanted.keyMap
        let hidpp = session == nil ? nil : !hidppApplying && hidppLast?.outcome == .applied
        let facets = [keyMap, hidpp].compactMap { $0 }
        return !facets.isEmpty && facets.allSatisfy { $0 }
    }

    func invalidate(_ reason: ApplyReason) {
        applyKeyMap(reason)
        applyHIDPP(reason)
    }

    func close() {
        retry?.cancel()
        worker?.cancel()
        session?.close()
    }

    private func applyKeyMap(_ reason: ApplyReason) {
        guard hasKeyMap, scheduler.request(reason) == .startWorker else { return }
        worker = Task { await drain() }
    }

    private func applyHIDPP(_ reason: ApplyReason) {
        let wanted = desired()
        guard let hidppInterface, hidppWrites.pending(desired: wanted.hidpp) != nil || wanted.discoverHIDPP
        else { return }
        if session == nil {
            do {
                session = try HIDPPSession(opening: hidppInterface, journal: journal) { [unowned self] in hidppEvent($0) }
            } catch {
                hidppLast = (.skipped(error.description), Date())
                journal.note("HID++ \(device.id) \(device.name) skipped: \(error)")
                changed()
                return
            }
        }
        let plan = hidppWrites.send(desired: wanted.hidpp)
        session?.request(reason, plan: plan)
    }

    private func hidppEvent(_ event: HIDPPEvent) {
        switch event {
        case .discovered(let capabilities):
            journal.discovered(device, capabilities)
            discovered(capabilities)
        case .applyStarted:
            hidppApplying = true
            changed()
        case .applyFinished(let job, let outcome):
            hidppApplying = false
            switch outcome {
            case .applied: hidppLast = (.applied, Date())
            case .failed(let failure): hidppLast = (.failed(failure.description), Date())
            }
            journal.applied(device, job: job, hidpp: outcome)
            changed()
        case .perform(let action):
            perform(action)
        case .holdScroll(let event):
            holdScroll(event)
        case .heard(let press):
            heard(press)
        }
    }

    private func drain() async {
        while !Task.isCancelled, let job = scheduler.nextJob() {
            retry?.cancel()
            if !surveyed {
                do {
                    ownedOnDevice = KeyMapSetup.hyperpointLeftover(in: try await KeyMapWriter.read(matching: matching))
                    surveyed = true
                } catch {
                    journal.note("survey \(device.id) \(device.name) failed: \(error)")
                    failed(error)
                    changed()
                    continue
                }
            }
            guard let target = KeyMapSetup.pendingWrite(desired: desired().keyMap, written: ownedOnDevice) else {
                _ = scheduler.finished(failed: false)
                continue
            }
            phase = .applying
            changed()
            do {
                try await KeyMapWriter.write(target, matching: matching)
                ownedOnDevice = target
                phase = .idle
                _ = scheduler.finished(failed: false)
                journal.applied(device, job: job, wrote: target, failure: nil)
            } catch {
                journal.applied(device, job: job, wrote: target, failure: error)
                failed(error)
            }
            changed()
        }
        // The last job's change came while the scheduler still ran, so whoever waits for `busy` to clear hears it here.
        if !Task.isCancelled { changed() }
    }

    private func failed(_ error: KeyMapError) {
        phase = .failed(error)
        if let retryAfter = scheduler.finished(failed: true) {
            retry = Task { [weak self] in
                try? await Task.sleep(for: retryAfter)
                guard !Task.isCancelled else { return }
                self?.applyKeyMap(.retry)
            }
        }
    }
}
