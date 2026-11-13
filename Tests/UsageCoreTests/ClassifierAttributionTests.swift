import Foundation
import Testing
@testable import UsageCore

/// spec 045 FR-005 to FR-011: classifier rows take the account and project of
/// the session whose span covers them in the same working directory.
@Suite struct ClassifierAttributionTests {
    static let rawCwd = "/raw/W/"
    static let directory = "/fixture/W"
    static let logPath = DecisionLogProbe.logPath(inDirectory: directory)
    static let project = Project(rootPath: "/fixture/W")
    let pricer = try! PriceTable.builtIn()
    let start = isoDate("2026-11-12T17:36:23Z")
    let last = isoDate("2026-11-12T17:38:51Z")

    func session(_ id: String, at time: Date, account: String? = "acc-a", key: String = "s1", cwd: String? = rawCwd,
                 model: String = "claude-opus-5-5", input: Int = 100) -> UsageRecord {
        UsageRecord(messageId: id, timestamp: time, model: model, canonicalModel: model, requestId: "gw_" + id, accountId: account,
                    inputTokens: input, outputTokens: 1, cacheWrite5mTokens: 0, cacheWrite1hTokens: 0, cacheReadTokens: 0,
                    costUSD: nil, project: Self.project, sessionKey: key, cwd: cwd)
    }

    func row(_ offset: Int, at time: Date, model: String = "claude-opus-5-5") -> ClassifierRow {
        ClassifierRow(id: "\(Self.logPath)#\(offset)", timestamp: time, model: model, inputTokens: 484, cacheReadTokens: 34304,
                      cacheWrite5mTokens: 7, outputTokens: 23)
    }

    func entry(_ rows: [ClassifierRow]) -> DecisionLogEntry {
        DecisionLogEntry(canonicalPath: Self.logPath, directory: Self.directory, size: 0, modificationDate: Date(),
                         parsedOffset: 0, rows: rows)
    }

    func attribute(_ rows: [ClassifierRow], sessions: [UsageRecord],
                   canonical: [String: String] = [rawCwd: directory]) -> ClassifierAttributionResult {
        ClassifierAttribution.records(entries: [entry(rows)], sessionRecords: sessions, canonical: canonical, pricer: pricer)
    }

    var probeSession: [UsageRecord] { [session("a", at: start), session("b", at: last)] }

    @Test func rowInsideTheSpanTakesTheSessionsAccountAndProject() throws {
        let r = row(0, at: isoDate("2026-11-12T17:38:34Z"))
        let result = attribute([r], sessions: probeSession)
        let record = try #require(result.records.first)
        #expect(result.records.count == 1)
        #expect(result.assigned == 1)
        #expect(result.unassigned == 0)
        #expect(record.accountId == "acc-a")
        #expect(record.project == Self.project)
        #expect(record.origin == .classifier)
        #expect(record.messageId == r.id)
        #expect(record.requestId == "")
        #expect(record.harness == .claudeCode)
        #expect(record.timestamp == r.timestamp)
        #expect(record.model == "claude-opus-5-5")
        #expect(record.canonicalModel == PriceTable.canonicalModel("claude-opus-5-5"))
        #expect(record.inputTokens == 484)
        #expect(record.cacheReadTokens == 34304)
        #expect(record.cacheWrite5mTokens == 7)
        #expect(record.cacheWrite1hTokens == 0)
        #expect(record.outputTokens == 23)
        #expect(record.costUSD == pricer.cost(model: "claude-opus-5-5", input: 484, output: 23, cacheWrite5m: 7, cacheWrite1h: 0,
                                              cacheRead: 34304))
        #expect(record.costUSD != nil)
    }

    /// FR-005: the span ends 5 minutes after the session's last record.
    @Test func gracePeriodIsFiveMinutes() {
        let result = attribute([row(0, at: last.addingTimeInterval(299)), row(1, at: last.addingTimeInterval(301))],
                               sessions: probeSession)
        #expect(result.records.map(\.accountId) == ["acc-a", nil])
        #expect(result.assigned == 1)
        #expect(result.unassigned == 1)
    }

    @Test func rowBeforeTheFirstRecordIsNotCovered() {
        let result = attribute([row(0, at: start.addingTimeInterval(-1))], sessions: probeSession)
        #expect(result.records.map(\.accountId) == [nil])
    }

    /// The canonical directory comes only from the probe's map: a record
    /// whose raw cwd is not in it builds no span.
    @Test func recordWithoutCanonicalDirectoryBuildsNoSpan() {
        let result = attribute([row(0, at: isoDate("2026-11-12T17:38:34Z"))], sessions: probeSession, canonical: [:])
        #expect(result.records.map(\.accountId) == [nil])
        #expect(result.unassigned == 1)
    }

    @Test func rowWithAnotherModelIsPricedUnderItsOwnModel() throws {
        let result = attribute([row(0, at: isoDate("2026-11-12T17:38:34Z"), model: "claude-haiku-4-5")], sessions: probeSession)
        let record = try #require(result.records.first)
        #expect(record.model == "claude-haiku-4-5")
        #expect(record.accountId == "acc-a")
        #expect(record.costUSD == pricer.cost(model: "claude-haiku-4-5", input: 484, output: 23, cacheWrite5m: 7, cacheWrite1h: 0,
                                              cacheRead: 34304))
    }

    // MARK: Decision rule (US3, FR-006)

    var inside: Date { isoDate("2026-11-12T17:38:34Z") }

    /// Two overlapping sessions on accounts A and B.
    @Test func overlappingSessionsOnDifferentAccountsLeaveTheRowUnassigned() {
        let sessions = probeSession + [session("c", at: start, account: "acc-b", key: "s2"),
                                       session("d", at: last, account: "acc-b", key: "s2")]
        let result = attribute([row(0, at: inside)], sessions: sessions)
        #expect(result.records.map(\.accountId) == [nil])
        #expect(result.unassigned == 1)
        #expect(result.assigned == 0)
    }

    @Test func overlappingSessionsOnTheSameAccountAssignTheRow() {
        let sessions = probeSession + [session("c", at: start, key: "s2"), session("d", at: last, key: "s2")]
        let result = attribute([row(0, at: inside)], sessions: sessions)
        #expect(result.records.map(\.accountId) == ["acc-a"])
    }

    @Test func unassignedCoveringSessionLeavesTheRowUnassigned() {
        let alone = attribute([row(0, at: inside)], sessions: [session("a", at: start, account: nil), session("b", at: last, account: nil)])
        #expect(alone.records.map(\.accountId) == [nil])
        // Also when another covering session has an account.
        let mixed = attribute([row(0, at: inside)],
                              sessions: [session("x", at: start, account: nil, key: "s0")] + probeSession)
        #expect(mixed.records.map(\.accountId) == [nil])
    }

    /// A session whose own records went to two accounts, or partly to
    /// Unassigned, decides no row (FR-006, edge case "two accounts").
    @Test func sessionWithRecordsOnTwoAccountsLeavesTheRowUnassigned() {
        let split = attribute([row(0, at: inside)], sessions: [session("a", at: start, account: "acc-a"),
                                                               session("b", at: last, account: "acc-b")])
        #expect(split.records.map(\.accountId) == [nil])
        let partly = attribute([row(0, at: inside)], sessions: [session("a", at: start, account: "acc-a"),
                                                                session("b", at: last, account: nil)])
        #expect(partly.records.map(\.accountId) == [nil])
    }

    /// FR-005: only in-window records count toward a span, so a session
    /// that started before the window spans from its first in-window record.
    @Test func spanStartsAtTheFirstInWindowRecord() {
        let windowStart = isoDate("2026-11-12T00:00:00Z")
        let firstInWindow = isoDate("2026-11-12T00:10:00Z")
        let sessions = [session("a", at: firstInWindow), session("b", at: isoDate("2026-11-12T00:20:00Z"))]
        let result = attribute([row(0, at: windowStart.addingTimeInterval(60)), row(1, at: firstInWindow.addingTimeInterval(60))],
                               sessions: sessions)
        #expect(result.records.map(\.accountId) == [nil, "acc-a"])
    }

    // MARK: Possible double recording (FR-013, Assumptions)

    /// A session record of a covering span with the row's four counters
    /// (cache write as 5-minute plus 1-hour) marks its session.
    @Test func sessionRecordWithTheRowsCountersIsNoted() {
        var twin = session("t", at: inside, key: "s2")
        twin.inputTokens = 484
        twin.outputTokens = 23
        twin.cacheReadTokens = 34304
        twin.cacheWrite5mTokens = 3
        twin.cacheWrite1hTokens = 4
        let result = attribute([row(0, at: inside)], sessions: probeSession + [twin])
        #expect(result.doubleRecordingSessions == ["s2"])
        // The counting is unchanged.
        #expect(result.records.count == 1)
    }

    @Test func differentCountersOrNoCoverMeanNoNote() {
        var other = session("t", at: inside)
        other.inputTokens = 484
        other.outputTokens = 23
        other.cacheReadTokens = 34304
        let result = attribute([row(0, at: inside)], sessions: probeSession + [other])
        #expect(result.doubleRecordingSessions.isEmpty)

        var twin = session("t", at: inside, key: "s2")
        twin.inputTokens = 484
        twin.outputTokens = 23
        twin.cacheReadTokens = 34304
        twin.cacheWrite5mTokens = 7
        let uncovered = attribute([row(0, at: last.addingTimeInterval(3600))], sessions: probeSession + [twin])
        #expect(uncovered.doubleRecordingSessions.isEmpty)
    }
}
