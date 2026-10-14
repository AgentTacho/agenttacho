import Foundation
import Testing
@testable import UsageCore

@Suite struct SessionRecordParserTests {
    let parser = SessionRecordParser()

    private func parseAll(_ fixture: String) throws -> [RawUsageRecord] {
        try Fixtures.lines(fixture).compactMap { parser.parse(line: $0) }
    }

    @Test func parsesUsageFieldsAndSkipsOtherRecordTypes() throws {
        let records = try parseAll("vertex-session.jsonl")
        #expect(records.count == 4)
        let first = records[0]
        #expect(first.messageId == "msg_vrtx_A")
        #expect(first.requestId == "req_vrtx_001")
        #expect(first.model == "claude-opus-4-6")
        #expect(first.timestamp == isoDate("2026-10-12T10:00:05.000Z"))
        #expect(first.inputTokens == 3)
        #expect(first.outputTokens == 10)
        #expect(first.cacheWrite5mTokens == 39170)
        #expect(first.cacheWrite1hTokens == 0)
        #expect(first.cacheReadTokens == 0)

        let last = records[3]
        #expect(last.messageId == "msg_vrtx_B")
        #expect(last.cacheWrite5mTokens == 1500)
        #expect(last.cacheWrite1hTokens == 500)
        #expect(last.cacheReadTokens == 5000)
        #expect(last.inputTokens == 1000)
        #expect(last.outputTokens == 500)
    }

    @Test func extractsWorkingDirectory() {
        let line = #"{"type":"assistant","cwd":"/Users/me/work/repo","timestamp":"2026-10-12T10:00:00Z","requestId":"r1","message":{"id":"m1","model":"claude-opus-4-6","usage":{"input_tokens":1,"output_tokens":1}}}"#
        #expect(parser.parse(line: line)?.cwd == "/Users/me/work/repo")

        let missing = line.replacingOccurrences(of: #""cwd":"/Users/me/work/repo","#, with: "")
        #expect(parser.parse(line: missing)?.cwd == nil)

        let empty = line.replacingOccurrences(of: "/Users/me/work/repo", with: "")
        #expect(parser.parse(line: empty)?.cwd == nil)
    }

    @Test func dedupeKeepsTheLastWorkingDirectory() {
        let records = [makeRaw(id: "m1", output: 1, cwd: "/a"), makeRaw(id: "m1", output: 2, cwd: "/b")]
        #expect(SessionRecordParser.dedupe(records).map(\.cwd) == ["/b"])
    }

    @Test func dedupesByMessageIdKeepingTheLast() throws {
        let records = try parseAll("vertex-session.jsonl")
        let deduped = SessionRecordParser.dedupe(records)
        #expect(deduped.count == 2)
        #expect(deduped[0].messageId == "msg_vrtx_A")
        #expect(deduped[0].outputTokens == 169)
        #expect(deduped[0].timestamp == isoDate("2026-10-12T10:00:07.000Z"))
        #expect(deduped[1].messageId == "msg_vrtx_B")
    }

    @Test func dedupeFallsBackToRequestId() {
        let a = makeRaw(id: "", requestId: "req_1", output: 1)
        let b = makeRaw(id: "", requestId: "req_1", output: 2)
        let c = makeRaw(id: "", requestId: "req_2", output: 3)
        let deduped = SessionRecordParser.dedupe([a, b, c])
        #expect(deduped.map(\.outputTokens) == [2, 3])
    }

    @Test func skipsTruncatedLastLine() throws {
        let records = try parseAll("truncated.jsonl")
        #expect(records.count == 2)
        #expect(records.map(\.messageId) == ["msg_vrtx_T1", "msg_vrtx_T2"])
    }

    @Test func cacheCreationFallbacks() throws {
        let records = try parseAll("malformed-fields.jsonl")
        #expect(records.map(\.messageId) == ["msg_vrtx_M4", "msg_vrtx_M5"])
        let withoutSplit = records[0]
        #expect(withoutSplit.cacheWrite5mTokens == 500)
        #expect(withoutSplit.cacheWrite1hTokens == 0)
        #expect(withoutSplit.cacheReadTokens == 7)
        let withoutAny = records[1]
        #expect(withoutAny.cacheWrite5mTokens == 0)
        #expect(withoutAny.cacheWrite1hTokens == 0)
        #expect(withoutAny.cacheReadTokens == 0)
        #expect(withoutAny.inputTokens == 11)
    }

    @Test func parsesSidechainRecords() throws {
        let records = try parseAll("subagents/agent-x.jsonl")
        #expect(records.count == 1)
        #expect(records[0].model == "claude-haiku-4-5")
    }

    @Test func parsesDirectRecordsWithSnapshotModelId() throws {
        let records = try parseAll("direct-session.jsonl")
        #expect(records.count == 2)
        #expect(records[1].model == "claude-haiku-4-5-20251001")
        #expect(records[0].requestId.hasPrefix("req_011"))
    }

    @Test func dropsZeroUsagePlaceholderRecords() {
        let synthetic = """
        {"type":"assistant","timestamp":"2026-10-12T10:00:00.000Z","uuid":"e1","message":{"id":"msg_err","model":"<synthetic>","role":"assistant","content":[],"usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        #expect(parser.parse(line: synthetic) == nil)
        let cacheOnly = """
        {"type":"assistant","timestamp":"2026-10-12T10:00:00.000Z","requestId":"req_vrtx_C","message":{"id":"msg_c","model":"claude-opus-5-5","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":7}}}
        """
        #expect(parser.parse(line: cacheOnly)?.cacheReadTokens == 7)
    }

    @Test func rejectsEmptyAndGarbageLines() {
        #expect(parser.parse(line: "") == nil)
        #expect(parser.parse(line: "   ") == nil)
        #expect(parser.parse(line: "{}") == nil)
        #expect(parser.parse(line: "{\"type\":\"assistant\"}") == nil)
    }
}
