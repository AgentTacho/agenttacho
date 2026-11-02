import Foundation
import Testing
@testable import UsageCore

/// Holds a scan's workers: each job counts itself as started, then waits
/// until the test releases them (or 10 s pass, so a failing test never
/// hangs the suite).
final class WorkerGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private var started = 0

    var hook: @Sendable (Int) -> Void {
        { [self] _ in self.enter() }
    }

    private func enter() {
        condition.lock()
        started += 1
        condition.broadcast()
        let deadline = Date().addingTimeInterval(10)
        while !released, condition.wait(until: deadline) {}
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    var startedCount: Int {
        condition.lock(); defer { condition.unlock() }
        return started
    }

    /// Waits without blocking the cooperative pool until `count` jobs
    /// started; false after `timeout`.
    func waitForStart(_ count: Int = 1, timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if startedCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

/// Polls `condition` without blocking the cooperative pool; false after
/// `timeout`.
private func pollUntil(timeout: TimeInterval = 10, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

/// The sources do not block their actor or the cooperative pool while the
/// workers parse, and a scan has the source to itself (spec 039 FR-017,
/// FR-018, research R7).
@Suite(.serialized) struct ScanConcurrencyTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")

    // MARK: Claude Code source

    static let claudeConfig = Configuration(accounts: [
        Account(id: "acc-max", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: ""))),
    ])

    static let claudeFiles = ["vertex-session.jsonl", "gateway-session.jsonl", "custom-marker.jsonl", "unknown-model.jsonl",
                              "malformed-fields.jsonl"]

    /// A Claude Code tree under `home/.claude` with one fixture per project.
    func makeClaudeHome(_ name: String) throws -> URL {
        let home = try makeTempDirectory("scan-concurrency-\(name)")
        for (index, fixture) in Self.claudeFiles.enumerated() {
            try Fixtures.install(fixture, into: home.appendingPathComponent(".claude"), as: "proj-\(index)/\(fixture)")
        }
        return home
    }

    func claudeSource(_ home: URL, workers: ScanWorkers = .default) throws -> SessionLogSource {
        try SessionLogSource(paths: Paths(home: home), log: DiagnosticLog(fileURL: home.appendingPathComponent("usage.log")),
                             builtInPrices: try PriceTable.builtIn(), index: LogIndex(workers: workers), workers: workers)
    }

    func records(_ source: SessionLogSource) async throws -> [UsageRecord] {
        let output = try await source.collect(context: RefreshContext(configuration: Self.claudeConfig, window: window, now: now))
        guard case .records(let records) = output else { return [] }
        return records
    }

    /// A new session file with one record.
    func addClaudeFile(to home: URL) throws -> String {
        let url = home.appendingPathComponent(".claude/projects/proj-new/new.jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((#"{"type":"assistant","timestamp":"2026-10-13T08:00:00.000Z","requestId":"req_vrtx_NEW","sessionId":"s-new","message":{"id":"msg_new_1","model":"claude-opus-4-6","role":"assistant","content":[],"usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":4}}}"#
            + "\n").utf8).write(to: url)
        return "msg_new_1"
    }

    /// While the workers are held, the source answers and another source
    /// refreshes; after the release, the records equal an unheld run's.
    @Test func claudeSourceAnswersWhileItsWorkersAreHeld() async throws {
        let home = try makeClaudeHome("claude-held")
        defer { try? FileManager.default.removeItem(at: home) }
        let reference = try await records(try claudeSource(home))
        #expect(!reference.isEmpty)

        let gate = WorkerGate()
        defer { gate.release() }
        let source = try claudeSource(home, workers: ScanWorkers(count: 2, beforeJob: gate.hook))
        let scan = Task { try await records(source) }
        #expect(await gate.waitForStart())
        #expect(await source.isScanning())

        // FR-018: a second refresh completes while the first scan's workers
        // are busy.
        let codexHome = try makeCodexHome("claude-held-other")
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let other = try await codexRecords(try codexSource(codexHome))
        #expect(!other.isEmpty)
        #expect(await source.isScanning())

        gate.release()
        #expect(try await scan.value == reference)
        #expect(await !source.isScanning())
    }

    /// The merge, where attribution and its 50 ms condition limit run (spec
    /// 038 FR-007), runs at the refresh's own priority; only the parse jobs
    /// run at utility (FR-017).
    @Test func claudeAttributionRunsAtTheRefreshPriority() async throws {
        let home = try makeClaudeHome("claude-merge-priority")
        defer { try? FileManager.default.removeItem(at: home) }
        let merges = LockedLog<UInt32>()
        let jobs = LockedLog<UInt32>()
        let workers = ScanWorkers(count: 2, beforeJob: { _ in jobs.append(qos_class_self().rawValue) })
        let index = LogIndex(workers: workers)
        index.beforeMerge = { merges.append(qos_class_self().rawValue) }
        let source = try SessionLogSource(paths: Paths(home: home), log: DiagnosticLog(fileURL: home.appendingPathComponent("usage.log")),
                                          builtInPrices: try PriceTable.builtIn(), index: index, workers: workers)
        let found = try await Task(priority: .userInitiated) { try await records(source) }.value
        #expect(!found.isEmpty)
        #expect(!merges.values.isEmpty)
        #expect(merges.values.allSatisfy { $0 == QOS_CLASS_USER_INITIATED.rawValue }, "\(merges.values)")
        #expect(jobs.values.count == Self.claudeFiles.count)
        #expect(jobs.values.allSatisfy { $0 == QOS_CLASS_UTILITY.rawValue }, "\(jobs.values)")
    }

    /// A reset during the scan is applied after it: the scan returns its
    /// records, and the next refresh reads every file again.
    @Test func claudeResetDuringTheScanIsAppliedAfterIt() async throws {
        let home = try makeClaudeHome("claude-reset")
        defer { try? FileManager.default.removeItem(at: home) }
        let reference = try await records(try claudeSource(home))
        let gate = WorkerGate()
        defer { gate.release() }
        let source = try claudeSource(home, workers: ScanWorkers(count: 2, beforeJob: gate.hook))
        let scan = Task { try await records(source) }
        #expect(await gate.waitForStart())
        await source.resetForEarlierWindow()
        #expect(await source.isScanning())
        gate.release()
        #expect(try await scan.value == reference)
        #expect(try await records(source) == reference)
        #expect(await source.lastScanFigures.filesRead == Self.claudeFiles.count)
    }

    /// A refresh that starts during a scan waits for it, then runs.
    @Test func claudeSecondCollectWaitsForTheScan() async throws {
        let home = try makeClaudeHome("claude-wait")
        defer { try? FileManager.default.removeItem(at: home) }
        let reference = try await records(try claudeSource(home))
        let gate = WorkerGate()
        defer { gate.release() }
        let workers = ScanWorkers(count: 2, beforeJob: gate.hook)
        let source = try claudeSource(home, workers: workers)
        let first = Task { try await records(source) }
        #expect(await gate.waitForStart(workers.count))
        let started = gate.startedCount
        let second = Task { try await records(source) }
        // The second collect waits for the scan and starts no scan of its
        // own meanwhile.
        #expect(await pollUntil { await source.waitingCollects() == 1 })
        #expect(gate.startedCount == started)
        gate.release()
        #expect(try await first.value == reference)
        #expect(try await second.value == reference)
    }

    /// Two refreshes waiting for the same scan never scan at once: a file
    /// added meanwhile is read by one of them only.
    @Test func claudeWaitingCollectsScanOneAtATime() async throws {
        let home = try makeClaudeHome("claude-two-waiting")
        defer { try? FileManager.default.removeItem(at: home) }
        let gate = WorkerGate()
        defer { gate.release() }
        let source = try claudeSource(home, workers: ScanWorkers(count: 2, beforeJob: gate.hook))
        let first = Task { try await records(source) }
        #expect(await gate.waitForStart())
        let newId = try addClaudeFile(to: home)
        let second = Task { try await records(source) }
        let third = Task { try await records(source) }
        #expect(await pollUntil { await source.waitingCollects() == 2 })
        gate.release()
        let firstRecords = try await first.value
        let secondRecords = try await second.value
        let thirdRecords = try await third.value
        #expect(gate.startedCount == Self.claudeFiles.count + 1)
        #expect(firstRecords.filter { $0.messageId == newId }.count <= 1)
        #expect(secondRecords.filter { $0.messageId == newId }.count == 1)
        #expect(thirdRecords.filter { $0.messageId == newId }.count == 1)
    }

    // MARK: Codex source

    static let codexConfig = Configuration(accounts: [
        Account(id: "acc-plus", displayName: "Plus", kind: .codexSubscription(CodexSubscriptionSettings(codexHome: ""))),
        CodexSessionSourceTests.openAIAccount(),
    ])

    static let codexFiles = ["apikey-session.jsonl", "plan-session.jsonl", "subagent-session.jsonl", "review-subagent.jsonl"]

    func makeCodexHome(_ name: String) throws -> URL {
        let home = try makeTempDirectory("scan-concurrency-\(name)")
        for fixture in Self.codexFiles {
            try CodexFixtures.install(fixture, home: home.appendingPathComponent(".codex"))
        }
        return home
    }

    func codexSource(_ home: URL, workers: ScanWorkers = .default) throws -> CodexSessionSource {
        try CodexSessionSource(paths: Paths(home: home), log: DiagnosticLog(fileURL: home.appendingPathComponent("usage.log")),
                               builtInPrices: CodexSessionSourceTests.prices, workers: workers)
    }

    func codexRecords(_ source: CodexSessionSource) async throws -> [UsageRecord] {
        let output = try await source.collect(context: RefreshContext(configuration: Self.codexConfig, window: window, now: now))
        guard case .recordBatch(let batch) = output else { return [] }
        return batch.records
    }

    /// The Codex records in a stable order: the source returns them in
    /// file order, which a new file can shift.
    static func sorted(_ records: [UsageRecord]) -> [UsageRecord] {
        records.sorted { ($0.messageId, $0.timestamp) < ($1.messageId, $1.timestamp) }
    }

    @Test func codexSourceAnswersWhileItsWorkersAreHeld() async throws {
        let home = try makeCodexHome("codex-held")
        defer { try? FileManager.default.removeItem(at: home) }
        let reference = try await codexRecords(try codexSource(home))
        #expect(!reference.isEmpty)

        let gate = WorkerGate()
        defer { gate.release() }
        let source = try codexSource(home, workers: ScanWorkers(count: 2, beforeJob: gate.hook))
        let scan = Task { try await codexRecords(source) }
        #expect(await gate.waitForStart())
        #expect(await source.isScanning())

        let claudeHome = try makeClaudeHome("codex-held-other")
        defer { try? FileManager.default.removeItem(at: claudeHome) }
        #expect(!(try await records(try claudeSource(claudeHome))).isEmpty)
        #expect(await source.isScanning())

        gate.release()
        #expect(Self.sorted(try await scan.value) == Self.sorted(reference))
        #expect(await !source.isScanning())
    }

    @Test func codexResetDuringTheScanIsAppliedAfterIt() async throws {
        let home = try makeCodexHome("codex-reset")
        defer { try? FileManager.default.removeItem(at: home) }
        let reference = try await codexRecords(try codexSource(home))
        let gate = WorkerGate()
        defer { gate.release() }
        let source = try codexSource(home, workers: ScanWorkers(count: 2, beforeJob: gate.hook))
        let scan = Task { try await codexRecords(source) }
        #expect(await gate.waitForStart())
        await source.resetForEarlierWindow()
        #expect(await source.isScanning())
        gate.release()
        #expect(Self.sorted(try await scan.value) == Self.sorted(reference))
        #expect(Self.sorted(try await codexRecords(source)) == Self.sorted(reference))
        #expect(await source.lastFilesParsed == Self.codexFiles.count)
    }

    @Test func codexSecondCollectWaitsForTheScan() async throws {
        let home = try makeCodexHome("codex-wait")
        defer { try? FileManager.default.removeItem(at: home) }
        let reference = Self.sorted(try await codexRecords(try codexSource(home)))
        let gate = WorkerGate()
        defer { gate.release() }
        let workers = ScanWorkers(count: 2, beforeJob: gate.hook)
        let source = try codexSource(home, workers: workers)
        let first = Task { try await codexRecords(source) }
        #expect(await gate.waitForStart(workers.count))
        let started = gate.startedCount
        let second = Task { try await codexRecords(source) }
        // The second collect waits for the scan and starts no scan of its
        // own meanwhile.
        #expect(await pollUntil { await source.waitingCollects() == 1 })
        #expect(gate.startedCount == started)
        gate.release()
        #expect(Self.sorted(try await first.value) == reference)
        #expect(Self.sorted(try await second.value) == reference)
    }

    @Test func codexWaitingCollectsScanOneAtATime() async throws {
        let home = try makeCodexHome("codex-two-waiting")
        defer { try? FileManager.default.removeItem(at: home) }
        let gate = WorkerGate()
        defer { gate.release() }
        let source = try codexSource(home, workers: ScanWorkers(count: 2, beforeJob: gate.hook))
        let first = Task { try await codexRecords(source) }
        #expect(await gate.waitForStart())
        try CodexFixtures.install("truncated.jsonl", home: home.appendingPathComponent(".codex"))
        let second = Task { try await codexRecords(source) }
        let third = Task { try await codexRecords(source) }
        #expect(await pollUntil { await source.waitingCollects() == 2 })
        gate.release()
        _ = try await first.value
        let secondRecords = try await second.value
        let thirdRecords = try await third.value
        let newId = "codex:019a0000-0000-7000-8000-0000000000e1:440"
        #expect(gate.startedCount == Self.codexFiles.count + 1)
        #expect(secondRecords.filter { $0.messageId == newId }.count == 1)
        #expect(thirdRecords.filter { $0.messageId == newId }.count == 1)
    }

    /// A rollout file with a session meta line, a turn context and one
    /// token event; `parent` makes it a subagent, `plan` gives it a plan
    /// marker.
    static func rollout(id: String, day: String, parent: String?, plan: Bool) -> String {
        let source = parent.map { #"{"subagent":{"thread_spawn":{"parent_thread_id":"\#($0)","depth":1}}}"# } ?? #""cli""#
        let limits = plan ? #"{"limit_id":"codex","plan_type":"plus"}"# : "null"
        return [
            #"{"timestamp":"\#(day)T10:00:00.000Z","type":"session_meta","payload":{"id":"\#(id)","timestamp":"\#(day)T10:00:00.000Z","cwd":"/fixture/codex-rounds","originator":"codex_cli_rs","cli_version":"0.161.0","model_provider":"openai","source":\#(source),"forked_from_id":null,"parent_thread_id":null}}"#,
            #"{"timestamp":"\#(day)T10:00:00.100Z","type":"turn_context","payload":{"turn_id":"t","cwd":"/fixture/codex-rounds","model":"gpt-5.5"}}"#,
            #"{"timestamp":"\#(day)T10:00:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":0,"total_tokens":550}},"rate_limits":\#(limits)}}"#,
        ].joined(separator: "\n") + "\n"
    }

    /// A subagent in the window without a plan marker, its parent in an
    /// older file without one, the grandparent in an older file with one:
    /// the subagent takes the plan hint, as the recursion gave it before,
    /// and both older files are parsed on the workers, one round each, never
    /// on the actor (spec 039 research R6, FR-017).
    @Test func codexParentsInOlderFilesAreReadOnTheWorkersInRounds() async throws {
        let home = try makeTempDirectory("scan-concurrency-codex-rounds")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent(".codex/sessions/2026/10")
        let child = "019a0000-0000-7000-8000-00000000f003"
        let parent = "019a0000-0000-7000-8000-00000000f002"
        let grandparent = "019a0000-0000-7000-8000-00000000f001"
        func write(_ id: String, day: String, parent: String?, plan: Bool, modified: Date?) throws {
            let dir = sessions.appendingPathComponent(String(day.suffix(2)))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("rollout-\(day)T10-00-00-\(id).jsonl")
            try Data(Self.rollout(id: id, day: day, parent: parent, plan: plan).utf8).write(to: url)
            if let modified { try CodexFixtures.setModificationDate(modified, of: url) }
        }
        try write(grandparent, day: "2026-10-01", parent: nil, plan: true, modified: isoDate("2026-10-01T12:00:00Z"))
        try write(parent, day: "2026-10-02", parent: grandparent, plan: false, modified: isoDate("2026-10-02T12:00:00Z"))
        try write(child, day: "2026-10-13", parent: parent, plan: false, modified: nil)

        let jobs = LockedLog<Int>()
        let source = try codexSource(home, workers: ScanWorkers(count: 2, beforeJob: { jobs.append($0) }))
        let records = try await codexRecords(source)
        #expect(records.count == 1)
        #expect(records.first?.accountId == "acc-plus")
        #expect(await source.lastHints[child] == Attributor.codexPlanHint)
        // One window file, then one round for the parent and one for the
        // grandparent; the older files count as neither parsed nor read.
        #expect(jobs.values.count == 1 + 2)
        #expect(await source.lastFilesParsed == 1)
        #expect(await source.lastScanFigures.filesRead == 1)

        // The next refresh reads nothing: the parents are kept.
        _ = try await codexRecords(source)
        #expect(jobs.values.count == 3)
        #expect(await source.lastHints[child] == Attributor.codexPlanHint)
    }

    /// Parents in older files that name each other, a session that names
    /// itself, and an older parent file that cannot be read: the rounds
    /// end, each older file is read once, and the sessions take the API
    /// key hint, as the recursion gave it before (spec 039 research R6).
    @Test(.timeLimit(.minutes(1))) func codexParentRoundsEndOnCyclesAndUnreadableFiles() async throws {
        let home = try makeTempDirectory("scan-concurrency-codex-cycle")
        let sessions = home.appendingPathComponent(".codex/sessions/2026/10")
        var locked: URL?
        defer {
            if let locked { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
            try? FileManager.default.removeItem(at: home)
        }
        @discardableResult
        func write(_ id: String, day: String, parent: String?, modified: Date?) throws -> URL {
            let dir = sessions.appendingPathComponent(String(day.suffix(2)))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("rollout-\(day)T10-00-00-\(id).jsonl")
            try Data(Self.rollout(id: id, day: day, parent: parent, plan: false).utf8).write(to: url)
            if let modified { try CodexFixtures.setModificationDate(modified, of: url) }
            return url
        }
        let first = "019a0000-0000-7000-8000-00000000f101"
        let second = "019a0000-0000-7000-8000-00000000f102"
        let unreadable = "019a0000-0000-7000-8000-00000000f103"
        let child = "019a0000-0000-7000-8000-00000000f111"
        let selfParent = "019a0000-0000-7000-8000-00000000f112"
        let orphan = "019a0000-0000-7000-8000-00000000f113"
        try write(first, day: "2026-10-01", parent: second, modified: isoDate("2026-10-01T12:00:00Z"))
        try write(second, day: "2026-10-02", parent: first, modified: isoDate("2026-10-02T12:00:00Z"))
        locked = try write(unreadable, day: "2026-10-03", parent: nil, modified: isoDate("2026-10-03T12:00:00Z"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: try #require(locked).path)
        try write(child, day: "2026-10-13", parent: first, modified: nil)
        try write(selfParent, day: "2026-10-13", parent: selfParent, modified: nil)
        try write(orphan, day: "2026-10-13", parent: unreadable, modified: nil)

        let jobs = LockedLog<Int>()
        let source = try codexSource(home, workers: ScanWorkers(count: 2, beforeJob: { jobs.append($0) }))
        let records = try await codexRecords(source)
        #expect(records.count == 3)
        let hints = await source.lastHints
        for id in [child, selfParent, orphan] {
            #expect(hints[id] == Attributor.codexAPIKeyHint, "\(id)")
        }
        // Three window files, then one round for `first` and the unreadable
        // file, one for `second`; the cycle back to `first` reads nothing.
        #expect(jobs.values.count == 3 + 2 + 1)
    }
}
