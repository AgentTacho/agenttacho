import Foundation

/// One Codex usage record and the `token_count` line it came from (the line
/// is matched against custom markers, spec 006 FR-013).
public struct CodexRecord: Equatable, Sendable {
    public var raw: RawUsageRecord
    public var line: String

    public init(raw: RawUsageRecord, line: String) {
        self.raw = raw
        self.line = line
    }
}

/// One parsed Codex rollout file (spec 006 data-model CodexSession).
public struct CodexSession: Equatable, Sendable {
    public var sessionId: String
    /// The session that spawned or forked this one, when known (FR-014).
    public var parentSessionId: String?
    public var cwd: String?
    /// True when any `rate_limits.plan_type` is a non-empty string: the
    /// session ran on a ChatGPT plan login (FR-014).
    public var planMarker: Bool
    /// The first `session_meta` line, for custom markers.
    public var metaLine: String
    public var records: [CodexRecord]

    public init(sessionId: String, parentSessionId: String? = nil, cwd: String? = nil, planMarker: Bool = false,
                metaLine: String = "", records: [CodexRecord] = []) {
        self.sessionId = sessionId
        self.parentSessionId = parentSessionId
        self.cwd = cwd
        self.planMarker = planMarker
        self.metaLine = metaLine
        self.records = records
    }
}

/// Parses a Codex rollout file as a whole session (spec 006 research R3,
/// contracts/harness-formats.md). Pure: works on the file's bytes only.
///
/// Usage is the change of the running `total_token_usage` between
/// consecutive `token_count` events, so repeated events, events without
/// `info` and all-zero events add nothing (FR-008a). Codex counts cached and
/// cache-write input inside input and reasoning inside output: input is split
/// into input, cache read and cache write, and reasoning stays in output
/// (FR-008). Lines that do not decode, such as a partly written last line,
/// are skipped (FR-004).
///
/// Subagent and forked files copy the parent's history after a second
/// `session_meta` line, including the parent's `token_count` events, all
/// written in one burst right after the fork (observed up to a few
/// milliseconds after the first meta line). Those copied events only set the
/// running total the child continues from; they add no usage and carry no
/// plan marker of the child's own, so the parent's tokens are not counted
/// twice (SC-002, FR-014).
public struct CodexSessionParser: Sendable {
    /// Copied parent events are stamped within this many seconds of the
    /// fork; the child's own first turn always takes longer.
    static let copiedHistoryTolerance: TimeInterval = 1
    /// Upper bound for one token field, so a corrupt line cannot overflow
    /// the arithmetic.
    static let maxTokenValue = 1 << 50

    public init() {}

    /// `fallbackSessionId` names the session when the file has no
    /// `session_meta` line (the source passes the file name).
    public func parse(data: Data, fallbackSessionId: String = "") -> CodexSession {
        var lines = 0
        return parse(data: data, fallbackSessionId: fallbackSessionId, linesVisited: &lines)
    }

    /// As `parse(data:fallbackSessionId:)`, and adds the number of
    /// non-empty lines walked to `linesVisited`, for the bench (spec 039
    /// FR-002, research R6).
    func parse(data: Data, fallbackSessionId: String = "", linesVisited: inout Int) -> CodexSession {
        var session = CodexSession(sessionId: fallbackSessionId)
        var fork = CopiedHistory()
        var model = ""
        var cwd: String?
        var previous = Totals.zero
        var pending: [(timestamp: Date, delta: Totals, total: Int, model: String, cwd: String?, line: String)] = []

        for (kind, lineData) in Self.relevantLines(of: data, linesVisited: &linesVisited) {
            // Typed, lenient decoding: a line that is no object, or has no
            // payload object, is skipped (spec 039 FR-016, research R6).
            guard let line = CodexLine.decode(lineData), let payload = line.payload else { continue }
            switch kind {
            case .sessionMeta:
                // Forked files repeat the parent's meta line; only the first counts.
                guard fork.sessionMeta(at: line.timestamp.flatMap(ISO8601Timestamp.parse)) else { continue }
                if let id = payload.id, !id.isEmpty { session.sessionId = id }
                session.cwd = Self.nonEmpty(payload.cwd)
                session.parentSessionId = payload.parent
                session.metaLine = String(decoding: lineData, as: UTF8.self)
            case .turnContext:
                if let m = Self.nonEmpty(payload.model) { model = m }
                if let c = Self.nonEmpty(payload.cwd) { cwd = c }
            case .tokenCount:
                guard payload.type == "token_count",
                      let timestamp = line.timestamp.flatMap(ISO8601Timestamp.parse) else { continue }
                let copiedHistory = fork.isCopied(eventAt: timestamp)
                if !copiedHistory, Self.nonEmpty(payload.rateLimits?.planType) != nil {
                    session.planMarker = true
                }
                guard let usage = payload.info?.totalTokenUsage else { continue }
                let total = Totals(usage)
                // An all-zero event adds nothing and must not reset the
                // baseline, or the next event would count the whole running
                // total again (FR-008a).
                guard total != .zero else { continue }
                if copiedHistory {
                    // The parent's copied event: baseline only.
                    previous = total
                    continue
                }
                guard total != previous else { continue }
                let delta = total.minus(previous)
                previous = total
                guard !delta.isZero else { continue }
                pending.append((timestamp, delta, total.total, model, cwd, String(decoding: lineData, as: UTF8.self)))
            }
        }

        session.records = pending.enumerated().map { index, item in
            let d = item.delta
            let cacheRead = d.cached
            let cacheWrite = d.cacheWrite
            // The running total identifies the event; without one, its
            // position in the session keeps ids distinct.
            let key = item.total > 0 ? "\(item.total)" : "event\(index)"
            let raw = RawUsageRecord(messageId: "codex:\(session.sessionId):\(key)", timestamp: item.timestamp,
                                     model: item.model, requestId: "",
                                     inputTokens: max(0, d.input - cacheRead - cacheWrite), outputTokens: d.output,
                                     cacheWrite5mTokens: cacheWrite, cacheWrite1hTokens: 0, cacheReadTokens: cacheRead,
                                     cwd: item.cwd ?? session.cwd, harness: .codex, providerHint: nil,
                                     reasoningTokens: d.reasoning, sessionId: session.sessionId)
            return CodexRecord(raw: raw, line: item.line)
        }
        return session
    }

    // MARK: - Plan limit snapshots (spec 007)

    /// The newest plan limit snapshot of a rollout file (spec 007 FR-004,
    /// FR-008, research R4, contracts/codex-usage-endpoint.md section 3).
    /// Pure: works on the file's bytes only.
    ///
    /// Reads `rate_limits` of every `token_count` event, also of events
    /// without `info`. A snapshot counts when it describes the main Codex
    /// bucket (`limit_id` "codex" or absent), has a plan type (API-key
    /// sessions have none) and at least one window with a percent and a
    /// length greater than 0. The parent's copied snapshots in a forked file
    /// are skipped, as for tokens. The observation time is the event's
    /// timestamp.
    public static func latestLimitSnapshot(in data: Data) -> CodexLimitObservation? {
        var fork = CopiedHistory()
        var latest: CodexLimitObservation?
        for (kind, lineData) in relevantLines(of: data) {
            guard kind != .turnContext,
                  let line = CodexLine.decode(lineData), let payload = line.payload else { continue }
            let timestamp = line.timestamp.flatMap(ISO8601Timestamp.parse)
            if kind == .sessionMeta {
                _ = fork.sessionMeta(at: timestamp)
                continue
            }
            guard payload.type == "token_count", let timestamp,
                  !fork.isCopied(eventAt: timestamp),
                  let limits = payload.rateLimits,
                  let snapshot = limitSnapshot(limits, at: timestamp) else { continue }
            if latest.map({ timestamp >= $0.observedAt }) ?? true {
                latest = snapshot
            }
        }
        return latest
    }

    /// One `rate_limits` object as an observation, or nil when it does not
    /// count (another bucket, no plan type, no window).
    private static func limitSnapshot(_ limits: CodexRateLimits, at timestamp: Date) -> CodexLimitObservation? {
        if let bucket = limits.limitId, bucket != "codex" { return nil }
        guard let plan = nonEmpty(limits.planType) else { return nil }
        let windows = [limits.primary, limits.secondary].compactMap { window -> CodexLimitWindow? in
            guard let window else { return nil }
            return CodexLimitWindow(minutes: window.windowMinutes, usedPercent: window.usedPercent, resetEpoch: window.resetsAt)
        }
        guard !windows.isEmpty else { return nil }
        return CodexLimitObservation(planType: plan, observedAt: timestamp, origin: .snapshot,
                                     windows: CodexLimitWindow.applyingReachedRule(windows, sourceReportsReached: limits.reached))
    }

    // MARK: - Helpers

    /// Detects the parent's copied history in subagent and forked files: it
    /// starts at the repeated `session_meta` line and ends with the first
    /// event stamped at least `copiedHistoryTolerance` after the fork.
    struct CopiedHistory {
        private var sawMeta = false
        /// Timestamp of the first `session_meta` line (the fork time).
        private var metaTime: Date?
        /// True from the repeated parent meta line until the first event
        /// outside the copied burst.
        private var copied = false

        /// Records a `session_meta` line; true for the first one, the
        /// session's own.
        mutating func sessionMeta(at timestamp: Date?) -> Bool {
            guard !sawMeta else {
                // Without a fork time on the first meta line, the repeated
                // one anchors the copied burst.
                if metaTime == nil { metaTime = timestamp }
                copied = metaTime != nil
                return false
            }
            sawMeta = true
            metaTime = timestamp
            return true
        }

        /// True when the event at `timestamp` belongs to the copied burst.
        mutating func isCopied(eventAt timestamp: Date) -> Bool {
            if copied, let metaTime, timestamp >= metaTime.addingTimeInterval(CodexSessionParser.copiedHistoryTolerance) {
                copied = false
            }
            return copied
        }
    }

    /// The fields of `total_token_usage`.
    struct Totals: Equatable {
        var input = 0, cached = 0, cacheWrite = 0, output = 0, reasoning = 0, total = 0

        static let zero = Totals()

        init() {}

        /// A missing, non-finite or non-positive value counts 0; a value at
        /// or above `maxTokenValue` counts `maxTokenValue`; a fraction is
        /// truncated (spec 039 research R6: the rules of the dictionary
        /// walk before).
        init(_ usage: CodexTokenUsage) {
            func value(_ number: Double?) -> Int {
                guard let number, number.isFinite, number > 0 else { return 0 }
                return number >= Double(CodexSessionParser.maxTokenValue) ? CodexSessionParser.maxTokenValue : Int(number)
            }
            input = value(usage.inputTokens)
            cached = value(usage.cachedInputTokens)
            cacheWrite = value(usage.cacheWriteInputTokens)
            output = value(usage.outputTokens)
            reasoning = value(usage.reasoningOutputTokens)
            total = value(usage.totalTokens)
        }

        /// Field-wise difference, clamped at 0 (running totals never decrease).
        func minus(_ other: Totals) -> Totals {
            var d = Totals()
            d.input = max(0, input - other.input)
            d.cached = max(0, cached - other.cached)
            d.cacheWrite = max(0, cacheWrite - other.cacheWrite)
            d.output = max(0, output - other.output)
            d.reasoning = max(0, reasoning - other.reasoning)
            d.total = max(0, total - other.total)
            return d
        }

        var isZero: Bool { input == 0 && cached == 0 && cacheWrite == 0 && output == 0 && reasoning == 0 }
    }

    enum LineKind {
        case sessionMeta, turnContext, tokenCount
    }

    private static let sessionMetaMarker = Array("\"type\":\"session_meta\"".utf8)
    private static let turnContextMarker = Array("\"type\":\"turn_context\"".utf8)
    private static let eventMarker = Array("\"type\":\"event_msg\"".utf8)
    private static let tokenCountMarker = Array("\"type\":\"token_count\"".utf8)
    /// The line's own `type` and the payload's `type` sit at the start of
    /// every line; only that head is searched.
    private static let headLength = 256

    /// The lines AgentTacho reads, with their kind, in file order. A cheap
    /// byte check on each line's head runs before any JSON decoding: most
    /// lines are conversation items, often large, that are never decoded.
    static func relevantLines(of data: Data) -> [(LineKind, Data)] {
        var lines = 0
        return relevantLines(of: data, linesVisited: &lines)
    }

    /// As `relevantLines(of:)`, and adds the number of non-empty lines
    /// walked to `linesVisited` (spec 039 FR-002).
    static func relevantLines(of data: Data, linesVisited: inout Int) -> [(LineKind, Data)] {
        var walked = 0
        defer { linesVisited += walked }
        return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> [(LineKind, Data)] in
            guard let base = buffer.baseAddress else { return [] }
            var result: [(LineKind, Data)] = []
            var start = 0
            let count = buffer.count
            while start < count {
                let remaining = count - start
                let newline = memchr(base + start, 0x0A, remaining).map { base.distance(to: UnsafeRawPointer($0)) } ?? count
                let length = newline - start
                if length > 0 {
                    walked += 1
                    let head = min(length, headLength)
                    func contains(_ marker: [UInt8]) -> Bool {
                        marker.withUnsafeBytes { m in memmem(base + start, head, m.baseAddress, m.count) != nil }
                    }
                    var kind: LineKind?
                    if contains(sessionMetaMarker) {
                        kind = .sessionMeta
                    } else if contains(turnContextMarker) {
                        kind = .turnContext
                    } else if contains(eventMarker), contains(tokenCountMarker) {
                        kind = .tokenCount
                    }
                    if let kind {
                        result.append((kind, Data(bytes: base + start, count: length)))
                    }
                }
                start = newline + 1
            }
            return result
        }
    }

    /// A non-empty string, or nil.
    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}

// MARK: - Typed lines (spec 039 FR-016, research R6)
//
// The relevant lines decode into typed values that hold only the fields the
// reader uses. Every field is optional and decoded with `try?`, so a field
// of the wrong JSON type reads as absent, as the dictionary casts made it
// before; synthesized `Codable` would fail the whole line instead.

/// One relevant rollout line.
struct CodexLine: Decodable {
    var timestamp: String?
    var payload: CodexPayload?

    private enum Key: String, CodingKey {
        case timestamp, payload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        timestamp = try? c.decode(String.self, forKey: .timestamp)
        payload = try? c.decode(CodexPayload.self, forKey: .payload)
    }

    /// One shared decoder for every line.
    private static let decoder = JSONDecoder()

    /// The line decoded, or nil when it is no JSON object.
    static func decode(_ line: Data) -> CodexLine? {
        try? decoder.decode(CodexLine.self, from: line)
    }
}

/// `payload.source.subagent` as the parent lookup reads it.
enum CodexSubagent: Equatable, Sendable {
    /// No `source` object, or one without a `subagent` key.
    case absent
    /// `subagent.thread_spawn` is an object.
    case threadSpawn(parentThreadId: String?)
    /// A subagent of another shape, such as the string `"review"`.
    case other
}

/// The fields of a line's `payload` the reader uses.
struct CodexPayload: Decodable {
    var type: String?
    var id: String?
    var cwd: String?
    var model: String?
    var forkedFromId: String?
    var subagent: CodexSubagent = .absent
    var info: CodexTokenInfo?
    var rateLimits: CodexRateLimits?

    private enum Key: String, CodingKey {
        case type, id, cwd, model, source, info
        case forkedFromId = "forked_from_id"
        case rateLimits = "rate_limits"
    }

    private enum SourceKey: String, CodingKey {
        case subagent
    }

    private enum SubagentKey: String, CodingKey {
        case threadSpawn = "thread_spawn"
    }

    private enum SpawnKey: String, CodingKey {
        case parentThreadId = "parent_thread_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        type = try? c.decode(String.self, forKey: .type)
        id = try? c.decode(String.self, forKey: .id)
        cwd = try? c.decode(String.self, forKey: .cwd)
        model = try? c.decode(String.self, forKey: .model)
        forkedFromId = try? c.decode(String.self, forKey: .forkedFromId)
        info = try? c.decode(CodexTokenInfo.self, forKey: .info)
        rateLimits = try? c.decode(CodexRateLimits.self, forKey: .rateLimits)
        if let source = try? c.nestedContainer(keyedBy: SourceKey.self, forKey: .source), source.contains(.subagent) {
            // A `subagent` key whose value is not an object with a
            // `thread_spawn` object, `null` included, is another shape.
            if let subagent = try? source.nestedContainer(keyedBy: SubagentKey.self, forKey: .subagent),
               let spawn = try? subagent.nestedContainer(keyedBy: SpawnKey.self, forKey: .threadSpawn) {
                self.subagent = .threadSpawn(parentThreadId: try? spawn.decode(String.self, forKey: .parentThreadId))
            } else {
                self.subagent = .other
            }
        }
    }

    /// The parent session: `source.subagent.thread_spawn.parent_thread_id`,
    /// then `forked_from_id`. A subagent of another shape (such as the
    /// string `"review"`) has no parent (spec 006 FR-014).
    var parent: String? {
        let forked = CodexSessionParser.nonEmpty(forkedFromId)
        switch subagent {
        case .absent: return forked
        case .threadSpawn(let parentThreadId): return CodexSessionParser.nonEmpty(parentThreadId) ?? forked
        case .other: return nil
        }
    }
}

/// `payload.info`.
struct CodexTokenInfo: Decodable {
    var totalTokenUsage: CodexTokenUsage?

    private enum Key: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        totalTokenUsage = try? c.decode(CodexTokenUsage.self, forKey: .totalTokenUsage)
    }
}

/// `info.total_token_usage`: the six running counters.
struct CodexTokenUsage: Decodable, Equatable {
    var inputTokens: Double?
    var cachedInputTokens: Double?
    var cacheWriteInputTokens: Double?
    var outputTokens: Double?
    var reasoningOutputTokens: Double?
    var totalTokens: Double?

    private enum Key: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case cacheWriteInputTokens = "cache_write_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    init(inputTokens: Double? = nil, cachedInputTokens: Double? = nil, cacheWriteInputTokens: Double? = nil,
         outputTokens: Double? = nil, reasoningOutputTokens: Double? = nil, totalTokens: Double? = nil) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        inputTokens = c.number(forKey: .inputTokens)
        cachedInputTokens = c.number(forKey: .cachedInputTokens)
        cacheWriteInputTokens = c.number(forKey: .cacheWriteInputTokens)
        outputTokens = c.number(forKey: .outputTokens)
        reasoningOutputTokens = c.number(forKey: .reasoningOutputTokens)
        totalTokens = c.number(forKey: .totalTokens)
    }
}

private extension KeyedDecodingContainer {
    /// A JSON number, or a boolean as 1 or 0: the dictionary walk read both
    /// as `NSNumber` (spec 039 FR-011). Absent, `null` or another type is
    /// nil.
    func number(forKey key: Key) -> Double? {
        do {
            return try decodeIfPresent(Double.self, forKey: key)
        } catch {
            return (try? decode(Bool.self, forKey: key)).map { $0 ? 1 : 0 }
        }
    }
}

/// `payload.rate_limits` (spec 007 research R4).
struct CodexRateLimits: Decodable {
    var limitId: String?
    var planType: String?
    var primary: CodexLimitWindowFields?
    var secondary: CodexLimitWindowFields?
    /// `rate_limit_reached_type` is present and not null, whatever its value.
    var reached = false

    private enum Key: String, CodingKey {
        case primary, secondary
        case limitId = "limit_id"
        case planType = "plan_type"
        case reachedType = "rate_limit_reached_type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        limitId = try? c.decode(String.self, forKey: .limitId)
        planType = try? c.decode(String.self, forKey: .planType)
        primary = try? c.decode(CodexLimitWindowFields.self, forKey: .primary)
        secondary = try? c.decode(CodexLimitWindowFields.self, forKey: .secondary)
        reached = c.contains(.reachedType) && !((try? c.decodeNil(forKey: .reachedType)) ?? true)
    }
}

/// One window of `rate_limits`.
struct CodexLimitWindowFields: Decodable {
    var windowMinutes: Double?
    var usedPercent: Double?
    var resetsAt: Double?

    private enum Key: String, CodingKey {
        case windowMinutes = "window_minutes"
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        windowMinutes = c.number(forKey: .windowMinutes)
        usedPercent = c.number(forKey: .usedPercent)
        resetsAt = c.number(forKey: .resetsAt)
    }
}
