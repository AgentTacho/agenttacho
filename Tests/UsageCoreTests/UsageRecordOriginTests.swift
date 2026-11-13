import Foundation
import Testing
@testable import UsageCore

/// spec 045 data-model "UsageRecord (changed)", research R2: session records
/// carry their session key and working directory, so classifier rows can be
/// attributed through session spans.
@Suite struct UsageRecordOriginTests {
    let window = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-12-01T00:00:00Z"))
    let pricer = try! PriceTable.builtIn()

    @Test func newFieldsDefaultToSessionOriginWithoutKeyOrCwd() {
        let record = UsageRecord(messageId: "m", timestamp: Date(), model: "claude-opus-5-5", canonicalModel: "claude-opus-5-5",
                                 requestId: "r", accountId: nil, inputTokens: 1, outputTokens: 1, cacheWrite5mTokens: 0,
                                 cacheWrite1hTokens: 0, cacheReadTokens: 0, costUSD: nil)
        #expect(record.sessionKey == nil)
        #expect(record.cwd == nil)
        #expect(record.origin == .session)
    }

    @Test func rawInitializerCopiesCwd() {
        let raw = RawUsageRecord(messageId: "m", timestamp: Date(), model: "x", requestId: "r", inputTokens: 1, outputTokens: 0,
                                 cacheWrite5mTokens: 0, cacheWrite1hTokens: 0, cacheReadTokens: 0, cwd: "/fixture/W", sessionId: "s")
        let record = UsageRecord(raw: raw, canonicalModel: "x", accountId: nil, costUSD: nil)
        #expect(record.cwd == "/fixture/W")
        #expect(record.sessionKey == nil)
        #expect(record.origin == .session)
        let keyed = UsageRecord(raw: raw, canonicalModel: "x", accountId: nil, costUSD: nil, sessionKey: "s")
        #expect(keyed.sessionKey == "s")
    }

    @Test func logIndexStampsSessionIdAsSessionKey() throws {
        let root = try makeTempDirectory("origin-session-id")
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.install("direct-session.jsonl", into: root, as: "p/s.jsonl")
        let index = LogIndex()
        _ = index.update(files: LogDirectoryScanner().scan(directories: [root.path]).files, window: window,
                         parser: SessionRecordParser(), attributor: Attributor(configuration: Configuration()), pricer: pricer)
        #expect(!index.records.isEmpty)
        #expect(index.records.allSatisfy { $0.sessionKey == "s-direct" })
        #expect(index.records.allSatisfy { $0.origin == .session })
    }

    @Test func logIndexFallsBackToTheFilePathAndKeepsTheRawCwd() throws {
        let root = try makeTempDirectory("origin-no-session-id")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects/p/s.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = #"{"type":"assistant","cwd":"/fixture/W/","timestamp":"2026-11-12T17:36:23.000Z","requestId":"gw_1","message":{"id":"msg_1","model":"claude-opus-5-5","role":"assistant","content":[],"usage":{"input_tokens":10,"output_tokens":1}}}"#
        try Data((line + "\n").utf8).write(to: file)
        let files = LogDirectoryScanner().scan(directories: [root.path]).files
        let index = LogIndex()
        _ = index.update(files: files, window: window, parser: SessionRecordParser(),
                         attributor: Attributor(configuration: Configuration()), pricer: pricer)
        let record = try #require(index.records.first)
        #expect(record.sessionKey == files.first?.canonicalPath)
        #expect(record.cwd == "/fixture/W/")
    }
}
