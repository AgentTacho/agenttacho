import Foundation

/// Well-known file locations with an injectable home directory for tests.
public struct Paths: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL
    }

    /// Expands a leading `~` or `~/` to the home directory and strips a trailing slash.
    public func expand(_ path: String) -> String {
        var result: String
        if path == "~" {
            result = home.path
        } else if path.hasPrefix("~/") {
            result = home.appendingPathComponent(String(path.dropFirst(2))).path
        } else {
            result = path
        }
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    /// `~/.config/llm-usage-menubar/config.json`
    public var configFileURL: URL {
        home.appendingPathComponent(".config/llm-usage-menubar/config.json")
    }

    /// `~/Library/Logs/llm-usage-menubar/usage.log`
    public var logFileURL: URL {
        home.appendingPathComponent("Library/Logs/llm-usage-menubar/usage.log")
    }

    /// `~/.claude`, unexpanded form as stored in configuration files.
    public static let defaultClaudeDirectory = "~/.claude"

    /// `~/.claude`, expanded against this instance's home.
    public var defaultClaudeDirectoryPath: String {
        expand(Paths.defaultClaudeDirectory)
    }
}
