import Foundation

/// Well-known file locations with an injectable home directory for tests.
public struct Paths: Sendable {
    public let home: URL
    /// The folder name of AgentTacho's own files below `.config`,
    /// `Library/Logs` and `Library/Application Support`: `agenttacho`, or
    /// `agenttacho-demo` for the demo build (spec 024 FR-005).
    public let appFolder: String

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, appFolder: String = "agenttacho") {
        self.home = home.standardizedFileURL
        self.appFolder = appFolder
    }

    /// Expands a leading `~` or `~/` to the home directory and strips a trailing slash.
    /// Only builds a string: the explicit `isDirectory` keeps Foundation from
    /// statting the path, so the demo build never touches `~/.claude`
    /// (spec 024 SC-002).
    public func expand(_ path: String) -> String {
        var result: String
        if path == "~" {
            result = home.path
        } else if path.hasPrefix("~/") {
            result = home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: false).path
        } else {
            result = path
        }
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    /// `~/.config/<appFolder>/config.json`
    public var configFileURL: URL {
        home.appendingPathComponent(".config/\(appFolder)/config.json")
    }

    /// `~/.config/<appFolder>/imported-prices.json`: imported price
    /// batches, kept apart from `config.json` (FR-025).
    public var importedPricesFileURL: URL {
        home.appendingPathComponent(".config/\(appFolder)/imported-prices.json")
    }

    /// `~/Library/Logs/<appFolder>/usage.log`
    public var logFileURL: URL {
        home.appendingPathComponent("Library/Logs/\(appFolder)/usage.log")
    }

    /// `~/Library/Application Support/<appFolder>/last-good.json`: the last
    /// good plan limits per account across launches (spec 010 FR-014).
    public var lastGoodFileURL: URL {
        home.appendingPathComponent("Library/Application Support/\(appFolder)/last-good.json")
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
