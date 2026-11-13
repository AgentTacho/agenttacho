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

/// The four token counters a session record and a classifier row share,
/// for the double-recording check (spec 045 FR-013): input, output, cache
/// read and cache write (5-minute plus 1-hour).
struct TokenCounters: Hashable {
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int

    init(_ record: UsageRecord) {
        input = record.inputTokens
        output = record.outputTokens
        cacheRead = record.cacheReadTokens
        cacheWrite = record.cacheWriteTokens
    }

    init(_ row: ClassifierRow) {
        input = row.inputTokens
        output = row.outputTokens
        cacheRead = row.cacheReadTokens
        cacheWrite = row.cacheWrite5mTokens
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
    /// The counters of the span's session records, for the
    /// double-recording check: one lookup per row instead of a scan.
    var counters: Set<TokenCounters>

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

    /// `sessionRecords` are the in-window session records (the session
    /// index's records, never classifier records); `canonical` maps
    /// a raw working directory to its canonical directory, from the probe
    /// only: a record whose raw directory is not in it builds no span.
    public static func records(entries: [DecisionLogEntry], sessionRecords: [UsageRecord], canonical: [String: String],
                               pricer: PriceTable) -> ClassifierAttributionResult {
        var result = ClassifierAttributionResult()
        // Spans are needed only in directories with rows: without any, the
        // step costs nothing per session record (SC-003, SC-004).
        let directories = Set(entries.lazy.filter { !$0.rows.isEmpty }.map(\.directory))
        guard !directories.isEmpty else { return result }
        let spans = spansByDirectory(sessionRecords, canonical: canonical, in: directories)
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
                let rowCounters = TokenCounters(row)
                for span in covering where span.counters.contains(rowCounters) {
                    result.doubleRecordingSessions.insert(span.sessionKey)
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
    /// directory (FR-005); only for the canonical `directories` given.
    /// Spans are updated in place, so building one costs linear time in its
    /// records.
    static func spansByDirectory(_ records: [UsageRecord], canonical: [String: String],
                                 in directories: Set<String>) -> [String: [SessionSpan]] {
        var spans: [SessionSpan] = []
        var indexByKey: [String: Int] = [:]
        for record in records where record.harness == .claudeCode {
            guard let sessionKey = record.sessionKey, let cwd = record.cwd, let directory = canonical[cwd],
                  directories.contains(directory) else { continue }
            let key = sessionKey + "\u{0}" + directory
            if let i = indexByKey[key] {
                spans[i].start = min(spans[i].start, record.timestamp)
                spans[i].end = max(spans[i].end, record.timestamp.addingTimeInterval(gracePeriod))
                spans[i].accounts.insert(record.accountId)
                if spans[i].project == nil { spans[i].project = record.project }
                spans[i].counters.insert(TokenCounters(record))
            } else {
                indexByKey[key] = spans.count
                spans.append(SessionSpan(directory: directory, sessionKey: sessionKey, start: record.timestamp,
                                         end: record.timestamp.addingTimeInterval(gracePeriod), accounts: [record.accountId],
                                         project: record.project, counters: [TokenCounters(record)]))
            }
        }
        return Dictionary(grouping: spans, by: \.directory)
    }
}
