import AppKit
import UsageCore

/// Opens the dropdown when the user clicks an AgentTacho notification
/// (spec 014 FR-013, research R6). SwiftUI's `MenuBarExtra` has no public
/// API to open its window, so the opener clicks the status item's button,
/// as a user would. Without the button, AgentTacho is brought to the front
/// and nothing else happens.
@MainActor
enum MenuBarOpener {
    static func open(log: DiagnosticLog) {
        guard let button = statusButton() else {
            NSApp.activate()
            log.append(source: "notifications", message: "notification click: activated app")
            return
        }
        // A click on an open dropdown would close it. The visibility check
        // relies on SwiftUI's window class name, so its outcome is logged
        // on its own line.
        if let window = visibleDropdownWindow() {
            log.append(source: "notifications",
                       message: "notification click: dropdown already open (\(String(describing: type(of: window))))")
            return
        }
        button.performClick(nil)
        log.append(source: "notifications", message: "notification click: opened dropdown")
    }

    /// The `NSStatusBarButton` of the app's status item, found in the
    /// content views of the app's windows.
    private static func statusButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            if let button = window.contentView.flatMap(findButton) {
                return button
            }
        }
        return nil
    }

    private static func findButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }

    /// The `MenuBarExtra` window while it is shown, nil otherwise.
    private static func visibleDropdownWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && String(describing: type(of: window)).contains("MenuBarExtra")
        }
    }
}
