import Foundation

enum KeyMapError: Error, Equatable, CustomStringConvertible {
    /// The read-back did not show the mapping. The service can lag its device, or no service matched.
    case serviceNotReady
    case hidutilFailed(status: Int32, output: String)
    case timedOut

    var description: String {
        switch self {
        case .serviceNotReady: "keyboard service not ready"
        case .hidutilFailed(let status, let output): "hidutil exited \(status): \(output)"
        case .timedOut: "hidutil timed out"
        }
    }
}

/// Writes a key map into one keyboard service with `/usr/bin/hidutil` (TN2450, no privileges) and reads it back.
/// `UserKeyMapping` is replaced whole, so the write is absolute and an empty map clears it.
enum KeyMapWriter {
    @concurrent
    static func write(_ setup: KeyMapSetup, matching: String) async throws(KeyMapError) {
        let set = try await hidutil(["property", "--matching", matching, "--set", setup.userKeyMappingJSON])
        guard set.status == 0 else { throw .hidutilFailed(status: set.status, output: set.output) }
        // hidutil exits 0 and changes nothing when no service matches, so only the read-back proves the write.
        let get = try await hidutil(["property", "--matching", matching, "--get", "UserKeyMapping"])
        guard get.status == 0 else { throw .hidutilFailed(status: get.status, output: get.output) }
        let services = HidutilReadback.parse(get.output)
        guard !services.isEmpty, services.values.allSatisfy({ $0 == setup.pairs }) else { throw .serviceNotReady }
    }

    @concurrent
    private static func hidutil(_ arguments: [String]) async throws(KeyMapError) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw .hidutilFailed(status: -1, output: "\(error)")
        }
        let pid = process.processIdentifier
        let watchdog = Task {
            try await Task.sleep(for: .seconds(3))
            kill(pid, SIGKILL)
        }
        // hidutil prints a few lines, and reading to the end drains the pipe so the process cannot block on it.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        if process.terminationReason == .uncaughtSignal { throw .timedOut }
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/// Parses `hidutil property --get UserKeyMapping` output into each listed service's mapping pairs.
///
///     RegistryID  Key                   Value
///     100000cdb   UserKeyMapping   (
///             {
///             HIDKeyboardModifierMappingDst = 30064771181;
///             HIDKeyboardModifierMappingSrc = 30064771129;
///         }
///     )
enum HidutilReadback {
    static func parse(_ output: String) -> [UInt64: Set<KeyMapSetup.Pair>] {
        var services: [UInt64: Set<KeyMapSetup.Pair>] = [:]
        var service: UInt64?
        var source: UInt64?
        var destination: UInt64?
        for line in output.split(separator: "\n") {
            let words = line.split(whereSeparator: \.isWhitespace)
            if words.count >= 2, words[1] == "UserKeyMapping", let id = UInt64(words[0], radix: 16) {
                service = id
                services[id] = []
            } else if words.count == 3, words[1] == "=", let value = number(words[2].dropLast()) {
                if words[0] == "HIDKeyboardModifierMappingSrc" { source = value }
                if words[0] == "HIDKeyboardModifierMappingDst" { destination = value }
            } else if words.first?.hasPrefix("}") == true {
                if let service, let source, let destination {
                    services[service, default: []].insert(KeyMapSetup.Pair(source: source, destination: destination))
                }
                source = nil
                destination = nil
            }
        }
        return services
    }

    private static func number(_ text: Substring) -> UInt64? {
        text.hasPrefix("0x") ? UInt64(text.dropFirst(2), radix: 16) : UInt64(text)
    }
}
