import Foundation

/// A named built-in rule of one harness (spec 037 FR-007, data-model
/// "MatchPreset"). The stored value is unique per harness only, so decoding
/// reads it together with the account's harness.
public enum MatchPreset: String, CaseIterable, Equatable, Hashable, Sendable {
    /// Claude Code: the request id starts with `req_vrtx_`.
    case claudeCodeVertex
    /// Codex: the session signs in with an API key.
    case codexAPIKey
    /// OpenCode: the provider is `google-vertex` or `google-vertex-anthropic`.
    case openCodeVertex
    /// OpenCode: the provider is `openai`.
    case openCodeOpenAI

    /// The harness whose records the preset matches; it never matches a
    /// record of another harness (spec 037 FR-008).
    public var harness: Harness {
        switch self {
        case .claudeCodeVertex: return .claudeCode
        case .codexAPIKey: return .codex
        case .openCodeVertex, .openCodeOpenAI: return .openCode
        }
    }

    /// The value of `matchRule.preset` in the configuration file
    /// (contracts/configuration.md).
    public var storedValue: String {
        switch self {
        case .claudeCodeVertex, .openCodeVertex: return "vertex"
        case .codexAPIKey: return "apiKey"
        case .openCodeOpenAI: return "openai"
        }
    }

    /// "Vertex", "API key" or "OpenAI", for the rule pop-up.
    public var displayName: String {
        switch self {
        case .claudeCodeVertex, .openCodeVertex: return "Vertex"
        case .codexAPIKey: return "API key"
        case .openCodeOpenAI: return "OpenAI"
        }
    }

    /// What the preset checks, the same rules the removed provider choice
    /// used per harness (spec 001 research R3, spec 006 FR-012, FR-014).
    public var detectionRule: DetectionRule {
        switch self {
        case .claudeCodeVertex: return .requestIdPrefix("req_vrtx_")
        case .codexAPIKey: return .providerHint([Attributor.codexAPIKeyHint])
        case .openCodeVertex: return .providerHint(["google-vertex", "google-vertex-anthropic"])
        case .openCodeOpenAI: return .providerHint(["openai"])
        }
    }

    /// The presets of `harness` in pop-up order; the first is the default
    /// of a new account (spec 037 clarification, FR-007).
    public static func presets(for harness: Harness) -> [MatchPreset] {
        allCases.filter { $0.harness == harness }
    }

    /// The preset of `harness` stored as `value`, nil when there is none.
    public static func preset(stored value: String, harness: Harness) -> MatchPreset? {
        presets(for: harness).first { $0.storedValue == value }
    }
}

/// The record field a custom rule compares (spec 037 FR-007, data-model
/// "MatchField").
public enum MatchField: String, CaseIterable, Equatable, Hashable, Sendable {
    case model
    case requestId
    case messageId
    /// The raw record line, including tool inputs and outputs.
    case anywhere

    /// The value of `matchRule.field` in the configuration file.
    public var storedValue: String { rawValue }

    /// The fields offered for `harness`, in pop-up order: "Anywhere in the
    /// record line" always comes last (spec 037 FR-007).
    public static func fields(for harness: Harness) -> [MatchField] {
        switch harness {
        case .claudeCode: return [.model, .requestId, .messageId, .anywhere]
        case .codex, .openCode: return [.model, .anywhere]
        }
    }

    /// True when the record's field starts with `text`, or for `anywhere`
    /// when the raw line contains it; case-sensitive, exactly as entered
    /// (spec 037 FR-007 clarification). A blank text never matches.
    func matches(_ text: String, record: RawUsageRecord, rawLine: String) -> Bool {
        guard !MatchRule.isBlank(text) else { return false }
        switch self {
        case .model: return record.model.hasPrefix(text)
        case .requestId: return record.requestId.hasPrefix(text)
        case .messageId: return record.messageId.hasPrefix(text)
        case .anywhere: return rawLine.contains(text)
        }
    }
}

/// How a token-based account recognizes records without a decisive profile
/// (spec 037 FR-007, data-model "MatchRule").
public enum MatchRule: Equatable, Hashable, Sendable {
    case preset(MatchPreset)
    case custom(field: MatchField, text: String)
    /// Claims records through the profile step only (Claude Code), or,
    /// after a dropped rule, nothing (Codex, OpenCode; FR-015).
    case none

    /// The first preset of `harness` (spec 037 clarification).
    public static func `default`(for harness: Harness) -> MatchRule {
        .preset(MatchPreset.presets(for: harness)[0])
    }

    /// True when the rule pop-up of a `harness` account offers this rule:
    /// a preset of that harness, a custom field of that harness, and
    /// "None (profile only)" for Claude Code only (spec 037 FR-007).
    public func isOffered(for harness: Harness) -> Bool {
        switch self {
        case .preset(let preset): return preset.harness == harness
        case .custom(let field, _): return MatchField.fields(for: harness).contains(field)
        case .none: return harness == .claudeCode
        }
    }

    /// True when matching reads the raw record line, so callers only build
    /// it when it can matter (spec 037 plan "Attribution").
    public var needsRawLine: Bool {
        if case .custom(.anywhere, _) = self { return true }
        return false
    }

    /// True for a custom rule whose text is blank after trimming, which
    /// Settings refuses (spec 037 FR-011).
    public var hasBlankText: Bool {
        if case .custom(_, let text) = self { return Self.isBlank(text) }
        return false
    }

    /// True for a custom rule.
    public var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// True when the rule claims `record` in the rule step. A preset
    /// matches only records of its own harness; `.none` never matches
    /// (spec 037 FR-007, FR-008).
    public func matches(record: RawUsageRecord, rawLine: String) -> Bool {
        switch self {
        case .preset(let preset):
            return record.harness == preset.harness && preset.detectionRule.matches(record: record, rawLine: rawLine)
        case .custom(let field, let text):
            return field.matches(text, record: record, rawLine: rawLine)
        case .none:
            return false
        }
    }

    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The rule pop-up item of this rule.
    public var choice: MatchRuleChoice {
        switch self {
        case .preset(let preset): return .preset(preset)
        case .custom: return .custom
        case .none: return .none
        }
    }

    /// The items of the rule pop-up of a `harness` account whose rule is
    /// `current`, in order: the harness's presets, "Custom", then "None"
    /// for Claude Code, or for another harness only while a rule dropped on
    /// load is selected (spec 037 FR-007, FR-015, contracts/settings-ui.md).
    public static func choices(for harness: Harness, current: MatchRule) -> [MatchRuleChoice] {
        var items = MatchPreset.presets(for: harness).map(MatchRuleChoice.preset) + [.custom]
        if MatchRule.none.isOffered(for: harness) || current == .none { items.append(.none) }
        return items
    }

    /// The rule after choosing `choice` in the pop-up of a `harness`
    /// account. Choosing "Custom" again keeps the current custom rule;
    /// coming back to it from another item restores `lastCustom` when its
    /// field is offered for the harness, else starts with the harness's
    /// first field and an empty text.
    public func choosing(_ choice: MatchRuleChoice, harness: Harness,
                         lastCustom: (field: MatchField, text: String)?) -> MatchRule {
        switch choice {
        case .preset(let preset): return .preset(preset)
        case .none: return .none
        case .custom:
            if isCustom { return self }
            let offered = MatchField.fields(for: harness)
            guard let last = lastCustom, offered.contains(last.field) else {
                return .custom(field: offered[0], text: lastCustom?.text ?? "")
            }
            return .custom(field: last.field, text: last.text)
        }
    }
}

/// One item of the rule pop-up (spec 037 FR-007).
public enum MatchRuleChoice: Hashable, Sendable {
    case preset(MatchPreset)
    case custom
    case none
}
