import os

struct Journal: Sendable {
    private let logger = Logger(subsystem: "dev.emir.hyperpoint", category: "devices")

    func connected(_ device: PresentDevice, profile: String?, atLaunch: Bool) {
        let properties = device.properties
        let ids = "vendor=0x\(String(properties.vendor.rawValue, radix: 16)) product=0x\(String(properties.product.rawValue, radix: 16))"
        logger.notice(
            "\(atLaunch ? "present" : "connect", privacy: .public) \(device.id, privacy: .public) \(device.name, privacy: .public) profile=\(profile ?? "none", privacy: .public) \(ids, privacy: .public) builtIn=\(properties.builtIn, privacy: .public) transport=\(properties.transport ?? "-", privacy: .public) services=[\(Self.services(of: device), privacy: .public)]"
        )
    }

    func servicesChanged(_ device: PresentDevice) {
        logger.notice(
            "services \(device.id, privacy: .public) \(device.name, privacy: .public) services=[\(Self.services(of: device), privacy: .public)]"
        )
    }

    private static func services(of device: PresentDevice) -> String {
        device.eventServices.map { "0x" + String($0.rawValue, radix: 16) }.joined(separator: ",")
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

    func discovered(_ device: PresentDevice, _ capabilities: HIDPPCapabilities) {
        let controls = capabilities.controls.map { control in
            control.cid.hex + (control.divertable ? (control.rawXY ? "+divert+rawXY" : "+divert") : "")
        }
        logger.notice(
            "discovered \(device.id, privacy: .public) \(device.name, privacy: .public) controls=[\(controls.joined(separator: ","), privacy: .public)] thumbWheel=\(capabilities.thumbWheel, privacy: .public)"
        )
    }

    func applied(_ device: PresentDevice, job: ApplyScheduler.Job, hidpp outcome: HIDPPOutcome) {
        let reasons = job.reasons.map(\.rawValue).sorted().joined(separator: ",")
        let result =
            switch outcome {
            case .applied: "applied"
            case .failed(let failure): "failed: \(failure)"
            }
        logger.notice(
            "hidpp \(device.id, privacy: .public) \(device.name, privacy: .public) reasons=\(reasons, privacy: .public) attempt=\(job.attempt, privacy: .public) \(result, privacy: .public)"
        )
    }

    func note(_ text: String) {
        logger.notice("\(text, privacy: .public)")
    }
}
