import Foundation
import Testing
@testable import UsageCore

/// A credential reader with a fixed answer per Codex home that counts its
/// reads (spec 007 FR-019: live limits off never reads the sign-in).
final class FakeCodexCredentialReader: CodexCredentialReader, @unchecked Sendable {
    struct Failure: Error, CustomStringConvertible { let description = "Codex sign-in file could not be read" }

    private let lock = NSLock()
    private var answers: [String: Result<CodexCredentialLookup, Error>]
    private var readHomes: [String] = []

    init(_ answers: [String: Result<CodexCredentialLookup, Error>] = [:]) {
        self.answers = answers
    }

    func set(_ home: String, _ answer: Result<CodexCredentialLookup, Error>) {
        lock.lock(); defer { lock.unlock() }
        answers[home] = answer
    }

    var reads: [String] {
        lock.lock(); defer { lock.unlock() }
        return readHomes
    }

    func read(codexHome: String) throws -> CodexCredentialLookup {
        lock.lock()
        readHomes.append(codexHome)
        let answer = answers[codexHome] ?? .success(.missing(reason: CodexCredentialLookup.noPlanSignIn))
        lock.unlock()
        return try answer.get()
    }
}

/// Shared setup for the Codex limits source tests: a temp directory with
/// Codex homes, stubbed usage service answers keyed by token, and contexts
/// at chosen times.
struct CodexLimitsHarness {
    static let start = isoDate("2026-10-14T15:00:00Z")
    static let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))

    let root: URL
    let reader = FakeCodexCredentialReader()
    let log: DiagnosticLog
    let source: CodexLimitsSource
    /// The source's clock; each `collect` moves it to the context's time,
    /// and a stub may advance it while a request runs.
    let clock = MutableClock(CodexLimitsHarness.start)

    /// With `clockedClient` the client reads the harness clock too, so the
    /// usable rule of reset credits (spec 033 FR-002) follows it.
    init(_ name: String, clockedClient: Bool = false, store: LastGoodStore? = nil) throws {
        root = try makeTempDirectory(name)
        log = DiagnosticLog(fileURL: root.appendingPathComponent("usage.log"))
        let clock = self.clock
        let client = clockedClient
            ? CodexUsageClient(session: StubURLProtocol.makeSession(), clock: { clock.now() }, userAgent: "AgentTacho/test")
            : CodexUsageClient(session: StubURLProtocol.makeSession(), userAgent: "AgentTacho/test")
        source = CodexLimitsSource(credentialReader: reader, client: client,
                                   log: log, paths: Paths(home: root), clock: { clock.now() }, store: store)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    /// An absolute Codex home path under the temp directory.
    func home(_ name: String = ".codex") -> String {
        root.appendingPathComponent(name).path
    }

    static func account(_ id: String = "acc-codex", home: String, liveLimits: Bool = true) -> Account {
        Account(id: id, displayName: "ChatGPT \(id)", harness: .codex,
                kind: .codexSubscription(CodexSubscriptionSettings(codexHome: home, liveLimits: liveLimits)))
    }

    /// A unique token whose requests the stub answers with `status` and `body`.
    static func stub(status: Int = 200, body: String = codexUsageSampleJSON, headers: [String: String] = [:]) -> String {
        let token = "codex-src-\(UUID().uuidString)"
        StubURLProtocol.register(key: "Bearer \(token)", headers: headers) { _ in (status, Data(body.utf8)) }
        return token
    }

    static func offlineStub() -> String {
        let token = "codex-src-offline-\(UUID().uuidString)"
        StubURLProtocol.register(key: "Bearer \(token)") { _ in throw URLError(.notConnectedToInternet) }
        return token
    }

    static func requests(_ token: String) -> Int {
        StubURLProtocol.usageRequests(key: "Bearer \(token)").count
    }

    func signIn(_ home: String, token: String, accountId: String? = "acct", expiresAt: Date? = nil) {
        reader.set(home, .success(.found(CodexCredential(accessToken: token, accountId: accountId, expiresAt: expiresAt))))
    }

    /// `manualRequested` defaults to true for a `.manual` trigger, as the
    /// coordinator sets it (spec 021 FR-003a).
    func collect(_ configuration: Configuration, at offset: TimeInterval = 0, trigger: RefreshTrigger = .scheduled,
                 codexPaceDue: Bool = true, manualRequested: Bool? = nil) async throws -> [String: CodexLimitsEntry] {
        let now = Self.start.addingTimeInterval(offset)
        clock.advance(now.timeIntervalSince(clock.now()))
        var context = RefreshContext(configuration: configuration, window: Self.window, now: now, trigger: trigger,
                                     codexPaceDue: codexPaceDue)
        context.manualRequested = manualRequested ?? (trigger == .manual)
        guard case .codexLimits(let entries) = try await source.collect(context: context) else {
            Issue.record("expected codex limits")
            return [:]
        }
        return entries
    }

    func logText() -> String {
        (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
    }
}

/// spec 007 FR-001, FR-002, FR-003, FR-005, FR-021 (live path).
@Suite struct CodexLimitsSourceLiveTests {
    @Test func liveFetchGivesALiveEntry() async throws {
        let h = try CodexLimitsHarness("codex-src-live")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let entries = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
        let entry = try #require(entries["acc-codex"])
        #expect(entry.state == .live)
        #expect(entry.sourceError == nil)
        #expect(entry.observation?.origin == .live)
        #expect(entry.observation?.observedAt == CodexLimitsHarness.start)
        #expect(entry.observation?.planType == "plus")
        #expect(entry.observation?.windows.map(\.name) == ["5-hour", "weekly"])
        #expect(CodexLimitsHarness.requests(token) == 1)
    }

    @Test func accountsUseTheirOwnSignIn() async throws {
        let h = try CodexLimitsHarness("codex-src-two")
        defer { h.cleanUp() }
        let free = """
        { "plan_type": "free", "rate_limit": { "primary_window": { "used_percent": 7, "limit_window_seconds": 2592000, "reset_at": 1794000000 } } }
        """
        let plusToken = CodexLimitsHarness.stub()
        let freeToken = CodexLimitsHarness.stub(body: free)
        h.signIn(h.home(".codex"), token: plusToken)
        h.signIn(h.home(".codex-free"), token: freeToken)
        let configuration = Configuration(accounts: [CodexLimitsHarness.account("acc-plus", home: h.home(".codex")),
                                                     CodexLimitsHarness.account("acc-free", home: h.home(".codex-free"))])
        let entries = try await h.collect(configuration)
        #expect(entries["acc-plus"]?.observation?.planType == "plus")
        #expect(entries["acc-free"]?.observation?.planType == "free")
        #expect(entries["acc-free"]?.observation?.windows.map(\.name) == ["30-day"])
        #expect(CodexLimitsHarness.requests(plusToken) == 1)
        #expect(CodexLimitsHarness.requests(freeToken) == 1)
    }

    /// FR-003: an expired sign-in makes no request.
    @Test func expiredSignInMakesNoRequest() async throws {
        let h = try CodexLimitsHarness("codex-src-expired")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token, expiresAt: CodexLimitsHarness.start)
        let entries = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
        #expect(entries["acc-codex"] == CodexLimitsEntry(observation: nil, state: .unavailable(reason: "Codex sign-in expired, run Codex to renew it"),
                                                         credentialProblem: .expired(at: CodexLimitsHarness.start)))
        #expect(CodexLimitsHarness.requests(token) == 0)
    }

    /// FR-021: one account's unreadable sign-in does not affect another.
    @Test func unreadableSignInStaysWithItsAccount() async throws {
        let h = try CodexLimitsHarness("codex-src-unreadable")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(".codex"), token: token)
        h.reader.set(h.home(".codex-broken"), .failure(CodexCredentialError("Codex sign-in file is not in the expected format")))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account("acc-ok", home: h.home(".codex")),
                                                     CodexLimitsHarness.account("acc-broken", home: h.home(".codex-broken"))])
        let entries = try await h.collect(configuration)
        #expect(entries["acc-ok"]?.state == .live)
        #expect(entries["acc-broken"]?.state == .unavailable(reason: "Codex sign-in file is not in the expected format"))
        #expect(entries["acc-broken"]?.sourceError == nil)
    }

    @Test func missingSignInMakesNoRequestAndShowsTheReason() async throws {
        let h = try CodexLimitsHarness("codex-src-missing")
        defer { h.cleanUp() }
        h.reader.set(h.home(), .success(.missing(reason: CodexCredentialLookup.keychain)))
        let entries = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
        #expect(entries["acc-codex"]?.state == .unavailable(reason: CodexCredentialLookup.keychain))
        #expect(h.reader.reads == [h.home()])
    }
}

/// spec 007 FR-004, FR-005, FR-006, FR-010, FR-020, research R4, R6
/// (snapshots and the shown observation).
@Suite struct CodexLimitsSourceFallbackTests {
    static let start = CodexLimitsHarness.start

    /// Installs a rollout fixture into the Codex home with a modification
    /// date just after its last event, as Codex would leave it.
    @discardableResult
    static func install(_ fixture: String, into home: String, modified: Date) throws -> URL {
        let url = try CodexFixtures.install(fixture, home: URL(fileURLWithPath: home), day: "2026/10/14",
                                            as: "rollout-2026-10-14T00-00-00-\((fixture as NSString).deletingPathExtension).jsonl")
        try CodexFixtures.setModificationDate(modified, of: url)
        return url
    }

    static let plusObserved = isoDate("2026-10-14T14:20:01.123Z")

    /// FR-004: the newest snapshot counts whatever its file's age.
    @Test func snapshotOlderThanTheTokenWindowCounts() async throws {
        let h = try CodexLimitsHarness("codex-src-old")
        defer { h.cleanUp() }
        try Self.install("limits-plus.jsonl", into: h.home(), modified: Self.start.addingTimeInterval(-20 * 86400))
        let entries = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
        let entry = try #require(entries["acc-codex"])
        #expect(entry.observation?.origin == .snapshot)
        #expect(entry.observation?.observedAt == Self.plusObserved)
        #expect(entry.state == .stale(reason: CodexCredentialLookup.noPlanSignIn))
    }

    /// research R4: newest first, stop early, and no parsing of unchanged files.
    @Test func newestFirstScanWithCache() async throws {
        let h = try CodexLimitsHarness("codex-src-scan")
        defer { h.cleanUp() }
        try Self.install("limits-free.jsonl", into: h.home(), modified: isoDate("2026-10-14T09:00:06Z"))
        try Self.install("limits-noise.jsonl", into: h.home(), modified: isoDate("2026-10-14T13:00:09Z"))
        try Self.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        let first = try await h.collect(configuration)
        #expect(first["acc-codex"]?.observation?.observedAt == Self.plusObserved)
        // The newest file holds a snapshot newer than the next file: one parse.
        #expect(await h.source.lastFilesParsed == 1)
        _ = try await h.collect(configuration, at: 60)
        #expect(await h.source.lastFilesParsed == 0)
        // A newer file with a snapshot replaces the result.
        try Self.install("limits-reached.jsonl", into: h.home(), modified: isoDate("2026-10-14T15:00:06Z"))
        let third = try await h.collect(configuration, at: 120)
        #expect(third["acc-codex"]?.observation?.observedAt == isoDate("2026-10-14T15:00:05Z"))
        #expect(await h.source.lastFilesParsed == 1)
    }

    /// A running Codex session appends to its rollout file: a cached file
    /// whose size and modification date changed is parsed again (FR-004,
    /// FR-005).
    @Test func appendedSnapshotInACachedFileIsRead() async throws {
        let h = try CodexLimitsHarness("codex-src-append")
        defer { h.cleanUp() }
        let url = try Self.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        let first = try await h.collect(configuration)
        #expect(first["acc-codex"]?.observation?.observedAt == Self.plusObserved)
        // Codex records a newer snapshot in the same file.
        let text = try String(contentsOf: url, encoding: .utf8)
        let last = try #require(text.split(separator: "\n").last { $0.contains("\"rate_limits\":{") })
        let appended = String(last)
            .replacingOccurrences(of: "2026-10-14T14:20:01.123Z", with: "2026-10-14T14:40:00.000Z")
            .replacingOccurrences(of: "\"used_percent\":20.0", with: "\"used_percent\":55.0")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + appended + "\n").utf8))
        try handle.close()
        try CodexFixtures.setModificationDate(isoDate("2026-10-14T14:40:01Z"), of: url)
        let second = try await h.collect(configuration, at: 60)
        #expect(second["acc-codex"]?.observation?.observedAt == isoDate("2026-10-14T14:40:00Z"))
        #expect(second["acc-codex"]?.observation?.windows.first?.usedPercent == 55)
        #expect(await h.source.lastFilesParsed == 1)
    }

    /// A successful fetch is shown as is, so no session log is read for it;
    /// after a failure only files newer than the kept live result are read
    /// (FR-004, FR-005).
    @Test func liveResultBoundsTheSnapshotScan() async throws {
        let h = try CodexLimitsHarness("codex-src-bound")
        defer { h.cleanUp() }
        try Self.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        #expect(try await h.collect(configuration)["acc-codex"]?.state == .live)
        #expect(await h.source.lastFilesParsed == 0)
        // The service goes offline: the snapshot is older than the live
        // result, so it is not parsed and the live result stays, unmarked
        // until the quick retry (spec 010 FR-005).
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        let entry = try await h.collect(configuration, at: 300)["acc-codex"]
        #expect(entry?.state == .retrying(reason: "offline", retryAt: CodexLimitsHarness.start.addingTimeInterval(330)))
        #expect(entry?.observation?.origin == .live)
        #expect(await h.source.lastFilesParsed == 0)
        // A snapshot newer than the live result is read and shown.
        try Self.install("limits-reached.jsonl", into: h.home(), modified: isoDate("2026-10-14T15:00:06Z"))
        let newer = try await h.collect(configuration, at: 600)["acc-codex"]
        #expect(newer?.observation?.origin == .snapshot)
        #expect(newer?.observation?.observedAt == isoDate("2026-10-14T15:00:05Z"))
        #expect(await h.source.lastFilesParsed == 1)
    }

    /// An unreadable rollout file is logged, like in the token reading.
    @Test func unreadableRolloutFileIsLogged() async throws {
        let h = try CodexLimitsHarness("codex-src-unreadable-file")
        defer { h.cleanUp() }
        let url = try Self.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home(), liveLimits: false)])
        let entry = try await h.collect(configuration)["acc-codex"]
        #expect(entry?.observation == nil)
        #expect(h.logText().contains("error: cannot read \(url.path)"))
    }

    @Test func unreachableServiceShowsTheSnapshotAsStale() async throws {
        let h = try CodexLimitsHarness("codex-src-offline")
        defer { h.cleanUp() }
        try Self.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        let token = CodexLimitsHarness.offlineStub()
        h.signIn(h.home(), token: token)
        let entries = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
        #expect(entries["acc-codex"]?.state == .stale(reason: "offline"))
        #expect(entries["acc-codex"]?.observation?.origin == .snapshot)
        #expect(entries["acc-codex"]?.sourceError == nil)
        #expect(CodexLimitsHarness.requests(token) == 1)
    }

    /// FR-005: the newer of the last live result and the snapshot.
    @Test func newerOfLiveAndSnapshotWins() async throws {
        let h = try CodexLimitsHarness("codex-src-newer")
        defer { h.cleanUp() }
        try Self.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        #expect(try await h.collect(configuration)["acc-codex"]?.state == .live)

        // The live result (15:00) is newer than the snapshot (14:20).
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        let failed = try await h.collect(configuration, at: 300)
        // spec 010 FR-005: the first transport failure keeps the values unmarked.
        #expect(failed["acc-codex"]?.state == .retrying(reason: "offline", retryAt: Self.start.addingTimeInterval(330)))
        #expect(failed["acc-codex"]?.observation?.origin == .live)
        #expect(failed["acc-codex"]?.observation?.observedAt == Self.start)

        // Codex ran on this machine after the failure: the snapshot is newer.
        try Self.install("limits-reached.jsonl", into: h.home(), modified: isoDate("2026-10-14T15:00:06Z"))
        let later = try await h.collect(configuration, at: 600)
        #expect(later["acc-codex"]?.observation?.origin == .snapshot)
        #expect(later["acc-codex"]?.observation?.observedAt == isoDate("2026-10-14T15:00:05Z"))
    }

    /// FR-005: a snapshot time in the future counts as the current time.
    @Test func futureSnapshotIsClampedToNow() async throws {
        let h = try CodexLimitsHarness("codex-src-future")
        defer { h.cleanUp() }
        // Event at 15:00:05, after every refresh below (clock skew).
        try Self.install("limits-reached.jsonl", into: h.home(), modified: isoDate("2026-10-14T15:00:06Z"))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        _ = try await h.collect(configuration, at: -60)   // live at 14:59:00
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        // At 14:59:30 the snapshot counts as 14:59:30, newer than 14:59:00.
        let newer = try await h.collect(configuration, at: -30)
        #expect(newer["acc-codex"]?.observation?.origin == .snapshot)
        // With the clock set back to 14:58:30, the snapshot counts as
        // 14:58:30 and the live result from 14:59:00 is newer.
        let skewed = try await h.collect(configuration, at: -90)
        #expect(skewed["acc-codex"]?.observation?.origin == .live)
        #expect(skewed["acc-codex"]?.observation?.observedAt == Self.start.addingTimeInterval(-60))
    }

    /// FR-006 and the contract's outcome table.
    @Test func reasonsAndSourceErrors() async throws {
        let h = try CodexLimitsHarness("codex-src-reasons")
        defer { h.cleanUp() }
        try Self.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        let cases: [(String, CodexLimitsState, String?)] = [
            (CodexLimitsHarness.stub(body: "{\"plan_type\": \"plus\"}"), .stale(reason: "usage service reported no limits"), nil),
            (CodexLimitsHarness.stub(body: "garbage"), .stale(reason: "usage service changed"), "usage service changed"),
            (CodexLimitsHarness.stub(status: 401, body: "{}"), .stale(reason: "Codex sign-in rejected, run Codex to renew it"), "Codex sign-in rejected"),
            (CodexLimitsHarness.stub(status: 403, body: "{}"), .stale(reason: "Codex sign-in rejected"), "Codex sign-in rejected"),
            (CodexLimitsHarness.stub(status: 503, body: "{}"), .stale(reason: "usage service unavailable (HTTP 503)"), nil),
            (CodexLimitsHarness.offlineStub(), .stale(reason: "offline"), nil),
        ]
        for (index, (token, state, sourceError)) in cases.enumerated() {
            h.signIn(h.home(), token: token)
            // Scheduled refreshes far enough apart: each one makes a request.
            let entry = try await h.collect(configuration, at: TimeInterval(index) * 600)["acc-codex"]
            #expect(entry?.state == state, "\(token)")
            #expect(entry?.sourceError == sourceError, "\(token)")
            #expect(entry?.observation?.origin == .snapshot)
        }
        // A rate limit and an expired sign-in only set the reason.
        let limited = try CodexLimitsHarness("codex-src-reasons-429")
        defer { limited.cleanUp() }
        limited.signIn(limited.home(), token: CodexLimitsHarness.stub(status: 429, body: "{}"))
        let rateLimited = try await limited.collect(Configuration(accounts: [CodexLimitsHarness.account(home: limited.home())]))
        #expect(rateLimited["acc-codex"] == CodexLimitsEntry(observation: nil, state: .unavailable(reason: "rate limited by the usage service")))
        let expired = try CodexLimitsHarness("codex-src-reasons-expired")
        defer { expired.cleanUp() }
        expired.signIn(expired.home(), token: "unused", expiresAt: Self.start.addingTimeInterval(-1))
        let expiredEntry = try await expired.collect(Configuration(accounts: [CodexLimitsHarness.account(home: expired.home())]))
        #expect(expiredEntry["acc-codex"]?.sourceError == nil)
    }

    @Test func nothingAtAllIsUnavailable() async throws {
        let h = try CodexLimitsHarness("codex-src-nothing")
        defer { h.cleanUp() }
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        let entries = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
        #expect(entries["acc-codex"] == CodexLimitsEntry(observation: nil, state: .unavailable(reason: "offline"),
                                                         quickRetryAt: CodexLimitsHarness.start.addingTimeInterval(30)))
    }

    /// FR-005: the last live result is in memory only.
    @Test func afterLaunchOnlySnapshotsApply() async throws {
        let h = try CodexLimitsHarness("codex-src-launch")
        defer { h.cleanUp() }
        try Self.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        #expect(try await h.collect(configuration)["acc-codex"]?.state == .live)
        // A new source (the app relaunched) with the service unreachable.
        let relaunched = CodexLimitsSource(credentialReader: h.reader,
                                           client: CodexUsageClient(session: StubURLProtocol.makeSession()), paths: Paths(home: h.root))
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        let context = RefreshContext(configuration: configuration, window: CodexLimitsHarness.window, now: Self.start.addingTimeInterval(60))
        guard case .codexLimits(let entries) = try await relaunched.collect(context: context) else {
            Issue.record("expected codex limits"); return
        }
        #expect(entries["acc-codex"]?.observation?.origin == .snapshot)
        #expect(entries["acc-codex"]?.state == .stale(reason: "offline"))
    }

    /// FR-020: one line per account with the shown source, time and reason.
    @Test func logNamesSourceTimeAndReason() async throws {
        let h = try CodexLimitsHarness("codex-src-log")
        defer { h.cleanUp() }
        try Self.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        _ = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
        let text = h.logText()
        #expect(text.contains("[codexLimits] acc-codex: stale, snapshot, observed 2026-10-14T14:20:01Z, reason: offline, request failed: "))
    }

    /// FR-020: the log says why no request was made or why it failed.
    @Test func logNamesWhyNoRequestWasMade() async throws {
        let h = try CodexLimitsHarness("codex-src-log-notes")
        defer { h.cleanUp() }
        let account = CodexLimitsHarness.account(home: h.home())
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        _ = try await h.collect(Configuration(accounts: [account]))
        #expect(h.logText().contains("acc-codex: live, observed 2026-10-14T15:00:00Z, fetched"))
        _ = try await h.collect(Configuration(accounts: [account]), at: 10, trigger: .local)
        #expect(h.logText().contains("acc-codex: live, observed 2026-10-14T15:00:00Z, no request due (local)"))
        h.signIn(h.home(), token: CodexLimitsHarness.stub(status: 429, body: "{}", headers: ["Retry-After": "600"]))
        _ = try await h.collect(Configuration(accounts: [account]), at: 300)
        #expect(h.logText().contains("reason: rate limited by the usage service, request failed: "))
        _ = try await h.collect(Configuration(accounts: [account]), at: 400)
        #expect(h.logText().contains("rate limited until 2026-10-14T15:15:00Z"))
        _ = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home(), liveLimits: false)]), at: 500)
        #expect(h.logText().contains("acc-codex: unavailable, reason: \(CodexLimitsSource.noLocalLimitsReason), live limits off"))
    }

    /// spec 021 FR-007, FR-008, SC-003: the log line of a no-answer failure
    /// names the error domain, code, underlying error and stream code; the
    /// shown reason stays "offline", and no token or account id is logged.
    @Test func noAnswerFailureLogsTheErrorDetail() async throws {
        let h = try CodexLimitsHarness("codex-src-detail")
        defer { h.cleanUp() }
        let token = "SECRET-CODEX-DETAIL-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key) { _ in throw offlineErrorWithDetail(secret: token) }
        defer { StubURLProtocol.unregister(key: key) }
        h.signIn(h.home(), token: token, accountId: "SECRET-ACCOUNT-DETAIL")
        let entries = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
        #expect(entries["acc-codex"]?.state == .unavailable(reason: "offline"))
        #expect(entries["acc-codex"]?.sourceError == nil)
        let text = h.logText()
        #expect(text.contains("request failed: usage endpoint unreachable: \(offlineDescription)"
                              + " [NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009; stream error 50] (transport)"))
        #expect(!text.contains("SECRET"))
        #expect(!String(describing: entries).contains("NSURLErrorDomain"))
    }
}

/// spec 007 FR-006, FR-007, research R5 (fetch gate per Codex home).
@Suite struct CodexLimitsSourceGateTests {
    static func config(_ accounts: [Account], interval: Int = Configuration.defaultRefreshIntervalSeconds) -> Configuration {
        Configuration(refreshIntervalSeconds: interval, accounts: accounts)
    }

    /// Assumption 3: a reprice makes no request; the kept live result stays live.
    @Test func localTriggerMakesNoRequest() async throws {
        let h = try CodexLimitsHarness("codex-gate-local")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        let reprice = try await h.collect(configuration, at: 10, trigger: .local)
        #expect(CodexLimitsHarness.requests(token) == 1)
        #expect(reprice["acc-codex"]?.state == .live)
        #expect(reprice["acc-codex"]?.observation?.observedAt == CodexLimitsHarness.start)
    }

    /// FR-007: Retry-After blocks this Codex home, manual refreshes included;
    /// another home still fetches.
    @Test func retryAfterBlocksOnlyThatHome() async throws {
        let h = try CodexLimitsHarness("codex-gate-429")
        defer { h.cleanUp() }
        let limited = CodexLimitsHarness.stub(status: 429, body: "{}", headers: ["Retry-After": "300"])
        let other = CodexLimitsHarness.stub()
        h.signIn(h.home(".codex"), token: limited)
        h.signIn(h.home(".codex-other"), token: other)
        let configuration = Self.config([CodexLimitsHarness.account("acc-a", home: h.home(".codex")),
                                         CodexLimitsHarness.account("acc-b", home: h.home(".codex-other"))])
        let first = try await h.collect(configuration)
        #expect(first["acc-a"]?.state == .unavailable(reason: "rate limited by the usage service"))
        let blocked = try await h.collect(configuration, at: 100)
        _ = try await h.collect(configuration, at: 200, trigger: .manual)
        #expect(CodexLimitsHarness.requests(limited) == 1)
        #expect(CodexLimitsHarness.requests(other) == 3)
        #expect(blocked["acc-a"]?.state == .unavailable(reason: "rate limited by the usage service"))
        #expect(blocked["acc-b"]?.state == .live)
        _ = try await h.collect(configuration, at: 300)
        #expect(CodexLimitsHarness.requests(limited) == 2)
    }

    /// FR-007: without Retry-After, one refresh interval from that refresh.
    @Test func rateLimitWithoutRetryAfterBlocksOneInterval() async throws {
        let h = try CodexLimitsHarness("codex-gate-429-bare")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub(status: 429, body: "{}")
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())], interval: 120)
        _ = try await h.collect(configuration, at: 10)
        _ = try await h.collect(configuration, at: 129)
        #expect(CodexLimitsHarness.requests(token) == 1)
        _ = try await h.collect(configuration, at: 130)
        #expect(CodexLimitsHarness.requests(token) == 2)
    }

    @Test func manualRefreshesAreSpaced() async throws {
        let h = try CodexLimitsHarness("codex-gate-manual")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration, trigger: .manual)
        let spaced = try await h.collect(configuration, at: 30, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 1)
        #expect(spaced["acc-codex"]?.state == .live)
        _ = try await h.collect(configuration, at: 61, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 2)
        for (offset, trigger) in [(70.0, RefreshTrigger.retry), (80, .launch), (90, .wake), (100, .settings)] {
            _ = try await h.collect(configuration, at: offset, trigger: trigger)
        }
        #expect(CodexLimitsHarness.requests(token) == 2)
        _ = try await h.collect(configuration, at: 122, trigger: .retry)
        #expect(CodexLimitsHarness.requests(token) == 3)
    }

    // MARK: No-answer bypass (spec 021 FR-003 to FR-006, research R7)

    /// Answers the requests of `token` with no answer at all.
    static func goOffline(_ token: String) {
        StubURLProtocol.register(key: "Bearer \(token)") { _ in throw URLError(.notConnectedToInternet) }
    }

    /// Answers the requests of `token` with `status`. Registering an answer
    /// resets the token's recorded requests.
    static func answer(_ token: String, status: Int = 200, headers: [String: String] = [:]) {
        let body = status == 200 ? codexUsageSampleJSON : "{}"
        StubURLProtocol.register(key: "Bearer \(token)", headers: headers) { _ in (status, Data(body.utf8)) }
    }

    /// FR-003: after a no-answer failure, "Refresh now" asks the Codex home
    /// again within the 60 s spacing, as long as it gets no answer; after a
    /// success the spacing applies again.
    @Test func manualAfterNoAnswerBypassesHomeSpacing() async throws {
        let h = try CodexLimitsHarness("codex-gate-noanswer")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.offlineStub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        _ = try await h.collect(configuration, at: 10, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 2)
        _ = try await h.collect(configuration, at: 20, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 3)
        Self.answer(token)
        let fresh = try await h.collect(configuration, at: 25, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 1)
        #expect(fresh["acc-codex"]?.state == .live)
        _ = try await h.collect(configuration, at: 40, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 1)
    }

    /// FR-004: an HTTP 5xx answer keeps the manual spacing.
    @Test func manualAfterHTTP5xxStaysSpaced() async throws {
        let h = try CodexLimitsHarness("codex-gate-5xx")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub(status: 503, body: "{}")
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        let spaced = try await h.collect(configuration, at: 10, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 1)
        #expect(spaced["acc-codex"]?.state == .unavailable(reason: "usage service unavailable (HTTP 503)"))
    }

    /// FR-004: once the bypass request got a 5xx answer, the next click
    /// within the spacing is spaced again.
    @Test func manualAfterNoAnswerThen5xxStaysSpaced() async throws {
        let h = try CodexLimitsHarness("codex-gate-noanswer-5xx")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.offlineStub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        Self.answer(token, status: 503)
        _ = try await h.collect(configuration, at: 10, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 1)
        _ = try await h.collect(configuration, at: 20, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 1)
    }

    /// FR-003: an active rate-limit wait still wins over the bypass.
    @Test func noAnswerBypassRespectsTheRateLimitWait() async throws {
        let h = try CodexLimitsHarness("codex-gate-noanswer-blocked")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.offlineStub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        await h.source.block(home: h.home(), until: CodexLimitsHarness.start.addingTimeInterval(120))
        _ = try await h.collect(configuration, at: 10, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 1)
        _ = try await h.collect(configuration, at: 121, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 2)
    }

    /// FR-005: wake, dropdown open, settings and the return from idle keep
    /// the per-home spacing after a no-answer failure, and so does a manual
    /// trigger the user did not click.
    @Test func otherTriggersStaySpacedAfterNoAnswer() async throws {
        let h = try CodexLimitsHarness("codex-gate-noanswer-others")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.offlineStub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        for (offset, trigger) in [(10.0, RefreshTrigger.wake), (20, .dropdownOpen), (30, .idleReturn), (40, .settings), (50, .launch)] {
            _ = try await h.collect(configuration, at: offset, trigger: trigger)
        }
        _ = try await h.collect(configuration, at: 55, trigger: .manual, manualRequested: false)
        #expect(CodexLimitsHarness.requests(token) == 1)
    }

    /// FR-003a: a click merged into another trigger still asks a home whose
    /// last request got no answer, both for a scheduled run the pace holds
    /// back and for a wake inside the spacing; without the click both keep
    /// their own rule.
    @Test func mergedClickBypassesTheOtherTriggersRule() async throws {
        let h = try CodexLimitsHarness("codex-gate-noanswer-merged")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.offlineStub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        _ = try await h.collect(configuration, at: 5, trigger: .scheduled, codexPaceDue: false)
        _ = try await h.collect(configuration, at: 6, trigger: .wake)
        #expect(CodexLimitsHarness.requests(token) == 1)
        _ = try await h.collect(configuration, at: 10, trigger: .scheduled, codexPaceDue: false, manualRequested: true)
        #expect(CodexLimitsHarness.requests(token) == 2)
        _ = try await h.collect(configuration, at: 20, trigger: .wake, manualRequested: true)
        #expect(CodexLimitsHarness.requests(token) == 3)
    }

    /// FR-003b: a bypass request counts for the home spacing, and a rate
    /// limit it gets sets the wait as usual.
    @Test func bypassCountsForHomeSpacingAndItsRateLimitSetsTheWait() async throws {
        let h = try CodexLimitsHarness("codex-gate-noanswer-counts")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.offlineStub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        Self.answer(token)
        _ = try await h.collect(configuration, at: 10, trigger: .manual)
        _ = try await h.collect(configuration, at: 30, trigger: .manual)
        _ = try await h.collect(configuration, at: 40, trigger: .wake)
        #expect(CodexLimitsHarness.requests(token) == 1)

        Self.goOffline(token)
        _ = try await h.collect(configuration, at: 300)
        Self.answer(token, status: 429, headers: ["Retry-After": "300"])
        _ = try await h.collect(configuration, at: 310, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 1)
        let blocked = try await h.collect(configuration, at: 400)
        #expect(CodexLimitsHarness.requests(token) == 1)
        #expect(h.logText().contains("rate limited until 2026-10-14T15:10:10Z"))
        #expect(blocked["acc-codex"]?.state == .stale(reason: "rate limited by the usage service"))
        _ = try await h.collect(configuration, at: 611)
        #expect(CodexLimitsHarness.requests(token) == 2)
    }

    @Test func scheduledRefreshesAreNotSpaced() async throws {
        let h = try CodexLimitsHarness("codex-gate-scheduled")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        _ = try await h.collect(configuration, at: 10)
        #expect(CodexLimitsHarness.requests(token) == 2)
    }

    /// FR-006: a rate-limit wait is stale, unlike a skip because none was due.
    @Test func rateLimitWaitShowsTheKeptLiveResultAsStale() async throws {
        let h = try CodexLimitsHarness("codex-gate-stale")
        defer { h.cleanUp() }
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        _ = try await h.collect(configuration)
        let limited = CodexLimitsHarness.stub(status: 429, body: "{}")
        h.signIn(h.home(), token: limited)
        let hit = try await h.collect(configuration, at: 100)
        let waiting = try await h.collect(configuration, at: 200)
        for entry in [hit["acc-codex"], waiting["acc-codex"]] {
            #expect(entry?.state == .stale(reason: "rate limited by the usage service"))
            #expect(entry?.observation?.origin == .live)
            #expect(entry?.observation?.observedAt == CodexLimitsHarness.start)
        }
        #expect(CodexLimitsHarness.requests(limited) == 1)
    }

    /// research R5: a new (Codex home, live limits) combination is fetched
    /// once even on a reprice; after a failed attempt a reprice makes no
    /// request.
    @Test func firstAttemptPerCombinationIgnoresTheTrigger() async throws {
        let h = try CodexLimitsHarness("codex-gate-first")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(".codex"), token: token)
        let live = Self.config([CodexLimitsHarness.account(home: h.home(".codex"))])
        // A new account.
        #expect(try await h.collect(live, trigger: .local)["acc-codex"]?.state == .live)
        #expect(CodexLimitsHarness.requests(token) == 1)
        // Live limits off, then back on.
        _ = try await h.collect(Self.config([CodexLimitsHarness.account(home: h.home(".codex"), liveLimits: false)]), at: 10, trigger: .local)
        _ = try await h.collect(live, at: 20, trigger: .local)
        #expect(CodexLimitsHarness.requests(token) == 2)
        // A changed Codex home.
        let moved = CodexLimitsHarness.stub()
        h.signIn(h.home(".codex-moved"), token: moved)
        _ = try await h.collect(Self.config([CodexLimitsHarness.account(home: h.home(".codex-moved"))]), at: 30, trigger: .local)
        #expect(CodexLimitsHarness.requests(moved) == 1)
        // After a failed attempt, a reprice makes no request.
        let offline = CodexLimitsHarness.offlineStub()
        h.signIn(h.home(".codex-offline"), token: offline)
        let failing = Self.config([CodexLimitsHarness.account(home: h.home(".codex-offline"))])
        _ = try await h.collect(failing, at: 40, trigger: .local)
        let again = try await h.collect(failing, at: 50, trigger: .local)
        #expect(CodexLimitsHarness.requests(offline) == 1)
        #expect(again["acc-codex"]?.state == .unavailable(reason: "offline"))
    }

    /// Changing the Codex home drops the live result of the old home.
    @Test func changedHomeDropsTheLiveResult() async throws {
        let h = try CodexLimitsHarness("codex-gate-home")
        defer { h.cleanUp() }
        h.signIn(h.home(".codex"), token: CodexLimitsHarness.stub())
        _ = try await h.collect(Self.config([CodexLimitsHarness.account(home: h.home(".codex"))]))
        h.signIn(h.home(".codex-new"), token: CodexLimitsHarness.offlineStub())
        let moved = try await h.collect(Self.config([CodexLimitsHarness.account(home: h.home(".codex-new"))]), at: 10)
        // The first transport failure has a quick retry (spec 010 FR-004).
        #expect(moved["acc-codex"] == CodexLimitsEntry(observation: nil, state: .unavailable(reason: "offline"),
                                                       quickRetryAt: CodexLimitsHarness.start.addingTimeInterval(40)))
    }

    /// FR-005, FR-006: after a failed fetch, a refresh that makes no request
    /// (a reprice, or a manual refresh within the spacing) keeps the values
    /// stale; the earlier live result never turns live again.
    @Test func notDueAfterAFailureStaysStale() async throws {
        let h = try CodexLimitsHarness("codex-gate-notdue-failure")
        defer { h.cleanUp() }
        try CodexLimitsSourceFallbackTests.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        #expect(try await h.collect(configuration)["acc-codex"]?.state == .live)
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        _ = try await h.collect(configuration, at: 300)
        // spec 010 FR-006: the failed quick retry marks the values stale.
        let failed = try await h.collect(configuration, at: 331, trigger: .quickRetry)
        #expect(failed["acc-codex"]?.state == .stale(reason: "offline"))
        for (offset, trigger) in [(340.0, RefreshTrigger.local), (350, .manual)] {
            let entry = try await h.collect(configuration, at: offset, trigger: trigger)["acc-codex"]
            #expect(entry?.state == .stale(reason: "offline"))
            // The newer of the live result (15:00) and the snapshot (14:20).
            #expect(entry?.observation?.origin == .live)
            #expect(entry?.observation?.observedAt == CodexLimitsHarness.start)
        }
    }

    /// FR-005, FR-006: a refresh that makes no request after a successful
    /// one shows a newer snapshot, not stale and without a source error.
    @Test func notDueShowsANewerSnapshotWithoutStaleMarking() async throws {
        let h = try CodexLimitsHarness("codex-gate-notdue-newer")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        #expect(try await h.collect(configuration)["acc-codex"]?.state == .live)
        // Codex ran after the fetch: its snapshot (15:00:05) is newer than
        // the live result (15:00:00).
        try CodexLimitsSourceFallbackTests.install("limits-reached.jsonl", into: h.home(), modified: isoDate("2026-10-14T15:00:06Z"))
        for (offset, trigger) in [(10.0, RefreshTrigger.local), (20, .manual)] {
            let entry = try await h.collect(configuration, at: offset, trigger: trigger)["acc-codex"]
            #expect(entry?.state == .newerSnapshot)
            #expect(entry?.state.isStale == false)
            #expect(entry?.sourceError == nil)
            #expect(entry?.observation?.origin == .snapshot)
            #expect(entry?.observation?.observedAt == isoDate("2026-10-14T15:00:05Z"))
        }
        #expect(CodexLimitsHarness.requests(token) == 1)
        #expect(h.logText().contains("acc-codex: newer snapshot, snapshot, observed 2026-10-14T15:00:05Z"))
    }

    /// FR-006: a refresh that makes no request keeps a live result that is
    /// newer than the snapshot live.
    @Test func notDueKeepsALiveResultNewerThanTheSnapshot() async throws {
        let h = try CodexLimitsHarness("codex-gate-notdue-older")
        defer { h.cleanUp() }
        try CodexLimitsSourceFallbackTests.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        for (offset, trigger) in [(10.0, RefreshTrigger.local), (20, .manual)] {
            let entry = try await h.collect(configuration, at: offset, trigger: trigger)["acc-codex"]
            #expect(entry?.state == .live)
            #expect(entry?.observation?.origin == .live)
            #expect(entry?.observation?.observedAt == CodexLimitsHarness.start)
        }
        #expect(CodexLimitsHarness.requests(token) == 1)
    }

    /// FR-005, FR-006: after a failed fetch, a newer snapshot shown on a
    /// refresh that makes no request stays stale with the failure's reason.
    @Test func notDueAfterAFailureShowsANewerSnapshotAsStale() async throws {
        let h = try CodexLimitsHarness("codex-gate-notdue-failure-newer")
        defer { h.cleanUp() }
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration, at: -300)
        let offline = CodexLimitsHarness.offlineStub()
        h.signIn(h.home(), token: offline)
        _ = try await h.collect(configuration)
        // spec 010 FR-006: the failed quick retry marks the values stale.
        #expect(try await h.collect(configuration, at: 31, trigger: .quickRetry)["acc-codex"]?.state == .stale(reason: "offline"))
        try CodexLimitsSourceFallbackTests.install("limits-reached.jsonl", into: h.home(), modified: isoDate("2026-10-14T15:00:06Z"))
        // A click on "Refresh now" would ask again after this no-answer
        // failure (spec 021 FR-003); a spaced settings refresh does not.
        for (offset, trigger) in [(40.0, RefreshTrigger.local), (50, .settings)] {
            let entry = try await h.collect(configuration, at: offset, trigger: trigger)["acc-codex"]
            #expect(entry?.state == .stale(reason: "offline"))
            #expect(entry?.observation?.origin == .snapshot)
            #expect(entry?.observation?.observedAt == isoDate("2026-10-14T15:00:05Z"))
        }
        #expect(CodexLimitsHarness.requests(offline) == 2)
    }

    /// FR-007: a stated wait longer than one hour blocks for one hour.
    @Test func retryAfterIsCappedAtOneHour() async throws {
        let h = try CodexLimitsHarness("codex-gate-429-cap")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub(status: 429, body: "{}", headers: ["Retry-After": "86400"])
        h.signIn(h.home(), token: token)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        _ = try await h.collect(configuration, at: 3599)
        _ = try await h.collect(configuration, at: 3599.5, trigger: .manual)
        #expect(CodexLimitsHarness.requests(token) == 1)
        _ = try await h.collect(configuration, at: 3600)
        #expect(CodexLimitsHarness.requests(token) == 2)
    }

    /// A token the service rejected (HTTP 401) is not sent again; a renewed
    /// token is (FR-003).
    @Test func rejectedTokenIsNotSentAgain() async throws {
        let h = try CodexLimitsHarness("codex-gate-rejected")
        defer { h.cleanUp() }
        let rejected = CodexLimitsHarness.stub(status: 401, body: "{}")
        h.signIn(h.home(), token: rejected)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        for offset in [0.0, 300, 600] {
            let entry = try await h.collect(configuration, at: offset)["acc-codex"]
            #expect(entry?.state == .unavailable(reason: "Codex sign-in rejected, run Codex to renew it"))
            #expect(entry?.sourceError == "Codex sign-in rejected")
        }
        #expect(CodexLimitsHarness.requests(rejected) == 1)
        // A manual refresh tries the rejected token once more.
        _ = try await h.collect(configuration, at: 700, trigger: .manual)
        #expect(CodexLimitsHarness.requests(rejected) == 2)
        _ = try await h.collect(configuration, at: 800)
        #expect(CodexLimitsHarness.requests(rejected) == 2)
        // Turning live limits off and on again tries it once more too.
        _ = try await h.collect(Self.config([CodexLimitsHarness.account(home: h.home(), liveLimits: false)]), at: 820)
        _ = try await h.collect(configuration, at: 840)
        #expect(CodexLimitsHarness.requests(rejected) == 3)
        _ = try await h.collect(configuration, at: 860)
        #expect(CodexLimitsHarness.requests(rejected) == 3)
        // Codex renewed the sign-in.
        let renewed = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: renewed)
        #expect(try await h.collect(configuration, at: 900)["acc-codex"]?.state == .live)
        #expect(CodexLimitsHarness.requests(renewed) == 1)
    }

    /// Two accounts on spellings of one Codex home (a symlink) share one
    /// sign-in: one request per refresh, and the live-off account does not
    /// release the token the service rejected (FR-003, FR-007).
    @Test func aliasedHomesShareOneRequestAndTheRejection() async throws {
        let h = try CodexLimitsHarness("codex-gate-alias")
        defer { h.cleanUp() }
        try FileManager.default.createDirectory(atPath: h.home(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: h.home("codex-link"), withDestinationPath: h.home())
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        h.signIn(h.home("codex-link"), token: token)
        let both = Self.config([CodexLimitsHarness.account("acc-a", home: h.home()),
                                CodexLimitsHarness.account("acc-b", home: h.home("codex-link"))])
        let entries = try await h.collect(both)
        #expect(entries["acc-a"]?.state == .live)
        #expect(entries["acc-b"]?.state == .live)
        #expect(CodexLimitsHarness.requests(token) == 1)

        let rejected = CodexLimitsHarness.stub(status: 401, body: "{}")
        h.signIn(h.home(), token: rejected)
        h.signIn(h.home("codex-link"), token: rejected)
        let mixed = Self.config([CodexLimitsHarness.account("acc-a", home: h.home()),
                                 CodexLimitsHarness.account("acc-b", home: h.home("codex-link"), liveLimits: false)])
        for offset in [300.0, 600, 900] {
            _ = try await h.collect(mixed, at: offset)
        }
        #expect(CodexLimitsHarness.requests(rejected) == 1)
    }

    /// A 403 may be the service's front end rather than the sign-in, so the
    /// token is sent again on each scheduled refresh.
    @Test func forbiddenTokenIsRetried() async throws {
        let h = try CodexLimitsHarness("codex-gate-forbidden")
        defer { h.cleanUp() }
        let forbidden = CodexLimitsHarness.stub(status: 403, body: "{}")
        h.signIn(h.home(), token: forbidden)
        let configuration = Self.config([CodexLimitsHarness.account(home: h.home())])
        for offset in [0.0, 300, 600] {
            let entry = try await h.collect(configuration, at: offset)["acc-codex"]
            #expect(entry?.state == .unavailable(reason: "Codex sign-in rejected"))
            #expect(entry?.sourceError == "Codex sign-in rejected")
        }
        #expect(CodexLimitsHarness.requests(forbidden) == 3)
    }
}

/// spec 007 FR-005, FR-006, FR-019 (live limits off).
@Suite struct CodexLimitsSourceLocalOnlyTests {
    @Test func liveOffShowsTheSnapshotWithoutReadsOrRequests() async throws {
        let h = try CodexLimitsHarness("codex-local-only")
        defer { h.cleanUp() }
        try CodexLimitsSourceFallbackTests.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home(), liveLimits: false)])
        for (offset, trigger) in [(0.0, RefreshTrigger.launch), (60, .scheduled), (120, .manual), (130, .local)] {
            let entry = try await h.collect(configuration, at: offset, trigger: trigger)["acc-codex"]
            #expect(entry?.state == .localOnly)
            #expect(entry?.observation?.origin == .snapshot)
            #expect(entry?.observation?.observedAt == CodexLimitsSourceFallbackTests.plusObserved)
            #expect(entry?.sourceError == nil)
        }
        #expect(h.reader.reads.isEmpty)
        #expect(CodexLimitsHarness.requests(token) == 0)
    }

    /// FR-005: turning live limits off discards a kept live result, even a
    /// newer one.
    @Test func turningLiveOffDiscardsTheLiveResult() async throws {
        let h = try CodexLimitsHarness("codex-local-discard")
        defer { h.cleanUp() }
        try CodexLimitsSourceFallbackTests.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        let live = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
        #expect(live["acc-codex"]?.observation?.observedAt == CodexLimitsHarness.start)
        let off = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home(), liveLimits: false)]), at: 60)
        #expect(off["acc-codex"]?.state == .localOnly)
        #expect(off["acc-codex"]?.observation?.origin == .snapshot)
        // Back on with the service unreachable: the discarded live result
        // (15:00, newer than the snapshot) does not come back.
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        let on = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]), at: 120)
        #expect(on["acc-codex"]?.state == .stale(reason: "offline"))
        #expect(on["acc-codex"]?.observation?.origin == .snapshot)
        #expect(on["acc-codex"]?.observation?.observedAt == CodexLimitsSourceFallbackTests.plusObserved)
    }

    @Test func liveOffWithoutSnapshotsIsUnavailable() async throws {
        let h = try CodexLimitsHarness("codex-local-none")
        defer { h.cleanUp() }
        let entries = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home(), liveLimits: false)]))
        #expect(entries["acc-codex"]?.observation == nil)
        guard case .unavailable = entries["acc-codex"]?.state else {
            Issue.record("expected unavailable"); return
        }
        #expect(h.reader.reads.isEmpty)
    }
}

/// spec 007 FR-003, FR-018, SC-004, SC-005: credentials never leak and the
/// Codex home is never changed.
@Suite struct CodexLimitsPrivacyTests {
    static let token = "SECRET-CODEX-TOKEN-123"
    static let accountId = "SECRET-ACCOUNT-456"

    /// Every file under `root` with its size and modification date.
    static func inventory(_ root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]))
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            result[url.path] = "\(values.isDirectory == true ? "dir" : "\(values.fileSize ?? -1)")|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        return result
    }

    /// FR-018, SC-005: the token and the account id appear in no log line,
    /// entry, source error or threshold crossing.
    @Test func credentialsNeverLeak() async throws {
        let h = try CodexLimitsHarness("codex-sentinel")
        defer { h.cleanUp() }
        h.reader.set(h.home(), .success(.found(CodexCredential(accessToken: Self.token, accountId: Self.accountId, expiresAt: nil))))
        let key = "Bearer \(Self.token)"
        defer { StubURLProtocol.unregister(key: key) }
        let higher = codexUsageSampleJSON.replacingOccurrences(of: "\"used_percent\": 11", with: "\"used_percent\": 60")
        let configuration = Configuration(accounts: [
            Account(id: "acc-codex", displayName: "ChatGPT Plus", harness: .codex,
                    kind: .codexSubscription(CodexSubscriptionSettings(codexHome: h.home(), thresholds: [50]))),
        ])
        let phases: [(Int, String, [String: String]?)] = [
            (200, codexUsageSampleJSON, nil), (200, higher, nil), (401, "{}", nil), (200, "garbage", nil),
            (0, "", nil), (429, "{}", ["Retry-After": "60"]),
        ]
        var tracker = ThresholdTracker()
        var crossings: [ThresholdCrossing] = []
        var texts: [String] = []
        for (index, (status, body, headers)) in phases.enumerated() {
            if status == 0 {
                // spec 021 FR-008: the error's user info holds the token and
                // the account id, which must not reach the log with the detail.
                StubURLProtocol.register(key: key) { _ in throw offlineErrorWithDetail(secret: Self.token + Self.accountId) }
            } else {
                StubURLProtocol.register(key: key, headers: headers ?? [:]) { _ in (status, Data(body.utf8)) }
            }
            let offset = TimeInterval(index) * 600
            let entries = try await h.collect(configuration, at: offset)
            texts.append(String(describing: entries))
            texts.append(String(reflecting: entries))
            texts += entries.values.compactMap(\.sourceError)
            var snapshot = UsageSnapshot(generatedAt: CodexLimitsHarness.start.addingTimeInterval(offset),
                                         window: CodexLimitsHarness.window, windowSource: .fallback)
            snapshot.codexLimits = entries
            crossings += tracker.observe(snapshot: snapshot, configuration: configuration)
        }
        #expect(crossings.map(\.windowKind.displayName) == ["weekly"])
        texts += crossings.map { String(describing: $0) }
        texts += crossings.map { "\($0.entityName) \($0.windowKind.displayName)" }
        texts.append(h.logText())
        #expect(h.logText().contains("acc-codex"))
        for text in texts {
            #expect(!text.contains(Self.token))
            #expect(!text.contains(Self.accountId))
        }
    }

    /// FR-003, SC-004: refreshes with live limits on change nothing in the
    /// Codex home.
    @Test func codexHomeIsNeverChanged() async throws {
        let root = try makeTempDirectory("codex-immutable")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent(".codex")
        let token = syntheticJWT(exp: isoDate("2026-10-20T00:00:00Z"))
        try writeCodexAuth(home, accessToken: token)
        try Data("model = \"gpt-5.5\"\n".utf8).write(to: home.appendingPathComponent("config.toml"))
        try CodexFixtures.install("limits-plus.jsonl", home: home, day: "2026/10/14")
        let past = isoDate("2026-10-14T14:30:00Z")
        for path in try FileManager.default.subpathsOfDirectory(atPath: home.path) {
            try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: home.appendingPathComponent(path).path)
        }
        let before = try Self.inventory(home)

        // The synthetic JWT keys the stub; each phase answers differently.
        let key = "Bearer \(token)"
        defer { StubURLProtocol.unregister(key: key) }
        let source = CodexLimitsSource(credentialReader: FileCodexCredentialReader(paths: Paths(home: root)),
                                       client: CodexUsageClient(session: StubURLProtocol.makeSession()),
                                       log: DiagnosticLog(fileURL: root.appendingPathComponent("usage.log")),
                                       paths: Paths(home: root))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: "~/.codex")])
        // 401 last: a rejected token is not sent again.
        let phases: [(Int, String)] = [(200, codexUsageSampleJSON), (0, ""), (200, "garbage"), (429, "{}"), (401, "{}")]
        var requests = 0
        for (index, (status, body)) in phases.enumerated() {
            if status == 0 {
                StubURLProtocol.register(key: key) { _ in throw URLError(.notConnectedToInternet) }
            } else {
                StubURLProtocol.register(key: key) { _ in (status, Data(body.utf8)) }
            }
            let context = RefreshContext(configuration: configuration, window: CodexLimitsHarness.window,
                                         now: CodexLimitsHarness.start.addingTimeInterval(TimeInterval(index) * 600))
            _ = try await source.collect(context: context)
            // Registering a handler clears the stub's request list.
            requests += StubURLProtocol.usageRequests(key: key).count
        }
        #expect(requests == 5)
        #expect(try Self.inventory(home) == before)
        // SC-005 end to end: the real reader's log holds no credential text.
        let log = (try? String(contentsOf: root.appendingPathComponent("usage.log"), encoding: .utf8)) ?? ""
        #expect(log.contains("acc-codex"))
        for secret in [token, "REFRESH-SENTINEL", "ID-SENTINEL", "acct-test"] {
            #expect(!log.contains(secret))
        }
    }
}

/// spec 010 FR-001, FR-002, FR-004 to FR-008: one quick retry after a
/// transport failure, values unmarked meanwhile.
@Suite struct CodexLimitsSourceQuickRetryTests {
    static let start = CodexLimitsHarness.start

    /// A live success at 0 and a transport failure at 300 for one account.
    static func inGrace(_ h: CodexLimitsHarness, home: String? = nil) async throws -> Configuration {
        let home = home ?? h.home()
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: home)])
        h.signIn(home, token: CodexLimitsHarness.stub())
        #expect(try await h.collect(configuration)["acc-codex"]?.state == .live)
        h.signIn(home, token: CodexLimitsHarness.offlineStub())
        _ = try await h.collect(configuration, at: 300)
        return configuration
    }

    @Test func transportFailureAfterALiveSuccessIsRetrying() async throws {
        let h = try CodexLimitsHarness("codex-qr-grace")
        defer { h.cleanUp() }
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        _ = try await h.collect(configuration)
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        let entry = try #require(try await h.collect(configuration, at: 300)["acc-codex"])
        let retryAt = Self.start.addingTimeInterval(330)
        #expect(entry.state == .retrying(reason: "offline", retryAt: retryAt))
        #expect(entry.quickRetryAt == retryAt)
        #expect(entry.observation?.origin == .live)
        #expect(entry.observation?.observedAt == Self.start)
        #expect(entry.sourceError == nil)
        #expect(!entry.signInRejected)
        #expect(h.logText().contains("quick retry scheduled at"))
        #expect(h.logText().contains("transport"))
    }

    /// A request that times out fails 30 s after the refresh started: the
    /// quick retry counts from the failure (spec 010 FR-004).
    @Test func quickRetryCountsFromTheFailureNotTheRefreshStart() async throws {
        let h = try CodexLimitsHarness("codex-qr-timeout")
        defer { h.cleanUp() }
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        _ = try await h.collect(configuration)
        let token = "codex-src-timeout-\(UUID().uuidString)"
        let clock = h.clock
        StubURLProtocol.register(key: "Bearer \(token)") { _ in
            clock.advance(30)
            throw URLError(.timedOut)
        }
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let entry = try #require(try await h.collect(configuration, at: 300)["acc-codex"])
        let retryAt = Self.start.addingTimeInterval(360)
        #expect(entry.state == .retrying(reason: "offline", retryAt: retryAt))
        #expect(entry.quickRetryAt == retryAt)
    }

    /// Edge case "Retry and timer collide": a scheduled request during the
    /// grace period that fails ends it stale, without a second quick retry
    /// in the episode (spec 010 FR-008).
    @Test func failedScheduledRequestThatTakesTheRetrysPlaceIsStale() async throws {
        let h = try CodexLimitsHarness("codex-qr-collide")
        defer { h.cleanUp() }
        let configuration = try await Self.inGrace(h)
        let replaced = try #require(try await h.collect(configuration, at: 310)["acc-codex"])
        #expect(replaced.state == .stale(reason: "offline"))
        #expect(replaced.quickRetryAt == nil)
        let later = try #require(try await h.collect(configuration, at: 610)["acc-codex"])
        #expect(later.state == .stale(reason: "offline"))
        #expect(later.quickRetryAt == nil)
    }

    @Test func quickRetryFetchesOnlyAccountsWhoseRetryIsDue() async throws {
        let h = try CodexLimitsHarness("codex-qr-due")
        defer { h.cleanUp() }
        let configuration = Configuration(accounts: [CodexLimitsHarness.account("acc-a", home: h.home(".codex-a")),
                                                     CodexLimitsHarness.account("acc-b", home: h.home(".codex-b"))])
        let good = CodexLimitsHarness.stub()
        h.signIn(h.home(".codex-a"), token: good)
        h.signIn(h.home(".codex-b"), token: CodexLimitsHarness.stub())
        _ = try await h.collect(configuration)
        let offline = CodexLimitsHarness.offlineStub()
        h.signIn(h.home(".codex-b"), token: offline)
        let failed = try await h.collect(configuration, at: 300)
        #expect(failed["acc-a"]?.state == .live)
        #expect(CodexLimitsHarness.requests(good) == 2)
        #expect(CodexLimitsHarness.requests(offline) == 1)

        // Before the retry time nothing is fetched.
        let early = try await h.collect(configuration, at: 310, trigger: .quickRetry)
        #expect(CodexLimitsHarness.requests(good) == 2)
        #expect(CodexLimitsHarness.requests(offline) == 1)
        #expect(early["acc-b"]?.state == .retrying(reason: "offline", retryAt: Self.start.addingTimeInterval(330)))
        #expect(early["acc-a"]?.state == .live)

        // At the retry time, 31 s after the failed attempt: spacing bypassed.
        let recovered = CodexLimitsHarness.stub()
        h.signIn(h.home(".codex-b"), token: recovered)
        let retried = try await h.collect(configuration, at: 331, trigger: .quickRetry)
        #expect(CodexLimitsHarness.requests(recovered) == 1)
        #expect(CodexLimitsHarness.requests(good) == 2)
        #expect(retried["acc-b"]?.state == .live)
        #expect(retried["acc-b"]?.quickRetryAt == nil)
        #expect(retried["acc-a"]?.state == .live)
        #expect(h.logText().contains("quick retry sent"))
    }

    @Test func refreshesWithoutARequestBeforeTheRetryKeepRetrying() async throws {
        let h = try CodexLimitsHarness("codex-qr-notdue")
        defer { h.cleanUp() }
        let configuration = try await Self.inGrace(h)
        let retrying = CodexLimitsState.retrying(reason: "offline", retryAt: Self.start.addingTimeInterval(330))
        // A click on "Refresh now" asks again instead (spec 021 FR-003, see
        // manualClickInTheGracePeriodTakesTheQuickRetrysPlace).
        for (offset, trigger) in [(305.0, RefreshTrigger.local), (310, .wake), (320, .dropdownOpen)] {
            let entry = try await h.collect(configuration, at: offset, trigger: trigger)["acc-codex"]
            #expect(entry?.state == retrying, "\(trigger)")
            #expect(entry?.quickRetryAt == Self.start.addingTimeInterval(330), "\(trigger)")
            #expect(entry?.observation?.origin == .live)
        }
    }

    /// spec 021 FR-003, edge case "A no-answer failure inside the spec 010
    /// grace period": a click before the quick retry sends one request,
    /// which takes the retry's place; a success ends the grace period.
    @Test func manualClickInTheGracePeriodTakesTheQuickRetrysPlace() async throws {
        let h = try CodexLimitsHarness("codex-qr-manual")
        defer { h.cleanUp() }
        let configuration = try await Self.inGrace(h)
        let recovered = CodexLimitsHarness.stub()
        defer { StubURLProtocol.unregister(key: "Bearer \(recovered)") }
        h.signIn(h.home(), token: recovered)
        let clicked = try await h.collect(configuration, at: 310, trigger: .manual)["acc-codex"]
        #expect(CodexLimitsHarness.requests(recovered) == 1)
        #expect(clicked?.state == .live)
        #expect(clicked?.quickRetryAt == nil)
        let retry = try await h.collect(configuration, at: 331, trigger: .quickRetry)["acc-codex"]
        #expect(CodexLimitsHarness.requests(recovered) == 1)
        #expect(retry?.state == .live)
    }

    /// Refreshes without a request after the retry time but before the
    /// quick retry ran (the coordinator's timer fires at `retryAt + 1 s`)
    /// keep the grace period, and the quick retry still fetches (spec 010
    /// FR-005, FR-008, SC-001).
    @Test func refreshesWithoutARequestBeforeTheQuickRetryRanKeepRetrying() async throws {
        let h = try CodexLimitsHarness("codex-qr-window")
        defer { h.cleanUp() }
        let configuration = try await Self.inGrace(h)
        let retryAt = Self.start.addingTimeInterval(330)
        // A click on "Refresh now" would ask again (spec 021 FR-003).
        for trigger in [RefreshTrigger.local, .settings, .wake] {
            let entry = try await h.collect(configuration, at: 330.5, trigger: trigger)["acc-codex"]
            #expect(entry?.state == .retrying(reason: "offline", retryAt: retryAt), "\(trigger)")
            #expect(entry?.quickRetryAt == retryAt, "\(trigger)")
        }
        let recovered = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: recovered)
        let retried = try await h.collect(configuration, at: 331, trigger: .quickRetry)["acc-codex"]
        #expect(CodexLimitsHarness.requests(recovered) == 1)
        #expect(retried?.state == .live)
        #expect(retried?.quickRetryAt == nil)
    }

    @Test func quickRetryWhileRateLimitedIsStaleAndExhaustsTheEpisode() async throws {
        let h = try CodexLimitsHarness("codex-qr-blocked")
        defer { h.cleanUp() }
        let configuration = try await Self.inGrace(h)
        await h.source.block(home: h.home(), until: Self.start.addingTimeInterval(900))
        // Blocked before the retry time: still in grace.
        let before = try await h.collect(configuration, at: 310, trigger: .local)
        #expect(before["acc-codex"]?.state == .retrying(reason: "offline", retryAt: Self.start.addingTimeInterval(330)))
        // Blocked after the retry time, but the quick retry has not run yet.
        let waiting = try await h.collect(configuration, at: 330.5, trigger: .local)
        #expect(waiting["acc-codex"]?.state == .retrying(reason: "offline", retryAt: Self.start.addingTimeInterval(330)))
        #expect(waiting["acc-codex"]?.quickRetryAt == Self.start.addingTimeInterval(330))
        // Blocked at the retry time: stale with the transport reason.
        let suppressed = try await h.collect(configuration, at: 331, trigger: .quickRetry)
        #expect(suppressed["acc-codex"]?.state == .stale(reason: "offline"))
        #expect(suppressed["acc-codex"]?.quickRetryAt == nil)
        #expect(suppressed["acc-codex"]?.observation?.origin == .live)
        #expect(h.logText().contains("quick retry suppressed (rate limited)"))
        // The episode's retry is used: the next failure gets none.
        let later = try await h.collect(configuration, at: 1000)
        #expect(later["acc-codex"]?.state == .stale(reason: "offline"))
        #expect(later["acc-codex"]?.quickRetryAt == nil)
    }

    @Test func failedQuickRetryIsStaleWithoutAnotherRetry() async throws {
        let h = try CodexLimitsHarness("codex-qr-second")
        defer { h.cleanUp() }
        let configuration = try await Self.inGrace(h)
        let entry = try await h.collect(configuration, at: 331, trigger: .quickRetry)["acc-codex"]
        #expect(entry?.state == .stale(reason: "offline"))
        #expect(entry?.quickRetryAt == nil)
        let later = try await h.collect(configuration, at: 900)["acc-codex"]
        #expect(later?.state == .stale(reason: "offline"))
        #expect(later?.quickRetryAt == nil)
    }

    @Test func overdueGraceWithoutARequestIsExpired() async throws {
        let h = try CodexLimitsHarness("codex-qr-overdue")
        defer { h.cleanUp() }
        let configuration = try await Self.inGrace(h)
        let offline = CodexLimitsHarness.offlineStub()
        h.signIn(h.home(), token: offline)
        // Past retryAt + 30 s: a quick retry fired for another provider does not fetch.
        let late = try await h.collect(configuration, at: 361, trigger: .quickRetry)["acc-codex"]
        #expect(CodexLimitsHarness.requests(offline) == 0)
        #expect(late?.state == .stale(reason: "offline"))
        #expect(late?.quickRetryAt == nil)
    }

    @Test func serverErrorIsTransport() async throws {
        let h = try CodexLimitsHarness("codex-qr-503")
        defer { h.cleanUp() }
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        _ = try await h.collect(configuration)
        h.signIn(h.home(), token: CodexLimitsHarness.stub(status: 503, body: "{}"))
        let entry = try await h.collect(configuration, at: 300)["acc-codex"]
        #expect(entry?.state == .retrying(reason: "usage service unavailable (HTTP 503)", retryAt: Self.start.addingTimeInterval(330)))
    }

    @Test func serviceChangedGetsNoQuickRetry() async throws {
        let h = try CodexLimitsHarness("codex-qr-changed")
        defer { h.cleanUp() }
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        _ = try await h.collect(configuration)
        h.signIn(h.home(), token: CodexLimitsHarness.stub(body: "{\"plan_type\": \"plus\"}"))
        let noLimits = try await h.collect(configuration, at: 300)["acc-codex"]
        #expect(noLimits?.state == .stale(reason: "usage service reported no limits"))
        #expect(noLimits?.quickRetryAt == nil)

        let other = try CodexLimitsHarness("codex-qr-location")
        defer { other.cleanUp() }
        let otherConfiguration = Configuration(accounts: [CodexLimitsHarness.account(home: other.home())])
        other.signIn(other.home(), token: CodexLimitsHarness.stub())
        _ = try await other.collect(otherConfiguration)
        let token = "codex-src-location-\(UUID().uuidString)"
        StubURLProtocol.register(key: "Bearer \(token)", respondingFrom: URL(string: "https://elsewhere.example/x")!) { _ in
            (200, Data(codexUsageSampleJSON.utf8))
        }
        other.signIn(other.home(), token: token)
        let moved = try await other.collect(otherConfiguration, at: 300)["acc-codex"]
        #expect(moved?.state == .stale(reason: "usage service changed"))
        #expect(moved?.quickRetryAt == nil)
    }

    @Test func failuresBeforeARequestGetNoQuickRetry() async throws {
        let h = try CodexLimitsHarness("codex-qr-unclassified")
        defer { h.cleanUp() }
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        _ = try await h.collect(configuration)
        h.signIn(h.home(), token: "unused", expiresAt: Self.start)
        let expired = try await h.collect(configuration, at: 300)["acc-codex"]
        #expect(expired?.state == .stale(reason: CodexLimitsSource.expiredReason))
        #expect(expired?.quickRetryAt == nil)
        h.reader.set(h.home(), .success(.missing(reason: CodexCredentialLookup.keychain)))
        let missing = try await h.collect(configuration, at: 600)["acc-codex"]
        #expect(missing?.state == .stale(reason: CodexCredentialLookup.keychain))
        #expect(missing?.quickRetryAt == nil)
        // A rejected token, then the same token again (not sent).
        let rejected = CodexLimitsHarness.stub(status: 401, body: "{}")
        h.signIn(h.home(), token: rejected)
        let first = try await h.collect(configuration, at: 900)["acc-codex"]
        #expect(first?.state == .stale(reason: CodexLimitsSource.rejectedReason))
        #expect(first?.quickRetryAt == nil)
        let remembered = try await h.collect(configuration, at: 1200)["acc-codex"]
        #expect(CodexLimitsHarness.requests(rejected) == 1)
        #expect(remembered?.state == .stale(reason: CodexLimitsSource.rejectedReason))
        #expect(remembered?.quickRetryAt == nil)
    }
    /// Values shown stale by a failure before a request never become
    /// unmarked again, and a pending quick retry is dropped (spec 010
    /// FR-002, FR-005).
    @Test func failureBeforeARequestKeepsValuesStaleAndDropsTheRetry() async throws {
        let h = try CodexLimitsHarness("codex-qr-restale")
        defer { h.cleanUp() }
        let configuration = try await Self.inGrace(h)
        h.signIn(h.home(), token: "unused", expiresAt: Self.start)
        let expired = try await h.collect(configuration, at: 310)["acc-codex"]
        #expect(expired?.state == .stale(reason: CodexLimitsSource.expiredReason))
        #expect(expired?.quickRetryAt == nil)
        let local = try await h.collect(configuration, at: 315, trigger: .local)["acc-codex"]
        #expect(local?.state == .stale(reason: CodexLimitsSource.expiredReason))
        #expect(local?.quickRetryAt == nil)
        // Renewed sign-in, still offline: the values stay stale.
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        let again = try await h.collect(configuration, at: 900)["acc-codex"]
        #expect(again?.state == .stale(reason: "offline"))
    }
}

/// spec 010 FR-012: a rejected Codex sign-in uses the attention style.
@Suite struct CodexLimitsSourceRejectedTests {
    static let start = CodexLimitsHarness.start

    @Test func rejectedAnswersAndTheRememberedTokenSetTheFlag() async throws {
        for (status, reason) in [(401, CodexLimitsSource.rejectedReason), (403, CodexLimitsSource.rejectedSourceError)] {
            // Without an observation.
            let bare = try CodexLimitsHarness("codex-rej-bare-\(status)")
            defer { bare.cleanUp() }
            let bareConfig = Configuration(accounts: [CodexLimitsHarness.account(home: bare.home())])
            bare.signIn(bare.home(), token: CodexLimitsHarness.stub(status: status, body: "{}"))
            let none = try await bare.collect(bareConfig)["acc-codex"]
            #expect(none?.state == .unavailable(reason: reason))
            #expect(none?.signInRejected == true)

            // With an observation.
            let h = try CodexLimitsHarness("codex-rej-\(status)")
            defer { h.cleanUp() }
            let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
            h.signIn(h.home(), token: CodexLimitsHarness.stub())
            _ = try await h.collect(configuration)
            h.signIn(h.home(), token: CodexLimitsHarness.stub(status: status, body: "{}"))
            let rejected = try await h.collect(configuration, at: 300)["acc-codex"]
            #expect(rejected?.state == .stale(reason: reason))
            #expect(rejected?.signInRejected == true)
            #expect(rejected?.observation?.origin == .live)
            // A reprice keeps the flag.
            let reprice = try await h.collect(configuration, at: 310, trigger: .local)["acc-codex"]
            #expect(reprice?.signInRejected == true)
        }
    }

    @Test func rememberedRejectedTokenSetsTheFlag() async throws {
        let h = try CodexLimitsHarness("codex-rej-remembered")
        defer { h.cleanUp() }
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        let token = CodexLimitsHarness.stub(status: 401, body: "{}")
        h.signIn(h.home(), token: token)
        _ = try await h.collect(configuration)
        let remembered = try await h.collect(configuration, at: 300)["acc-codex"]
        #expect(CodexLimitsHarness.requests(token) == 1)
        #expect(remembered?.state == .unavailable(reason: CodexLimitsSource.rejectedReason))
        #expect(remembered?.signInRejected == true)
    }

    @Test func offlineFailureDoesNotSetTheFlag() async throws {
        let h = try CodexLimitsHarness("codex-rej-offline")
        defer { h.cleanUp() }
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        let entry = try await h.collect(configuration)["acc-codex"]
        #expect(entry?.signInRejected == false)
    }
}

/// spec 010 FR-005, FR-013, FR-015, FR-017: the last live result survives a relaunch.
@Suite struct CodexLimitsSourceSavedTests {
    static let start = CodexLimitsHarness.start

    static func source(_ h: CodexLimitsHarness, initial: LastGoodValues?) -> (CodexLimitsSource, LastGoodStore) {
        let store = LastGoodStore(fileURL: Paths(home: h.root).lastGoodFileURL, initial: initial, log: nil)
        let clock = h.clock
        let source = CodexLimitsSource(credentialReader: h.reader,
                                       client: CodexUsageClient(session: StubURLProtocol.makeSession(), userAgent: "AgentTacho/test"),
                                       log: h.log, paths: Paths(home: h.root), clock: { clock.now() }, store: store)
        return (source, store)
    }

    static func collect(_ source: CodexLimitsSource, _ configuration: Configuration, at offset: TimeInterval = 0,
                        trigger: RefreshTrigger = .scheduled) async throws -> [String: CodexLimitsEntry] {
        let context = RefreshContext(configuration: configuration, window: CodexLimitsHarness.window,
                                     now: start.addingTimeInterval(offset), trigger: trigger)
        guard case .codexLimits(let entries) = try await source.collect(context: context) else { return [:] }
        return entries
    }

    static func saved(_ home: String, observedAt: Date) -> SavedCodexValues {
        SavedCodexValues(codexHome: Attributor.canonical(home), observedAt: observedAt, planType: "pro", windows: [
            SavedCodexWindow(lengthMinutes: 300, usedPercent: 33, resetsAt: start.addingTimeInterval(3600), limitReached: false),
            SavedCodexWindow(lengthMinutes: 10080, usedPercent: 100, resetsAt: start.addingTimeInterval(86400), limitReached: true),
        ])
    }

    @Test func liveSuccessWritesItsWindows() async throws {
        let h = try CodexLimitsHarness("codex-saved-write")
        defer { h.cleanUp() }
        try FileManager.default.createDirectory(atPath: h.home(), withIntermediateDirectories: true)
        let (source, _) = Self.source(h, initial: nil)
        let token = CodexLimitsHarness.stub()
        let chatGPTAccountId = "chatgpt-acct-\(UUID().uuidString)"
        h.signIn(h.home(), token: token, accountId: chatGPTAccountId)
        _ = try await Self.collect(source, Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
        // SC-004: neither the token nor the ChatGPT account id sent with the
        // request is in the file (FR-014).
        let text = try String(contentsOf: Paths(home: h.root).lastGoodFileURL, encoding: .utf8)
        #expect(!text.contains(token))
        #expect(!text.contains(chatGPTAccountId))
        let (loaded, _) = LastGoodStore.load(from: Paths(home: h.root).lastGoodFileURL)
        let saved = try #require(loaded?.codex["acc-codex"])
        #expect(saved.codexHome == Attributor.canonical(h.home()))
        #expect(saved.observedAt == Self.start)
        #expect(saved.planType == "plus")
        #expect(saved.windows.map(\.lengthMinutes) == [300, 10080])
        #expect(saved.windows.map(\.limitReached) == [false, false])
    }

    @Test func savedLiveResultIsShownAndStaleAfterAFailedFirstFetch() async throws {
        let h = try CodexLimitsHarness("codex-saved-seed")
        defer { h.cleanUp() }
        let observed = Self.start.addingTimeInterval(-600)
        let (source, _) = Self.source(h, initial: LastGoodValues(codex: ["acc-codex": Self.saved(h.home(), observedAt: observed)]))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        guard case .codexLimits(let early)? = await source.savedOutput(configuration: configuration, now: Self.start) else {
            Issue.record("expected saved codex limits")
            return
        }
        #expect(early["acc-codex"]?.state == .live)
        #expect(early["acc-codex"]?.observation?.observedAt == observed)
        #expect(early["acc-codex"]?.observation?.planType == "pro")

        // The first fetch after launch fails with a transport error: stale, not retrying.
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        let failed = try await Self.collect(source, configuration)["acc-codex"]
        #expect(failed?.state == .stale(reason: "offline"))
        #expect(failed?.observation?.observedAt == observed)
        #expect(failed?.observation?.origin == .live)
        #expect(failed?.quickRetryAt == Self.start.addingTimeInterval(30))
    }

    @Test func savedLiveResultCompetesWithSnapshots() async throws {
        let h = try CodexLimitsHarness("codex-saved-compete")
        defer { h.cleanUp() }
        // Snapshot observed at 14:20:01.
        try CodexLimitsSourceFallbackTests.install("limits-plus.jsonl", into: h.home(), modified: isoDate("2026-10-14T14:20:02Z"))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        let (newer, _) = Self.source(h, initial: LastGoodValues(codex: ["acc-codex": Self.saved(h.home(), observedAt: isoDate("2026-10-14T14:50:00Z"))]))
        guard case .codexLimits(let liveWins)? = await newer.savedOutput(configuration: configuration, now: Self.start) else {
            Issue.record("expected saved codex limits"); return
        }
        #expect(liveWins["acc-codex"]?.state == .live)
        #expect(liveWins["acc-codex"]?.observation?.origin == .live)

        let (older, _) = Self.source(h, initial: LastGoodValues(codex: ["acc-codex": Self.saved(h.home(), observedAt: isoDate("2026-10-14T14:00:00Z"))]))
        guard case .codexLimits(let snapshotWins)? = await older.savedOutput(configuration: configuration, now: Self.start) else {
            Issue.record("expected saved codex limits"); return
        }
        #expect(snapshotWins["acc-codex"]?.state == .newerSnapshot)
        #expect(snapshotWins["acc-codex"]?.observation?.origin == .snapshot)
    }

    @Test func futureObservationTimeIsClampedToNow() async throws {
        let h = try CodexLimitsHarness("codex-saved-future")
        defer { h.cleanUp() }
        let (source, _) = Self.source(h, initial: LastGoodValues(codex: ["acc-codex": Self.saved(h.home(), observedAt: Self.start.addingTimeInterval(3600))]))
        guard case .codexLimits(let early)? = await source.savedOutput(configuration: Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]),
                                                                      now: Self.start) else {
            Issue.record("expected saved codex limits"); return
        }
        #expect(early["acc-codex"]?.observation?.observedAt == Self.start)
    }

    @Test func liveLimitsOffDiscardsTheSavedResult() async throws {
        let h = try CodexLimitsHarness("codex-saved-off")
        defer { h.cleanUp() }
        let (source, _) = Self.source(h, initial: LastGoodValues(codex: ["acc-codex": Self.saved(h.home(), observedAt: Self.start)]))
        let off = Configuration(accounts: [CodexLimitsHarness.account(home: h.home(), liveLimits: false)])
        #expect(await source.savedOutput(configuration: off, now: Self.start) == nil)
        let entry = try await Self.collect(source, off)["acc-codex"]
        #expect(entry?.state == .unavailable(reason: CodexLimitsSource.noLocalLimitsReason))
        let (loaded, _) = LastGoodStore.load(from: Paths(home: h.root).lastGoodFileURL)
        #expect(loaded?.codex.isEmpty == true)
    }

    @Test func savedResultOfAnotherHomeIsIgnored() async throws {
        let h = try CodexLimitsHarness("codex-saved-home")
        defer { h.cleanUp() }
        let (source, _) = Self.source(h, initial: LastGoodValues(codex: ["acc-codex": Self.saved("/somewhere/else", observedAt: Self.start)]))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        #expect(await source.savedOutput(configuration: configuration, now: Self.start) == nil)
        h.signIn(h.home(), token: CodexLimitsHarness.offlineStub())
        let entry = try await Self.collect(source, configuration)["acc-codex"]
        #expect(entry?.observation == nil)
    }
}


/// spec 016 FR-006, FR-011, FR-012, research R4 to R6: the adaptive pace
/// gates scheduled Codex requests, the new triggers are spaced like wake,
/// and `reachedService` marks answers that are not transport failures.
@Suite struct CodexLimitsAdaptivePaceTests {
    @Test func paceNotDueSkipsTheScheduledRequestWithoutStaleMarking() async throws {
        let h = try CodexLimitsHarness("codex-pace-notdue")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        let first = try await h.collect(configuration)
        #expect(first["acc-codex"]?.reachedService == true)
        let paced = try await h.collect(configuration, at: 300, codexPaceDue: false)
        #expect(CodexLimitsHarness.requests(token) == 1)
        #expect(paced["acc-codex"]?.state == .live)
        #expect(paced["acc-codex"]?.reachedService == false)
        #expect(h.logText().contains("no request due (adaptive pace)"))
        _ = try await h.collect(configuration, at: 600)
        #expect(CodexLimitsHarness.requests(token) == 2)
    }

    @Test func newAccountOrChangedHomeStillFetchesOnce() async throws {
        let h = try CodexLimitsHarness("codex-pace-new")
        defer { h.cleanUp() }
        let first = CodexLimitsHarness.stub()
        let second = CodexLimitsHarness.stub()
        h.signIn(h.home(".codex"), token: first)
        h.signIn(h.home(".codex-two"), token: second)
        var configuration = Configuration(accounts: [CodexLimitsHarness.account("acc-one", home: h.home(".codex"))])
        _ = try await h.collect(configuration)
        configuration.accounts.append(CodexLimitsHarness.account("acc-two", home: h.home(".codex-two")))
        _ = try await h.collect(configuration, at: 300, codexPaceDue: false)
        #expect(CodexLimitsHarness.requests(first) == 1)
        #expect(CodexLimitsHarness.requests(second) == 1)
        configuration.accounts[0] = CodexLimitsHarness.account("acc-one", home: h.home(".codex-two"))
        _ = try await h.collect(configuration, at: 600, codexPaceDue: false)
        #expect(CodexLimitsHarness.requests(second) == 2, "a changed home fetches once")
    }

    @Test(arguments: [RefreshTrigger.manual, .launch, .wake, .settings, .dropdownOpen, .idleReturn])
    func paceIsIgnoredForOtherTriggers(trigger: RefreshTrigger) async throws {
        let h = try CodexLimitsHarness("codex-pace-other")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        _ = try await h.collect(configuration, at: 120, trigger: trigger, codexPaceDue: false)
        #expect(CodexLimitsHarness.requests(token) == 2, "trigger \(trigger)")
    }

    @Test(arguments: [RefreshTrigger.dropdownOpen, .idleReturn])
    func newTriggersAreSpacedPerHomeAndBlocked(trigger: RefreshTrigger) async throws {
        let h = try CodexLimitsHarness("codex-pace-spaced")
        defer { h.cleanUp() }
        let token = CodexLimitsHarness.stub()
        h.signIn(h.home(), token: token)
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        let spaced = try await h.collect(configuration, at: 59, trigger: trigger)
        #expect(CodexLimitsHarness.requests(token) == 1)
        #expect(spaced["acc-codex"]?.state == .live)
        _ = try await h.collect(configuration, at: 60, trigger: trigger)
        #expect(CodexLimitsHarness.requests(token) == 2)
        await h.source.block(home: h.home(), until: CodexLimitsHarness.start.addingTimeInterval(900))
        _ = try await h.collect(configuration, at: 300, trigger: trigger)
        #expect(CodexLimitsHarness.requests(token) == 2, "never during a block")
    }

    @Test func reachedServiceFollowsTheAnswer() async throws {
        let cases: [(String, () -> String, Bool)] = [
            ("success", { CodexLimitsHarness.stub() }, true),
            ("401", { CodexLimitsHarness.stub(status: 401, body: "{}") }, true),
            ("429", { CodexLimitsHarness.stub(status: 429, body: "{}") }, true),
            ("unreadable", { CodexLimitsHarness.stub(body: "not json") }, true),
            ("offline", { CodexLimitsHarness.offlineStub() }, false),
            ("503", { CodexLimitsHarness.stub(status: 503, body: "") }, false),
        ]
        for (name, makeToken, expected) in cases {
            let h = try CodexLimitsHarness("codex-reached-\(name)")
            defer { h.cleanUp() }
            h.signIn(h.home(), token: makeToken())
            let entries = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))
            #expect(entries["acc-codex"]?.reachedService == expected, "\(name)")
            // Every due fetch is a try, whatever the answer.
            #expect(entries["acc-codex"]?.attempted == true, "\(name)")
        }
        let h = try CodexLimitsHarness("codex-reached-none")
        defer { h.cleanUp() }
        h.signIn(h.home(".codex-expired"), token: CodexLimitsHarness.stub(), expiresAt: Date(timeIntervalSince1970: 1))
        let entries = try await h.collect(Configuration(accounts: [
            CodexLimitsHarness.account("acc-missing", home: h.home()),
            CodexLimitsHarness.account("acc-expired", home: h.home(".codex-expired")),
            CodexLimitsHarness.account("acc-off", home: h.home(".codex-off"), liveLimits: false),
        ]))
        #expect(entries["acc-missing"]?.reachedService == false)
        #expect(entries["acc-expired"]?.reachedService == false)
        #expect(entries["acc-off"]?.reachedService == false)
        // A missing or expired sign-in is a try without a request (spec 016
        // FR-012, FR-014); live limits off is none.
        #expect(entries["acc-missing"]?.attempted == true)
        #expect(entries["acc-expired"]?.attempted == true)
        #expect(entries["acc-off"]?.attempted == false)
        var carried = CodexLimitsEntry(observation: nil, state: .live)
        carried.reachedService = true
        carried.attempted = true
        #expect(carried.markedStale(reason: "x").reachedService == false)
        #expect(carried.markedStale(reason: "x").attempted == false)
    }

    /// A scheduled refresh held back by the pace is no try.
    @Test func pacedSkipIsNoTry() async throws {
        let h = try CodexLimitsHarness("codex-pace-notry")
        defer { h.cleanUp() }
        h.signIn(h.home(), token: CodexLimitsHarness.stub())
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        let paced = try await h.collect(configuration, at: 300, codexPaceDue: false)
        #expect(paced["acc-codex"]?.attempted == false)
    }
}

/// spec 014 FR-001, FR-005, FR-009: entries built from a failure before a
/// request carry the credential problem as a typed value.
@Suite struct CodexLimitsSourceCredentialProblemTests {
    static let start = CodexLimitsHarness.start

    @Test func missingSignInIsNotSignedIn() async throws {
        let h = try CodexLimitsHarness("codex-problem-missing")
        defer { h.cleanUp() }
        h.reader.set(h.home(), .success(.missing(reason: CodexCredentialLookup.noPlanSignIn)))
        let entry = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))["acc-codex"]
        #expect(entry?.credentialProblem == .notSignedIn)
    }

    /// The real reader reports keychain storage from `config.toml`.
    @Test func signInInTheKeychainIsKeychain() async throws {
        let root = try makeTempDirectory("codex-problem-keychain")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(home: root)
        let home = root.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("cli_auth_credentials_store = \"keyring\"\n".utf8).write(to: home.appendingPathComponent("config.toml"))
        let source = CodexLimitsSource(credentialReader: FileCodexCredentialReader(paths: paths),
                                       client: CodexUsageClient(session: StubURLProtocol.makeSession(), userAgent: "AgentTacho/test"),
                                       paths: paths, clock: { Self.start })
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: home.path)])
        let context = RefreshContext(configuration: configuration, window: CodexLimitsHarness.window, now: Self.start, trigger: .scheduled)
        guard case .codexLimits(let entries) = try await source.collect(context: context) else {
            Issue.record("expected codex limits"); return
        }
        #expect(entries["acc-codex"]?.credentialProblem == .keychain)
    }

    @Test func expiredTokenCarriesItsExpiry() async throws {
        let h = try CodexLimitsHarness("codex-problem-expired")
        defer { h.cleanUp() }
        let expiresAt = Self.start.addingTimeInterval(-3600)
        h.signIn(h.home(), token: CodexLimitsHarness.stub(), expiresAt: expiresAt)
        let entry = try await h.collect(Configuration(accounts: [CodexLimitsHarness.account(home: h.home())]))["acc-codex"]
        #expect(entry?.credentialProblem == .expired(at: expiresAt))
    }

    @Test func requestOutcomesAndUnreadableSignInsHaveNoProblem() async throws {
        let h = try CodexLimitsHarness("codex-problem-none")
        defer { h.cleanUp() }
        h.signIn(h.home(".codex-ok"), token: CodexLimitsHarness.stub())
        h.signIn(h.home(".codex-401"), token: CodexLimitsHarness.stub(status: 401, body: "{}"))
        h.signIn(h.home(".codex-down"), token: CodexLimitsHarness.offlineStub())
        h.reader.set(h.home(".codex-broken"), .failure(FakeCodexCredentialReader.Failure()))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account("ok", home: h.home(".codex-ok")),
                                                     CodexLimitsHarness.account("rejected", home: h.home(".codex-401")),
                                                     CodexLimitsHarness.account("down", home: h.home(".codex-down")),
                                                     CodexLimitsHarness.account("broken", home: h.home(".codex-broken"))])
        let first = try await h.collect(configuration)
        #expect(first["ok"]?.state == .live)
        #expect(first["rejected"]?.signInRejected == true)
        for id in ["ok", "rejected", "down", "broken"] {
            #expect(first[id] != nil, "\(id)")
            #expect(first[id]?.credentialProblem == nil, "\(id)")
        }
        // The token already rejected is not sent again and has no problem either.
        let second = try await h.collect(configuration, at: 300)
        #expect(second["rejected"]?.signInRejected == true)
        #expect(second["rejected"]?.credentialProblem == nil)
    }

    @Test func markedStaleKeepsTheProblem() {
        let entry = CodexLimitsEntry(observation: nil, state: .unavailable(reason: "x"), credentialProblem: .notSignedIn)
        #expect(entry.markedStale(reason: "y").credentialProblem == .notSignedIn)
        let live = CodexLimitsEntry(observation: nil, state: .live)
        #expect(live.markedStale(reason: "y").credentialProblem == nil)
    }

    /// A refresh without a due request shows the last failure again,
    /// problem included.
    @Test func notDueRefreshKeepsTheProblem() async throws {
        let h = try CodexLimitsHarness("codex-problem-notdue")
        defer { h.cleanUp() }
        h.reader.set(h.home(), .success(.missing(reason: CodexCredentialLookup.keychain)))
        let configuration = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        _ = try await h.collect(configuration)
        let reprice = try await h.collect(configuration, at: 10, trigger: .local)["acc-codex"]
        #expect(h.reader.reads.count == 1)
        #expect(reprice?.credentialProblem == .keychain)
    }
}

/// spec 033 FR-001, FR-003, FR-005, FR-006, FR-019, SC-004, SC-005: the
/// Codex reset credit request after a successful plan-limit request, and
/// the tickets on the entries.
@Suite struct CodexLimitsSourceTicketTests {
    typealias H = CodexLimitsHarness
    static let expiry = H.start.addingTimeInterval(2 * 86400)
    static let creditsJSON = """
    { "available_count": 2, "credits": [
      { "id": "CREDIT-ID-SENTINEL", "status": "available", "expires_at": "\(ISO8601DateFormatter().string(from: expiry))" },
      { "id": "CREDIT-ID-SENTINEL-2", "status": "available" } ] }
    """
    static let tickets = [ResetTicket(expiresAt: expiry), ResetTicket(expiresAt: nil)]

    /// A token whose plan-limit requests get `usage` and credit requests
    /// get `credits`.
    static func stub(usage: @escaping @Sendable () throws -> (Int, Data) = { (200, Data(codexUsageSampleJSON.utf8)) },
                     credits: @escaping @Sendable () throws -> (Int, Data) = { (200, Data(creditsJSON.utf8)) }) -> String {
        let token = "codex-tickets-\(UUID().uuidString)"
        answer(token, usage: usage, credits: credits)
        return token
    }

    static func answer(_ token: String, usage: @escaping @Sendable () throws -> (Int, Data) = { (200, Data(codexUsageSampleJSON.utf8)) },
                       credits: @escaping @Sendable () throws -> (Int, Data) = { (200, Data(creditsJSON.utf8)) }) {
        StubURLProtocol.register(key: "Bearer \(token)") { request in
            request.url?.path.contains("rate-limit-reset-credits") == true ? try credits() : try usage()
        }
    }

    static func credits(_ token: String) -> Int { StubURLProtocol.resetCreditRequests(key: "Bearer \(token)").count }

    static func config(_ accounts: Account...) -> Configuration { Configuration(accounts: accounts) }

    @Test func creditsFollowASuccessfulPlanLimitRequest() async throws {
        let h = try H("codex-tickets-ok", clockedClient: true)
        defer { h.cleanUp() }
        let token = Self.stub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let entry = try await h.collect(Self.config(H.account(home: h.home())))["acc-codex"]
        #expect(entry?.state == .live)
        #expect(entry?.resetTickets == Self.tickets)
        #expect(H.requests(token) == 1)
        #expect(Self.credits(token) == 1)
        let request = try #require(StubURLProtocol.resetCreditRequests(key: "Bearer \(token)").first)
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")
    }

    @Test func noCreditRequestWithLiveLimitsOff() async throws {
        let h = try H("codex-tickets-off", clockedClient: true)
        defer { h.cleanUp() }
        let token = Self.stub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        _ = try await h.collect(Self.config(H.account(home: h.home())))
        let off = try await h.collect(Self.config(H.account(home: h.home(), liveLimits: false)), at: 600)["acc-codex"]
        #expect(off?.resetTickets == [])
        #expect(Self.credits(token) == 1)
        #expect(h.reader.reads.count == 1)
    }

    @Test func failedOrSkippedPlanLimitRequestsSendNoCreditRequest() async throws {
        let h = try H("codex-tickets-skip", clockedClient: true)
        defer { h.cleanUp() }
        let token = Self.stub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let config = Self.config(H.account(home: h.home()))
        _ = try await h.collect(config)
        // A failed plan-limit request: no credit request, tickets kept.
        Self.answer(token, usage: { (500, Data()) })
        let failed = try await h.collect(config, at: 600)["acc-codex"]
        #expect(Self.credits(token) == 0)
        #expect(failed?.resetTickets == Self.tickets)
        // No sign-in: no request at all, tickets kept.
        h.reader.set(h.home(), .success(.missing(reason: CodexCredentialLookup.noPlanSignIn)))
        let missing = try await h.collect(config, at: 1200)["acc-codex"]
        #expect(missing?.resetTickets == Self.tickets)
        // Not due (adaptive pace) and blocked: kept minus expired.
        h.signIn(h.home(), token: token)
        Self.answer(token)
        _ = try await h.collect(config, at: 1800)
        let (plansBefore, creditsBefore) = (H.requests(token), Self.credits(token))
        let notDue = try await h.collect(config, at: 2 * 86400 + 60, codexPaceDue: false)["acc-codex"]
        // Kept, not read again: the not-due refresh sends no request.
        #expect(H.requests(token) == plansBefore)
        #expect(Self.credits(token) == creditsBefore)
        #expect(notDue?.resetTickets == [ResetTicket(expiresAt: nil)])
        Self.answer(token, usage: { (429, Data()) })
        _ = try await h.collect(config, at: 2 * 86400 + 120)
        let blocked = try await h.collect(config, at: 2 * 86400 + 180)["acc-codex"]
        #expect(blocked?.resetTickets == [ResetTicket(expiresAt: nil)])
        #expect(Self.credits(token) == 0)
        let log = h.logText()
        #expect(log.components(separatedBy: "acc-codex: free reset tickets not read (skipped)").count == 2)
    }

    @Test func twoAccountsOnOneHomeShareOneRequest() async throws {
        let h = try H("codex-tickets-shared", clockedClient: true)
        defer { h.cleanUp() }
        let token = Self.stub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let entries = try await h.collect(Self.config(H.account("acc-a", home: h.home()), H.account("acc-b", home: h.home())))
        #expect(entries["acc-a"]?.resetTickets == Self.tickets)
        #expect(entries["acc-b"]?.resetTickets == Self.tickets)
        #expect(Self.credits(token) == 1)
    }

    @Test func clearingFailureEmptiesTheTickets() async throws {
        let h = try H("codex-tickets-clear", clockedClient: true)
        defer { h.cleanUp() }
        let token = Self.stub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let config = Self.config(H.account(home: h.home()))
        _ = try await h.collect(config)
        Self.answer(token, credits: { (200, Data("{ \"credits\": 5 }".utf8)) })
        let cleared = try await h.collect(config, at: 600)["acc-codex"]
        #expect(cleared?.state == .live)
        #expect(cleared?.resetTickets == [])
        // A later temporary failure has nothing to keep.
        Self.answer(token, credits: { (500, Data()) })
        #expect(try await h.collect(config, at: 1200)["acc-codex"]?.resetTickets == [])
        let log = h.logText()
        #expect(log.contains("acc-codex: free reset tickets not read (malformed)"))
        #expect(log.contains("acc-codex: free reset tickets not read (http-500)"))
        #expect(!log.contains("CREDIT-ID-SENTINEL"))
        #expect(!log.contains(token))
    }

    @Test func savedValuesHoldNoTickets() async throws {
        let root = try makeTempDirectory("codex-lg-store")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("last-good.json")
        let h = try H("codex-lg-source", clockedClient: true, store: LastGoodStore(fileURL: file, initial: nil, log: nil))
        defer { h.cleanUp() }
        let token = Self.stub()
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        h.signIn(h.home(), token: token)
        let entry = try await h.collect(Self.config(H.account(home: h.home())))["acc-codex"]
        #expect(entry?.resetTickets.count == 2)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("acc-codex"))
        #expect(!text.contains("ticket"))
        #expect(!text.contains("credit"))
        #expect(!text.contains("CREDIT-ID-SENTINEL"))
    }

    /// SC-004: a failed credit request leaves the entry and the per-home
    /// request decisions as the same refreshes without the credit request.
    @Test func failedCreditRequestsLeaveThePlanLimitsUnchanged() async throws {
        let failures: [(String, @Sendable () throws -> (Int, Data))] = [
            ("401", { (401, Data()) }), ("429", { (429, Data()) }), ("500", { (500, Data()) }),
            ("timeout", { throw URLError(.timedOut) }),
        ]
        func shown(_ entry: CodexLimitsEntry?) -> String {
            String(describing: (entry?.state, entry?.observation, entry?.credentialProblem, entry?.signInRejected, entry?.sourceError,
                                entry?.quickRetryAt, entry?.reachedService, entry?.attempted))
        }
        for (name, failure) in failures {
            let h = try H("codex-tickets-sc004-\(name)", clockedClient: true)
            let control = try H("codex-tickets-sc004-control-\(name)", clockedClient: true)
            defer { h.cleanUp(); control.cleanUp() }
            let token = Self.stub(credits: failure)
            let controlToken = Self.stub(credits: { (200, Data("{ \"credits\": [] }".utf8)) })
            defer { StubURLProtocol.unregister(key: "Bearer \(token)"); StubURLProtocol.unregister(key: "Bearer \(controlToken)") }
            h.signIn(h.home(), token: token)
            control.signIn(control.home(), token: controlToken)
            // Fetch, a wake within the spacing, a scheduled one, a manual one.
            let steps: [(TimeInterval, RefreshTrigger)] = [(0, .scheduled), (60, .wake), (120, .scheduled), (180, .manual), (240, .scheduled)]
            for (offset, trigger) in steps {
                let entry = try await h.collect(Self.config(H.account(home: h.home())), at: offset, trigger: trigger)["acc-codex"]
                let expected = try await control.collect(Self.config(H.account(home: control.home())), at: offset, trigger: trigger)["acc-codex"]
                #expect(shown(entry) == shown(expected), "\(name) at \(offset)")
            }
            #expect(H.requests(token) == H.requests(controlToken), "\(name)")
            #expect(H.requests(token) >= 3, "\(name)")
        }
    }
}
