import Foundation

/// Another running AgentTacho, or a running AgentMeter (spec 023 FR-012),
/// found when a copy starts. AgentTacho runs only once: the new copy shows
/// this instance with a kill command and quits, so two copies never poll the
/// usage endpoints or write the same configuration at the same time.
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

    /// AgentTacho's bundle identifier.
    public static let ownBundleIdentifier = "dev.rhuss.agenttacho"
    /// AgentMeter's, the app's former name, which counts as another running
    /// copy (spec 023 FR-012).
    public static let legacyBundleIdentifier = "dev.rhuss.agentmeter"
    public static let ownAppName = "AgentTacho"
    public static let legacyAppName = "AgentMeter"

    /// The bundle identifiers whose processes count as another running copy:
    /// the running app's own (the official one when unknown) and AgentMeter's
    /// (spec 023 FR-012).
    public static func watchedBundleIdentifiers(own: String?) -> Set<String> {
        [own ?? ownBundleIdentifier, legacyBundleIdentifier]
    }

    public var pid: Int32
    public var bundlePath: String?
    public var versionText: String?
    /// "AgentTacho" or "AgentMeter", from the process's bundle identifier.
    public var appName: String

    public init(pid: Int32, bundlePath: String?, versionText: String?, appName: String = RunningInstance.ownAppName) {
        self.pid = pid
        self.bundlePath = bundlePath
        self.versionText = versionText
        self.appName = appName
    }

    public init(_ process: Process) {
        self.init(pid: process.pid, bundlePath: process.bundlePath, versionText: process.versionText,
                  appName: Self.appName(forBundleIdentifier: process.bundleIdentifier))
    }

    /// "AgentMeter" for the legacy identifier, "AgentTacho" for anything else.
    public static func appName(forBundleIdentifier id: String?) -> String {
        id == legacyBundleIdentifier ? legacyAppName : ownAppName
    }

    /// The other, still running processes whose bundle identifier is one of
    /// the given ones (own and legacy, spec 023 FR-012).
    public static func others(from processes: [Process], ownPID: Int32, bundleIdentifiers: Set<String>) -> [RunningInstance] {
        processes
            .filter { process in
                process.pid != ownPID && !process.isTerminated
                    && process.bundleIdentifier.map(bundleIdentifiers.contains) == true
            }
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
        var text = appName
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
