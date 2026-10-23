import os

/// One line per connect, disconnect and apply, in unified logging:
/// `log stream --predicate 'subsystem == "dev.emir.hyperpoint"'`.
struct Journal: Sendable {
    private let logger = Logger(subsystem: "dev.emir.hyperpoint", category: "devices")

    func connected(_ device: PresentDevice, profile: String?, atLaunch: Bool) {
        let properties = device.properties
        let ids = "vendor=0x\(String(properties.vendor.rawValue, radix: 16)) product=0x\(String(properties.product.rawValue, radix: 16))"
        let services = device.eventServices.map { "0x" + String($0.rawValue, radix: 16) }.joined(separator: ",")
        logger.notice(
            "\(atLaunch ? "present" : "connect", privacy: .public) \(device.id, privacy: .public) \(device.name, privacy: .public) profile=\(profile ?? "none", privacy: .public) \(ids, privacy: .public) builtIn=\(properties.builtIn, privacy: .public) transport=\(properties.transport ?? "-", privacy: .public) services=[\(services, privacy: .public)]"
        )
    }

    func disconnected(_ device: PresentDevice) {
        logger.notice("disconnect \(device.id, privacy: .public) \(device.name, privacy: .public)")
    }

    func applied(
        _ device: PresentDevice, job: ApplyScheduler.Job, wrote setup: KeyMapSetup, failure: KeyMapError?
    ) {
        let reasons = job.reasons.map(\.rawValue).sorted().joined(separator: ",")
        let outcome = failure.map { "failed: \($0)" } ?? "applied"
        logger.notice(
            "apply \(device.id, privacy: .public) \(device.name, privacy: .public) reasons=\(reasons, privacy: .public) attempt=\(job.attempt, privacy: .public) routes=\(setup.routes.count, privacy: .public) \(outcome, privacy: .public)"
        )
    }

    func note(_ text: String) {
        logger.notice("\(text, privacy: .public)")
    }
}
