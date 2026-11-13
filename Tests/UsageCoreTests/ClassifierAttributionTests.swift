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

    func session(_ id: String, at time: Date, account: String? = "acc-a", key: SessionKey = "s1", cwd: String? = rawCwd,
                 model: String = "claude-opus-5-5", input: Int = 100, project: Project? = Self.project) -> UsageRecord {
        UsageRecord(messageId: id, timestamp: time, model: model, canonicalModel: model, requestId: "gw_" + id, accountId: account,
                    inputTokens: input, outputTokens: 1, cacheWrite5mTokens: 0, cacheWrite1hTokens: 0, cacheReadTokens: 0,
                    costUSD: nil, project: project, sessionKey: key, cwd: cwd)
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

    /// Edge case "several sessions at different times on different
    /// accounts" and the US3 Independent Test: each row goes to the session
    /// whose span covers it; a row in the gap stays unassigned.
    @Test func nonOverlappingSessionsOnDifferentAccountsEachKeepTheirRows() {
        let sessions = [session("a1", at: isoDate("2026-11-12T10:00:00Z"), account: "acc-a", key: "s1"),
                        session("a2", at: isoDate("2026-11-12T10:10:00Z"), account: "acc-a", key: "s1"),
                        session("b1", at: isoDate("2026-11-12T14:00:00Z"), account: "acc-b", key: "s2"),
                        session("b2", at: isoDate("2026-11-12T14:10:00Z"), account: "acc-b", key: "s2")]
        let result = attribute([row(0, at: isoDate("2026-11-12T10:05:00Z")), row(1, at: isoDate("2026-11-12T12:00:00Z")),
                                row(2, at: isoDate("2026-11-12T14:05:00Z"))], sessions: sessions)
        #expect(result.records.map(\.accountId) == ["acc-a", nil, "acc-b"])
        #expect(result.assigned == 2)
        #expect(result.unassigned == 1)
    }

    /// FR-001, FR-005: records of one session under two spellings of its
    /// working directory build one span.
    @Test func twoSpellingsOfTheDirectoryBuildOneSpan() {
        let sessions = [session("a", at: start, cwd: "/raw/W"), session("b", at: last, cwd: "/raw/W/")]
        let result = attribute([row(0, at: inside)], sessions: sessions,
                               canonical: ["/raw/W": Self.directory, "/raw/W/": Self.directory])
        #expect(result.records.map(\.accountId) == ["acc-a"])
    }

    @Test func noRowsMeansNoRecords() {
        let result = attribute([], sessions: probeSession)
        #expect(result == ClassifierAttributionResult())
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

    // MARK: Project fallback and directory scope (FR-005, FR-007; review findings of 2026-11-13)

    static let otherProject = Project(rootPath: "/fixture/W/sub")

    /// FR-007: a row no session covers takes the project of another
    /// session in the same directory.
    @Test func uncoveredRowTakesTheProjectOfASessionInItsDirectory() throws {
        let result = attribute([row(0, at: last.addingTimeInterval(301))], sessions: probeSession)
        let record = try #require(result.records.first)
        #expect(record.accountId == nil)
        #expect(record.project == Self.project)
    }

    /// FR-007: the covering session's project wins over another session's
    /// in the same directory.
    @Test func coveringSessionsProjectWinsOverTheDirectorys() throws {
        let early = session("x", at: start.addingTimeInterval(-3600), key: "s0", project: Self.otherProject)
        let covering = [session("a", at: start, project: Self.project), session("b", at: last, project: Self.project)]
        let result = attribute([row(0, at: inside)], sessions: [early] + covering)
        #expect(result.records.first?.project == Self.project)
        let uncovered = attribute([row(0, at: last.addingTimeInterval(400))],
                                  sessions: [session("a", at: start, project: nil), session("b", at: last, project: nil), early])
        #expect(uncovered.records.first?.project == Self.otherProject)
    }

    /// FR-007: without any session project in the directory, the row has
    /// none.
    @Test func rowWithoutAnyProjectInTheDirectoryHasNone() throws {
        let sessions = [session("a", at: start, project: nil), session("b", at: last, project: nil)]
        let covered = attribute([row(0, at: inside)], sessions: sessions)
        #expect(covered.records.first?.project == nil)
        #expect(covered.records.first?.accountId == "acc-a")
        let uncovered = attribute([row(0, at: last.addingTimeInterval(301))], sessions: sessions)
        #expect(uncovered.records.first?.project == nil)
    }

    /// FR-005: only sessions of the log's own directory cover its rows; a
    /// session on another account in another directory at the same time
    /// changes nothing.
    @Test func sessionsOfAnotherDirectoryDoNotCoverTheRow() throws {
        let otherDirectory = "/fixture/V"
        let otherProject = Project(rootPath: otherDirectory)
        let sessions = probeSession + [session("c", at: start, account: "acc-b", key: "s2", cwd: "/raw/V/", project: otherProject),
                                       session("d", at: last, account: "acc-b", key: "s2", cwd: "/raw/V/", project: otherProject)]
        let result = attribute([row(0, at: inside)], sessions: sessions,
                               canonical: [Self.rawCwd: Self.directory, "/raw/V/": otherDirectory])
        let record = try #require(result.records.first)
        #expect(record.accountId == "acc-a")
        #expect(record.project == Self.project)
        #expect(result.assigned == 1)
        #expect(result.unassigned == 0)
    }

    /// Review finding of 2026-11-13: a row dated after the refresh waits in
    /// the index and counts once its time has come, so it never reports
    /// activity from the future.
    @Test func rowAfterNowIsLeftOutUntilItsTime() {
        let future = row(0, at: inside.addingTimeInterval(86_400 * 30))
        let rows = [row(1, at: inside), future]
        let early = ClassifierAttribution.records(entries: [entry(rows)], sessionRecords: probeSession,
                                                  canonical: [Self.rawCwd: Self.directory], pricer: pricer, now: inside)
        #expect(early.records.map(\.messageId) == [rows[0].id])
        let later = ClassifierAttribution.records(entries: [entry(rows)], sessionRecords: probeSession,
                                                  canonical: [Self.rawCwd: Self.directory], pricer: pricer,
                                                  now: future.timestamp)
        #expect(later.records.count == 2)
    }

    /// FR-013: a session without id is never logged by its file path.
    @Test func sessionKeyOfAFileIsNotLoggedByItsPath() {
        #expect(SessionKey.id("abc").loggable == "session abc")
        #expect(SessionKey.file("/Users/me/.claude/projects/p/s.jsonl").loggable == "a session without id")
    }
}
