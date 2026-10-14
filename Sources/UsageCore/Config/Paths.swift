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

    /// `~/.config/llm-usage-menubar/imported-prices.json`: imported price
    /// batches, kept apart from `config.json` (FR-025).
    public var importedPricesFileURL: URL {
        home.appendingPathComponent(".config/llm-usage-menubar/imported-prices.json")
    }

    /// `~/Library/Logs/llm-usage-menubar/usage.log`
    public var logFileURL: URL {
        home.appendingPathComponent("Library/Logs/llm-usage-menubar/usage.log")
    }

    /// `~/.claude`, unexpanded form as stored in configuration files.
    public static let defaultClaudeDirectory = "~/.claude"

    /// `~/.codex`, the default Codex home, unexpanded (spec 006 FR-002).
    public static let defaultCodexHome = "~/.codex"

    /// `~/.local/share/opencode`, the default OpenCode data directory,
    /// unexpanded (spec 006 FR-002).
    public static let defaultOpenCodeDirectory = "~/.local/share/opencode"

    /// `~/.claude`, expanded against this instance's home.
    public var defaultClaudeDirectoryPath: String {
        expand(Paths.defaultClaudeDirectory)
    }
}
