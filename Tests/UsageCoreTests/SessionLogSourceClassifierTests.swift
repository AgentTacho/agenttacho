import Foundation
import Testing
@testable import UsageCore

/// A temporary home with a Claude Code configuration directory, a session
/// working directory and a diagnostic log, for the end-to-end tests of
/// spec 045. Fixture paths `/fixture/W` are rewritten to the real working
/// directory.
final class ClassifierScenario {
    let root: URL
    let claude: URL
    let work: URL
    let logURL: URL
    let window = DateInterval(start: isoDate("2026-11-12T00:00:00Z"), end: isoDate("2026-11-19T00:00:00Z"))
    static let fileDate = isoDate("2026-11-12T18:00:00Z")
    var configuration: Configuration
    let source: SessionLogSource
    let log: DiagnosticLog

    init(_ name: String, probe: DecisionLogProbe = DecisionLogProbe(), accounts: [Account]? = nil,
         classifierIndex: ClassifierLogIndex = ClassifierLogIndex()) throws {
        root = try makeTempDirectory(name).resolvingSymlinksInPath()
        claude = root.appendingPathComponent(".claude")
        work = root.appendingPathComponent("W")
        logURL = root.appendingPathComponent("usage.log")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        var c = Configuration()
        c.accounts = accounts ?? [Self.gateway("acc-gw", directory: "~/.claude")]
        c.groups = [BudgetGroup(id: "grp", name: "Gateway", budgetUSD: 60)]
        try c.validate()
        configuration = c
        log = DiagnosticLog(fileURL: logURL)
        source = try SessionLogSource(paths: Paths(home: root), log: log, builtInPrices: PriceTable.builtIn(), probe: probe,
                                      classifierIndex: classifierIndex)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// A token-based Claude Code account for a gateway (no `req_` request
    /// ids), reading `directory`; `modelPrefix` adds a condition.
    static func gateway(_ id: String, directory: String, modelPrefix: String? = nil) -> Account {
        let condition = modelPrefix.map { MatchCondition(field: .model, operator: .startsWith, text: $0) }
        return Account(id: id, displayName: id,
                       kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), harness: .claudeCode,
                                                            sessionKind: .claudeCodeOtherProvider, condition: condition,
                                                            sessionDirectory: directory)))
    }

    func rewrite(_ text: String, cwd: URL? = nil) -> String {
        text.replacingOccurrences(of: "/fixture/W", with: (cwd ?? work).path)
    }

    /// Writes a session file into `<claude>/projects/p/<name>`.
    @discardableResult
    func writeSession(_ lines: [String], name: String = "probe.jsonl", in directory: URL? = nil) throws -> URL {
        let url = (directory ?? claude).appendingPathComponent("projects/p/\(name)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lines.map { rewrite($0) + "\n" }.joined().utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Self.fileDate], ofItemAtPath: url.path)
        return url
    }

    func installProbeSession() throws {
        try writeSession(try Fixtures.lines("classifier/probe-session.jsonl"))
    }

    var decisionLog: URL { work.appendingPathComponent(DecisionLogProbe.fileName) }

    func writeDecisions(_ text: String, date: Date = ClassifierScenario.fileDate, in directory: URL? = nil) throws {
        let url = (directory ?? work).appendingPathComponent(DecisionLogProbe.fileName)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func appendDecisions(_ text: String, date: Date) throws {
        try FileHandle(forWritingTo: decisionLog).withAppend(Data(text.utf8))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: decisionLog.path)
    }

    func installProbeDecisions() throws {
        let data = try Data(contentsOf: Fixtures.url("classifier/probe-decisions.jsonl"))
        try writeDecisions(String(decoding: data, as: UTF8.self))
    }

    func collect(now: Date = isoDate("2026-11-13T09:00:00Z")) async throws -> [UsageRecord] {
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window, now: now))
        guard case .records(let records) = output else {
            Issue.record("expected records output")
            return []
        }
        return records
    }

    func logLines() -> [String] { log.tail(lines: 1000) }
}

/// A thread-safe list of the directories an injected probe check saw.
final class CheckedDirectories: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

func totalTokens(_ records: [UsageRecord], account: String?) -> Int {
    records.filter { $0.accountId == account }.reduce(0) { $0 + $1.totalTokens }
}

/// spec 045 end to end: SessionLogSource over a Claude configuration with a
/// decision log in the session's working directory.
@Suite struct SessionLogSourceClassifierTests {
    /// SC-001, US1 scenarios 1 to 3.
    @Test func probeFixtureGivesTheCombinedTotal() async throws {
        let s = try ClassifierScenario("classifier-e2e-probe")
        try s.installProbeSession()
        try s.installProbeDecisions()

        let records = try await s.collect()
        #expect(totalTokens(records, account: "acc-gw") == 149_792)
        let classifier = records.filter { $0.origin == .classifier }
        #expect(classifier.count == 2)
        #expect(classifier.allSatisfy { $0.model == "rits/zai-org/glm-5-3" && $0.accountId == "acc-gw" })
        let sessionProject = try #require(records.first { $0.origin == .session }?.project)
        #expect(classifier.allSatisfy { $0.project == sessionProject })
        #expect(classifier.reduce(0) { $0 + $1.inputTokens } == 969)
        #expect(classifier.reduce(0) { $0 + $1.cacheReadTokens } == 68_608)
        #expect(classifier.reduce(0) { $0 + $1.outputTokens } == 47)
    }

    /// US1 scenario 4, SC-003, FR-011: session records are the same with and
    /// without a decision log.
    @Test func withoutDecisionLogSessionRecordsAreUnchanged() async throws {
        let with = try ClassifierScenario("classifier-e2e-with")
        try with.installProbeSession()
        try with.installProbeDecisions()
        let without = try ClassifierScenario("classifier-e2e-without")
        try without.installProbeSession()

        let withRecords = try await with.collect().filter { $0.origin == .session }
        let withoutRecords = try await without.collect()
        #expect(withoutRecords.allSatisfy { $0.origin == .session })
        #expect(totalTokens(withoutRecords, account: "acc-gw") == 80_168)
        // Paths differ between the two temporary homes; compare with them
        // rewritten to the fixture path.
        func normalized(_ records: [UsageRecord], _ s: ClassifierScenario) -> [String] {
            records.map { RecordsDigest.line(for: $0).replacingOccurrences(of: s.root.path, with: "/ROOT") }
        }
        #expect(normalized(withRecords, with) == normalized(withoutRecords, without))
        #expect(withRecords.count == withoutRecords.count)
        for (a, b) in zip(withRecords, withoutRecords) {
            #expect(a.messageId == b.messageId && a.accountId == b.accountId && a.totalTokens == b.totalTokens
                    && a.costUSD == b.costUSD && a.model == b.model && a.timestamp == b.timestamp)
        }
    }

    /// FR-002: a session whose records have no cwd, or whose records all
    /// lie before the window, causes no check of a directory.
    @Test func onlyInWindowSessionsWithCwdAreChecked() async throws {
        let seen = CheckedDirectories()
        let probe = DecisionLogProbe(check: { directory, known, notBefore, readLimit in
            seen.append(directory)
            return DecisionLogProbe.inspect(directory: directory, known: known, notBefore: notBefore, readLimit: readLimit)
        })
        let s = try ClassifierScenario("classifier-e2e-window", probe: probe)
        try s.installProbeSession()
        let old = s.root.appendingPathComponent("Old")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let oldLine = #"{"type":"assistant","cwd":"\#(old.path)","sessionId":"old","timestamp":"2026-11-01T10:00:00.000Z","requestId":"gw_old","message":{"id":"msg_old","model":"m","role":"assistant","content":[],"usage":{"input_tokens":5,"output_tokens":1}}}"#
        let noCwdLine = #"{"type":"assistant","sessionId":"nocwd","timestamp":"2026-11-12T12:00:00.000Z","requestId":"gw_nocwd","message":{"id":"msg_nocwd","model":"m","role":"assistant","content":[],"usage":{"input_tokens":5,"output_tokens":1}}}"#
        try s.writeSession([oldLine], name: "old.jsonl")
        try s.writeSession([noCwdLine], name: "nocwd.jsonl")

        _ = try await s.collect()
        #expect(seen.all == [Attributor.canonical(s.work.path)])
    }

    /// A decision log line at `time` with the given counters.
    static func decision(_ time: String, input: Int = 10, cacheRead: Int = 100, output: Int = 2,
                         model: String = "rits/zai-org/glm-5-3[1m]") -> String {
        let ms = Int(isoDate(time).timeIntervalSince1970 * 1000)
        return #"{"ts":\#(ms),"tool":"Bash","decision":"allowed","classifierModel":"\#(model)","inputTokens":\#(input),"outputTokens":\#(output),"cacheReadInputTokens":\#(cacheRead),"cacheCreationInputTokens":0}"# + "\n"
    }

    /// SC-002: ten refreshes over unchanged data give identical totals;
    /// appending N rows changes them by exactly those rows.
    @Test func repeatedRefreshesCountEachRowOnce() async throws {
        let s = try ClassifierScenario("classifier-e2e-repeat")
        try s.installProbeSession()
        try s.installProbeDecisions()

        var totals: [Int] = []
        for _ in 0..<10 {
            totals.append(totalTokens(try await s.collect(), account: "acc-gw"))
        }
        #expect(totals == Array(repeating: 149_792, count: 10))

        let appended = [Self.decision("2026-11-12T17:39:00Z", input: 1, cacheRead: 2, output: 3),
                        Self.decision("2026-11-12T17:40:00Z", input: 4, cacheRead: 5, output: 6),
                        Self.decision("2026-11-12T17:41:00Z", input: 7, cacheRead: 8, output: 9)]
        try s.appendDecisions(appended.joined(), date: isoDate("2026-11-12T18:05:00Z"))
        #expect(totalTokens(try await s.collect(), account: "acc-gw") == 149_792 + 45)
        #expect(totalTokens(try await s.collect(), account: "acc-gw") == 149_792 + 45)

        try s.appendDecisions(Self.decision("2026-11-12T17:42:00Z", input: 100, cacheRead: 0, output: 0),
                              date: isoDate("2026-11-12T18:06:00Z"))
        let records = try await s.collect()
        #expect(totalTokens(records, account: "acc-gw") == 149_792 + 145)
        #expect(records.filter { $0.origin == .classifier }.count == 6)
    }

    /// A probe that remembers how many bytes each check read.
    static func countingProbe(_ reads: CheckedDirectories) -> DecisionLogProbe {
        DecisionLogProbe(check: { directory, known, notBefore, readLimit in
            let result = DecisionLogProbe.inspect(directory: directory, known: known, notBefore: notBefore, readLimit: readLimit)
            if case .found(_, _, _, let chunk?) = result { reads.append("\(chunk.data.count)") }
            return result
        })
    }

    static func sessionLine(_ id: String, at time: String, session: String = "probe-session", model: String = "rits/zai-org/glm-5-3",
                            input: Int = 10) -> String {
        #"{"type":"assistant","timestamp":"\#(time)","requestId":"gw_\#(id)","uuid":"\#(id)","sessionId":"\#(session)","cwd":"/fixture/W","message":{"id":"msg_\#(id)","model":"\#(model)","role":"assistant","type":"message","content":[],"usage":{"input_tokens":\#(input),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}"#
    }

    /// US1 scenario 5, FR-006: a row after the grace period is unassigned
    /// until a later session record extends the span; the decision log is
    /// not read again for that.
    @Test func laterSessionRecordAssignsAnEarlierRowWithoutRereadingTheLog() async throws {
        let reads = CheckedDirectories()
        let s = try ClassifierScenario("classifier-e2e-extend", probe: Self.countingProbe(reads))
        var lines = try Fixtures.lines("classifier/probe-session.jsonl")
        let session = try s.writeSession(lines)
        // 6 minutes after the last record (17:38:51).
        try s.writeDecisions(Self.decision("2026-11-12T17:44:51Z", input: 1, cacheRead: 2, output: 3))

        var records = try await s.collect()
        #expect(records.filter { $0.origin == .classifier }.map(\.accountId) == [nil])
        #expect(totalTokens(records, account: nil) == 6)
        #expect(reads.all.count == 1)

        lines.append(Self.sessionLine("late", at: "2026-11-12T17:44:00.000Z"))
        try s.writeSession(lines)
        try FileManager.default.setAttributes([.modificationDate: isoDate("2026-11-12T18:10:00Z")], ofItemAtPath: session.path)
        records = try await s.collect()
        #expect(records.filter { $0.origin == .classifier }.map(\.accountId) == ["acc-gw"])
        #expect(totalTokens(records, account: nil) == 0)
        #expect(reads.all.count == 1)
    }

    /// FR-006, SC-005: a session on another account that appears later in
    /// the same directory makes covered rows unassigned.
    @Test func newSessionOnAnotherAccountMakesCoveredRowsUnassigned() async throws {
        let s = try ClassifierScenario("classifier-e2e-ambiguous",
                                       accounts: [ClassifierScenario.gateway("acc-a", directory: "~/.claude", modelPrefix: "rits/"),
                                                  ClassifierScenario.gateway("acc-b", directory: "~/.claude", modelPrefix: "other/")])
        try s.installProbeSession()
        try s.installProbeDecisions()
        var records = try await s.collect()
        #expect(totalTokens(records, account: "acc-a") == 149_792)

        try s.writeSession([Self.sessionLine("b1", at: "2026-11-12T17:38:00.000Z", session: "s-b", model: "other/glm", input: 5)],
                           name: "other.jsonl")
        records = try await s.collect()
        #expect(records.filter { $0.accountId == "acc-b" }.count == 1)
        let classifier = records.filter { $0.origin == .classifier }
        #expect(classifier.count == 2)
        // SC-005: no row whose covering sessions disagree is assigned.
        #expect(classifier.allSatisfy { $0.accountId == nil })
        #expect(totalTokens(records, account: "acc-a") == 80_168)
        #expect(totalTokens(records, account: nil) == 69_624)
    }

    // MARK: Diagnostics (US4, FR-013)

    @Test func refreshWithADecisionLogLogsOneSummaryLine() async throws {
        let s = try ClassifierScenario("classifier-e2e-logline")
        try s.installProbeSession()
        let probe = try String(decoding: Data(contentsOf: Fixtures.url("classifier/probe-decisions.jsonl")), as: UTF8.self)
        let withoutUsage = #"{"ts":1794505120000,"tool":"Read","decision":"allowed","classifierModel":"rits/zai-org/glm-5-3[1m]","stage":"rule"}"# + "\n"
        let malformed = "{not json\n"
        // After the grace period: counted, but unassigned.
        let late = Self.decision("2026-11-12T17:50:00Z")
        try s.writeDecisions(probe + withoutUsage + malformed + late)

        _ = try await s.collect()
        let lines = s.logLines().filter { $0.contains("decision logs read") }
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.contains("decision logs read 1 (found 1, checked 1, timed out 0, busy 0, skipped 0)"))
        #expect(line.contains("rows counted 3, assigned 2, unassigned 1, in new lines: without usage 1, malformed 1"))
        // FR-013: no row content, tool name or log file name.
        for logged in s.logLines() {
            #expect(!logged.contains("Bash") && !logged.contains("Read\"") && !logged.contains("allowed"))
            #expect(!logged.contains(DecisionLogProbe.fileName))
        }

        // An unchanged log is found, not read.
        _ = try await s.collect()
        let second = s.logLines().filter { $0.contains("decision logs read") }
        #expect(second.count == 2)
        #expect(second.last?.contains("decision logs read 0 (found 1, checked 1, timed out 0, busy 0, skipped 0), rows counted 3, assigned 2, unassigned 1, in new lines: without usage 0, malformed 0") == true)
    }

    /// FR-013: a session record and a covered row with the same four
    /// counters are noted once per session; a session without an id is
    /// named without its file path.
    @Test func possibleDoubleRecordingIsLoggedOncePerSession() async throws {
        let s = try ClassifierScenario("classifier-e2e-double")
        try s.installProbeSession()
        // A session without an id in the same directory, and its twin row.
        let noId = Self.sessionLine("n1", at: "2026-11-12T17:37:00.000Z", input: 77)
            .replacingOccurrences(of: #""sessionId":"probe-session","#, with: "")
        let sessionFile = try s.writeSession([noId], name: "no-id.jsonl")
        // Twins of a probe session record (input 10 is not in it, so a
        // record of `sessionLine` is added) and of the session without id.
        try s.writeSession(try Fixtures.lines("classifier/probe-session.jsonl")
                           + [Self.sessionLine("twin", at: "2026-11-12T17:38:00.000Z")])
        try s.writeDecisions(Self.decision("2026-11-12T17:38:10Z", input: 10, cacheRead: 0, output: 1)
                             + Self.decision("2026-11-12T17:37:05Z", input: 77, cacheRead: 0, output: 1))

        _ = try await s.collect()
        _ = try await s.collect()
        let notes = s.logLines().filter { $0.contains("possible double recording") }
        #expect(notes.filter { $0.contains("session probe-session") }.count == 1)
        #expect(notes.filter { $0.contains("a session without id") }.count == 1)
        #expect(notes.count == 2)
        #expect(!notes.contains { $0.contains(sessionFile.path) || $0.contains(sessionFile.lastPathComponent) })
    }

    @Test func refreshWithoutDecisionLogsLogsNoSummaryLine() async throws {
        let s = try ClassifierScenario("classifier-e2e-nolog")
        try s.installProbeSession()
        _ = try await s.collect()
        #expect(!s.logLines().contains { $0.contains("decision logs") })
    }

    // MARK: Hung working directories (FR-012)

    /// A directory whose check hangs is logged once until a check of it
    /// finishes, and the refresh still returns the session records.
    @Test func timedOutDirectoryIsLoggedOnce() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { for _ in 0..<4 { gate.signal() } }
        let probe = DecisionLogProbe(timeout: 0.2, check: { _, _, _, _ in
            gate.wait()
            return .absent
        })
        let s = try ClassifierScenario("classifier-e2e-hung", probe: probe)
        try s.installProbeSession()

        var records = try await s.collect()
        #expect(totalTokens(records, account: "acc-gw") == 80_168)
        records = try await s.collect()
        #expect(totalTokens(records, account: "acc-gw") == 80_168)
        let hung = s.logLines().filter { $0.contains("did not finish") }
        #expect(hung.count == 1)
        #expect(hung.first?.contains(s.work.path) == true)
        let summaries = s.logLines().filter { $0.contains("decision logs read") }
        #expect(summaries.count == 2)
        #expect(summaries.first?.contains("timed out 1, busy 0") == true)
        #expect(summaries.last?.contains("timed out 0, busy 1") == true)
    }

    /// FR-012: rows already read from a directory that later hangs keep
    /// counting and keep their account.
    @Test func rowsOfAHungDirectoryKeepCounting() async throws {
        let hang = HangSwitch()
        defer { hang.release() }
        let probe = DecisionLogProbe(timeout: 0.2, check: { directory, known, notBefore, readLimit in
            hang.waitIfOn()
            return DecisionLogProbe.inspect(directory: directory, known: known, notBefore: notBefore, readLimit: readLimit)
        })
        let s = try ClassifierScenario("classifier-e2e-hung-rows", probe: probe)
        try s.installProbeSession()
        try s.installProbeDecisions()
        #expect(totalTokens(try await s.collect(), account: "acc-gw") == 149_792)

        hang.turnOn()
        for _ in 0..<2 {
            let records = try await s.collect()
            #expect(totalTokens(records, account: "acc-gw") == 149_792)
            #expect(records.filter { $0.origin == .classifier }.allSatisfy { $0.accountId == "acc-gw" })
        }
    }

    /// FR-001: a too-large log is skipped and logged once.
    @Test func tooLargeLogIsSkippedAndLoggedOnce() async throws {
        let s = try ClassifierScenario("classifier-e2e-large")
        try s.installProbeSession()
        try s.installProbeDecisions()
        let handle = try FileHandle(forWritingTo: s.decisionLog)
        try handle.truncate(atOffset: UInt64(DecisionLogProbe.maximumSize + 1))
        try handle.close()

        for _ in 0..<2 {
            #expect(totalTokens(try await s.collect(), account: "acc-gw") == 80_168)
        }
        let skipped = s.logLines().filter { $0.contains("skipped: larger than") }
        #expect(skipped.count == 1)
        #expect(skipped.first?.contains(s.work.path) == true)
        #expect(skipped.first?.contains(DecisionLogProbe.fileName) == false)
    }

    /// FR-014: a refresh never creates, modifies or deletes a file in the
    /// session working directory or the Claude configuration directory.
    @Test func refreshWritesNothingInTheWorkingOrConfigDirectory() async throws {
        let s = try ClassifierScenario("classifier-e2e-readonly")
        try s.installProbeSession()
        try s.installProbeDecisions()
        func snapshot() throws -> [String: Date] {
            var result: [String: Date] = [:]
            for base in [s.work, s.claude] {
                result[base.path] = try base.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.contentModificationDateKey])
                while let url = walker?.nextObject() as? URL {
                    result[url.path] = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                }
            }
            return result
        }
        let before = try snapshot()
        _ = try await s.collect()
        _ = try await s.collect()
        #expect(try snapshot() == before)
    }
}


/// Makes a probe check hang while on; `release` lets every waiting check go.
final class HangSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    private let gate = DispatchSemaphore(value: 0)
    private var waiting = 0

    func turnOn() { lock.lock(); on = true; lock.unlock() }

    func waitIfOn() {
        lock.lock()
        let hang = on
        if hang { waiting += 1 }
        lock.unlock()
        if hang { gate.wait() }
    }

    func release() {
        lock.lock()
        on = false
        let count = waiting
        waiting = 0
        lock.unlock()
        for _ in 0..<count { gate.signal() }
    }
}

/// End-to-end and summary-line tests for the review findings of
/// 2026-11-13 (spec 045 FR-001, FR-005, FR-013).
@Suite struct ClassifierReviewFindingTests {
    /// FR-013: unreadable logs show in the summary line only when there
    /// were any, so the usual line is unchanged.
    @Test func unreadableLogsAreAppendedOnlyWhenPresent() throws {
        var stats = ClassifierIndexStats()
        stats.logsFound = 1
        let plain = try #require(SessionLogSource.classifierSummaryLine(stats, ClassifierAttributionResult()))
        #expect(!plain.contains("unreadable"))
        stats.logsFound = 0
        stats.unreadable = 2
        let line = try #require(SessionLogSource.classifierSummaryLine(stats, ClassifierAttributionResult()))
        #expect(line.hasSuffix(", unreadable 2"))
    }

    /// FR-005: a row dated after the refresh does not count until a refresh
    /// at or after its time.
    @Test func rowAfterTheRefreshCountsOnlyOnceItsTimeHasCome() async throws {
        let s = try ClassifierScenario("classifier-e2e-future")
        try s.installProbeSession()
        try s.writeDecisions(SessionLogSourceClassifierTests.decision("2026-11-12T17:38:00Z") + SessionLogSourceClassifierTests.decision("2026-11-14T10:00:00Z", input: 999))
        let early = try await s.collect().filter { $0.origin == .classifier }
        #expect(early.map(\.inputTokens) == [10])
        let later = try await s.collect(now: isoDate("2026-11-14T10:00:00Z")).filter { $0.origin == .classifier }
        #expect(later.map(\.inputTokens).sorted() == [10, 999])
    }

    /// FR-001: a skip is logged once while its directory is checked, also
    /// across a refresh in which the check timed out; once the directory
    /// is no longer checked it is forgotten, and logged again when it
    /// comes back.
    @Test func skipIsLoggedOnceWhileItsDirectoryIsChecked() async throws {
        let hang = HangSwitch()
        defer { hang.release() }
        let probe = DecisionLogProbe(timeout: 0.2, check: { directory, known, notBefore, readLimit in
            hang.waitIfOn()
            return DecisionLogProbe.inspect(directory: directory, known: known, notBefore: notBefore, readLimit: readLimit)
        })
        let s = try ClassifierScenario("classifier-e2e-skip-once", probe: probe)
        let session = try s.writeSession(try Fixtures.lines("classifier/probe-session.jsonl"))
        try s.installProbeDecisions()
        let handle = try FileHandle(forWritingTo: s.decisionLog)
        try handle.truncate(atOffset: UInt64(DecisionLogProbe.maximumSize + 1))
        try handle.close()
        func skips() -> Int { s.logLines().filter { $0.contains("skipped: larger than") }.count }

        _ = try await s.collect()
        #expect(skips() == 1)
        hang.turnOn()
        _ = try await s.collect()
        hang.release()
        for _ in 0..<200 where probe.isInFlight(s.work.path) { Thread.sleep(forTimeInterval: 0.01) }
        _ = try await s.collect()
        #expect(skips() == 1)

        let lines = try Fixtures.lines("classifier/probe-session.jsonl")
        try FileManager.default.removeItem(at: session)
        _ = try await s.collect()
        try s.writeSession(lines)
        _ = try await s.collect()
        #expect(skips() == 2)
    }

    /// FR-001: a log naming more models than the limit is skipped, logged
    /// once.
    @Test func logOverTheModelLimitIsLoggedOnce() async throws {
        let s = try ClassifierScenario("classifier-e2e-models", classifierIndex: ClassifierLogIndex(maximumModelsPerLog: 1))
        try s.installProbeSession()
        try s.writeDecisions(SessionLogSourceClassifierTests.decision("2026-11-12T17:37:00Z", model: "a")
                             + SessionLogSourceClassifierTests.decision("2026-11-12T17:37:30Z", model: "b"))
        let records = try await s.collect()
        #expect(!records.contains { $0.origin == .classifier })
        _ = try await s.collect()
        #expect(s.logLines().filter { $0.contains("skipped: more than 1 models") }.count == 1)
    }

    /// FR-001: a log over the row limit is skipped and the skip is logged
    /// once, naming only its directory.
    @Test func logOverTheRowLimitIsLoggedOnce() async throws {
        let s = try ClassifierScenario("classifier-e2e-rows", classifierIndex: ClassifierLogIndex(maximumRowsPerLog: 2))
        try s.installProbeSession()
        try s.writeDecisions(SessionLogSourceClassifierTests.decision("2026-11-12T17:37:00Z") + SessionLogSourceClassifierTests.decision("2026-11-12T17:37:30Z")
                             + SessionLogSourceClassifierTests.decision("2026-11-12T17:38:00Z"))
        let records = try await s.collect()
        #expect(!records.contains { $0.origin == .classifier })
        _ = try await s.collect()
        let skips = s.logLines().filter { $0.contains("skipped: more than 2 rows") }
        #expect(skips.count == 1)
        #expect(skips.first?.contains(Attributor.canonical(s.work.path)) == true)
        #expect(skips.first?.contains(DecisionLogProbe.fileName) == false)
    }
}
