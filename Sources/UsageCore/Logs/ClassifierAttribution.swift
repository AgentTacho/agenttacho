import Foundation

/// The classifier records of one refresh (spec 045 data-model
/// "ClassifierAttributionResult").
public struct ClassifierAttributionResult: Equatable, Sendable {
    /// One record per counted row, marked `.classifier` (FR-010).
    public var records: [UsageRecord] = []
    public var assigned = 0
    public var unassigned = 0
    /// Session keys with a session record whose four token counters equal
    /// a covered row's: a possible double recording (FR-013).
    public var doubleRecordingSessions: Set<String> = []

    public init(records: [UsageRecord] = [], assigned: Int = 0, unassigned: Int = 0, doubleRecordingSessions: Set<String> = []) {
        self.records = records
        self.assigned = assigned
        self.unassigned = unassigned
        self.doubleRecordingSessions = doubleRecordingSessions
    }
}

/// A session's time span in one working directory (spec 045 data-model
/// "SessionSpan", FR-005), rebuilt on every refresh.
struct SessionSpan {
    var directory: String
    var sessionKey: String
    var start: Date
    /// The latest record plus the grace period.
    var end: Date
    /// Account ids of the span's records; nil is Unassigned.
    var accounts: Set<String?>
    var project: Project?
    /// The span's session records, for the double-recording check.
    var records: [UsageRecord]

    func covers(_ time: Date) -> Bool { start <= time && time <= end }
}

/// Turns classifier rows into usage records whose account and project come
/// from the sessions that cover them (spec 045 FR-005 to FR-011). Account
/// match rules are never applied to a row; it is recomputed on every
/// refresh from the current session records (FR-006).
public enum ClassifierAttribution {
    /// A classifier call follows the assistant message that asked for the
    /// tool, so it can trail the session's last record (FR-005).
    public static let gracePeriod: TimeInterval = 300

    /// `sessionRecords` are the in-window session records; `canonical` maps
    /// a raw working directory to its canonical directory, from the probe
    /// only: a record whose raw directory is not in it builds no span.
    public static func records(entries: [DecisionLogEntry], sessionRecords: [UsageRecord], canonical: [String: String],
                               pricer: PriceTable) -> ClassifierAttributionResult {
        let spans = spansByDirectory(sessionRecords, canonical: canonical)
        var result = ClassifierAttributionResult()
        // One price lookup per model: `price(for:)` scans every entry for a
        // model it cannot match exactly (SC-004).
        var prices: [String: PriceEntry?] = [:]
        var canonicalModels: [String: String] = [:]
        for entry in entries {
            let directorySpans = spans[entry.directory] ?? []
            let directoryProject = directorySpans.lazy.compactMap(\.project).first
            for row in entry.rows {
                // Spans overlap and their ends are unordered: a linear scan
                // finds every covering span (plan "Attribution").
                let covering = directorySpans.filter { $0.covers(row.timestamp) }
                let accountId = account(of: covering)
                if accountId == nil { result.unassigned += 1 } else { result.assigned += 1 }
                let project = covering.lazy.compactMap(\.project).first ?? directoryProject
                // A session record with the row's four counters hints that a
                // future Claude Code records the same call twice; counting is
                // unchanged (FR-013, Assumptions).
                for span in covering where !result.doubleRecordingSessions.contains(span.sessionKey) {
                    if span.records.contains(where: { matchesCounters($0, row) }) {
                        result.doubleRecordingSessions.insert(span.sessionKey)
                    }
                }
                if prices[row.model] == nil {
                    prices[row.model] = .some(pricer.price(for: row.model))
                    canonicalModels[row.model] = PriceTable.canonicalModel(row.model)
                }
                // The same result as `pricer.cost(model:...)` (FR-008).
                let cost = prices[row.model]!.map {
                    PriceTable.cost(input: row.inputTokens, output: row.outputTokens, cacheWrite5m: row.cacheWrite5mTokens,
                                    cacheWrite1h: 0, cacheRead: row.cacheReadTokens, price: $0)
                }
                result.records.append(UsageRecord(
                    messageId: row.id, timestamp: row.timestamp, model: row.model,
                    canonicalModel: canonicalModels[row.model]!, requestId: "", accountId: accountId,
                    inputTokens: row.inputTokens, outputTokens: row.outputTokens,
                    cacheWrite5mTokens: row.cacheWrite5mTokens, cacheWrite1hTokens: 0, cacheReadTokens: row.cacheReadTokens,
                    costUSD: cost,
                    project: project, harness: .claudeCode, cwd: entry.directory, origin: .classifier))
            }
        }
        return result
    }

    /// True when a session record carries the row's input, output, cache
    /// read and cache write (5-minute plus 1-hour) counters (FR-013).
    static func matchesCounters(_ record: UsageRecord, _ row: ClassifierRow) -> Bool {
        record.inputTokens == row.inputTokens && record.outputTokens == row.outputTokens
            && record.cacheReadTokens == row.cacheReadTokens && record.cacheWriteTokens == row.cacheWrite5mTokens
    }

    /// The account of a row from its covering spans (FR-006): the union of
    /// their accounts must be exactly one account and not Unassigned. No
    /// covering span, spans on different accounts, an unassigned span, or
    /// a span whose own records went to several accounts leave the row
    /// unassigned.
    static func account(of covering: [SessionSpan]) -> String? {
        var accounts = Set<String?>()
        for span in covering {
            accounts.formUnion(span.accounts)
            if accounts.count > 1 { return nil }
        }
        guard accounts.count == 1, let only = accounts.first else { return nil }
        return only
    }

    /// Spans keyed by session key and canonical directory, grouped by
    /// directory (FR-005).
    static func spansByDirectory(_ records: [UsageRecord], canonical: [String: String]) -> [String: [SessionSpan]] {
        var byKey: [String: SessionSpan] = [:]
        var order: [String] = []
        for record in records where record.origin == .session && record.harness == .claudeCode {
            guard let sessionKey = record.sessionKey, let cwd = record.cwd, let directory = canonical[cwd] else { continue }
            let key = sessionKey + "\u{0}" + directory
            if var span = byKey[key] {
                span.start = min(span.start, record.timestamp)
                span.end = max(span.end, record.timestamp.addingTimeInterval(gracePeriod))
                span.accounts.insert(record.accountId)
                if span.project == nil { span.project = record.project }
                span.records.append(record)
                byKey[key] = span
            } else {
                order.append(key)
                byKey[key] = SessionSpan(directory: directory, sessionKey: sessionKey, start: record.timestamp,
                                         end: record.timestamp.addingTimeInterval(gracePeriod), accounts: [record.accountId],
                                         project: record.project, records: [record])
            }
        }
        var result: [String: [SessionSpan]] = [:]
        for key in order {
            let span = byKey[key]!
            result[span.directory, default: []].append(span)
        }
        return result
    }
}
