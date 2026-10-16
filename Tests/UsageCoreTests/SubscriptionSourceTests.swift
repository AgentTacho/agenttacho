import Foundation
import Testing
@testable import UsageCore

final class FakeCredentialReader: CredentialReader, @unchecked Sendable {
    var credentials: [String: OAuthCredential?] = [:]
    var error: Error?
    struct ReadFailure: Error {}

    func read(configDirectory: String) throws -> OAuthCredential? {
        if let error { throw error }
        return credentials[configDirectory] ?? nil
    }
}

@Suite struct SubscriptionSourceTests {
    static let secret = "SECRET-TOKEN-123"
    let far = Date(timeIntervalSince1970: 4_000_000_000)

    private func makeConfig(directories: [String] = ["~/.claude"]) -> Configuration {
        var config = Configuration()
        config.accounts = directories.enumerated().map { index, dir in
            Account(id: "acc-\(index)", displayName: "Account \(index)",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: dir, shownInBar: true, thresholds: [])))
        }
        return config
    }

    private func context(_ config: Configuration, trigger: RefreshTrigger = .scheduled) -> RefreshContext {
        RefreshContext(configuration: config, window: DateInterval(start: Date(), duration: 1), now: Date(), trigger: trigger)
    }

    private func makeSource(reader: FakeCredentialReader, token: String, logDir: URL,
                            now: @escaping @Sendable () -> Date = { Date() }) -> (SubscriptionSource, DiagnosticLog) {
        let log = DiagnosticLog(fileURL: logDir.appendingPathComponent("usage.log"))
        let client = UsageEndpointClient(session: StubURLProtocol.makeSession())
        let source = SubscriptionSource(credentialReader: reader, client: client, log: log, clock: now)
        return (source, log)
    }

    private func entries(_ output: SourceOutput) -> [String: SubscriptionEntry] {
        if case .subscriptions(let e) = output { return e }
        Issue.record("expected subscriptions output")
        return [:]
    }

    @Test func missingCredentialYieldsNotSignedIn() async throws {
        let dir = try makeTempDirectory("sub-nosign")
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = FakeCredentialReader()
        let (source, _) = makeSource(reader: reader, token: "none", logDir: dir)
        let out = entries(try await source.collect(context: context(makeConfig())))
        #expect(out["acc-0"]?.state == .notSignedIn)
        #expect(out["acc-0"]?.status == nil)
    }

    @Test func expiredCredentialSkipsRequest() async throws {
        let dir = try makeTempDirectory("sub-expired")
        defer { try? FileManager.default.removeItem(at: dir) }
        let token = "expired-\(Self.secret)"
        StubURLProtocol.register(key: "Bearer \(token)") { _ in (200, Data(usageResponseJSON.utf8)) }
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let reader = FakeCredentialReader()
        reader.credentials["~/.claude"] = OAuthCredential(accessToken: token, expiresAt: Date(timeIntervalSince1970: 1))
        let (source, _) = makeSource(reader: reader, token: token, logDir: dir)
        let out = entries(try await source.collect(context: context(makeConfig())))
        #expect(out["acc-0"]?.state == .credentialsExpired)
        #expect(StubURLProtocol.recordedRequests(key: "Bearer \(token)").isEmpty)
    }

    @Test func successThenFailureThenRecovery() async throws {
        let dir = try makeTempDirectory("sub-recover")
        defer { try? FileManager.default.removeItem(at: dir) }
        let token = "recover-\(Self.secret)"
        StubURLProtocol.register(key: "Bearer \(token)") { _ in (200, Data(usageResponseJSON.utf8)) }
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let reader = FakeCredentialReader()
        reader.credentials["~/.claude"] = OAuthCredential(accessToken: token, expiresAt: far)
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let (source, log) = makeSource(reader: reader, token: token, logDir: dir, now: { t1 })

        let first = entries(try await source.collect(context: context(makeConfig())))
        #expect(first["acc-0"]?.state == .ok)
        #expect(first["acc-0"]?.status?.sevenDay?.utilizationPercent == 50.4)
        #expect(first["acc-0"]?.status?.fetchedAt == t1)

        // spec 010 FR-005: a 503 after a success keeps the values unmarked
        // until the quick retry.
        StubURLProtocol.register(key: "Bearer \(token)") { _ in (503, Data()) }
        let second = entries(try await source.collect(context: context(makeConfig())))
        guard case .retrying(let lastGoodAt, let error, _) = second["acc-0"]?.state else {
            Issue.record("expected retrying, got \(String(describing: second["acc-0"]?.state))")
            return
        }
        #expect(lastGoodAt == t1)
        #expect(error.contains("503"))
        #expect(second["acc-0"]?.status?.sevenDay?.utilizationPercent == 50.4)

        StubURLProtocol.register(key: "Bearer \(token)") { _ in (200, Data(usageResponseJSON.utf8)) }
        let third = entries(try await source.collect(context: context(makeConfig())))
        #expect(third["acc-0"]?.state == .ok)

        // FR-011a: nothing that leaves the source carries the token.
        let logText = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(!logText.contains(Self.secret))
        #expect(!String(describing: first).contains(Self.secret))
        #expect(!String(describing: second).contains(Self.secret))
        #expect(!String(describing: third).contains(Self.secret))
    }

    @Test func failureWithoutPriorSuccessHasNoLastGoodTime() async throws {
        let dir = try makeTempDirectory("sub-firstfail")
        defer { try? FileManager.default.removeItem(at: dir) }
        let token = "firstfail-\(Self.secret)"
        // spec 021 FR-008: the token also sits in the error's user info,
        // which must not reach the log with the error detail.
        StubURLProtocol.register(key: "Bearer \(token)") { _ in throw offlineErrorWithDetail(secret: token) }
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let reader = FakeCredentialReader()
        reader.credentials["~/.claude"] = OAuthCredential(accessToken: token, expiresAt: far)
        let (source, log) = makeSource(reader: reader, token: token, logDir: dir)
        let out = entries(try await source.collect(context: context(makeConfig())))
        guard case .stale(let lastGoodAt, let error) = out["acc-0"]?.state else {
            Issue.record("expected stale")
            return
        }
        #expect(lastGoodAt == nil)
        #expect(!error.isEmpty)
        #expect(!error.contains(Self.secret))
        #expect(out["acc-0"]?.status == nil)
        let logText = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(!logText.contains(Self.secret))
        #expect(!logText.contains("leak.example"))
        #expect(!String(describing: out).contains(Self.secret))
    }

    /// spec 021 FR-007, SC-003: the log line of a no-answer failure names
    /// the error domain, code, underlying error and stream code; the
    /// entry's error text stays today's.
    @Test func noAnswerFailureLogsTheErrorDetail() async throws {
        let dir = try makeTempDirectory("sub-detail")
        defer { try? FileManager.default.removeItem(at: dir) }
        let token = "detail-\(Self.secret)"
        StubURLProtocol.register(key: "Bearer \(token)") { _ in throw offlineErrorWithDetail(secret: token) }
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let reader = FakeCredentialReader()
        reader.credentials["~/.claude"] = OAuthCredential(accessToken: token, expiresAt: far)
        let (source, log) = makeSource(reader: reader, token: token, logDir: dir)
        let out = entries(try await source.collect(context: context(makeConfig())))
        let today = UsageEndpointError.network(offlineDescription).description
        #expect(out["acc-0"]?.state == .stale(lastGoodAt: nil, error: today))
        let logText = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(logText.contains("fetch failed (transport): \(today) [NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009; stream error 50]"))
        #expect(!logText.contains(Self.secret))
        #expect(!String(describing: out).contains("NSURLErrorDomain"))
    }

    @Test func oneAccountFailingDoesNotHideTheOther() async throws {
        let dir = try makeTempDirectory("sub-two")
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = "good-\(Self.secret)"
        let bad = "bad-\(Self.secret)"
        StubURLProtocol.register(key: "Bearer \(good)") { _ in (200, Data(usageResponseJSON.utf8)) }
        StubURLProtocol.register(key: "Bearer \(bad)") { _ in (500, Data()) }
        defer {
            StubURLProtocol.unregister(key: "Bearer \(good)")
            StubURLProtocol.unregister(key: "Bearer \(bad)")
        }
        let reader = FakeCredentialReader()
        reader.credentials["~/.claude"] = OAuthCredential(accessToken: good, expiresAt: far)
        reader.credentials["~/other"] = OAuthCredential(accessToken: bad, expiresAt: far)
        let (source, log) = makeSource(reader: reader, token: good, logDir: dir)
        let out = entries(try await source.collect(context: context(makeConfig(directories: ["~/.claude", "~/other"]))))
        #expect(out.count == 2)
        #expect(out["acc-0"]?.state == .ok)
        guard case .stale = out["acc-1"]?.state else {
            Issue.record("expected stale for the failing account")
            return
        }
        let logText = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(!logText.contains(Self.secret))
        #expect(!String(describing: out).contains(Self.secret))
    }

    @Test func keychainReadErrorIsReportedWithoutToken() async throws {
        let dir = try makeTempDirectory("sub-keychain")
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = FakeCredentialReader()
        reader.error = FakeCredentialReader.ReadFailure()
        let (source, _) = makeSource(reader: reader, token: "x", logDir: dir)
        let out = entries(try await source.collect(context: context(makeConfig())))
        guard case .stale(let lastGoodAt, _) = out["acc-0"]?.state else {
            Issue.record("expected stale")
            return
        }
        #expect(lastGoodAt == nil)
    }

    @Test func fetchOutcomePerAccount() async throws {
        let dir = try makeTempDirectory("sub-outcome")
        defer { try? FileManager.default.removeItem(at: dir) }
        let okToken = "outcome-ok-\(Self.secret)"
        let limitedToken = "outcome-429-\(Self.secret)"
        let brokenToken = "outcome-net-\(Self.secret)"
        StubURLProtocol.register(key: "Bearer \(okToken)") { _ in (200, Data(usageResponseJSON.utf8)) }
        StubURLProtocol.register(key: "Bearer \(limitedToken)", headers: ["Retry-After": "30"]) { _ in (429, Data("{}".utf8)) }
        StubURLProtocol.register(key: "Bearer \(brokenToken)") { _ in throw URLError(.notConnectedToInternet) }
        defer {
            for t in [okToken, limitedToken, brokenToken] { StubURLProtocol.unregister(key: "Bearer \(t)") }
        }
        let reader = FakeCredentialReader()
        reader.credentials["~/a"] = OAuthCredential(accessToken: okToken, expiresAt: far)
        reader.credentials["~/b"] = OAuthCredential(accessToken: limitedToken, expiresAt: far)
        reader.credentials["~/c"] = OAuthCredential(accessToken: brokenToken, expiresAt: far)
        let (source, _) = makeSource(reader: reader, token: okToken, logDir: dir)
        let out = entries(try await source.collect(context: context(makeConfig(directories: ["~/a", "~/b", "~/c", "~/none"]))))
        #expect(out["acc-0"]?.fetchOutcome == .success)
        #expect(out["acc-1"]?.fetchOutcome == .rateLimited(retryAfter: 30))
        #expect(out["acc-2"]?.fetchOutcome == .otherError)
        #expect(out["acc-3"]?.state == .notSignedIn)
        #expect(out["acc-3"]?.fetchOutcome == nil)
    }
    // MARK: Grace expiry (spec 010 FR-007, research R3)

    @Test func endingGraceTurnsAnOverdueRetryingEntryStale() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 40, resetsAt: nil), fetchedAt: t0)
        let retryAt = t0.addingTimeInterval(30)
        let entry = SubscriptionEntry(status: status, state: .retrying(lastGoodAt: t0, error: "offline", retryAt: retryAt),
                                      quickRetryAt: retryAt)
        let ended = entry.endingGrace(now: retryAt)
        #expect(ended.state == .stale(lastGoodAt: t0, error: "offline"))
        #expect(ended.status == status)
        #expect(entry.endingGrace(now: retryAt.addingTimeInterval(60)).state == .stale(lastGoodAt: t0, error: "offline"))
        // Before the retry time, and for every other state, nothing changes.
        #expect(entry.endingGrace(now: retryAt.addingTimeInterval(-1)) == entry)
        for state in [SubscriptionState.ok, .stale(lastGoodAt: t0, error: "x"), .notSignedIn, .credentialsExpired, .signInRejected(lastGoodAt: t0)] {
            let other = SubscriptionEntry(status: status, state: state)
            #expect(other.endingGrace(now: retryAt.addingTimeInterval(600)) == other)
        }
    }

    /// A reused entry's retry has not been attempted: it keeps its grace
    /// period and retry time until the retry's due window has passed
    /// (spec 010 FR-005, FR-007, FR-008).
    @Test func reusedEntryKeepsItsGraceUntilTheDueWindowPassed() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 40, resetsAt: nil), fetchedAt: t0)
        let retryAt = t0.addingTimeInterval(30)
        let entry = SubscriptionEntry(status: status, state: .retrying(lastGoodAt: t0, error: "offline", retryAt: retryAt),
                                      quickRetryAt: retryAt)
        #expect(entry.reused(now: retryAt.addingTimeInterval(-1)) == entry)
        #expect(entry.reused(now: retryAt.addingTimeInterval(0.5)) == entry)
        #expect(entry.reused(now: retryAt.addingTimeInterval(29)) == entry)
        let overdue = entry.reused(now: retryAt.addingTimeInterval(RetryEpisodes.delay))
        #expect(overdue.state == .stale(lastGoodAt: t0, error: "offline"))
        #expect(overdue.quickRetryAt == nil)
        // A stale entry with a retry (saved values) loses only its retry time.
        let stale = SubscriptionEntry(status: status, state: .stale(lastGoodAt: t0, error: "offline"), quickRetryAt: retryAt)
        #expect(stale.reused(now: retryAt.addingTimeInterval(1)) == stale)
        #expect(stale.reused(now: retryAt.addingTimeInterval(31)).quickRetryAt == nil)
        #expect(stale.reused(now: retryAt.addingTimeInterval(31)).state == stale.state)
    }

    @Test func staleStatesForTheBar() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SubscriptionState.stale(lastGoodAt: t0, error: "x").isStale)
        #expect(SubscriptionState.signInRejected(lastGoodAt: nil).isStale)
        #expect(SubscriptionState.credentialsExpired.isStale)
        #expect(!SubscriptionState.ok.isStale)
        #expect(!SubscriptionState.notSignedIn.isStale)
        #expect(!SubscriptionState.retrying(lastGoodAt: t0, error: "x", retryAt: t0).isStale)
    }
    // MARK: Quick retry (spec 010 FR-002, FR-004 to FR-007, FR-009)

    /// A source with a hand-moved clock and one account per token in
    /// `directories` (`~/a`, `~/b`, ...).
    private func graceSource(_ name: String, tokens: [String], directories: [String]? = nil)
        throws -> (SubscriptionSource, MutableClock, DiagnosticLog, URL, Configuration) {
        let dir = try makeTempDirectory(name)
        let reader = FakeCredentialReader()
        let dirs = directories ?? tokens.indices.map { "~/acct\($0)" }
        for (token, directory) in zip(tokens, dirs) {
            reader.credentials[directory] = OAuthCredential(accessToken: token, expiresAt: far)
        }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
        let (source, log) = makeSource(reader: reader, token: tokens.first ?? "", logDir: dir, now: { clock.now() })
        return (source, clock, log, dir, makeConfig(directories: dirs))
    }

    private func ok(_ token: String) { StubURLProtocol.register(key: "Bearer \(token)") { _ in (200, Data(usageResponseJSON.utf8)) } }
    private func offline(_ token: String) { StubURLProtocol.register(key: "Bearer \(token)") { _ in throw URLError(.notConnectedToInternet) } }
    private func status(_ token: String, _ code: Int) { StubURLProtocol.register(key: "Bearer \(token)") { _ in (code, Data("{}".utf8)) } }
    private func requests(_ token: String) -> Int { StubURLProtocol.recordedRequests(key: "Bearer \(token)").count }

    @Test func transportFailureAfterSuccessStartsAGracePeriod() async throws {
        let token = "grace-\(Self.secret)"
        let (source, clock, log, dir, config) = try graceSource("sub-grace", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        let t0 = clock.now()
        let first = entries(try await source.collect(context: context(config)))
        #expect(first["acc-0"]?.state == .ok)
        #expect(first["acc-0"]?.quickRetryAt == nil)

        clock.advance(300)
        offline(token)
        let second = entries(try await source.collect(context: context(config)))
        let retryAt = clock.now().addingTimeInterval(30)
        guard case .retrying(let lastGoodAt, let error, let at) = second["acc-0"]?.state else {
            Issue.record("expected retrying, got \(String(describing: second["acc-0"]?.state))")
            return
        }
        #expect(lastGoodAt == t0)
        #expect(at == retryAt)
        #expect(!error.isEmpty)
        #expect(second["acc-0"]?.status == first["acc-0"]?.status)
        #expect(second["acc-0"]?.quickRetryAt == retryAt)
        #expect(second["acc-0"]?.fetchOutcome == .otherError)
        let logText = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(logText.contains("fetch failed (transport)"))
        #expect(logText.contains("quick retry scheduled at"))
        #expect(!logText.contains(Self.secret))
    }

    /// A request that times out fails 30 s after it started: the quick retry
    /// counts from the failure, so it is still in the future (FR-004).
    @Test func quickRetryCountsFromTheFailureNotTheRefreshStart() async throws {
        let token = "grace-timeout-\(Self.secret)"
        let (source, clock, _, dir, config) = try graceSource("sub-grace-timeout", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        _ = try await source.collect(context: context(config))
        clock.advance(300)
        StubURLProtocol.register(key: "Bearer \(token)") { _ in
            clock.advance(30)
            throw URLError(.timedOut)
        }
        let started = clock.now()
        let out = entries(try await source.collect(context: context(config)))
        #expect(out["acc-0"]?.quickRetryAt == started.addingTimeInterval(60))
        guard case .retrying(_, _, let retryAt)? = out["acc-0"]?.state else {
            Issue.record("expected retrying, got \(String(describing: out["acc-0"]?.state))")
            return
        }
        #expect(retryAt == started.addingTimeInterval(60))
    }

    /// Edge cases "Retry and timer collide" and "Retry while asleep": a
    /// scheduled or wake request during the grace period that fails ends
    /// the grace stale, without a second quick retry in the episode (FR-008).
    @Test(arguments: [RefreshTrigger.scheduled, .wake])
    func failedRequestThatTakesTheRetrysPlaceIsStale(trigger: RefreshTrigger) async throws {
        let token = "grace-collide-\(trigger.rawValue)-\(Self.secret)"
        let (source, clock, _, dir, config) = try graceSource("sub-grace-collide-\(trigger.rawValue)", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        let t0 = clock.now()
        _ = try await source.collect(context: context(config))
        clock.advance(300)
        offline(token)
        let grace = entries(try await source.collect(context: context(config)))
        #expect(grace["acc-0"]?.quickRetryAt != nil)
        clock.advance(10)
        let replaced = entries(try await source.collect(context: context(config, trigger: trigger)))
        guard case .stale(let lastGoodAt, _)? = replaced["acc-0"]?.state else {
            Issue.record("expected stale, got \(String(describing: replaced["acc-0"]?.state))")
            return
        }
        #expect(lastGoodAt == t0)
        #expect(replaced["acc-0"]?.quickRetryAt == nil)
        clock.advance(300)
        let later = entries(try await source.collect(context: context(config)))
        #expect(later["acc-0"]?.quickRetryAt == nil)
        #expect(later["acc-0"]?.state.isStale == true)
    }

    @Test func serverErrorAfterSuccessAlsoStartsAGracePeriod() async throws {
        let token = "grace503-\(Self.secret)"
        let (source, clock, log, dir, config) = try graceSource("sub-grace503", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        _ = try await source.collect(context: context(config))
        clock.advance(300)
        status(token, 503)
        let out = entries(try await source.collect(context: context(config)))
        guard case .retrying(_, let error, _) = out["acc-0"]?.state else {
            Issue.record("expected retrying")
            return
        }
        #expect(error.contains("503"))
        #expect(try String(contentsOf: log.fileURL, encoding: .utf8).contains("fetch failed (transport)"))
        #expect(out["acc-0"]?.quickRetryAt == clock.now().addingTimeInterval(30))
    }

    @Test func secondFailureInAnyCategoryIsStaleWithoutAnotherRetry() async throws {
        for (index, code) in [0, 401, 404, 429].enumerated() {
            let token = "second-\(index)-\(Self.secret)"
            let (source, clock, _, dir, config) = try graceSource("sub-second-\(index)", tokens: [token])
            defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
            ok(token)
            let t0 = clock.now()
            _ = try await source.collect(context: context(config))
            offline(token)
            clock.advance(300)
            _ = try await source.collect(context: context(config))
            clock.advance(31)
            if code == 0 { offline(token) } else { status(token, code) }
            let out = entries(try await source.collect(context: context(config, trigger: .quickRetry)))
            #expect(out["acc-0"]?.quickRetryAt == nil, "code \(code)")
            #expect(out["acc-0"]?.status != nil, "code \(code)")
            switch out["acc-0"]?.state {
            case .stale(let lastGoodAt, _)?:
                #expect(lastGoodAt == t0)
                #expect(code != 401)
            case .signInRejected(let lastGoodAt)?:
                #expect(lastGoodAt == t0)
                #expect(code == 401)
            default:
                Issue.record("expected stale or rejected for code \(code), got \(String(describing: out["acc-0"]?.state))")
            }
            // Still exhausted: a further transport failure gets no retry.
            clock.advance(300)
            offline(token)
            let later = entries(try await source.collect(context: context(config)))
            #expect(later["acc-0"]?.quickRetryAt == nil, "code \(code)")
            #expect(later["acc-0"]?.state.isStale == true, "code \(code)")
        }
    }

    @Test func successEndsTheEpisodeSoTheNextFailureGetsANewGracePeriod() async throws {
        let token = "episode-\(Self.secret)"
        let (source, clock, _, dir, config) = try graceSource("sub-episode", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        _ = try await source.collect(context: context(config))
        offline(token)
        clock.advance(300)
        _ = try await source.collect(context: context(config))
        clock.advance(31)
        ok(token)
        let retried = entries(try await source.collect(context: context(config, trigger: .quickRetry)))
        #expect(retried["acc-0"]?.state == .ok)
        #expect(retried["acc-0"]?.quickRetryAt == nil)
        clock.advance(300)
        offline(token)
        let again = entries(try await source.collect(context: context(config)))
        guard case .retrying = again["acc-0"]?.state else {
            Issue.record("expected a new grace period")
            return
        }
        #expect(again["acc-0"]?.quickRetryAt == clock.now().addingTimeInterval(30))
    }

    @Test func firstLaunchTransportFailureIsNoDataYetWithAQuickRetry() async throws {
        let token = "nodata-\(Self.secret)"
        let (source, clock, log, dir, config) = try graceSource("sub-nodata", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        offline(token)
        let out = entries(try await source.collect(context: context(config)))
        guard case .stale(let lastGoodAt, _) = out["acc-0"]?.state else {
            Issue.record("expected stale")
            return
        }
        #expect(lastGoodAt == nil)
        #expect(out["acc-0"]?.status == nil)
        #expect(out["acc-0"]?.quickRetryAt == clock.now().addingTimeInterval(30))
        #expect(try String(contentsOf: log.fileURL, encoding: .utf8).contains("fetch failed (transport)"))
    }

    @Test func quickRetryRequestsOnlyAccountsWhoseRetryIsDue() async throws {
        let good = "subset-good-\(Self.secret)"
        let bad = "subset-bad-\(Self.secret)"
        let (source, clock, _, dir, config) = try graceSource("sub-subset", tokens: [good, bad])
        defer {
            try? FileManager.default.removeItem(at: dir)
            StubURLProtocol.unregister(key: "Bearer \(good)")
            StubURLProtocol.unregister(key: "Bearer \(bad)")
        }
        ok(good); ok(bad)
        _ = try await source.collect(context: context(config))
        offline(bad)
        clock.advance(300)
        let failed = entries(try await source.collect(context: context(config)))
        #expect(failed["acc-0"]?.state == .ok)
        let goodRequests = requests(good)
        let badRequests = requests(bad)

        // Before the retry time nothing is requested.
        clock.advance(10)
        let early = entries(try await source.collect(context: context(config, trigger: .quickRetry)))
        #expect(requests(good) == goodRequests)
        #expect(requests(bad) == badRequests)
        #expect(early["acc-0"]?.fetchOutcome == nil)
        #expect(early["acc-1"]?.fetchOutcome == nil)
        guard case .retrying = early["acc-1"]?.state else {
            Issue.record("expected the failed account to stay in grace")
            return
        }

        // At the retry time only the failed account is requested.
        clock.advance(20)
        ok(bad)
        let retried = entries(try await source.collect(context: context(config, trigger: .quickRetry)))
        #expect(requests(good) == goodRequests)
        // Registering a handler resets its request log.
        #expect(requests(bad) == 1)
        #expect(retried["acc-0"]?.fetchOutcome == nil)
        #expect(retried["acc-0"]?.state == .ok)
        #expect(retried["acc-0"]?.status == failed["acc-0"]?.status)
        #expect(retried["acc-1"]?.fetchOutcome == .success)
        #expect(retried["acc-1"]?.state == .ok)
    }

    @Test func quickRetryRequestsNewAndChangedAccounts() async throws {
        let a = "changed-a-\(Self.secret)"
        let b = "changed-b-\(Self.secret)"
        let (source, clock, _, dir, _) = try graceSource("sub-changed", tokens: [a, b], directories: ["~/a", "~/b"])
        defer {
            try? FileManager.default.removeItem(at: dir)
            StubURLProtocol.unregister(key: "Bearer \(a)")
            StubURLProtocol.unregister(key: "Bearer \(b)")
        }
        ok(a); ok(b)
        _ = try await source.collect(context: context(makeConfig(directories: ["~/a"])))
        #expect(requests(a) == 1)
        clock.advance(5)
        // acc-0 moves to ~/b (changed directory), acc-1 is new.
        let out = entries(try await source.collect(context: context(makeConfig(directories: ["~/b", "~/a"]), trigger: .quickRetry)))
        #expect(out["acc-0"]?.fetchOutcome == .success)
        #expect(out["acc-1"]?.fetchOutcome == .success)
        #expect(requests(a) == 2)
        #expect(requests(b) == 1)
    }

    @Test func graceOverdueWithoutARequestExpiresTheEpisode() async throws {
        let token = "overdue-\(Self.secret)"
        let (source, clock, _, dir, config) = try graceSource("sub-overdue", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        _ = try await source.collect(context: context(config))
        offline(token)
        clock.advance(300)
        _ = try await source.collect(context: context(config))
        let before = requests(token)
        // The retry was suppressed (rate limit) and its due window passed.
        clock.advance(30 + 30)
        let late = entries(try await source.collect(context: context(config, trigger: .quickRetry)))
        #expect(requests(token) == before)
        #expect(late["acc-0"]?.quickRetryAt == nil)
        #expect(late["acc-0"]?.state.isStale == true)
        // The next failure is stale with no second retry.
        clock.advance(200)
        let next = entries(try await source.collect(context: context(config)))
        #expect(requests(token) == before + 1)
        #expect(next["acc-0"]?.quickRetryAt == nil)
        guard case .stale = next["acc-0"]?.state else {
            Issue.record("expected stale")
            return
        }
    }

    @Test func rateLimitAndServiceChangedNeverScheduleAQuickRetry() async throws {
        for (index, code) in [429, 404, 302].enumerated() {
            let token = "noretry-\(index)-\(Self.secret)"
            let (source, clock, log, dir, config) = try graceSource("sub-noretry-\(index)", tokens: [token])
            defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
            ok(token)
            _ = try await source.collect(context: context(config))
            clock.advance(300)
            status(token, code)
            let out = entries(try await source.collect(context: context(config)))
            #expect(out["acc-0"]?.quickRetryAt == nil, "code \(code)")
            let category = code == 429 ? "rateLimited" : "serviceChanged"
            #expect(try String(contentsOf: log.fileURL, encoding: .utf8).contains("fetch failed (\(category))"), "code \(code)")
            guard case .stale = out["acc-0"]?.state else {
                Issue.record("expected stale for \(code)")
                return
            }
        }
    }

    @Test func failuresBeforeARequestAreNotClassified() async throws {
        let dir = try makeTempDirectory("sub-unclassified")
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = FakeCredentialReader()
        reader.credentials["~/expired"] = OAuthCredential(accessToken: "x-\(Self.secret)", expiresAt: Date(timeIntervalSince1970: 1))
        let (source, log) = makeSource(reader: reader, token: "x", logDir: dir)
        let out = entries(try await source.collect(context: context(makeConfig(directories: ["~/expired", "~/none"]))))
        #expect(out["acc-0"]?.state == .credentialsExpired)
        #expect(out["acc-1"]?.state == .notSignedIn)
        for id in ["acc-0", "acc-1"] {
            #expect(out[id]?.quickRetryAt == nil)
        }
        reader.error = FakeCredentialReader.ReadFailure()
        let unreadable = entries(try await source.collect(context: context(makeConfig())))
        guard case .stale(_, let error) = unreadable["acc-0"]?.state else {
            Issue.record("expected stale")
            return
        }
        #expect(error.hasPrefix("credential read failed"))
        #expect(unreadable["acc-0"]?.quickRetryAt == nil)
        // Not classified: no failed request is logged (FR-002).
        #expect(!(try String(contentsOf: log.fileURL, encoding: .utf8)).contains("fetch failed"))
    }
    /// Values shown stale by a failure before a request never become
    /// unmarked again, and a pending quick retry is dropped (spec 010
    /// FR-002, FR-005, edge case "Already stale").
    @Test func failureBeforeARequestKeepsValuesStaleAndDropsTheRetry() async throws {
        let dir = try makeTempDirectory("sub-restale")
        defer { try? FileManager.default.removeItem(at: dir) }
        let token = "restale-\(Self.secret)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let reader = FakeCredentialReader()
        let valid = OAuthCredential(accessToken: token, expiresAt: far)
        let expired = OAuthCredential(accessToken: token, expiresAt: Date(timeIntervalSince1970: 1))
        reader.credentials["~/.claude"] = valid
        let clock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
        let (source, _) = makeSource(reader: reader, token: token, logDir: dir, now: { clock.now() })
        let config = makeConfig()
        ok(token)
        _ = try await source.collect(context: context(config))

        // Grace, then the credentials expire before the retry.
        offline(token)
        clock.advance(300)
        _ = try await source.collect(context: context(config))
        reader.credentials["~/.claude"] = expired
        clock.advance(10)
        let stale = entries(try await source.collect(context: context(config)))
        #expect(stale["acc-0"]?.state == .credentialsExpired)
        #expect(stale["acc-0"]?.quickRetryAt == nil)
        clock.advance(25)
        let kept = entries(try await source.collect(context: context(config, trigger: .quickRetry)))
        #expect(kept["acc-0"]?.quickRetryAt == nil)
        #expect(kept["acc-0"]?.fetchOutcome == nil)

        // Renewed credentials, still offline: the stale values stay stale.
        reader.credentials["~/.claude"] = valid
        clock.advance(300)
        let again = entries(try await source.collect(context: context(config)))
        guard case .stale = again["acc-0"]?.state else {
            Issue.record("expected stale, got \(String(describing: again["acc-0"]?.state))")
            return
        }
        #expect(again["acc-0"]?.status != nil)
    }
    // MARK: Rejected sign-in (spec 010 FR-006, FR-010, FR-011)

    @Test func unauthorizedAndForbiddenAreRejectedSignIns() async throws {
        for code in [401, 403] {
            let token = "rejected-\(code)-\(Self.secret)"
            let (source, clock, log, dir, config) = try graceSource("sub-rejected-\(code)", tokens: [token])
            defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
            ok(token)
            let t0 = clock.now()
            let first = entries(try await source.collect(context: context(config)))
            clock.advance(300)
            status(token, code)
            let out = entries(try await source.collect(context: context(config)))
            #expect(out["acc-0"]?.state == .signInRejected(lastGoodAt: t0), "code \(code)")
            #expect(out["acc-0"]?.status == first["acc-0"]?.status)
            #expect(try String(contentsOf: log.fileURL, encoding: .utf8).contains("fetch failed (signInRejected)"))
            #expect(out["acc-0"]?.quickRetryAt == nil)
            #expect(!(try String(contentsOf: log.fileURL, encoding: .utf8)).contains(Self.secret))

            // FR-011: a later success clears it.
            clock.advance(300)
            ok(token)
            let recovered = entries(try await source.collect(context: context(config)))
            #expect(recovered["acc-0"]?.state == .ok)
        }
    }

    @Test func rejectionWithoutValuesHasNoStatus() async throws {
        let token = "rejected-none-\(Self.secret)"
        let (source, _, _, dir, config) = try graceSource("sub-rejected-none", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        status(token, 401)
        let out = entries(try await source.collect(context: context(config)))
        #expect(out["acc-0"]?.state == .signInRejected(lastGoodAt: nil))
        #expect(out["acc-0"]?.status == nil)
    }

    @Test func rejectedQuickRetryIsARejectedSignIn() async throws {
        let token = "rejected-retry-\(Self.secret)"
        let (source, clock, _, dir, config) = try graceSource("sub-rejected-retry", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        let t0 = clock.now()
        _ = try await source.collect(context: context(config))
        clock.advance(300)
        offline(token)
        _ = try await source.collect(context: context(config))
        clock.advance(31)
        status(token, 401)
        let out = entries(try await source.collect(context: context(config, trigger: .quickRetry)))
        #expect(out["acc-0"]?.state == .signInRejected(lastGoodAt: t0))
        #expect(out["acc-0"]?.quickRetryAt == nil)
    }

    /// spec 010 FR-007: a quick retry suppressed by a rate-limit wait counts
    /// as used, even if another quick retry comes inside the due window.
    @Test func suppressedQuickRetryIsUsed() async throws {
        let token = "suppressed-\(Self.secret)"
        let (source, clock, _, dir, config) = try graceSource("sub-suppressed", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        _ = try await source.collect(context: context(config))
        clock.advance(300)
        offline(token)
        _ = try await source.collect(context: context(config))
        clock.advance(31)
        await source.quickRetrySuppressed(now: clock.now())
        let before = requests(token)
        clock.advance(5)
        let later = entries(try await source.collect(context: context(config, trigger: .quickRetry)))
        #expect(requests(token) == before)
        #expect(later["acc-0"]?.quickRetryAt == nil)
        #expect(later["acc-0"]?.state.isStale == true)
    }

    // MARK: Saved values (spec 010 FR-005, FR-013, FR-015)

    /// A source with a store on a temporary file, accounts under a temporary
    /// home, and a hand-moved clock.
    struct SavedSetup {
        let root: URL
        let paths: Paths
        let reader = FakeCredentialReader()
        let clock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
        let store: LastGoodStore
        let source: SubscriptionSource

        init(_ name: String, initial: LastGoodValues? = nil) throws {
            root = try makeTempDirectory(name)
            paths = Paths(home: root)
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
            store = LastGoodStore(fileURL: paths.lastGoodFileURL, initial: initial, log: nil)
            let clock = self.clock
            source = SubscriptionSource(credentialReader: reader, client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                        log: DiagnosticLog(fileURL: root.appendingPathComponent("usage.log")),
                                        clock: { clock.now() }, store: store, paths: paths)
        }

        var canonicalClaude: String { Attributor.canonical(root.appendingPathComponent(".claude").path) }

        func config(_ directories: [String] = ["~/.claude"]) -> Configuration {
            var config = Configuration()
            config.accounts = directories.enumerated().map { index, dir in
                Account(id: "acc-\(index)", displayName: "Account \(index)",
                        kind: .subscription(SubscriptionSettings(credentialDirectory: dir, shownInBar: true, thresholds: [])))
            }
            return config
        }

        func modificationDate() -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: paths.lastGoodFileURL.path))?[.modificationDate] as? Date
        }
    }

    static let saved = SavedClaudeValues(credentialDirectory: "", fetchedAt: Date(timeIntervalSince1970: 1_799_990_000),
                                         fiveHour: SavedWindow(utilizationPercent: 41, resetsAt: Date(timeIntervalSince1970: 1_800_010_000)),
                                         sevenDay: SavedWindow(utilizationPercent: 63, resetsAt: Date(timeIntervalSince1970: 1_800_200_000)),
                                         modelLimits: [SavedModelLimit(modelName: "Fable", utilizationPercent: 12, resetsAt: nil)])

    static func saved(directory: String, fetchedAt: Date = saved.fetchedAt) -> SavedClaudeValues {
        var copy = saved
        copy.credentialDirectory = directory
        copy.fetchedAt = fetchedAt
        return copy
    }

    @Test func successWritesTheAccountsValues() async throws {
        let s = try SavedSetup("sub-saved-write")
        defer { try? FileManager.default.removeItem(at: s.root) }
        let token = "saved-write-\(Self.secret)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        s.reader.credentials["~/.claude"] = OAuthCredential(accessToken: token, expiresAt: far, subscriptionType: "max")
        let out = entries(try await s.source.collect(context: context(s.config())))
        let (loaded, _) = LastGoodStore.load(from: s.paths.lastGoodFileURL)
        let saved = try #require(loaded?.claude["acc-0"])
        #expect(saved.credentialDirectory == s.canonicalClaude)
        #expect(saved.fetchedAt == s.clock.now())
        #expect(saved.sevenDay?.utilizationPercent == out["acc-0"]?.status?.sevenDay?.utilizationPercent)
        let text = try String(contentsOf: s.paths.lastGoodFileURL, encoding: .utf8)
        #expect(!text.contains("max"))
        #expect(!text.contains(Self.secret))

        // An unchanged second success does not rewrite the file.
        let first = s.modificationDate()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: s.paths.lastGoodFileURL.path)
        _ = try await s.source.collect(context: context(s.config()))
        #expect(first != nil)
        #expect(s.modificationDate() == Date(timeIntervalSince1970: 1_000_000))

        // A removed account is dropped at the next write.
        s.reader.credentials["~/.other"] = OAuthCredential(accessToken: token, expiresAt: far)
        _ = try await s.source.collect(context: context(s.config(["~/.other"])))
        let (after, _) = LastGoodStore.load(from: s.paths.lastGoodFileURL)
        #expect(after?.claude.keys.sorted() == ["acc-0"])
        #expect(after?.claude["acc-0"]?.credentialDirectory == Attributor.canonical(s.root.appendingPathComponent(".other").path))
    }

    @Test func matchingSavedValuesAreUsedAndShownEarly() async throws {
        // Saved for this account's canonical directory (configured as ~/.claude).
        let s = try SavedSetup("sub-saved-match")
        defer { try? FileManager.default.removeItem(at: s.root) }
        let store = LastGoodStore(fileURL: s.paths.lastGoodFileURL,
                                  initial: LastGoodValues(claude: ["acc-0": Self.saved(directory: s.canonicalClaude)]), log: nil)
        let clock = s.clock
        let source = SubscriptionSource(credentialReader: s.reader, client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                        clock: { clock.now() }, store: store, paths: s.paths)
        guard case .subscriptions(let shown)? = await source.savedOutput(configuration: s.config(), now: clock.now()) else {
            Issue.record("expected saved subscriptions")
            return
        }
        #expect(shown["acc-0"]?.state == .ok)
        #expect(shown["acc-0"]?.status?.sevenDay?.utilizationPercent == 63)
        #expect(shown["acc-0"]?.status?.fetchedAt == Self.saved.fetchedAt)
        #expect(shown["acc-0"]?.status?.modelLimits.map(\.modelName) == ["Fable"])
        #expect(shown["acc-0"]?.status?.subscriptionType == nil)

        // A mismatching directory is ignored.
        let other = try SavedSetup("sub-saved-mismatch")
        defer { try? FileManager.default.removeItem(at: other.root) }
        let otherStore = LastGoodStore(fileURL: other.paths.lastGoodFileURL,
                                       initial: LastGoodValues(claude: ["acc-0": Self.saved(directory: "/somewhere/else/.claude")]), log: nil)
        let otherSource = SubscriptionSource(credentialReader: other.reader, client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                             store: otherStore, paths: other.paths)
        #expect(await otherSource.savedOutput(configuration: other.config(), now: other.clock.now()) == nil)
    }

    @Test func futureSavedFetchTimeIsClampedToNow() async throws {
        let s = try SavedSetup("sub-saved-future")
        defer { try? FileManager.default.removeItem(at: s.root) }
        let store = LastGoodStore(fileURL: s.paths.lastGoodFileURL, initial: LastGoodValues(claude: [
            "acc-0": Self.saved(directory: s.canonicalClaude, fetchedAt: s.clock.now().addingTimeInterval(3600)),
        ]), log: nil)
        let clock = s.clock
        let source = SubscriptionSource(credentialReader: s.reader, client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                        clock: { clock.now() }, store: store, paths: s.paths)
        guard case .subscriptions(let shown)? = await source.savedOutput(configuration: s.config(), now: clock.now()) else {
            Issue.record("expected saved subscriptions")
            return
        }
        #expect(shown["acc-0"]?.status?.fetchedAt == clock.now())
    }

    @Test func failureAfterLaunchShowsSavedValuesStaleWithoutGrace() async throws {
        let s = try SavedSetup("sub-saved-fail")
        defer { try? FileManager.default.removeItem(at: s.root) }
        let store = LastGoodStore(fileURL: s.paths.lastGoodFileURL,
                                  initial: LastGoodValues(claude: ["acc-0": Self.saved(directory: s.canonicalClaude)]), log: nil)
        let clock = s.clock
        let source = SubscriptionSource(credentialReader: s.reader, client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                        clock: { clock.now() }, store: store, paths: s.paths)
        let token = "saved-fail-\(Self.secret)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        offline(token)
        s.reader.credentials["~/.claude"] = OAuthCredential(accessToken: token, expiresAt: far)
        let out = entries(try await source.collect(context: context(s.config())))
        guard case .stale(let lastGoodAt, _) = out["acc-0"]?.state else {
            Issue.record("expected stale, got \(String(describing: out["acc-0"]?.state))")
            return
        }
        #expect(lastGoodAt == Self.saved.fetchedAt)
        #expect(out["acc-0"]?.status?.sevenDay?.utilizationPercent == 63)
        #expect(out["acc-0"]?.quickRetryAt == clock.now().addingTimeInterval(30))
    }

    @Test func failuresBeforeARequestShowSavedValuesStaleExceptNotSignedIn() async throws {
        let s = try SavedSetup("sub-saved-before")
        defer { try? FileManager.default.removeItem(at: s.root) }
        let initial = LastGoodValues(claude: ["acc-0": Self.saved(directory: s.canonicalClaude)])
        func source() -> SubscriptionSource {
            let clock = s.clock
            return SubscriptionSource(credentialReader: s.reader, client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                      clock: { clock.now() }, store: LastGoodStore(fileURL: s.paths.lastGoodFileURL, initial: initial, log: nil),
                                      paths: s.paths)
        }
        s.reader.credentials["~/.claude"] = OAuthCredential(accessToken: "x", expiresAt: Date(timeIntervalSince1970: 1))
        let expired = entries(try await source().collect(context: context(s.config())))
        #expect(expired["acc-0"]?.state == .credentialsExpired)
        #expect(expired["acc-0"]?.status?.sevenDay?.utilizationPercent == 63)

        s.reader.error = FakeCredentialReader.ReadFailure()
        let unreadable = entries(try await source().collect(context: context(s.config())))
        guard case .stale(let at, _) = unreadable["acc-0"]?.state else {
            Issue.record("expected stale")
            return
        }
        #expect(at == Self.saved.fetchedAt)
        #expect(unreadable["acc-0"]?.status != nil)

        s.reader.error = nil
        s.reader.credentials = [:]
        let notSignedIn = source()
        let none = entries(try await notSignedIn.collect(context: context(s.config())))
        #expect(none["acc-0"]?.state == .notSignedIn)
        #expect(none["acc-0"]?.status == nil)
        // Not shown, so dropped at the next write.
        let loaded = try #require(LastGoodStore.load(from: s.paths.lastGoodFileURL).0)
        #expect(loaded.claude["acc-0"] == nil)
    }

    /// A not-signed-in account forgets its last good values in memory too:
    /// after signing in again, a failed request shows no values, and the
    /// next save does not write the old ones back (spec 010 FR-015).
    @Test func notSignedInForgetsTheLastGoodValues() async throws {
        let s = try SavedSetup("sub-saved-signed-out")
        defer { try? FileManager.default.removeItem(at: s.root) }
        let token = "signed-out-\(Self.secret)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        let credential = OAuthCredential(accessToken: token, expiresAt: far)
        s.reader.credentials["~/.claude"] = credential
        let first = entries(try await s.source.collect(context: context(s.config())))
        #expect(first["acc-0"]?.state == .ok)
        #expect(LastGoodStore.load(from: s.paths.lastGoodFileURL).0?.claude["acc-0"] != nil)

        s.reader.credentials = [:]
        s.clock.advance(300)
        let signedOut = entries(try await s.source.collect(context: context(s.config())))
        #expect(signedOut["acc-0"]?.state == .notSignedIn)
        #expect(LastGoodStore.load(from: s.paths.lastGoodFileURL).0?.claude["acc-0"] == nil)

        s.reader.credentials["~/.claude"] = credential
        offline(token)
        s.clock.advance(300)
        let failed = entries(try await s.source.collect(context: context(s.config())))
        #expect(failed["acc-0"]?.status == nil)
        guard case .stale(let lastGoodAt, _)? = failed["acc-0"]?.state else {
            Issue.record("expected stale, got \(String(describing: failed["acc-0"]?.state))")
            return
        }
        #expect(lastGoodAt == nil)
        #expect(LastGoodStore.load(from: s.paths.lastGoodFileURL).0?.claude["acc-0"] == nil)
    }

    // MARK: Credential expiry time (spec 014 FR-005)

    /// An expired credential's entry carries the credential's own expiry
    /// time, so the delay counts from it (spec 014 FR-005).
    @Test func expiredEntryCarriesTheCredentialsExpiryTime() async throws {
        let dir = try makeTempDirectory("sub-expiry-time")
        defer { try? FileManager.default.removeItem(at: dir) }
        let expiresAt = Date(timeIntervalSince1970: 1_799_990_000)
        let reader = FakeCredentialReader()
        reader.credentials["~/.claude"] = OAuthCredential(accessToken: "expiry-\(Self.secret)", expiresAt: expiresAt)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (source, _) = makeSource(reader: reader, token: "", logDir: dir, now: { now })
        let out = entries(try await source.collect(context: context(makeConfig())))
        #expect(out["acc-0"]?.state == .credentialsExpired)
        #expect(out["acc-0"]?.credentialExpiresAt == expiresAt)
    }

    /// Only `.credentialsExpired` carries an expiry time; working, missing,
    /// rejected and stale entries do not (spec 014 FR-005).
    @Test func otherStatesCarryNoExpiryTime() async throws {
        let working = "expiry-ok-\(Self.secret)", rejected = "expiry-401-\(Self.secret)", down = "expiry-down-\(Self.secret)"
        let (source, _, _, dir, _) = try graceSource("sub-expiry-none", tokens: [working, rejected, down],
                                                     directories: ["~/a", "~/b", "~/c"])
        defer {
            try? FileManager.default.removeItem(at: dir)
            for token in [working, rejected, down] { StubURLProtocol.unregister(key: "Bearer \(token)") }
        }
        ok(working)
        status(rejected, 401)
        offline(down)
        let out = entries(try await source.collect(context: context(makeConfig(directories: ["~/a", "~/b", "~/c", "~/missing"]))))
        #expect(out["acc-0"]?.state == .ok)
        #expect(out["acc-1"]?.state == .signInRejected(lastGoodAt: nil))
        guard case .stale? = out["acc-2"]?.state else {
            Issue.record("expected stale, got \(String(describing: out["acc-2"]?.state))")
            return
        }
        #expect(out["acc-3"]?.state == .notSignedIn)
        for id in ["acc-0", "acc-1", "acc-2", "acc-3"] {
            #expect(out[id]?.credentialExpiresAt == nil, "\(id)")
        }
    }

    /// Clock moved backwards: an expiry time in the future is not expired
    /// (spec 014 edge case "Clock moved backwards").
    @Test func futureExpiryIsNotExpired() async throws {
        let token = "expiry-future-\(Self.secret)"
        let dir = try makeTempDirectory("sub-expiry-future")
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        ok(token)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reader = FakeCredentialReader()
        reader.credentials["~/.claude"] = OAuthCredential(accessToken: token, expiresAt: now.addingTimeInterval(3600))
        let (source, _) = makeSource(reader: reader, token: token, logDir: dir, now: { now })
        let out = entries(try await source.collect(context: context(makeConfig())))
        #expect(out["acc-0"]?.state == .ok)
        #expect(out["acc-0"]?.credentialExpiresAt == nil)
    }

    // MARK: No-answer accounts (spec 021 FR-003, FR-003a, FR-003c, R3, R7)

    private func manualContext(_ config: Configuration, trigger: RefreshTrigger = .manual, noAnswerOnly: Bool = true) -> RefreshContext {
        var context = context(config, trigger: trigger)
        context.manualRequested = true
        context.claudeNoAnswerOnly = noAnswerOnly
        return context
    }

    /// FR-003c: a no-answer-only run asks only the accounts whose last
    /// request got no answer; an account that answered (with 200 or 503)
    /// keeps its last entry without a request.
    @Test func noAnswerOnlyRequestsOnlyNoAnswerAccounts() async throws {
        let tokens = ["na-ok-\(Self.secret)", "na-offline-\(Self.secret)", "na-503-\(Self.secret)"]
        let (source, clock, log, dir, config) = try graceSource("sub-noanswer-only", tokens: tokens)
        defer { try? FileManager.default.removeItem(at: dir); tokens.forEach { StubURLProtocol.unregister(key: "Bearer \($0)") } }
        ok(tokens[0])
        offline(tokens[1])
        status(tokens[2], 503)
        _ = try await source.collect(context: context(config))
        #expect(await source.noAnswerAccounts() == ["acc-1"])

        // Registering an answer resets a token's recorded requests.
        clock.advance(10)
        tokens.forEach(ok)
        let out = entries(try await source.collect(context: manualContext(config)))
        #expect(tokens.map(requests) == [0, 1, 0])
        #expect(out["acc-1"]?.state == .ok)
        #expect(out["acc-1"]?.fetchOutcome == .success)
        for id in ["acc-0", "acc-2"] {
            #expect(out[id]?.fetchOutcome == nil, "\(id)")
            #expect(out[id]?.reachedService == false, "\(id)")
        }
        #expect(out["acc-0"]?.state == .ok)
        #expect(await source.noAnswerAccounts().isEmpty)
        let logText = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(!logText.contains(Self.secret))
    }

    /// R3: an account leaves the no-answer set with a success or any HTTP
    /// answer, and with its removal from the configuration.
    @Test func noAnswerClearedBySuccessAndByAnHTTPAnswer() async throws {
        let token = "na-clear-\(Self.secret)"
        let (source, clock, _, dir, config) = try graceSource("sub-noanswer-clear", tokens: [token])
        defer { try? FileManager.default.removeItem(at: dir); StubURLProtocol.unregister(key: "Bearer \(token)") }
        let answers: [(() -> Void, Set<String>)] = [
            ({ self.offline(token) }, ["acc-0"]),
            ({ self.ok(token) }, []),
            ({ self.offline(token) }, ["acc-0"]),
            ({ self.status(token, 503) }, []),
            ({ self.offline(token) }, ["acc-0"]),
            ({ self.status(token, 429) }, []),
            ({ StubURLProtocol.register(key: "Bearer \(token)") { _ in throw URLError(.timedOut) } }, ["acc-0"]),
            ({ self.status(token, 401) }, []),
            ({ self.offline(token) }, ["acc-0"]),
        ]
        for (index, (answer, expected)) in answers.enumerated() {
            clock.advance(300)
            answer()
            _ = try await source.collect(context: context(config))
            #expect(await source.noAnswerAccounts() == expected, "step \(index)")
        }
        clock.advance(300)
        _ = try await source.collect(context: context(makeConfig(directories: [])))
        #expect(await source.noAnswerAccounts().isEmpty)
    }

    /// FR-003a: a click merged into a quick retry also asks the no-answer
    /// accounts whose retry is not due, in the same run.
    @Test func manualMergedIntoQuickRetryAlsoRequestsNoAnswerAccounts() async throws {
        let tokens = ["na-retry-\(Self.secret)", "na-exhausted-\(Self.secret)"]
        let (source, clock, _, dir, config) = try graceSource("sub-noanswer-merged", tokens: tokens)
        defer { try? FileManager.default.removeItem(at: dir); tokens.forEach { StubURLProtocol.unregister(key: "Bearer \($0)") } }
        // acc-1 fails twice, so its episode has no quick retry left.
        ok(tokens[0])
        offline(tokens[1])
        _ = try await source.collect(context: context(config))
        clock.advance(100)
        _ = try await source.collect(context: context(config))
        // acc-0 fails now; its quick retry is due 30 s later.
        clock.advance(100)
        offline(tokens[0])
        _ = try await source.collect(context: context(config))
        #expect(await source.noAnswerAccounts() == ["acc-0", "acc-1"])
        // Registering an answer resets a token's recorded requests.
        #expect(tokens.map(requests) == [1, 3])

        clock.advance(31)
        tokens.forEach(ok)
        let out = entries(try await source.collect(context: manualContext(config, trigger: .quickRetry, noAnswerOnly: false)))
        #expect(tokens.map(requests) == [1, 1])
        #expect(out["acc-0"]?.state == .ok)
        #expect(out["acc-1"]?.state == .ok)
    }

    /// FR-005: a quick retry without a click still asks only the due accounts.
    @Test func quickRetryWithoutAClickSkipsOtherNoAnswerAccounts() async throws {
        let tokens = ["na-qr-\(Self.secret)", "na-qr-exhausted-\(Self.secret)"]
        let (source, clock, _, dir, config) = try graceSource("sub-noanswer-qr", tokens: tokens)
        defer { try? FileManager.default.removeItem(at: dir); tokens.forEach { StubURLProtocol.unregister(key: "Bearer \($0)") } }
        ok(tokens[0])
        offline(tokens[1])
        _ = try await source.collect(context: context(config))
        clock.advance(100)
        _ = try await source.collect(context: context(config))
        clock.advance(100)
        offline(tokens[0])
        _ = try await source.collect(context: context(config))
        clock.advance(31)
        tokens.forEach(ok)
        _ = try await source.collect(context: context(config, trigger: .quickRetry))
        // Registering an answer resets a token's recorded requests.
        #expect(tokens.map(requests) == [1, 0])
    }
}

/// spec 016 research R5, FR-005, FR-013: `reachedService` is true only when
/// this refresh sent a request and got an answer that is not a transport
/// failure (spec 010 FR-001 counts HTTP 5xx as transport).
@Suite struct SubscriptionReachedServiceTests {
    static let secret = "SECRET-REACHED-456"
    let far = Date(timeIntervalSince1970: 4_000_000_000)

    private func config(_ directories: [String]) -> Configuration {
        var config = Configuration()
        config.accounts = directories.enumerated().map { index, dir in
            Account(id: "acc-\(index)", displayName: "Account \(index)",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: dir, shownInBar: true, thresholds: [])))
        }
        return config
    }

    private func context(_ config: Configuration, trigger: RefreshTrigger = .scheduled) -> RefreshContext {
        RefreshContext(configuration: config, window: DateInterval(start: Date(), duration: 1), now: Date(), trigger: trigger)
    }

    private func entries(_ output: SourceOutput) -> [String: SubscriptionEntry] {
        if case .subscriptions(let e) = output { return e }
        Issue.record("expected subscriptions output")
        return [:]
    }

    private func source(_ reader: FakeCredentialReader, dir: URL, clock: MutableClock) -> SubscriptionSource {
        let log = DiagnosticLog(fileURL: dir.appendingPathComponent("usage.log"))
        return SubscriptionSource(credentialReader: reader, client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                  log: log, clock: { clock.now() })
    }

    @Test func answersReachTheServiceTransportFailuresDoNot() async throws {
        let dir = try makeTempDirectory("sub-reached")
        defer { try? FileManager.default.removeItem(at: dir) }
        let tokens = ["ok", "401", "429", "garbled", "offline", "503"].map { "reached-\($0)-\(Self.secret)" }
        StubURLProtocol.register(key: "Bearer \(tokens[0])") { _ in (200, Data(usageResponseJSON.utf8)) }
        StubURLProtocol.register(key: "Bearer \(tokens[1])") { _ in (401, Data("{}".utf8)) }
        StubURLProtocol.register(key: "Bearer \(tokens[2])") { _ in (429, Data("{}".utf8)) }
        StubURLProtocol.register(key: "Bearer \(tokens[3])") { _ in (200, Data("not json".utf8)) }
        StubURLProtocol.register(key: "Bearer \(tokens[4])") { _ in throw URLError(.notConnectedToInternet) }
        StubURLProtocol.register(key: "Bearer \(tokens[5])") { _ in (503, Data()) }
        defer { for token in tokens { StubURLProtocol.unregister(key: "Bearer \(token)") } }
        let reader = FakeCredentialReader()
        let directories = tokens.indices.map { "~/reached\($0)" }
        for (token, directory) in zip(tokens, directories) {
            reader.credentials[directory] = OAuthCredential(accessToken: token, expiresAt: far)
        }
        reader.credentials["~/expired"] = OAuthCredential(accessToken: "expired-\(Self.secret)", expiresAt: Date(timeIntervalSince1970: 1))
        let clock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
        let out = entries(try await source(reader, dir: dir, clock: clock)
            .collect(context: context(config(directories + ["~/missing", "~/expired"]))))
        #expect(out["acc-0"]?.reachedService == true, "success")
        #expect(out["acc-1"]?.reachedService == true, "401")
        #expect(out["acc-2"]?.reachedService == true, "429")
        #expect(out["acc-3"]?.reachedService == true, "unreadable answer")
        #expect(out["acc-4"]?.reachedService == false, "transport failure")
        #expect(out["acc-5"]?.reachedService == false, "HTTP 5xx counts as transport")
        #expect(out["acc-6"]?.reachedService == false, "not signed in")
        #expect(out["acc-7"]?.reachedService == false, "expired sign-in")
    }

    @Test func credentialReadFailureDoesNotReachTheService() async throws {
        let dir = try makeTempDirectory("sub-reached-read")
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = FakeCredentialReader()
        reader.error = FakeCredentialReader.ReadFailure()
        let clock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
        let out = entries(try await source(reader, dir: dir, clock: clock).collect(context: context(config(["~/a"]))))
        #expect(out["acc-0"]?.reachedService == false)
    }

    /// An account a quick retry does not request keeps its entry without a
    /// request, so it did not reach the service in this refresh.
    @Test func entryKeptDuringAQuickRetryDidNotReachTheService() async throws {
        let dir = try makeTempDirectory("sub-reached-kept")
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = "kept-a-\(Self.secret)"
        let b = "kept-b-\(Self.secret)"
        StubURLProtocol.register(key: "Bearer \(a)") { _ in (200, Data(usageResponseJSON.utf8)) }
        StubURLProtocol.register(key: "Bearer \(b)") { _ in (200, Data(usageResponseJSON.utf8)) }
        defer { StubURLProtocol.unregister(key: "Bearer \(a)"); StubURLProtocol.unregister(key: "Bearer \(b)") }
        let reader = FakeCredentialReader()
        reader.credentials["~/a"] = OAuthCredential(accessToken: a, expiresAt: far)
        reader.credentials["~/b"] = OAuthCredential(accessToken: b, expiresAt: far)
        let clock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
        let source = source(reader, dir: dir, clock: clock)
        let config = config(["~/a", "~/b"])
        let first = entries(try await source.collect(context: context(config)))
        #expect(first["acc-1"]?.reachedService == true)
        clock.advance(300)
        StubURLProtocol.register(key: "Bearer \(a)") { _ in throw URLError(.notConnectedToInternet) }
        let failed = entries(try await source.collect(context: context(config)))
        #expect(failed["acc-0"]?.reachedService == false)
        #expect(failed["acc-1"]?.reachedService == true)
        clock.advance(30)
        StubURLProtocol.register(key: "Bearer \(a)") { _ in (200, Data(usageResponseJSON.utf8)) }
        let retried = entries(try await source.collect(context: context(config, trigger: .quickRetry)))
        #expect(retried["acc-0"]?.reachedService == true)
        #expect(retried["acc-1"]?.fetchOutcome == nil)
        #expect(retried["acc-1"]?.reachedService == false)
    }

    @Test func reusedEntriesDidNotReachTheService() {
        var entry = SubscriptionEntry(status: nil, state: .ok, fetchOutcome: .success)
        entry.reachedService = true
        #expect(entry.reused(now: Date()).reachedService == false)
        // A transient fact: entries still compare by what they show.
        #expect(entry == SubscriptionEntry(status: nil, state: .ok, fetchOutcome: .success))
    }
}
