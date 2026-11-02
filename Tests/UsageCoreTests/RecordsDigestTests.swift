import Foundation
import Testing
@testable import UsageCore

/// The records digest of the bench and its comparison (spec 039 FR-004,
/// FR-005, research R5, R9, contracts/bench-cli.md "Digest file").
@Suite struct RecordsDigestTests {
    static let header = RecordsDigest.Header(configuration: "~/.config/agenttacho/config.json",
                                             windowStart: "2026-10-01T00:00:00Z", directory: "~/.claude")

    static func record(messageId: String = "msg_01AB", requestId: String = "req_01", at timestamp: String = "2026-10-14T19:44:01.080Z",
                       model: String = "claude-sonnet-5-5", account: String? = "acc-max", cost: Decimal? = Decimal(string: "0.0123"),
                       project: String? = "/fixture/proj-alpha", harness: Harness = .claudeCode, reasoning: Int = 0) -> UsageRecord {
        UsageRecord(messageId: messageId, timestamp: isoDate(timestamp), model: model, canonicalModel: model, requestId: requestId,
                    accountId: account, inputTokens: 12, outputTokens: 340, cacheWrite5mTokens: 1, cacheWrite1hTokens: 2,
                    cacheReadTokens: 18000, costUSD: cost, project: project.map(Project.init(rootPath:)), harness: harness,
                    reasoningTokens: reasoning)
    }

    @Test func recordLineHasFourteenTabSeparatedColumns() {
        let line = RecordsDigest.line(for: Self.record())
        #expect(line == "claudeCode\tmsg:msg_01AB\t2026-10-14T19:44:01.080Z\tclaude-sonnet-5-5\tclaude-sonnet-5-5\t12\t340\t1\t2\t18000\t0\t/fixture/proj-alpha\tacc-max\t0.0123")
        #expect(line.split(separator: "\t", omittingEmptySubsequences: false).count == 14)
    }

    @Test func nilProjectAccountAndCostAreEmptyText() throws {
        let line = RecordsDigest.line(for: Self.record(account: nil, cost: nil, project: nil))
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        try #require(columns.count == 14)
        #expect(columns[11] == "")
        #expect(columns[12] == "")
        #expect(columns[13] == "")
    }

    @Test func costIsDecimalText() {
        let cost = Decimal(string: "12.345678901234567890")!
        let line = RecordsDigest.line(for: Self.record(cost: cost))
        #expect(line.hasSuffix("\t12.34567890123456789"))
    }

    @Test func keysUseTheMessageIdOrTheRequestId() throws {
        #expect(RecordsDigest.line(for: Self.record(messageId: "msg_X", requestId: "req_Y")).contains("\tmsg:msg_X\t"))
        #expect(RecordsDigest.line(for: Self.record(messageId: "", requestId: "req_Y")).contains("\treq:req_Y\t"))
        // Codex message ids carry the session id and the running total.
        let codex = Self.record(messageId: "codex:019a0000-0000-7000-8000-0000000000a1:1100", requestId: "", model: "gpt-5.5",
                                harness: .codex, reasoning: 40)
        let line = RecordsDigest.line(for: codex)
        #expect(line.hasPrefix("codex\tmsg:codex:019a0000-0000-7000-8000-0000000000a1:1100\t"))
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        try #require(columns.count == 14)
        #expect(columns[10] == "40")
    }

    /// Research R5: two parsers reach the millisecond grid through
    /// different floating-point paths, so the digest rounds instead of
    /// flooring.
    @Test func timestampsRoundToTheNearestMillisecond() {
        let base = isoDate("2026-10-14T19:44:01.080Z").timeIntervalSinceReferenceDate
        let below = Date(timeIntervalSinceReferenceDate: base.nextDown)
        let above = Date(timeIntervalSinceReferenceDate: base.nextUp)
        #expect(RecordsDigest.timestamp(below) == "2026-10-14T19:44:01.080Z")
        #expect(RecordsDigest.timestamp(above) == "2026-10-14T19:44:01.080Z")
        #expect(RecordsDigest.timestamp(isoDate("2026-10-14T19:44:01Z")) == "2026-10-14T19:44:01.000Z")
        #expect(RecordsDigest.timestamp(isoDate("2025-12-31T23:59:59.999Z")) == "2025-12-31T23:59:59.999Z")
        #expect(RecordsDigest.timestamp(isoDate("2028-02-29T12:00:00Z")) == "2028-02-29T12:00:00.000Z")
        // 0.9996 s rounds up into the next second, minute, hour and day.
        let late = Date(timeIntervalSinceReferenceDate: isoDate("2025-12-31T23:59:59Z").timeIntervalSinceReferenceDate + 0.9996)
        #expect(RecordsDigest.timestamp(late) == "2026-01-01T00:00:00.000Z")
    }

    @Test func headerLinesAreAsSpecified() {
        let digest = RecordsDigest(records: [], header: Self.header)
        #expect(digest.text == "digest 1\nconfig ~/.config/agenttacho/config.json\nwindow-start 2026-10-01T00:00:00Z\ndirectory ~/.claude\n")
    }

    @Test func sortingIsStableAndIndependentOfTheInputOrder() {
        let records = [
            Self.record(messageId: "msg_B", at: "2026-10-14T10:00:00Z"),
            Self.record(messageId: "codex:s:2", requestId: "", harness: .codex),
            Self.record(messageId: "msg_A", at: "2026-10-14T11:00:00Z"),
            Self.record(messageId: "", requestId: "req_A"),
            Self.record(messageId: "msg_A", at: "2026-10-14T09:00:00Z"),
            Self.record(messageId: "msg_A", at: "2026-10-14T09:00:00Z", model: "claude-haiku-5-5"),
        ]
        let digest = RecordsDigest(records: records, header: Self.header)
        let keys = digest.lines.map { $0.split(separator: "\t", omittingEmptySubsequences: false).prefix(4).joined(separator: " ") }
        #expect(keys == [
            "claudeCode msg:msg_A 2026-10-14T09:00:00.000Z claude-haiku-5-5",
            "claudeCode msg:msg_A 2026-10-14T09:00:00.000Z claude-sonnet-5-5",
            "claudeCode msg:msg_A 2026-10-14T11:00:00.000Z claude-sonnet-5-5",
            "claudeCode msg:msg_B 2026-10-14T10:00:00.000Z claude-sonnet-5-5",
            "claudeCode req:req_A 2026-10-14T19:44:01.080Z claude-sonnet-5-5",
            "codex msg:codex:s:2 2026-10-14T19:44:01.080Z claude-sonnet-5-5",
        ])
        for _ in 0..<5 {
            #expect(RecordsDigest(records: records.shuffled(), header: Self.header).text == digest.text)
        }
    }

    @Test func untilDropsRecordsAtOrAfterIt() {
        let records = [
            Self.record(messageId: "msg_early", at: "2026-10-14T09:59:59.999Z"),
            Self.record(messageId: "msg_at", at: "2026-10-14T10:00:00Z"),
            Self.record(messageId: "msg_late", at: "2026-10-14T10:00:01Z"),
        ]
        let digest = RecordsDigest(records: records, header: Self.header, until: isoDate("2026-10-14T10:00:00Z"))
        #expect(digest.lines.count == 1)
        #expect(digest.lines.first?.contains("msg:msg_early") == true)
    }

    @Test func textRoundTripsThroughParse() throws {
        let digest = RecordsDigest(records: [Self.record(), Self.record(messageId: "msg_2", account: nil, cost: nil, project: nil)],
                                   header: Self.header)
        let parsed = try RecordsDigest.parse(digest.text)
        #expect(parsed == digest)
        #expect(parsed.text == digest.text)
    }

    @Test func parseRefusesTextThatIsNoDigest() {
        #expect(throws: (any Error).self) { try RecordsDigest.parse("not a digest\n") }
        #expect(throws: (any Error).self) { try RecordsDigest.parse("") }
    }

    @Test func equalRecordLinesAreIdentical() {
        let a = RecordsDigest(records: [Self.record(), Self.record(messageId: "msg_2")], header: Self.header)
        let comparison = RecordsDigest.compare(a, a)
        #expect(comparison.identical)
        #expect(comparison.onlyInA.isEmpty && comparison.onlyInB.isEmpty)
        #expect(comparison.countA == 2 && comparison.countB == 2)
        #expect(comparison.headerNotes.isEmpty)
        #expect(comparison.text == "identical: 2 records\n")
    }

    @Test func differentHeadersAloneAreIdenticalWithNotes() {
        let a = RecordsDigest(records: [Self.record()], header: Self.header)
        let otherHeader = RecordsDigest.Header(configuration: "~/other.json", windowStart: "2026-10-01T00:00:00Z", directory: "~/.claude")
        let b = RecordsDigest(records: [Self.record()], header: otherHeader)
        let comparison = RecordsDigest.compare(a, b)
        #expect(comparison.identical)
        #expect(comparison.headerNotes.count == 1)
        #expect(comparison.headerNotes.first?.contains("~/other.json") == true)
        #expect(comparison.text.hasPrefix("identical: 1 records\n"))
    }

    @Test func differencesAreCappedAtTwentyLinesWithTheCounts() {
        let shared = Self.record(messageId: "msg_shared")
        let onlyA = (0..<25).map { Self.record(messageId: String(format: "msg_a%02d", $0)) }
        let onlyB = [Self.record(messageId: "msg_b")]
        let a = RecordsDigest(records: [shared] + onlyA, header: Self.header)
        let b = RecordsDigest(records: [shared] + onlyB, header: Self.header)
        let comparison = RecordsDigest.compare(a, b)
        #expect(!comparison.identical)
        #expect(comparison.countA == 26)
        #expect(comparison.countB == 2)
        #expect(comparison.onlyInA.count == 20)
        #expect(comparison.onlyInACount == 25)
        #expect(comparison.onlyInB == [RecordsDigest.line(for: onlyB[0])])
        #expect(comparison.onlyInBCount == 1)
        #expect(comparison.onlyInA.first == RecordsDigest.line(for: onlyA[0]))
        #expect(comparison.text.hasPrefix("different: 26 records in A, 2 in B\nonly in A (20 shown of 25):\n  claudeCode\tmsg:msg_a00\t"))
        #expect(comparison.text.contains("only in B (1 shown of 1):\n  claudeCode\tmsg:msg_b\t"))
    }

    /// A record that appears twice in one digest and once in the other is
    /// a difference: lines compare as a multiset.
    @Test func duplicateLinesCountAsDifferences() {
        let a = RecordsDigest(records: [Self.record(), Self.record()], header: Self.header)
        let b = RecordsDigest(records: [Self.record()], header: Self.header)
        let comparison = RecordsDigest.compare(a, b)
        #expect(!comparison.identical)
        #expect(comparison.onlyInACount == 1)
        #expect(comparison.onlyInBCount == 0)
    }
}
