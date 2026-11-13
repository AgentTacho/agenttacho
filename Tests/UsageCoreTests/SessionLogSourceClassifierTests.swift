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

    init(_ name: String, probe: DecisionLogProbe = DecisionLogProbe(), accounts: [Account]? = nil) throws {
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
        source = try SessionLogSource(paths: Paths(home: root), log: log, builtInPrices: PriceTable.builtIn(), probe: probe)
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

    func collect() async throws -> [UsageRecord] {
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window,
                                                                      now: isoDate("2026-11-13T09:00:00Z")))
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
        let probe = DecisionLogProbe(check: { directory, known, notBefore in
            seen.append(directory)
            return DecisionLogProbe.inspect(directory: directory, known: known, notBefore: notBefore)
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
        DecisionLogProbe(check: { directory, known, notBefore in
            let result = DecisionLogProbe.inspect(directory: directory, known: known, notBefore: notBefore)
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
}
