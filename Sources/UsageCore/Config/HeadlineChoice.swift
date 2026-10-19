import Foundation

/// The window a subscription account's menu bar value and section header
/// follow, as the user chose it in the dropdown (spec 027 Key Entities
/// "Headline choice", FR-010). Absent (nil) means the default window.
/// Stored with the account as `headlineWindow` (research R2).
public enum HeadlineChoice: Equatable, Hashable, Sendable {
    /// The Claude 5-hour window.
    case claudeFiveHour
    /// The Claude 7-day window, the default; a click never stores it.
    case claudeSevenDay
    /// A Claude model limit by its model name, matched exactly (FR-006).
    case claudeModel(String)
    /// A Codex plan window by its spec 007 FR-009 name ("5-hour", "weekly").
    case codexWindow(String)

    /// The configuration file's value: `"fiveHour"`, `"sevenDay"`,
    /// `"model:<name>"` or `"window:<name>"` (contracts/config-file.md).
    public var stored: String {
        switch self {
        case .claudeFiveHour: return "fiveHour"
        case .claudeSevenDay: return "sevenDay"
        case .claudeModel(let name): return "model:\(name)"
        case .codexWindow(let name): return "window:\(name)"
        }
    }

    /// The choice of a stored value, or nil when it names no known kind of
    /// window or one of the other account kind (FR-010): Claude values for a
    /// subscription account, `window:` values for a Codex account. A model
    /// name must not be empty; a Codex name must read `N-hour`, `N-day`
    /// (N at least 1) or `weekly`.
    public static func parse(_ raw: String, forCodex: Bool) -> HeadlineChoice? {
        if forCodex {
            guard raw.hasPrefix("window:") else { return nil }
            let name = String(raw.dropFirst("window:".count))
            return isCodexWindowName(name) ? .codexWindow(name) : nil
        }
        switch raw {
        case "fiveHour": return .claudeFiveHour
        case "sevenDay": return .claudeSevenDay
        default:
            guard raw.hasPrefix("model:") else { return nil }
            let name = String(raw.dropFirst("model:".count))
            return name.isEmpty ? nil : .claudeModel(name)
        }
    }

    /// The Claude window this choice names; nil for a Codex window.
    public var claudeWindow: ClaudeWindow? {
        switch self {
        case .claudeFiveHour: return .fiveHour
        case .claudeSevenDay: return .sevenDay
        case .claudeModel(let name): return .model(name)
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
