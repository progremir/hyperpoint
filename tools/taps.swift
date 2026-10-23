import CoreGraphics
import AppKit
var n: UInt32 = 0
CGGetEventTapList(0, nil, &n)
var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(n))
CGGetEventTapList(n, &taps, &n)
let mouseMask: UInt64 = (1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<22)|(1<<25)|(1<<26)|(1<<27)|(1<<29)
for t in taps {
  let name = NSRunningApplication(processIdentifier: pid_t(t.tappingProcess))?.localizedName ?? "pid \(t.tappingProcess)"
  let kind = t.options == .defaultTap ? "ACTIVE(can modify/eat)" : "listen-only"
  let mouse = (t.eventsOfInterest & mouseMask) != 0 ? "MOUSE" : "kbd-only"
  print("\(name)\t\(kind)\t\(mouse)\tenabled=\(t.enabled)\tavgLatency=\(String(format:"%.2f",t.avgUsecLatency))us maxLatency=\(String(format:"%.0f",t.maxUsecLatency))us\tmask=0x\(String(t.eventsOfInterest,radix:16))")
}
