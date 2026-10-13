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
            Account(id: "acc-\(index)", label: "A\(index)", displayName: "Account \(index)",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: dir, shownInBar: true, thresholds: [])))
        }
        return config
    }

    private func context(_ config: Configuration) -> RefreshContext {
        RefreshContext(configuration: config, window: DateInterval(start: Date(), duration: 1), now: Date())
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

        StubURLProtocol.register(key: "Bearer \(token)") { _ in (503, Data()) }
        let second = entries(try await source.collect(context: context(makeConfig())))
        guard case .stale(let lastGoodAt, let error) = second["acc-0"]?.state else {
            Issue.record("expected stale, got \(String(describing: second["acc-0"]?.state))")
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
        StubURLProtocol.register(key: "Bearer \(token)") { _ in throw URLError(.notConnectedToInternet) }
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
}
