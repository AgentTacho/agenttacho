import Foundation

/// Recognizes an installation managed by the Homebrew cask `agentmeter`
/// (spec 013 FR-012, research R7). Homebrew records an installed cask as a
/// link `<prefix>/Caskroom/agentmeter/<version>/AgentMeter.app` pointing at
/// the app it installed. The installation counts as Homebrew-managed only
/// when such a link points at the running app, so a disk image copy is not
/// mistaken for it because a cask was once installed (review M9). Reading
/// the file system is injected; the decision is pure.
public enum HomebrewDetector {
    /// The standard Homebrew prefixes (Apple silicon, Intel).
    public static let prefixes = ["/opt/homebrew", "/usr/local"]
    public static let caskName = "agentmeter"
    public static let appName = "AgentMeter.app"

    /// True when a Caskroom link of some installed version resolves to
    /// `runningAppPath`. `listVersions` returns the entries of a Caskroom
    /// folder (nil when it does not exist); `resolveLink` returns a link's
    /// destination (nil when the path is not a link).
    public static func isManaged(runningAppPath: String,
                                 listVersions: (String) -> [String]?,
                                 resolveLink: (String) -> String?) -> Bool {
        let running = normalized(runningAppPath)
        for prefix in prefixes {
            let caskroom = "\(prefix)/Caskroom/\(caskName)"
            for version in listVersions(caskroom) ?? [] where !version.hasPrefix(".") {
                let folder = "\(caskroom)/\(version)"
                guard let destination = resolveLink("\(folder)/\(appName)") else { continue }
                let absolute = URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: folder, isDirectory: true)).path
                if normalized(absolute) == running { return true }
            }
        }
        return false
    }

    /// `isManaged` on the real file system; reads only, never writes.
    public static func isManagedLive(runningAppPath: String) -> Bool {
        isManaged(runningAppPath: runningAppPath, listVersions: listVersionsLive, resolveLink: resolveLinkLive)
    }

    /// The entries of a folder, or nil when it cannot be read.
    public static func listVersionsLive(_ path: String) -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: path)
    }

    /// A link's destination as stored, or nil for anything else.
    public static func resolveLinkLive(_ path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    /// Standardized (`.` and `..` resolved), without a trailing slash and
    /// without the `/private` of `/private/var`, `/private/tmp` and
    /// `/private/etc`.
    static func normalized(_ path: String) -> String {
        var result = URL(fileURLWithPath: path).standardized.path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        for alias in ["/var", "/tmp", "/etc"] where result == "/private\(alias)" || result.hasPrefix("/private\(alias)/") {
            result.removeFirst("/private".count)
        }
        return result
    }
}
