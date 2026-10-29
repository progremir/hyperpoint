import Carbon
import Foundation

// Holds secure event input, as a terminal's hidden prompt does, until it is killed or the given seconds pass.
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
for signal in [SIGTERM, SIGINT] {
    Foundation.signal(signal) { _ in
        DisableSecureEventInput()
        exit(0)
    }
}
EnableSecureEventInput()
print("secureInput=\(IsSecureEventInputEnabled()) pid=\(getpid())")
fflush(stdout)
Thread.sleep(forTimeInterval: seconds)
DisableSecureEventInput()
