import Foundation
import Testing
@testable import UsageCore

/// spec 006 FR-008, FR-008a, FR-014, research R3.
@Suite struct CodexSessionParserTests {
    let parser = CodexSessionParser()

    func parse(_ name: String) throws -> CodexSession {
        parser.parse(data: try Data(contentsOf: Fixtures.url("codex/\(name)")))
    }

    @Test func deltasSplitInputAndKeepReasoningInOutput() throws {
        let session = try parse("apikey-session.jsonl")
        let raws = session.records.map(\.raw)
        // The null, zero and duplicate events add nothing: three records.
        #expect(raws.count == 3)
        #expect(raws.map(\.inputTokens) == [200, 500, 1000])
        #expect(raws.map(\.cacheReadTokens) == [0, 800, 2000])
        #expect(raws.map(\.cacheWrite5mTokens) == [800, 700, 0])
        #expect(raws.map(\.cacheWrite1hTokens) == [0, 0, 0])
        #expect(raws.map(\.outputTokens) == [100, 200, 50])
        #expect(raws.map(\.reasoningTokens) == [40, 50, 0])
        // Input plus both cache parts equals the reported input change.
        #expect(raws.map { $0.inputTokens + $0.cacheReadTokens + $0.cacheWrite5mTokens } == [1000, 2000, 3000])
    }

    @Test func timestampAndModelComeFromTheLines() throws {
        let raws = try parse("apikey-session.jsonl").records.map(\.raw)
        #expect(raws.map(\.timestamp) == [isoDate("2026-10-13T09:00:03.000Z"), isoDate("2026-10-13T09:01:00.000Z"),
                                          isoDate("2026-10-13T09:03:00.000Z")])
        #expect(raws.map(\.model) == ["gpt-5.5", "gpt-5.5", "gpt-5.5-mini"])
        #expect(raws.allSatisfy { $0.cwd == "/tmp/codex-apikey" })
        #expect(raws.allSatisfy { $0.harness == .codex })
    }

    @Test func recordsCarrySessionAndNoRequestId() throws {
        let session = try parse("apikey-session.jsonl")
        #expect(session.sessionId == "019a0000-0000-7000-8000-0000000000a1")
        #expect(session.cwd == "/tmp/codex-apikey")
        #expect(session.records.allSatisfy { $0.raw.requestId == "" })
        #expect(session.records.allSatisfy { $0.raw.sessionId == session.sessionId })
        #expect(session.records.allSatisfy { $0.raw.providerHint == nil })
        #expect(session.records.allSatisfy { $0.line.contains("\"token_count\"") })
        #expect(session.metaLine.contains("\"session_meta\""))
    }

    @Test func messageIdsAreStableAcrossParses() throws {
        let first = try parse("apikey-session.jsonl").records.map(\.raw.messageId)
        let second = try parse("apikey-session.jsonl").records.map(\.raw.messageId)
        #expect(first == second)
        #expect(Set(first).count == 3)
        #expect(first[0] == "codex:019a0000-0000-7000-8000-0000000000a1:1100")
    }

    @Test func planMarker() throws {
        #expect(try parse("apikey-session.jsonl").planMarker == false)
        #expect(try parse("plan-session.jsonl").planMarker == true)
        #expect(try parse("plan-session.jsonl").parentSessionId == nil)
    }

    @Test func subagentParentAndFirstMetaOnly() throws {
        let session = try parse("subagent-session.jsonl")
        #expect(session.sessionId == "019a0000-0000-7000-8000-0000000000c1")
        #expect(session.parentSessionId == "019a0000-0000-7000-8000-0000000000b1")
        // The repeated parent meta line does not redefine the session.
        #expect(session.cwd == "/tmp/codex-plan")
        #expect(session.metaLine.contains("0000000000c1"))
        #expect(session.planMarker == false)
        #expect(session.records.count == 1)
    }

    /// SC-002: the parent's copied `token_count` events (stamped with the
    /// fork time) only set the baseline the child continues from.
    @Test func copiedParentHistoryAddsNoUsage() throws {
        let session = try parse("subagent-session.jsonl")
        let raw = try #require(session.records.first?.raw)
        #expect(raw.inputTokens == 100)
        #expect(raw.cacheWrite5mTokens == 100)
        #expect(raw.cacheReadTokens == 0)
        #expect(raw.outputTokens == 20)
        #expect(raw.messageId == "codex:019a0000-0000-7000-8000-0000000000c1:1870")
        #expect(raw.timestamp == isoDate("2026-10-13T10:05:01.000Z"))
    }

    @Test func parentFallsBackToForkedFromId() {
        let line = """
        {"timestamp":"2026-10-13T09:00:00.000Z","type":"session_meta","payload":{"id":"child","cwd":"/tmp","source":"cli","forked_from_id":"parent-1"}}
        """
        #expect(parser.parse(data: Data((line + "\n").utf8)).parentSessionId == "parent-1")
    }

    @Test func reviewSubagentHasNoParent() throws {
        let session = try parse("review-subagent.jsonl")
        #expect(session.parentSessionId == nil)
        #expect(session.planMarker == false)
        #expect(session.records.count == 1)
    }

    @Test func truncatedLastLineIsSkipped() throws {
        let session = try parse("truncated.jsonl")
        #expect(session.records.count == 1)
        #expect(session.records.first?.raw.inputTokens == 100)
    }

    /// One `token_count` line with the given running totals.
    func tokenLine(_ time: String, input: Int, cached: Int = 0, output: Int, total: Int? = nil, plan: String? = nil) -> String {
        let totalField = total.map { ",\"total_tokens\":\($0)" } ?? ""
        let limits = plan.map { "{\"plan_type\":\"\($0)\"}" } ?? "null"
        return """
        {"timestamp":"\(time)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"cache_write_input_tokens":0,"output_tokens":\(output),"reasoning_output_tokens":0\(totalField)}},"rate_limits":\(limits)}}
        """
    }

    func meta(_ time: String, id: String, parent: String? = nil) -> String {
        let forked = parent.map { ",\"forked_from_id\":\"\($0)\"" } ?? ""
        return """
        {"timestamp":"\(time)","type":"session_meta","payload":{"id":"\(id)","cwd":"/tmp","source":"cli"\(forked)}}
        """
    }

    func parseLines(_ lines: [String]) -> CodexSession {
        parser.parse(data: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    /// FR-008a, SC-002: an all-zero event in the middle of a session adds
    /// nothing and does not make the next event count the whole total again.
    @Test func zeroEventMidSessionKeepsTheBaseline() {
        let session = parseLines([
            meta("2026-10-13T09:00:00.000Z", id: "s"),
            tokenLine("2026-10-13T09:00:10.000Z", input: 1000, output: 100, total: 1100),
            tokenLine("2026-10-13T09:00:20.000Z", input: 0, output: 0, total: 0),
            tokenLine("2026-10-13T09:00:30.000Z", input: 1500, output: 150, total: 1650),
        ])
        let raws = session.records.map(\.raw)
        #expect(raws.count == 2)
        #expect(raws.map(\.inputTokens) == [1000, 500])
        #expect(raws.map(\.outputTokens) == [100, 50])
        // The deltas add up to the final running total.
        #expect(raws.reduce(0) { $0 + $1.inputTokens + $1.outputTokens } == 1650)
    }

    /// SC-002: real forks stamp the copied parent events a few milliseconds
    /// after the meta line; they still only set the baseline.
    @Test func copiedHistoryStampedMillisecondsAfterTheForkAddsNoUsage() {
        let session = parseLines([
            meta("2026-10-13T10:05:00.000Z", id: "child", parent: "parent"),
            meta("2026-10-13T10:05:00.000Z", id: "parent"),
            tokenLine("2026-10-13T10:05:00.001Z", input: 500, output: 50, total: 550, plan: "plus"),
            tokenLine("2026-10-13T10:05:00.002Z", input: 1500, output: 150, total: 1650, plan: "plus"),
            tokenLine("2026-10-13T10:05:04.000Z", input: 1700, output: 170, total: 1870),
        ])
        let raws = session.records.map(\.raw)
        #expect(raws.count == 1)
        #expect(raws.first?.inputTokens == 200)
        #expect(raws.first?.outputTokens == 20)
        // FR-014: the parent's copied plan markers are not the child's own.
        #expect(session.planMarker == false)
    }

    /// Without a timestamp on the first meta line, the repeated parent meta
    /// line anchors the copied burst.
    @Test func copiedHistoryWithoutFirstMetaTimestampIsAnchoredOnTheRepeatedMeta() {
        let session = parseLines([
            #"{"type":"session_meta","payload":{"id":"child","cwd":"/tmp","source":"cli","forked_from_id":"parent"}}"#,
            meta("2026-10-13T10:05:00.000Z", id: "parent"),
            tokenLine("2026-10-13T10:05:00.001Z", input: 500, output: 50, total: 550, plan: "plus"),
            tokenLine("2026-10-13T10:05:04.000Z", input: 700, output: 70, total: 770),
        ])
        #expect(session.records.map(\.raw.inputTokens) == [200])
        #expect(session.planMarker == false)
    }

    /// FR-014: a marker on the child's own events still counts.
    @Test func ownPlanMarkerAfterCopiedHistoryCounts() {
        let session = parseLines([
            meta("2026-10-13T10:05:00.000Z", id: "child", parent: "parent"),
            meta("2026-10-13T10:05:00.000Z", id: "parent"),
            tokenLine("2026-10-13T10:05:00.001Z", input: 500, output: 50, total: 550),
            tokenLine("2026-10-13T10:05:04.000Z", input: 700, output: 70, total: 770, plan: "plus"),
        ])
        #expect(session.planMarker == true)
        #expect(session.records.count == 1)
    }

    /// Events without `total_tokens` still get distinct message ids.
    @Test func eventsWithoutTotalGetDistinctIds() {
        let session = parseLines([
            meta("2026-10-13T09:00:00.000Z", id: "s"),
            tokenLine("2026-10-13T09:00:10.000Z", input: 100, output: 10),
            tokenLine("2026-10-13T09:00:20.000Z", input: 200, output: 20),
        ])
        let ids = session.records.map(\.raw.messageId)
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
    }

    /// Out-of-range token values from a corrupt line are clamped, not trapped on.
    @Test func hugeTokenValuesDoNotTrap() {
        let line = """
        {"timestamp":"2026-10-13T09:00:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"cached_input_tokens":1e300,"cache_write_input_tokens":1e300,"output_tokens":-5,"reasoning_output_tokens":0,"total_tokens":1e300}},"rate_limits":null}}
        """
        let session = parseLines([meta("2026-10-13T09:00:00.000Z", id: "s"), line])
        #expect(session.records.count == 1)
        #expect(session.records.first?.raw.inputTokens == 0)
        #expect(session.records.first?.raw.outputTokens == 0)
    }

    @Test func fileWithoutMetaUsesTheFallbackSessionId() {
        let line = """
        {"timestamp":"2026-10-13T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":0,"total_tokens":12}},"rate_limits":null}}
        """
        let session = parser.parse(data: Data((line + "\n").utf8), fallbackSessionId: "rollout-x")
        #expect(session.sessionId == "rollout-x")
        #expect(session.records.first?.raw.messageId == "codex:rollout-x:12")
    }
}
