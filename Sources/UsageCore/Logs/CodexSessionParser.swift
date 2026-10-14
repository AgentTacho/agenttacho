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
        var session = CodexSession(sessionId: fallbackSessionId)
        var fork = CopiedHistory()
        var model = ""
        var cwd: String?
        var previous = Totals.zero
        var pending: [(timestamp: Date, delta: Totals, total: Int, model: String, cwd: String?, line: String)] = []
        let dates = ISO8601Parser()

        for (kind, lineData) in Self.relevantLines(of: data) {
            guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }
            switch kind {
            case .sessionMeta:
                // Forked files repeat the parent's meta line; only the first counts.
                guard fork.sessionMeta(at: (object["timestamp"] as? String).flatMap(dates.date)) else { continue }
                if let id = payload["id"] as? String, !id.isEmpty { session.sessionId = id }
                session.cwd = Self.nonEmpty(payload["cwd"])
                session.parentSessionId = Self.parent(of: payload)
                session.metaLine = String(decoding: lineData, as: UTF8.self)
            case .turnContext:
                if let m = Self.nonEmpty(payload["model"]) { model = m }
                if let c = Self.nonEmpty(payload["cwd"]) { cwd = c }
            case .tokenCount:
                guard payload["type"] as? String == "token_count",
                      let timestamp = (object["timestamp"] as? String).flatMap(dates.date) else { continue }
                let copiedHistory = fork.isCopied(eventAt: timestamp)
                if !copiedHistory, let limits = payload["rate_limits"] as? [String: Any],
                   let plan = limits["plan_type"] as? String, !plan.isEmpty {
                    session.planMarker = true
                }
                guard let info = payload["info"] as? [String: Any],
                      let usage = info["total_token_usage"] as? [String: Any] else { continue }
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
        let dates = ISO8601Parser()
        for (kind, lineData) in relevantLines(of: data) {
            guard kind != .turnContext,
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }
            let timestamp = (object["timestamp"] as? String).flatMap(dates.date)
            if kind == .sessionMeta {
                _ = fork.sessionMeta(at: timestamp)
                continue
            }
            guard payload["type"] as? String == "token_count", let timestamp,
                  !fork.isCopied(eventAt: timestamp),
                  let limits = payload["rate_limits"] as? [String: Any],
                  let snapshot = limitSnapshot(limits, at: timestamp) else { continue }
            if latest.map({ timestamp >= $0.observedAt }) ?? true {
                latest = snapshot
            }
        }
        return latest
    }

    /// One `rate_limits` object as an observation, or nil when it does not
    /// count (another bucket, no plan type, no window).
    private static func limitSnapshot(_ limits: [String: Any], at timestamp: Date) -> CodexLimitObservation? {
        if let bucket = limits["limit_id"] as? String, bucket != "codex" { return nil }
        guard let plan = nonEmpty(limits["plan_type"]) else { return nil }
        let windows = ["primary", "secondary"].compactMap { key -> CodexLimitWindow? in
            guard let window = limits[key] as? [String: Any] else { return nil }
            return CodexLimitWindow(minutes: (window["window_minutes"] as? NSNumber)?.doubleValue,
                                    usedPercent: (window["used_percent"] as? NSNumber)?.doubleValue,
                                    resetEpoch: (window["resets_at"] as? NSNumber)?.doubleValue)
        }
        guard !windows.isEmpty else { return nil }
        let reached = limits["rate_limit_reached_type"].map { !($0 is NSNull) } ?? false
        return CodexLimitObservation(planType: plan, observedAt: timestamp, origin: .snapshot,
                                     windows: CodexLimitWindow.applyingReachedRule(windows, sourceReportsReached: reached))
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

        init(_ usage: [String: Any]) {
            func value(_ key: String) -> Int {
                guard let number = usage[key] as? NSNumber else { return 0 }
                let double = number.doubleValue
                guard double.isFinite, double > 0 else { return 0 }
                return double >= Double(CodexSessionParser.maxTokenValue) ? CodexSessionParser.maxTokenValue : number.intValue
            }
            input = value("input_tokens")
            cached = value("cached_input_tokens")
            cacheWrite = value("cache_write_input_tokens")
            output = value("output_tokens")
            reasoning = value("reasoning_output_tokens")
            total = value("total_tokens")
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

    /// The lines AgentMeter reads, with their kind, in file order. A cheap
    /// byte check on each line's head runs before any JSON decoding: most
    /// lines are conversation items, often large, that are never decoded.
    static func relevantLines(of data: Data) -> [(LineKind, Data)] {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> [(LineKind, Data)] in
            guard let base = buffer.baseAddress else { return [] }
            var result: [(LineKind, Data)] = []
            var start = 0
            let count = buffer.count
            while start < count {
                let remaining = count - start
                let newline = memchr(base + start, 0x0A, remaining).map { base.distance(to: UnsafeRawPointer($0)) } ?? count
                let length = newline - start
                if length > 0 {
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

    /// The parent session: `source.subagent.thread_spawn.parent_thread_id`,
    /// then `forked_from_id`. A subagent of another shape (such as the string
    /// `"review"`) has no parent.
    static func parent(of payload: [String: Any]) -> String? {
        let forked = nonEmpty(payload["forked_from_id"])
        guard let source = payload["source"] as? [String: Any], let subagent = source["subagent"] else {
            return forked
        }
        guard let spawn = (subagent as? [String: Any])?["thread_spawn"] as? [String: Any] else { return nil }
        return nonEmpty(spawn["parent_thread_id"]) ?? forked
    }

    static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}

/// ISO 8601 timestamps with or without fractional seconds.
private final class ISO8601Parser {
    private let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func date(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }
}
