// Presses a new device's Set Up button on the Devices tab, or chooses an item from its menu, as a click does.
// Needs Accessibility for the calling shell, and opens Settings from the menu bar item if it is closed.
import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func role(_ element: AXUIElement) -> String { attribute(element, kAXRoleAttribute) as? String ?? "" }

/// SwiftUI gives a menu's primary button its label as a description, not a title.
func title(_ element: AXUIElement) -> String {
    (attribute(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
        ?? attribute(element, kAXDescriptionAttribute) as? String ?? ""
}

func descendants(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    depth < 14 ? [element] + children(element).flatMap { descendants($0, depth: depth + 1) } : []
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard (1...2).contains(arguments.count) else { fail("usage: set-up \"<button title>\" [\"<menu item title>\"]") }
guard AXIsProcessTrusted() else { fail("this shell lacks Accessibility") }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.emir.hyperpoint.dev").first
else { fail("Hyperpoint Dev is not running") }
let element = AXUIElementCreateApplication(app.processIdentifier)

func settingsWindow() -> AXUIElement? {
    (attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []).first { window in
        children(window).contains { role($0) == kAXToolbarRole }
    }
}

if settingsWindow() == nil, let bar = attribute(element, "AXExtrasMenuBar"), let item = children(bar as! AXUIElement).first {
    AXUIElementPerformAction(item, kAXPressAction as CFString)
    usleep(300_000)
    if let settings = descendants(item).first(where: { title($0) == "Settings…" }) {
        AXUIElementPerformAction(settings, kAXPressAction as CFString)
    }
    usleep(1_000_000)
}
guard let window = settingsWindow(), let toolbar = children(window).first(where: { role($0) == kAXToolbarRole })
else { fail("no settings window") }
guard let devices = children(toolbar).first(where: { title($0) == "Devices" }) else { fail("no Devices tab") }
AXUIElementPerformAction(devices, kAXPressAction as CFString)
usleep(700_000)

// A Set Up button with a menu is a pop-up button holding the button itself and a separate menu button.
guard let button = descendants(window).first(where: { role($0) == kAXButtonRole && title($0) == arguments[0] })
else { fail("no button \"\(arguments[0])\" on Devices") }
if arguments.count == 1 {
    AXUIElementPerformAction(button, kAXPressAction as CFString)
    print("pressed \"\(arguments[0])\"")
} else {
    let parent = attribute(button, kAXParentAttribute).map { $0 as! AXUIElement }
    guard let menuButton = parent.flatMap({ children($0).first { role($0) == kAXMenuButtonRole } })
    else { fail("\"\(arguments[0])\" has no menu") }
    AXUIElementPerformAction(menuButton, kAXShowMenuAction as CFString)
    usleep(700_000)
    let items = descendants(element).filter { role($0) == kAXMenuItemRole }
    guard let item = items.first(where: { title($0) == arguments[1] })
    else { fail("no item \"\(arguments[1])\" in the menu of \"\(arguments[0])\"") }
    AXUIElementPerformAction(item, kAXPressAction as CFString)
    print("chose \"\(arguments[1])\" from \"\(arguments[0])\"")
}
usleep(1_500_000)
