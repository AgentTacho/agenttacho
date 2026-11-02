import Foundation

/// The window a subscription account's menu bar value and section header
/// follow, as the user chose it in the dropdown (spec 027 Key Entities
/// "Headline choice", FR-010). Absent (nil) means the default window.
/// Stored with the account as `headlineWindow` (research R2).
public enum HeadlineChoice: Equatable, Hashable, Sendable {
    /// A Claude window by its identity (spec 040 FR-004, FR-015):
    /// `fiveHour`, `sevenDay`, `model:<name>` (matched exactly, spec 027
    /// FR-006), `model:<name>:<kind>` or `limit:<kind>`.
    case claude(ClaudeWindow)
    /// A Codex plan window by its spec 007 FR-009 name ("5-hour", "weekly").
    case codexWindow(String)

    /// The configuration file's value: the Claude identity or
    /// `"window:<name>"` (contracts/config-file.md, spec 040
    /// contracts/config-and-last-good.md).
    public var stored: String {
        switch self {
        case .claude(let window): return window.rawValue
        case .codexWindow(let name): return "window:\(name)"
        }
    }

    /// The choice of a stored value, or nil when it names no known kind of
    /// window or one of the other account kind (FR-010): Claude values for a
    /// subscription account (`fiveHour`, `sevenDay`, `model:` or `limit:`
    /// with a non-empty rest, spec 040 FR-015), `window:` values for a Codex
    /// account. A Codex name must read `N-hour`, `N-day` (N at least 1) or
    /// `weekly`.
    public static func parse(_ raw: String, forCodex: Bool) -> HeadlineChoice? {
        if forCodex {
            guard raw.hasPrefix("window:") else { return nil }
            let name = String(raw.dropFirst("window:".count))
            return isCodexWindowName(name) ? .codexWindow(name) : nil
        }
        if raw == ClaudeWindow.fiveHour.rawValue || raw == ClaudeWindow.sevenDay.rawValue {
            return .claude(ClaudeWindow(rawValue: raw))
        }
        for prefix in ["model:", "limit:"] where raw.hasPrefix(prefix) {
            return raw.count > prefix.count ? .claude(ClaudeWindow(rawValue: raw)) : nil
        }
        return nil
    }

    /// The Claude window this choice names; nil for a Codex window.
    public var claudeWindow: ClaudeWindow? {
        switch self {
        case .claude(let window): return window
        case .codexWindow: return nil
        }
    }

    /// True for the names `CodexLimitWindow.name` produces: "weekly", or a
    /// whole number of at least 1 in its plain form followed by "-hour" or
    /// "-day".
    private static func isCodexWindowName(_ name: String) -> Bool {
        if name == "weekly" { return true }
        for suffix in ["-hour", "-day"] where name.hasSuffix(suffix) {
            let digits = String(name.dropLast(suffix.count))
            guard let count = Int(digits), count >= 1, String(count) == digits else { return false }
            return true
        }
        return false
    }
}

/// The stored string as a single value. `Account` decodes the key itself,
/// tolerantly and with the account kind (spec 027 FR-010); this conformance
/// only keeps the settings types `Codable`.
extension HeadlineChoice: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let choice = HeadlineChoice.parse(raw, forCodex: raw.hasPrefix("window:")) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "Unknown headline window \"\(raw)\""))
        }
        self = choice
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(stored)
    }
}
