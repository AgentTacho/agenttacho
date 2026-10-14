import Foundation

/// One assistant record as read from a session log, before attribution and pricing.
public struct RawUsageRecord: Equatable, Sendable {
    public var messageId: String
    public var timestamp: Date
    public var model: String
    public var requestId: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheWrite5mTokens: Int
    public var cacheWrite1hTokens: Int
    public var cacheReadTokens: Int
    /// The session's working directory; nil when the line has none.
    public var cwd: String?
    /// The harness that wrote the record (spec 006 FR-007).
    public var harness: Harness
    /// What the record reveals about who bills it: the OpenCode `providerID`,
    /// or the Codex auth mode `"chatgpt"` / `"apikey"`. Nil for Claude Code,
    /// whose hint is the request id (spec 006 FR-007, FR-012).
    public var providerHint: String?
    /// Reasoning tokens, informational only: already included in
    /// `outputTokens` and never priced on top (spec 006 FR-008, FR-020).
    public var reasoningTokens: Int
    /// The harness session the record belongs to, when known.
    public var sessionId: String?

    public init(messageId: String, timestamp: Date, model: String, requestId: String, inputTokens: Int, outputTokens: Int, cacheWrite5mTokens: Int, cacheWrite1hTokens: Int, cacheReadTokens: Int, cwd: String? = nil,
                harness: Harness = .claudeCode, providerHint: String? = nil, reasoningTokens: Int = 0, sessionId: String? = nil) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.model = model
        self.requestId = requestId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.cwd = cwd
        self.harness = harness
        self.providerHint = providerHint
        self.reasoningTokens = reasoningTokens
        self.sessionId = sessionId
    }
}

/// One priced unit of consumption attributed to an account (data-model.md).
public struct UsageRecord: Equatable, Sendable {
    public var messageId: String
    public var timestamp: Date
    public var model: String
    public var canonicalModel: String
    public var requestId: String
    /// nil means Unassigned (FR-009).
    public var accountId: String?
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheWrite5mTokens: Int
    public var cacheWrite1hTokens: Int
    public var cacheReadTokens: Int
    /// nil when unpriced (FR-016).
    public var costUSD: Decimal?
    /// nil when the log line has no working directory ("Unknown").
    public var project: Project?
    /// The harness that wrote the record (spec 006 FR-007, FR-021).
    public var harness: Harness
    /// Informational; already included in `outputTokens` (spec 006 FR-008).
    public var reasoningTokens: Int

    public init(messageId: String, timestamp: Date, model: String, canonicalModel: String, requestId: String, accountId: String?, inputTokens: Int, outputTokens: Int, cacheWrite5mTokens: Int, cacheWrite1hTokens: Int, cacheReadTokens: Int, costUSD: Decimal?, project: Project? = nil,
                harness: Harness = .claudeCode, reasoningTokens: Int = 0) {
        self.messageId = messageId
        self.timestamp = timestamp
        self.model = model
        self.canonicalModel = canonicalModel
        self.requestId = requestId
        self.accountId = accountId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.project = project
        self.harness = harness
        self.reasoningTokens = reasoningTokens
    }

    public init(raw: RawUsageRecord, canonicalModel: String, accountId: String?, costUSD: Decimal?, project: Project? = nil) {
        self.init(messageId: raw.messageId, timestamp: raw.timestamp, model: raw.model, canonicalModel: canonicalModel,
                  requestId: raw.requestId, accountId: accountId,
                  inputTokens: raw.inputTokens, outputTokens: raw.outputTokens,
                  cacheWrite5mTokens: raw.cacheWrite5mTokens, cacheWrite1hTokens: raw.cacheWrite1hTokens,
                  cacheReadTokens: raw.cacheReadTokens, costUSD: costUSD, project: project,
                  harness: raw.harness, reasoningTokens: raw.reasoningTokens)
    }

    public var cacheWriteTokens: Int { cacheWrite5mTokens + cacheWrite1hTokens }
    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }
    public var isPriced: Bool { costUSD != nil }
}
