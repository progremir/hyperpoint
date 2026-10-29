// On-screen height of Hyperpoint's tallest normal window, one line per change, sampled every 15 ms.
// Window bounds need no Screen Recording grant. An animated resize prints a run of heights, a jump prints one.
// Usage: window-heights <seconds>
import CoreGraphics
import Foundation

let deadline = Date().addingTimeInterval(Double(CommandLine.arguments.dropFirst().first ?? "") ?? 60)
var last = -1.0
while Date() < deadline {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let heights = windows
        .filter {
            ["Hyperpoint", "Hyperpoint Dev"].contains($0[kCGWindowOwnerName as String] as? String)
                && $0[kCGWindowLayer as String] as? Int == 0
        }
        .compactMap { ($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double }
    if let height = heights.max(), height != last {
        print(String(format: "%.3f %.0f", Date().timeIntervalSince1970, height))
        fflush(stdout)
        last = height
    }
    usleep(15_000)
}
