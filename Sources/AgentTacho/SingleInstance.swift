import AppKit
import UsageCore

/// AgentTacho runs only once. At launch, before the model starts refreshing,
/// a second copy looks for another running AgentTacho (same bundle id, for
/// example the installed app and a build from `build/`) or a running
/// AgentMeter, its former name (spec 023 FR-012). This runs before
/// `AppModel` copies AgentMeter's settings, so AgentMeter is no longer
/// writing them while they are copied. If it finds one, it
/// shows that instance's version, location and process with a copyable kill
/// command. The user can stop the running copy and continue with this one,
/// copy the command, or quit; quitting leaves the configuration and the log
/// untouched.
@MainActor
enum SingleInstance {
    /// Seconds to wait for the running copy to quit after asking it to.
    private static let stopTimeout: TimeInterval = 5

    /// Handles every other running copy in turn, looking again after each
    /// one was stopped, so neither a second AgentTacho nor AgentMeter keeps
    /// running next to this one.
    static func ensure() {
        let identifiers = RunningInstance.watchedBundleIdentifiers(own: Bundle.main.bundleIdentifier)
        while true {
            let apps = identifiers.sorted().flatMap(NSRunningApplication.runningApplications(withBundleIdentifier:))
            guard let other = RunningInstance.others(from: apps.map(process),
                                                     ownPID: ProcessInfo.processInfo.processIdentifier,
                                                     bundleIdentifiers: identifiers).first,
                  let running = apps.first(where: { $0.processIdentifier == other.pid })
            else { return }
            switch showAlert(for: other) {
            case .stopAndContinue:
                if stop(running) { continue }
                showStopFailed(for: other)
                exit(0)
            case .quit:
                exit(0)
            }
        }
    }

    private static func process(_ app: NSRunningApplication) -> RunningInstance.Process {
        RunningInstance.Process(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier,
                                bundlePath: app.bundleURL?.path, isTerminated: app.isTerminated,
                                versionText: app.bundleURL.flatMap(versionText(ofBundleAt:)))
    }

    /// Asks the running copy to quit, as its own Quit button does, and waits
    /// until it has. True when it is gone within the timeout.
    private static func stop(_ app: NSRunningApplication) -> Bool {
        guard app.terminate() || app.isTerminated else { return false }
        let deadline = Date().addingTimeInterval(stopTimeout)
        while !app.isTerminated && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return app.isTerminated
    }

    private enum Choice {
        case stopAndContinue
        case quit
    }

    /// The other bundle's version as the About tab shows it, nil when its
    /// Info.plist has none.
    private static func versionText(ofBundleAt url: URL) -> String? {
        let info = AppVersionInfo(infoDictionary: Bundle(url: url)?.infoDictionary ?? [:])
        return info.version == nil ? nil : info.versionText
    }

    private static func showAlert(for other: RunningInstance) -> Choice {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(other.appName) is already running"
        alert.informativeText = other.summary()
            + "\n\nStop it and start this AgentTacho instead, or stop it yourself with the command below."

        let command = NSTextField(labelWithString: other.killCommand)
        command.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        command.isSelectable = true
        command.sizeToFit()
        alert.accessoryView = command

        alert.addButton(withTitle: "Stop It and Start This One")
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Quit")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .stopAndContinue
        case .alertSecondButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(other.killCommand, forType: .string)
            return .quit
        default:
            return .quit
        }
    }

    private static func showStopFailed(for other: RunningInstance) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The running \(other.appName) did not quit"
        alert.informativeText = "Process \(other.pid) is still running. Stop it with the command below, then start AgentTacho again."
        let command = NSTextField(labelWithString: other.killCommand)
        command.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        command.isSelectable = true
        command.sizeToFit()
        alert.accessoryView = command
        alert.addButton(withTitle: "Quit")
        alert.runModal()
    }
}
