import Foundation

/// Which per-token sessions of its harness a token-based account counts
/// (spec 038 FR-001, FR-002, data-model "SessionKind"). The stored value is
/// unique per harness only, so decoding reads it together with the
/// account's harness. Every check is exact and case-sensitive; a condition
/// may narrow a kind but never widens it (FR-004).
public enum SessionKind: String, CaseIterable, Equatable, Hashable, Sendable {
    /// Claude Code: no record; the account counts only sessions from its
    /// Claude Code directories (spec 037 FR-003).
    case claudeCodeDirectoryOnly
    /// Claude Code: the request id starts with `req_vrtx_`.
    case claudeCodeVertex
    /// Claude Code: the record has no request id starting with `req_`, such
    /// as the records of a company gateway (research R9).
    case claudeCodeOtherProvider
    /// Codex: the session signed in with an API key.
    case codexAPIKey
    /// OpenCode: the provider is `google-vertex` or `google-vertex-anthropic`.
    case openCodeVertex
    /// OpenCode: the provider is `openai`.
    case openCodeOpenAI
    /// OpenCode: the provider is `anthropic`, which an API key and a
    /// Claude plan sign-in both report (walkthrough decision).
    case openCodeAnthropic
    /// OpenCode: a provider is set and is none of the four above.
    case openCodeOtherProvider

    /// The OpenCode providers of the Vertex, OpenAI and Anthropic kinds;
    /// Other provider is any other one (spec 038 FR-002).
    static let openCodeVertexProviders: Set<String> = ["google-vertex", "google-vertex-anthropic"]
    static let openCodeOpenAIProvider = "openai"
    static let openCodeAnthropicProvider = "anthropic"

    /// The harness whose records the kind matches; it never matches a
    /// record of another harness (spec 038 FR-002).
    public var harness: Harness {
        switch self {
        case .claudeCodeDirectoryOnly, .claudeCodeVertex, .claudeCodeOtherProvider: return .claudeCode
        case .codexAPIKey: return .codex
        case .openCodeVertex, .openCodeOpenAI, .openCodeAnthropic, .openCodeOtherProvider: return .openCode
        }
    }

    /// The value of `sessionKind` in the configuration file (spec 038
    /// FR-010, contracts/configuration.md).
    public var storedValue: String {
        switch self {
        case .claudeCodeDirectoryOnly: return "directoryOnly"
        case .claudeCodeVertex, .openCodeVertex: return "vertex"
        case .claudeCodeOtherProvider, .openCodeOtherProvider: return "otherProvider"
        case .codexAPIKey: return "apiKey"
        case .openCodeOpenAI: return "openai"
        case .openCodeAnthropic: return "anthropic"
        }
    }

    /// The Sessions pop-up item and the account list subtitle (spec 038
    /// FR-012).
    public var displayName: String {
        switch self {
        case .claudeCodeDirectoryOnly: return "Directory only"
        case .claudeCodeVertex, .openCodeVertex: return "Vertex"
        case .claudeCodeOtherProvider, .openCodeOtherProvider: return "Other provider"
        case .codexAPIKey: return "API key"
        case .openCodeOpenAI: return "OpenAI"
        case .openCodeAnthropic: return "Anthropic"
        }
    }

    /// False for Directory only, which matches no record, so a condition
    /// would have nothing to narrow (spec 038 FR-004).
    public var offersCondition: Bool { self != .claudeCodeDirectoryOnly }

    /// True for OpenCode Other provider: it counts only the provider the
    /// condition names (spec 038 FR-004, FR-012).
    public var requiresCondition: Bool { self == .openCodeOtherProvider }

    /// False for Codex, whose only kind is a sentence instead of a pop-up
    /// (spec 038 FR-012).
    public var showsPopUp: Bool { self != .codexAPIKey }

    /// True when `record` is of this kind: a record of the kind's harness
    /// that passes the kind's exact check (spec 038 FR-002, research R11).
    /// Directory only matches no record.
    public func matches(record: RawUsageRecord) -> Bool {
        guard record.harness == harness else { return false }
        switch self {
        case .claudeCodeDirectoryOnly:
            return false
        case .claudeCodeVertex:
            return record.requestId.hasPrefix("req_vrtx_")
        case .claudeCodeOtherProvider:
            // No Anthropic request id: the records of a company gateway
            // carry none, while Vertex and direct ids start with `req_`
            // (research R9).
            return !record.requestId.hasPrefix("req_")
        case .codexAPIKey:
            return record.providerHint == Attributor.codexAPIKeyHint
        case .openCodeVertex:
            return record.providerHint.map(Self.openCodeVertexProviders.contains) ?? false
        case .openCodeOpenAI:
            return record.providerHint == Self.openCodeOpenAIProvider
        case .openCodeAnthropic:
            return record.providerHint == Self.openCodeAnthropicProvider
        case .openCodeOtherProvider:
            guard let provider = record.providerHint, !provider.isEmpty else { return false }
            return !Self.openCodeVertexProviders.contains(provider) && provider != Self.openCodeOpenAIProvider
                && provider != Self.openCodeAnthropicProvider
        }
    }

    /// The icon a new account of this kind starts with: Google for the
    /// Vertex kinds, OpenAI for API key and OpenCode OpenAI, Claude for
    /// OpenCode Anthropic, else the harness's icon (contracts/settings-ui.md).
    public var defaultIcon: String {
        switch self {
        case .claudeCodeVertex, .openCodeVertex: return IconDefaults.vertex
        case .codexAPIKey, .openCodeOpenAI: return IconDefaults.openai
        case .claudeCodeDirectoryOnly, .claudeCodeOtherProvider, .openCodeAnthropic: return IconDefaults.subscription
        case .openCodeOtherProvider: return IconDefaults.openCode
        }
    }

    /// The kinds of `harness` in pop-up order (spec 038 FR-001).
    public static func kinds(for harness: Harness) -> [SessionKind] {
        allCases.filter { $0.harness == harness }
    }

    /// The first kind of `harness`, the default of a new account and of a
    /// harness change (spec 038 FR-001).
    public static func `default`(for harness: Harness) -> SessionKind {
        kinds(for: harness)[0]
    }

    /// The kind of `harness` stored as `value`, nil for an unknown value or
    /// one of another harness.
    public static func kind(stored value: String, harness: Harness) -> SessionKind? {
        kinds(for: harness).first { $0.storedValue == value }
    }

    /// The kind of an unreadable setting: one that matches no record
    /// outside the directory step where the harness has such a kind
    /// (Claude Code Directory only, OpenCode Other provider without a
    /// condition). Codex has only API key, so an unreadable Codex setting
    /// counts every API-key session, as FR-011 says (spec 038 FR-011,
    /// research R7).
    public static func fallback(for harness: Harness) -> SessionKind {
        switch harness {
        case .claudeCode: return .claudeCodeDirectoryOnly
        case .codex: return .codexAPIKey
        case .openCode: return .openCodeOtherProvider
        }
    }
}
