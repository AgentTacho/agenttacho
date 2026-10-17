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

    /// `~/.config/agenttacho`: the configuration folder. Whether it exists
    /// decides if AgentMeter's settings are copied (spec 023 FR-007, FR-008).
    public var configDirectoryURL: URL {
        home.appendingPathComponent(".config/agenttacho")
    }

    /// `~/.config/agenttacho/config.json`
    public var configFileURL: URL {
        configDirectoryURL.appendingPathComponent("config.json")
    }

    /// `~/.config/agenttacho/imported-prices.json`: imported price
    /// batches, kept apart from `config.json` (FR-025).
    public var importedPricesFileURL: URL {
        configDirectoryURL.appendingPathComponent("imported-prices.json")
    }

    /// `~/Library/Logs/agenttacho/usage.log`
    public var logFileURL: URL {
        home.appendingPathComponent("Library/Logs/agenttacho/usage.log")
    }

    /// `~/Library/Application Support/agenttacho/last-good.json`: the last
    /// good plan limits per account across launches (spec 010 FR-014).
    public var lastGoodFileURL: URL {
        home.appendingPathComponent("Library/Application Support/agenttacho/last-good.json")
    }

    /// `~/.config/agentmeter/config.json`, AgentMeter's configuration. Only
    /// ever read, once, by `LegacyDataMove` (spec 023 FR-008, FR-009).
    public var legacyConfigFileURL: URL {
        home.appendingPathComponent(".config/agentmeter/config.json")
    }

    /// `~/.config/agentmeter/imported-prices.json`, read once by
    /// `LegacyDataMove` (spec 023 FR-008, FR-009).
    public var legacyImportedPricesFileURL: URL {
        home.appendingPathComponent(".config/agentmeter/imported-prices.json")
    }

    /// `~/Library/Application Support/agentmeter/last-good.json`, read once
    /// by `LegacyDataMove` (spec 023 FR-008, FR-009).
    public var legacyLastGoodFileURL: URL {
        home.appendingPathComponent("Library/Application Support/agentmeter/last-good.json")
    }

    /// `~/Library/Logs/agentmeter`, AgentMeter's log folder: never read or
    /// written, only kept out of reach of the copy (spec 023 FR-009).
    public var legacyLogDirectoryURL: URL {
        home.appendingPathComponent("Library/Logs/agentmeter")
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
