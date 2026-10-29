// Presses an item of Hyperpoint's menu bar menu by its title, as a click does, and prints the item's checkmark state
// before the press. Needs Accessibility for the calling shell.
import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func title(_ element: AXUIElement) -> String { attribute(element, kAXTitleAttribute) as? String ?? "" }

func descendants(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    depth < 6 ? [element] + children(element).flatMap { descendants($0, depth: depth + 1) } : []
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("usage: menu \"<item title>\"") }
let wanted = CommandLine.arguments[1]
guard AXIsProcessTrusted() else { fail("this shell lacks Accessibility") }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.emir.hyperpoint.dev").first
else { fail("Hyperpoint Dev is not running") }
let element = AXUIElementCreateApplication(app.processIdentifier)
guard let bar = attribute(element, "AXExtrasMenuBar"), let status = children(bar as! AXUIElement).first
else { fail("no menu bar item") }
AXUIElementPerformAction(status, kAXPressAction as CFString)
usleep(300_000)
// Cancel goes to the open menu: sent to the status item it leaves the menu open, and the app then answers no Apple
// event, quit included, until someone closes it.
func close() { children(status).forEach { AXUIElementPerformAction($0, kAXCancelAction as CFString) } }
guard let item = descendants(status).first(where: { title($0) == wanted }) else {
    close()
    fail("no menu item \"\(wanted)\"")
}
guard attribute(item, kAXEnabledAttribute) as? Bool ?? false else {
    close()
    fail("menu item \"\(wanted)\" is disabled")
}
let checked = (attribute(item, "AXMenuItemMarkChar") as? String).map { !$0.isEmpty } ?? false
AXUIElementPerformAction(item, kAXPressAction as CFString)
print("pressed \"\(wanted)\", which was \(checked ? "checked" : "not checked")")
usleep(1_500_000)
