// Proves the settings window's tab switches, as a click on a toolbar item makes them. It presses every tab from every
// other tab, switches the Device popup on Buttons and Scrolling to the other mouse and back, and opens Scrolling on
// the shortest screen when the page is taller than it. It also starts and cancels the shortcut recorder of the first
// Buttons rule that does a shortcut. From each press it samples at 120 Hz the window's height on screen and the incoming
// page's scroll area: whether it has a scroll bar, and whether its content is taller than the part that shows. It
// prints every sample, then a verdict per change, and puts the window back where it was.
// Needs Accessibility for the calling shell, and opens Settings from the menu bar item if it is closed.
// Usage: tab-switches [seconds sampled per change] [recorders], where recorders runs the recorder check alone.
import AppKit
import ApplicationServices

let tabs = ["General", "Hyper Key", "Buttons", "Scrolling", "Devices"]
let seconds = CommandLine.arguments.dropFirst().compactMap(Double.init).first ?? 1.2
let recordersOnly = CommandLine.arguments.contains("recorders")
let period = 1.0 / 120

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func role(_ element: AXUIElement) -> String { attribute(element, kAXRoleAttribute) as? String ?? "" }

func title(_ element: AXUIElement) -> String { attribute(element, kAXTitleAttribute) as? String ?? "" }

func rect(_ element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute)
    else { return nil }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &origin)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: origin, size: extent)
}

func contentSize(_ element: AXUIElement) -> CGSize? {
    guard let value = attribute(element, "AXContentSize") else { return nil }
    var size = CGSize.zero
    AXValueGetValue(value as! AXValue, .cgSize, &size)
    return size
}

func scrollAreas(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    if role(element) == kAXScrollAreaRole { return [element] }
    guard depth < 6, role(element) != kAXToolbarRole else { return [] }
    return children(element).flatMap { scrollAreas(in: $0, depth: depth + 1) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

guard AXIsProcessTrusted() else { fail("this shell lacks Accessibility") }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.emir.hyperpoint").first
else { fail("Hyperpoint is not running") }
let element = AXUIElementCreateApplication(app.processIdentifier)

func settingsWindow() -> AXUIElement? {
    (attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []).first { window in
        children(window).contains { role($0) == kAXToolbarRole }
    }
}

if settingsWindow() == nil, let bar = attribute(element, "AXExtrasMenuBar"), let item = children(bar as! AXUIElement).first {
    AXUIElementPerformAction(item, kAXPressAction as CFString)
    usleep(300_000)
    func find(_ element: AXUIElement) -> AXUIElement? {
        title(element) == "Settings…" ? element : children(element).lazy.compactMap(find).first
    }
    if let settings = find(item) { AXUIElementPerformAction(settings, kAXPressAction as CFString) }
    usleep(1_000_000)
}
guard let window = settingsWindow(), let toolbar = children(window).first(where: { role($0) == kAXToolbarRole })
else { fail("no settings window") }
let buttons = Dictionary(children(toolbar).map { (title($0), $0) }, uniquingKeysWith: { first, _ in first })
guard tabs.allSatisfy({ buttons[$0] != nil }) else { fail("toolbar has \(buttons.keys.sorted())") }
AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
AXUIElementPerformAction(window, kAXRaiseAction as CFString)

let windowNumber: CGWindowID = {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let ours = windows.filter {
        $0[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0
    }
    return ours.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }.first ?? 0
}()

func screenHeight() -> Double {
    let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowNumber) as? [[String: Any]] ?? []
    return (info.first?[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0
}

/// The incoming page as the app reports it: its content height and the height of it that shows, or nil while it is
/// not in the window.
struct Sample {
    var time: Double
    var content: Double?
    var shown: Double?
    var scroller = false

    var clipped: Bool {
        guard let content, let shown else { return false }
        return content > shown + 0.5
    }
}

/// Reads the page first and the window's frame after it, both from the app, so the frame is never older than the page
/// it is compared with. Reading the content size can make SwiftUI lay the page out ahead of drawing it, so the page has
/// to still be in the window after that read to count as shown. The window server's height lags the app's by about a
/// frame, so it only gives the animation's shape. The app answers once its main thread is free, so the sample is timed
/// when the answer arrives.
func sample(since start: Date, outgoing: [AXUIElement]) -> Sample {
    var result = Sample(time: 0)
    let isIncoming = { (area: AXUIElement) in !outgoing.contains { CFEqual($0, area) } }
    if let incoming = scrollAreas(in: window).first(where: isIncoming), let content = contentSize(incoming),
        scrollAreas(in: window).contains(where: { CFEqual($0, incoming) }), let area = rect(incoming),
        let frame = rect(window)
    {
        result.content = Double(content.height)
        result.shown = Double(min(area.maxY, frame.maxY) - area.minY)
        result.scroller = attribute(incoming, kAXVerticalScrollBarAttribute) != nil
    }
    result.time = Date().timeIntervalSince(start)
    return result
}

func settle() {
    var last = screenHeight()
    var still = Date()
    let start = Date()
    while Date().timeIntervalSince(start) < 3 {
        usleep(20_000)
        let height = screenHeight()
        if height != last { last = height; still = Date() }
        if Date().timeIntervalSince(still) > 0.5, Date().timeIntervalSince(start) > 0.8 { return }
    }
}

/// One change: the window's height on screen every 1/120 s, and the incoming page as often as the app answers.
/// Reading the page waits for the app's main thread, so the heights come from their own thread and keep their pace
/// while the app is busy.
struct Recording {
    var heights: [(time: Double, height: Double)] = []
    var pages: [Sample] = []
}

/// Records from the moment `act` starts on another thread, so the recording covers the app handling it.
func record(_ label: String, outgoing: [AXUIElement], _ act: @escaping @Sendable () -> Void) -> Recording {
    let start = Date()
    let lock = NSLock()
    var recording = Recording()
    let heights = DispatchGroup()
    DispatchQueue.global().async(group: heights) {
        var ticks = 0
        while Date().timeIntervalSince(start) < seconds {
            let height = (Date().timeIntervalSince(start), screenHeight())
            lock.withLock { recording.heights.append(height) }
            ticks += 1
            let wait = start.addingTimeInterval(Double(ticks) * period).timeIntervalSinceNow
            if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
        }
    }
    DispatchQueue.global().async(execute: act)
    var pages: [Sample] = []
    while Date().timeIntervalSince(start) < seconds {
        pages.append(sample(since: start, outgoing: outgoing))
        usleep(UInt32(period * 1_000_000))
    }
    heights.wait()
    recording.pages = pages
    let lines =
        recording.heights.map { ($0.time, String(format: "h=%4.0f", $0.height)) }
        + pages.map { page in
            let flags = (page.scroller ? " SCROLLER" : "") + (page.clipped ? " CLIPPED" : "")
            let content = page.content.map { String(format: "%.0f", $0) } ?? "-"
            let shown = page.shown.map { String(format: "%.0f", $0) } ?? "-"
            return (page.time, "page content=\(content) shown=\(shown)\(flags)")
        }
    for (time, line) in lines.sorted(by: { $0.0 < $1.0 }) {
        print(String(format: "%@ %6.1f ms %@", label, time * 1000, line))
    }
    return recording
}

enum Change {
    /// A new page comes in: it must not show until the window has its height.
    case tabSwitch
    /// The page grows or shrinks where it is: the window follows within 50 ms, and a page that grew is hidden until
    /// the window has its height.
    case inPlace
    /// A page taller than the screen comes in: the window stops at the screen's bottom and the page scrolls.
    case pastScreen(visibleHeight: Double)
    /// Something in the page changes without changing its height: the window keeps its height and the page shows
    /// throughout.
    case steady

    var isInPlace: Bool {
        if case .inPlace = self { return true }
        return false
    }
}

/// The height moves one way over 0.1 to 0.3 s. A switch never shows the page clipped or with a scroll bar and is done
/// within 0.35 s. An in-place change is never clipped either, and the window starts within 50 ms of the page changing,
/// timed from the first sample that saw the change. A page past the screen's bottom shows only at the window's final
/// height, which is the screen's.
func verdict(_ label: String, _ recording: Recording, _ change: Change) -> Bool {
    let heights = recording.heights
    let changes = heights.indices.dropFirst().filter { heights[$0].height != heights[$0 - 1].height }
    let steps = changes.map { heights[$0].height - heights[$0 - 1].height }
    let monotonic = steps.allSatisfy { $0 > 0 } || steps.allSatisfy { $0 < 0 }
    let began = changes.first.map { heights[$0].time } ?? 0
    let ended = changes.last.map { heights[$0].time } ?? 0
    let animated = changes.count > 1 && (0.1...0.3).contains(ended - began)
    let shown = recording.pages.filter { $0.content != nil }
    let finished = max(ended, shown.first?.time ?? .infinity)
    let clipped = recording.pages.filter(\.clipped).count
    let scroller = recording.pages.filter(\.scroller).count
    let changedAt = recording.pages.first { $0.content != recording.pages.first?.content }?.time
    let lag = changes.isEmpty ? nil : changedAt.map { began - $0 }
    let ok: Bool
    switch change {
    case .tabSwitch:
        ok = monotonic && (changes.isEmpty || animated) && clipped == 0 && scroller == 0 && finished <= 0.35
    case .inPlace:
        ok = monotonic && animated && clipped == 0 && scroller == 0 && (lag ?? .infinity) <= 0.05
    case .steady:
        ok = changes.isEmpty && !recording.pages.isEmpty && recording.pages.allSatisfy { $0.content != nil } && clipped == 0
    case .pastScreen(let visibleHeight):
        let final = shown.last
        ok = monotonic && animated && abs(heights[heights.count - 1].height - visibleHeight) <= 1
            && final?.scroller == true && shown.allSatisfy { $0.shown == final?.shown }
    }
    print(
        String(
            format: "%@ %@: %.0f to %.0f, %d steps from %.0f to %.0f ms, %@, page shown at %@ ms, done %.0f ms, clipped %d, scroller %d",
            ok ? "PASS" : "FAIL", label, heights[0].height, heights[heights.count - 1].height, changes.count,
            began * 1000, ended * 1000, monotonic ? "monotonic" : "NOT monotonic",
            shown.first.map { String(format: "%.0f", $0.time * 1000) } ?? "never", finished * 1000, clipped, scroller)
            + (change.isInPlace
                ? String(
                    format: ", page changed at %@ ms, window started %@ ms after",
                    changedAt.map { String(format: "%.0f", $0 * 1000) } ?? "-",
                    lag.map { String(format: "%.0f", $0 * 1000) } ?? "-") : ""))
    return ok
}

func press(_ element: AXUIElement) -> @Sendable () -> Void {
    nonisolated(unsafe) let element = element
    return { AXUIElementPerformAction(element, kAXPressAction as CFString) }
}

func select(_ tab: String) {
    AXUIElementPerformAction(buttons[tab]!, kAXPressAction as CFString)
    settle()
}

let startTab = attribute(window, kAXTitleAttribute) as? String ?? tabs[0]
var results: [(String, Recording, Change)] = []
for from in tabs where !recordersOnly {
    for to in tabs where to != from {
        select(from)
        let label = "\(from) > \(to)"
        results.append((label, record(label, outgoing: scrollAreas(in: window), press(buttons[to]!)), .tabSwitch))
    }
}

func popUp(in element: AXUIElement) -> AXUIElement? {
    if role(element) == kAXPopUpButtonRole { return element }
    guard role(element) != kAXToolbarRole else { return nil }
    return children(element).lazy.compactMap(popUp).first
}

func openMenu(_ popUp: AXUIElement) -> [AXUIElement] {
    AXUIElementPerformAction(popUp, kAXPressAction as CFString)
    for _ in 0..<50 {
        let items = children(popUp).flatMap(children).filter { role($0) == kAXMenuItemRole && !title($0).isEmpty }
        if !items.isEmpty { return items }
        usleep(20_000)
    }
    fail("the popup's menu did not open")
}

func popUps(in element: AXUIElement) -> [AXUIElement] {
    if role(element) == kAXPopUpButtonRole { return [element] }
    guard role(element) != kAXToolbarRole else { return [] }
    return children(element).flatMap(popUps)
}

/// SwiftUI names a button by its description, not its title.
func button(_ name: String, in element: AXUIElement) -> AXUIElement? {
    if role(element) == kAXButtonRole, attribute(element, kAXDescriptionAttribute) as? String == name { return element }
    guard role(element) != kAXToolbarRole else { return nil }
    return children(element).lazy.compactMap { button(name, in: $0) }.first
}

for tab in ["Buttons", "Scrolling"] where !recordersOnly {
    select(tab)
    guard let device = popUp(in: window) else { fail("no Device popup on \(tab)") }
    let original = attribute(device, kAXValueAttribute) as? String ?? ""
    guard let other = openMenu(device).first(where: { title($0) != original }) else { fail("\(tab) lists one mouse") }
    let replacement = title(other)
    let label = "\(tab) device \(original) > \(replacement)"
    results.append((label, record(label, outgoing: [], press(other)), .inPlace))
    settle()
    guard let back = openMenu(device).first(where: { title($0) == original }) else { fail("\(tab) lost \(original)") }
    let returnLabel = "\(tab) device \(replacement) > \(original)"
    results.append((returnLabel, record(returnLabel, outgoing: [], press(back)), .inPlace))
    settle()
}

func position(_ element: AXUIElement) -> CGPoint? { rect(element)?.origin }

func move(_ element: AXUIElement, to point: CGPoint) {
    var point = point
    AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!)
    usleep(300_000)
}

// A rule's Do picker and When picker give way to the shortcut recorder, and come back on Cancel.
select("Buttons")
let doesShortcut = { (popUp: AXUIElement) in (attribute(popUp, kAXValueAttribute) as? String)?.hasPrefix("Shortcut ") == true }
if let shortcut = popUps(in: window).first(where: doesShortcut),
    let item = openMenu(shortcut).first(where: { title($0) == "Record Another Shortcut…" })
{
    results.append(("Buttons record a shortcut", record("Buttons record a shortcut", outgoing: [], press(item)), .steady))
    settle()
    guard let cancel = button("Cancel", in: window) else { fail("the shortcut recorder has no Cancel button") }
    results.append(("Buttons stop recording", record("Buttons stop recording", outgoing: [], press(cancel)), .steady))
    settle()
} else {
    print("SKIP no rule on Buttons does a shortcut")
}

let tallest = recordersOnly ? 0 : { select("Scrolling"); return screenHeight() }()
var restored = true
if !recordersOnly, let short = NSScreen.screens.min(by: { $0.visibleFrame.height < $1.visibleFrame.height }),
    Double(short.visibleFrame.height) < tallest, let home = position(window)
{
    select("General")
    let top = NSScreen.screens[0].frame.height - short.visibleFrame.maxY
    move(window, to: CGPoint(x: short.visibleFrame.minX + 40, y: top + 20))
    let label = "General > Scrolling on \(short.localizedName)"
    let change = Change.pastScreen(visibleHeight: Double(short.visibleFrame.height))
    results.append((label, record(label, outgoing: scrollAreas(in: window), press(buttons["Scrolling"]!)), change))
    select("General")
    move(window, to: home)
    let back = position(window) ?? .zero
    print(String(format: "window moved to %@ and back to %.0f,%.0f (was %.0f,%.0f)", short.localizedName, back.x, back.y, home.x, home.y))
    restored = abs(back.x - home.x) <= 1 && abs(back.y - home.y) <= 1
} else if !recordersOnly {
    print("SKIP no screen is shorter than the Scrolling page")
}
select(startTab)

let passed = results.filter { verdict($0.0, $0.1, $0.2) }.count
print("\(passed)/\(results.count) pass\(restored ? "" : ", but the window did not go back to where it was")")
exit(passed == results.count && restored ? 0 : 1)
