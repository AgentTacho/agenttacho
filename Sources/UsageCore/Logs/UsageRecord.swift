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

    public init(messageId: String, timestamp: Date, model: String, requestId: String, inputTokens: Int, outputTokens: Int, cacheWrite5mTokens: Int, cacheWrite1hTokens: Int, cacheReadTokens: Int, cwd: String? = nil) {
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

    public init(messageId: String, timestamp: Date, model: String, canonicalModel: String, requestId: String, accountId: String?, inputTokens: Int, outputTokens: Int, cacheWrite5mTokens: Int, cacheWrite1hTokens: Int, cacheReadTokens: Int, costUSD: Decimal?) {
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
    }

    public init(raw: RawUsageRecord, canonicalModel: String, accountId: String?, costUSD: Decimal?) {
        self.init(messageId: raw.messageId, timestamp: raw.timestamp, model: raw.model, canonicalModel: canonicalModel,
                  requestId: raw.requestId, accountId: accountId,
                  inputTokens: raw.inputTokens, outputTokens: raw.outputTokens,
                  cacheWrite5mTokens: raw.cacheWrite5mTokens, cacheWrite1hTokens: raw.cacheWrite1hTokens,
                  cacheReadTokens: raw.cacheReadTokens, costUSD: costUSD)
    }

    public var cacheWriteTokens: Int { cacheWrite5mTokens + cacheWrite1hTokens }
    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }
    public var isPriced: Bool { costUSD != nil }
}
