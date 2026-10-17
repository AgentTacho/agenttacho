import Foundation

/// Another running AgentTacho, found when a second copy starts. AgentTacho
/// runs only once: the second copy shows this instance with a kill command
/// and quits, so two copies never poll the usage endpoints or write the same
/// configuration at the same time.
public struct RunningInstance: Equatable, Sendable {
    /// A running process as the app sees it (from `NSRunningApplication`),
    /// kept free of AppKit so the selection can be tested.
    public struct Process: Equatable, Sendable {
        public var pid: Int32
        public var bundleIdentifier: String?
        public var bundlePath: String?
        public var isTerminated: Bool
        /// `AppVersionInfo.versionText` of the bundle, nil when unknown.
        public var versionText: String?

        public init(pid: Int32, bundleIdentifier: String?, bundlePath: String?, isTerminated: Bool, versionText: String?) {
            self.pid = pid
            self.bundleIdentifier = bundleIdentifier
            self.bundlePath = bundlePath
            self.isTerminated = isTerminated
            self.versionText = versionText
        }
    }

    public var pid: Int32
    public var bundlePath: String?
    public var versionText: String?

    public init(pid: Int32, bundlePath: String?, versionText: String?) {
        self.pid = pid
        self.bundlePath = bundlePath
        self.versionText = versionText
    }

    public init(_ process: Process) {
        self.init(pid: process.pid, bundlePath: process.bundlePath, versionText: process.versionText)
    }

    /// The other, still running processes with AgentTacho's bundle id.
    public static func others(from processes: [Process], ownPID: Int32, bundleIdentifier: String) -> [RunningInstance] {
        processes
            .filter { $0.pid != ownPID && !$0.isTerminated && $0.bundleIdentifier == bundleIdentifier }
            .map(RunningInstance.init)
    }

    /// The command that stops this instance, for copying into a terminal.
    public var killCommand: String {
        "kill \(pid)"
    }

    /// "AgentTacho 0.3.0 (build 72) is already running from
    /// /Applications/AgentTacho.app (process 2512).", with paths under the
    /// home directory shortened to `~`.
    public func summary(paths: Paths = Paths()) -> String {
        var text = "AgentTacho"
        if let versionText { text += " \(versionText)" }
        text += " is already running"
        if let bundlePath { text += " from \(Self.abbreviated(bundlePath, home: paths.home.path))" }
        return text + " (process \(pid))."
    }

    private static func abbreviated(_ path: String, home: String) -> String {
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
