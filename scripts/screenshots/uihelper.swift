// The UI scripting helper of the screenshot capture (spec 024 FR-018 to
// FR-021, research R10). capture.sh compiles it with swiftc into
// build/screenshots/uihelper and calls one subcommand per step.
//
// Every subcommand prints one line per result as key=value pairs, a title or
// name last, and exits 0. On failure it prints `error: <message>` on stderr
// and exits 1; a usage error exits 2.
//
//   perms                     accessibility=, screenRecording=, automation=
//                             (Automation for System Events: granted, denied,
//                             notAsked or unknown; never prompts)
//   display                   scale= of the main display
//   statusitem <pid>          frame of the app's status item (Accessibility)
//   windows <pid>             id=, layer=, frame and title= of each on-screen window
//   frame <pid> <identifier>  frame of the element with that accessibility identifier
//   scrollto <pid> <identifier>
//                             scrolls the element fully into its scroll area's
//                             visible part, then prints its frame
//   press <pid> <id|title> [--in <identifier>]
//                             presses the element with that identifier, title or
//                             description, inside the element with the --in
//                             identifier when given; clicks its center when it has
//                             no press
//   click <x> <y>             a left click at a screen point
//   quit <bundle-id> [--force]
//                             quits the app and waits up to 10 s (quit=done|none);
//                             with --force an app still running is then force quit
//
// Frames are in screen points with the origin at the top left of the main
// display, the coordinates of CGWindowList and CGEvent. Lookups by
// identifier or title retry for up to UIHELPER_WAIT seconds (default 5),
// since SwiftUI builds its accessibility tree lazily.

import AppKit
import ApplicationServices

func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(status)
}

func usage() -> Never {
    fail("usage: uihelper perms | display | statusitem <pid> | windows <pid> | frame <pid> <identifier> | "
         + "press <pid> <identifier or title> | click <x> <y> | quit <bundle-id>", status: 2)
}

func format(_ rect: CGRect) -> String {
    String(format: "x=%.1f y=%.1f w=%.1f h=%.1f", rect.minX, rect.minY, rect.width, rect.height)
}

func pid(_ text: String) -> pid_t {
    guard let value = Int32(text), value > 0 else { fail("not a process id: \(text)", status: 2) }
    return value
}

func point(_ x: String, _ y: String) -> CGPoint {
    guard let px = Double(x), let py = Double(y) else { fail("not a point: \(x) \(y)", status: 2) }
    return CGPoint(x: px, y: py)
}

// MARK: Accessibility

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func string(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

/// An application element. Every Accessibility call of this process gives
/// up after 2 s (set on the system-wide element), so a busy app cannot stall
/// a lookup for the system default of about 6 s per call.
func application(_ pid: pid_t) -> AXUIElement {
    AXUIElementCreateApplication(pid)
}

func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
    guard let value = attribute(element, name), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
    return (value as! [AXUIElement])
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = attribute(element, kAXPositionAttribute), let sizeValue = attribute(element, kAXSizeAttribute),
          CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: position, size: size)
}

/// Breadth first over the app's windows, its status item menu bar and all
/// their children, at most `limit` elements.
func find(in app: AXUIElement, limit: Int = 50_000, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
    var queue = elements(app, kAXWindowsAttribute) + elements(app, kAXChildrenAttribute)
    // A container (not an application) is searched from itself.
    if queue.isEmpty || string(app, kAXRoleAttribute) != kAXApplicationRole { queue = elements(app, kAXChildrenAttribute) }
    if let extras = attribute(app, kAXExtrasMenuBarAttribute), CFGetTypeID(extras) == AXUIElementGetTypeID() {
        queue.append(extras as! AXUIElement)
    }
    var index = 0
    while index < queue.count, index < limit {
        let element = queue[index]
        index += 1
        if matches(element) { return element }
        queue += elements(element, kAXChildrenAttribute)
    }
    return nil
}

func hasPress(_ element: AXUIElement) -> Bool {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success, let actions = names as? [String] else { return false }
    return actions.contains(kAXPressAction)
}

/// Retries `lookup` until it finds something or the wait is over.
func waiting<T>(_ lookup: () -> T?) -> T? {
    let wait = Double(ProcessInfo.processInfo.environment["UIHELPER_WAIT"] ?? "") ?? 5
    let deadline = Date().addingTimeInterval(wait)
    repeat {
        if let found = lookup() { return found }
        Thread.sleep(forTimeInterval: 0.25)
    } while Date() < deadline
    return nil
}

func element(pid: pid_t, identifier: String) -> AXUIElement? {
    let app = application(pid)
    return waiting { find(in: app) { string($0, "AXIdentifier") == identifier } }
}

func element(pid: pid_t, identifierOrTitle text: String, within scope: String? = nil) -> AXUIElement? {
    let app = application(pid)
    return waiting {
        var roots = [app]
        if let scope {
            guard let container = find(in: app, where: { string($0, "AXIdentifier") == scope }) else { return nil }
            roots = [container]
        }
        // By title, a pressable element first (a toolbar button before a
        // window of the same title); a window itself never counts.
        func titled(_ element: AXUIElement) -> Bool {
            string(element, kAXRoleAttribute) != kAXWindowRole
                && [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains { string(element, $0) == text }
        }
        for root in roots {
            if let found = find(in: root, where: { string($0, "AXIdentifier") == text })
                ?? find(in: root, where: { titled($0) && hasPress($0) })
                ?? find(in: root, where: titled) {
                return found
            }
        }
        return nil
    }
}

// MARK: Events

func post(_ type: CGEventType, at location: CGPoint) {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left) else {
        fail("cannot create a mouse event")
    }
    event.post(tap: .cghidEventTap)
}

/// A scroll wheel event of `pixels` lines at `location`; negative moves the
/// content up.
func scroll(_ pixels: Int32, at location: CGPoint) {
    guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: pixels, wheel2: 0, wheel3: 0) else {
        fail("cannot create a scroll event")
    }
    event.location = location
    event.post(tap: .cghidEventTap)
}

/// The nearest ancestor of `element` with the scroll area role.
func scrollArea(of element: AXUIElement) -> AXUIElement? {
    var current = element
    for _ in 0..<50 {
        guard let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        current = parent as! AXUIElement
        if string(current, kAXRoleAttribute) == kAXScrollAreaRole { return current }
    }
    return nil
}

func click(_ location: CGPoint) {
    post(.mouseMoved, at: location)
    Thread.sleep(forTimeInterval: 0.05)
    post(.leftMouseDown, at: location)
    Thread.sleep(forTimeInterval: 0.05)
    post(.leftMouseUp, at: location)
}

// MARK: Subcommands

AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2)
let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

switch (command, arguments.count) {
case ("perms", 1):
    let accessibility = AXIsProcessTrusted()
    let screenRecording = CGPreflightScreenCaptureAccess()
    let automation: String
    let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
    if let desc = target.aeDesc {
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false) {
        case noErr: automation = "granted"
        case OSStatus(errAEEventNotPermitted): automation = "denied"
        case OSStatus(errAEEventWouldRequireUserConsent): automation = "notAsked"
        default: automation = "unknown"
        }
    } else {
        automation = "unknown"
    }
    print("accessibility=\(accessibility) screenRecording=\(screenRecording) automation=\(automation)")

case ("display", 1):
    // The first screen holds the menu bar.
    guard let screen = NSScreen.screens.first else { fail("no display") }
    print(String(format: "scale=%.0f", screen.backingScaleFactor))

case ("statusitem", 2):
    let app = application(pid(arguments[1]))
    let found: CGRect? = waiting {
        guard let extras = attribute(app, kAXExtrasMenuBarAttribute), CFGetTypeID(extras) == AXUIElementGetTypeID() else { return nil }
        return elements(extras as! AXUIElement, kAXChildrenAttribute).first.flatMap(frame(of:))
    }
    guard let rect = found, rect.width > 0 else { fail("menubar item not found") }
    print(format(rect))

case ("windows", 2):
    let owner = pid(arguments[1])
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in list where (info[kCGWindowOwnerPID as String] as? Int32) == owner {
        guard let number = info[kCGWindowNumber as String] as? Int,
              let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { continue }
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        let title = info[kCGWindowName as String] as? String ?? ""
        print("id=\(number) layer=\(layer) \(format(bounds)) title=\(title)")
    }

case ("frame", 3):
    guard let found = element(pid: pid(arguments[1]), identifier: arguments[2]), let rect = frame(of: found) else {
        fail("no element with identifier \(arguments[2])")
    }
    print(format(rect))

case ("scrollto", 3):
    guard let found = element(pid: pid(arguments[1]), identifier: arguments[2]), var rect = frame(of: found) else {
        fail("no element with identifier \(arguments[2])")
    }
    // Without a scroll area the element is shown as it is.
    if let area = scrollArea(of: found), let visible = frame(of: area) {
        guard rect.height <= visible.height else { fail("\(arguments[2]) is taller than its scroll area") }
        // The crop adds 2 points above and below, so the element keeps up to
        // 4 points from the visible edges; flush against the bottom edge the
        // crop would take a sliver of the pinned footer's band (spec 028
        // FR-007).
        let margin = min(4, (visible.height - rect.height) / 2)
        let inner = visible.insetBy(dx: 0, dy: margin)
        // Scroll wheel steps toward the element until it lies inside the
        // visible part; the steps shrink so they do not overshoot.
        var tries = 0
        while rect.minY < inner.minY || rect.maxY > inner.maxY {
            guard tries < 60 else { fail("\(arguments[2]) did not scroll into view") }
            let distance = rect.maxY > inner.maxY ? inner.maxY - rect.maxY : inner.minY - rect.minY
            scroll(Int32(max(-60, min(60, distance.rounded(distance < 0 ? .down : .up)))), at: CGPoint(x: visible.midX, y: visible.midY))
            Thread.sleep(forTimeInterval: 0.15)
            guard let moved = frame(of: found) else { fail("\(arguments[2]) disappeared while scrolling") }
            rect = moved
            tries += 1
        }
    }
    print(format(rect))

case ("press", 3), ("press", 5):
    var scope: String?
    if arguments.count == 5 {
        guard arguments[3] == "--in" else { usage() }
        scope = arguments[4]
    }
    guard let named = element(pid: pid(arguments[1]), identifierOrTitle: arguments[2], within: scope) else {
        fail("no element named \(arguments[2])" + (scope.map { " in \($0)" } ?? ""))
    }
    // A container found by identifier (such as the Details group) has no
    // press of its own; its first pressable descendant (the disclosure
    // triangle) is what a click would hit.
    var found = named
    if !hasPress(named) {
        var queue = elements(named, kAXChildrenAttribute)
        var index = 0
        while index < queue.count, index < 500 {
            if hasPress(queue[index]) { found = queue[index]; break }
            queue += elements(queue[index], kAXChildrenAttribute)
            index += 1
        }
    }
    // A press that opens a menu often answers "cannot complete" while the
    // menu tracks: it was delivered. Any other failure falls back to Show
    // Menu and then to a click on the element's center.
    func delivered(_ error: AXError) -> Bool {
        error == .success || error == .cannotComplete
    }
    if !delivered(AXUIElementPerformAction(found, kAXPressAction as CFString)),
       !delivered(AXUIElementPerformAction(found, kAXShowMenuAction as CFString)) {
        guard let rect = frame(of: found) else { fail("\(arguments[2]) cannot be pressed") }
        click(CGPoint(x: rect.midX, y: rect.midY))
    }
    print("pressed=\(arguments[2])")

case ("click", 3):
    click(point(arguments[1], arguments[2]))
    print("clicked=\(arguments[1]),\(arguments[2])")

case ("quit", 2), ("quit", 3):
    let bundleId = arguments[1]
    let force = arguments.count == 3 && arguments[2] == "--force"
    if arguments.count == 3 && !force { usage() }
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    guard !running.isEmpty else {
        print("quit=none")
        exit(0)
    }
    running.forEach { $0.terminate() }
    let deadline = Date().addingTimeInterval(10)
    while running.contains(where: { !$0.isTerminated }), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    if force, !running.allSatisfy(\.isTerminated) {
        running.forEach { $0.forceTerminate() }
        let forced = Date().addingTimeInterval(3)
        while running.contains(where: { !$0.isTerminated }), Date() < forced {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }
    guard running.allSatisfy(\.isTerminated) else { fail("\(bundleId) did not quit within 10 s") }
    print("quit=done")

default:
    usage()
}
