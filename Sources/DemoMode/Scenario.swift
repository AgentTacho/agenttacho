import Foundation
import UsageCore

/// A problem with a scenario file, with the JSON path of the value it is
/// about (spec 024 FR-013, contracts/scenario-format.md). The demo app shows
/// `description` in the dropdown and the log.
public struct ScenarioError: Error, Equatable, Sendable, CustomStringConvertible {
    /// For example `frames[0].claude.acc-max.sevenDay.used`; empty for the
    /// file as a whole.
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var description: String {
        path.isEmpty ? message : "\(path): \(message)"
    }

    /// `claude.acc-max.sevenDay.used`, with array indices as `[0]`.
    static func path(_ codingPath: [CodingKey]) -> String {
        var result = ""
        for key in codingPath {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return result
    }

    /// A decoding error of the JSON layer, named by its path.
    static func decoding(_ error: DecodingError) -> ScenarioError {
        switch error {
        case .typeMismatch(let type, let context):
            return ScenarioError(path: path(context.codingPath), message: "expected \(typeName(type))")
        case .valueNotFound(let type, let context):
            return ScenarioError(path: path(context.codingPath), message: "expected \(typeName(type)), found null")
        case .keyNotFound(let key, let context):
            return ScenarioError(path: path(context.codingPath + [key]), message: "missing")
        case .dataCorrupted(let context):
            let text = context.debugDescription.isEmpty ? "invalid JSON" : context.debugDescription
            return ScenarioError(path: path(context.codingPath), message: text)
        @unknown default:
            return ScenarioError(path: "", message: String(describing: error))
        }
    }

    private static func typeName(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: return "a string"
        case is Int.Type: return "a whole number"
        case is Double.Type: return "a number"
        case is Bool.Type: return "true or false"
        default: return "\(type)"
        }
    }
}

/// Used percent and reset time of one plan window (data-model
/// "WindowValue"). The reset time is `launch + resetsIn` for the whole run.
public struct WindowValue: Equatable, Sendable, Decodable {
    public var used: Double
    public var resetsIn: ScenarioDuration

    public init(used: Double, resetsIn: ScenarioDuration) {
        self.used = used
        self.resetsIn = resetsIn
    }
}

/// A partial `WindowValue` in a frame: only the named fields change.
public struct WindowChange: Equatable, Sendable, Decodable {
    public var used: Double?
    public var resetsIn: ScenarioDuration?
}

/// The plan windows of one Claude subscription account (data-model
/// "ClaudeWindows").
public struct ClaudeWindows: Equatable, Sendable, Decodable {
    /// `pro` or `max`, reported as the subscription type.
    public var plan: String
    public var fiveHour: WindowValue
    public var sevenDay: WindowValue
    /// Model-scoped weekly limits, by model name (for example "Fable").
    public var models: [String: WindowValue]?
    /// Free limit resets of the account, shown as gift glyphs (spec 033
    /// FR-021).
    public var tickets: [ScenarioTicket]?
}

/// One free limit reset of a Claude subscription account (spec 033 FR-021,
/// research R7). It expires at `launch + expiresIn`; without `expiresIn` it
/// never expires.
public struct ScenarioTicket: Equatable, Sendable, Decodable {
    public var expiresIn: ScenarioDuration?

    public init(expiresIn: ScenarioDuration?) {
        self.expiresIn = expiresIn
    }
}

/// A frame's change to one Claude subscription account.
public struct ClaudeChange: Equatable, Sendable, Decodable {
    public var fiveHour: WindowChange?
    public var sevenDay: WindowChange?
    public var models: [String: WindowChange]?
}

/// One Codex plan window (data-model "CodexWindows").
public struct CodexWindowValue: Equatable, Sendable, Decodable {
    public var lengthMinutes: Int
    public var used: Double
    public var resetsIn: ScenarioDuration
}

/// The plan windows of one Codex subscription account.
public struct CodexWindows: Equatable, Sendable, Decodable {
    /// `plus` or `pro`, reported as the plan type.
    public var plan: String
    public var windows: [CodexWindowValue]
}

/// A frame's change to one Codex plan window, found by its length.
public struct CodexWindowChange: Equatable, Sendable, Decodable {
    public var lengthMinutes: Int
    public var used: Double?
    public var resetsIn: ScenarioDuration?
}

/// A frame's change to one Codex subscription account.
public struct CodexChange: Equatable, Sendable, Decodable {
    public var windows: [CodexWindowChange]
}

/// One token usage record of the scenario (data-model "UsageEntry").
public struct UsageEntry: Equatable, Sendable, Decodable {
    /// Before launch, for example `-2d3h`.
    public var at: ScenarioDuration
    public var account: String
    public var harness: Harness
    public var model: String
    /// Path-like, shown by its last component (`~/src/checkout-service`).
    public var project: String
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    /// Counted as 5-minute cache writes.
    public var cacheWrite: Int
}

/// A change at an offset after launch (spec 024 FR-012, data-model "Frame").
public struct Frame: Equatable, Sendable, Decodable {
    public var at: ScenarioDuration
    public var claude: [String: ClaudeChange]?
    public var codex: [String: CodexChange]?
    /// Records added from this frame on.
    public var usage: [UsageEntry]?
}

/// A made-up state of AgentTacho over the first minutes after launch
/// (spec 024 FR-010, FR-011, data-model "Scenario"). All times are relative
/// to launch.
public struct Scenario: Equatable, Sendable, Decodable {
    public let name: String
    /// Exactly the format of `config.json`, decoded with the app's decoder.
    public let configuration: Configuration
    /// Exactly the format of `imported-prices.json`.
    public let importedPrices: ImportedPrices?
    public let claude: [String: ClaudeWindows]
    public let codex: [String: CodexWindows]
    public let usage: [UsageEntry]
    public let frames: [Frame]

    private enum CodingKeys: String, CodingKey {
        case name, configuration, importedPrices, claude, codex, usage, frames
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        configuration = try c.decode(Configuration.self, forKey: .configuration)
        importedPrices = try c.decodeIfPresent(ImportedPrices.self, forKey: .importedPrices)
        claude = try c.decodeIfPresent([String: ClaudeWindows].self, forKey: .claude) ?? [:]
        codex = try c.decodeIfPresent([String: CodexWindows].self, forKey: .codex) ?? [:]
        usage = try c.decodeIfPresent([UsageEntry].self, forKey: .usage) ?? []
        frames = try c.decodeIfPresent([Frame].self, forKey: .frames) ?? []
    }

    /// Reads `<name>.json` and checks that its `name` matches the file name
    /// (spec 024 FR-013).
    public static func load(from url: URL) throws -> Scenario {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ScenarioError(path: "", message: "scenario file \(url.lastPathComponent) could not be read: \(error.localizedDescription)")
        }
        let scenario = try decode(data)
        let fileName = url.deletingPathExtension().lastPathComponent
        guard scenario.name == fileName else {
            throw ScenarioError(path: "name", message: "\"\(scenario.name)\" does not match the file name \"\(fileName)\"")
        }
        return scenario
    }

    /// Decodes and validates a scenario; every problem is a `ScenarioError`
    /// with the JSON path of the value (spec 024 FR-013).
    public static func decode(_ data: Data) throws -> Scenario {
        let scenario: Scenario
        do {
            scenario = try JSONDecoder().decode(Scenario.self, from: data)
        } catch let error as DecodingError {
            throw ScenarioError.decoding(error)
        }
        try scenario.validate()
        return scenario
    }

    /// The rules of data-model.md that decoding alone does not check.
    func validate() throws {
        do {
            try configuration.validate()
        } catch let error as ConfigurationError {
            throw ScenarioError(path: "configuration", message: error.message)
        }
        if let importedPrices {
            do {
                try importedPrices.validate()
            } catch {
                throw ScenarioError(path: "importedPrices", message: String(describing: error))
            }
        }
        for id in claude.keys.sorted() {
            try checkAccount(id, path: "claude.\(id)", kind: .claude)
            let windows = claude[id]!
            try checkWindow(windows.fiveHour, path: "claude.\(id).fiveHour")
            try checkWindow(windows.sevenDay, path: "claude.\(id).sevenDay")
            for name in (windows.models ?? [:]).keys.sorted() {
                try checkWindow(windows.models![name]!, path: "claude.\(id).models.\(name)")
            }
            for (index, ticket) in (windows.tickets ?? []).enumerated() {
                if let expiresIn = ticket.expiresIn { try checkReset(expiresIn, path: "claude.\(id).tickets[\(index)].expiresIn") }
            }
        }
        for id in codex.keys.sorted() {
            try checkAccount(id, path: "codex.\(id)", kind: .codex)
            for (index, window) in codex[id]!.windows.enumerated() {
                try checkLength(window.lengthMinutes, path: "codex.\(id).windows[\(index)].lengthMinutes")
                try checkUsed(window.used, path: "codex.\(id).windows[\(index)].used")
                try checkReset(window.resetsIn, path: "codex.\(id).windows[\(index)].resetsIn")
            }
        }
        for (index, entry) in usage.enumerated() {
            try checkUsage(entry, path: "usage[\(index)]")
        }
        var previous: TimeInterval = 0
        for (index, frame) in frames.enumerated() {
            let path = "frames[\(index)]"
            guard frame.at.seconds > 0 else {
                throw ScenarioError(path: "\(path).at", message: "expected a time after launch, for example 12s")
            }
            guard frame.at.seconds > previous else {
                throw ScenarioError(path: "\(path).at", message: "frames must be in increasing order of time")
            }
            previous = frame.at.seconds
            for id in (frame.claude ?? [:]).keys.sorted() {
                try checkAccount(id, path: "\(path).claude.\(id)", kind: .claude)
                guard claude[id] != nil else {
                    throw ScenarioError(path: "\(path).claude.\(id)", message: "no plan windows to change in claude")
                }
                let change = frame.claude![id]!
                try checkChange(change.fiveHour, path: "\(path).claude.\(id).fiveHour")
                try checkChange(change.sevenDay, path: "\(path).claude.\(id).sevenDay")
                for name in (change.models ?? [:]).keys.sorted() {
                    guard claude[id]?.models?[name] != nil else {
                        throw ScenarioError(path: "\(path).claude.\(id).models.\(name)", message: "no such model limit in claude")
                    }
                    try checkChange(change.models![name]!, path: "\(path).claude.\(id).models.\(name)")
                }
            }
            for id in (frame.codex ?? [:]).keys.sorted() {
                try checkAccount(id, path: "\(path).codex.\(id)", kind: .codex)
                for (windowIndex, change) in frame.codex![id]!.windows.enumerated() {
                    let windowPath = "\(path).codex.\(id).windows[\(windowIndex)]"
                    guard codex[id]?.windows.contains(where: { $0.lengthMinutes == change.lengthMinutes }) == true else {
                        throw ScenarioError(path: "\(windowPath).lengthMinutes", message: "no window of this length in codex")
                    }
                    if let used = change.used { try checkUsed(used, path: "\(windowPath).used") }
                    if let resetsIn = change.resetsIn { try checkReset(resetsIn, path: "\(windowPath).resetsIn") }
                }
            }
            for (entryIndex, entry) in (frame.usage ?? []).enumerated() {
                try checkUsage(entry, path: "\(path).usage[\(entryIndex)]")
            }
        }
    }

    private enum PlanKind {
        case claude
        case codex
    }

    private func checkAccount(_ id: String, path: String, kind: PlanKind) throws {
        guard let account = configuration.account(id: id) else {
            throw ScenarioError(path: path, message: "unknown account id")
        }
        switch kind {
        case .claude where !account.kind.isSubscription:
            throw ScenarioError(path: path, message: "not a subscription account")
        case .codex where !account.kind.isCodexSubscription:
            throw ScenarioError(path: path, message: "not a Codex subscription account")
        default:
            break
        }
    }

    private func checkUsed(_ used: Double, path: String) throws {
        guard used.isFinite, (0...100).contains(used) else {
            throw ScenarioError(path: path, message: "expected a number from 0 to 100")
        }
    }

    private func checkWindow(_ window: WindowValue, path: String) throws {
        try checkUsed(window.used, path: "\(path).used")
        try checkReset(window.resetsIn, path: "\(path).resetsIn")
    }

    private func checkChange(_ change: WindowChange?, path: String) throws {
        if let used = change?.used { try checkUsed(used, path: "\(path).used") }
        if let resetsIn = change?.resetsIn { try checkReset(resetsIn, path: "\(path).resetsIn") }
    }

    /// Reset times lie after launch (contracts/scenario-format.md).
    private func checkReset(_ resetsIn: ScenarioDuration, path: String) throws {
        guard resetsIn.seconds > 0 else {
            throw ScenarioError(path: path, message: "expected a time after launch, for example 2h")
        }
    }

    private func checkLength(_ minutes: Int, path: String) throws {
        guard minutes > 0 else {
            throw ScenarioError(path: path, message: "expected a length in minutes greater than 0")
        }
    }

    private func checkUsage(_ entry: UsageEntry, path: String) throws {
        guard entry.at.seconds < 0 else {
            throw ScenarioError(path: "\(path).at", message: "expected a time before launch, for example -2h")
        }
        guard configuration.account(id: entry.account) != nil else {
            throw ScenarioError(path: "\(path).account", message: "unknown account id")
        }
        for (name, value) in [("input", entry.input), ("output", entry.output), ("cacheRead", entry.cacheRead),
                              ("cacheWrite", entry.cacheWrite)] where value < 0 {
            throw ScenarioError(path: "\(path).\(name)", message: "expected a token count of 0 or more")
        }
    }
}
