import Foundation
import Testing
@testable import UsageCore

/// The sample answer of contracts/codex-usage-endpoint.md section 1.
let codexUsageSampleJSON = """
{
  "plan_type": "plus",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window":   { "used_percent": 20, "limit_window_seconds": 18000,  "reset_after_seconds": 1000, "reset_at": 1791999819 },
    "secondary_window": { "used_percent": 11, "limit_window_seconds": 604800, "reset_after_seconds": 9000, "reset_at": 1792477782 }
  },
  "credits": { "has_credits": false, "unlimited": false, "balance": "0" },
  "additional_rate_limits": [
    { "limit_name": "premium", "metered_feature": "x",
      "rate_limit": { "limit_reached": true, "primary_window": { "used_percent": 99, "limit_window_seconds": 3600, "reset_at": 1791999000 } } }
  ],
  "rate_limit_reached_type": null
}
"""

/// spec 007 FR-001, FR-002, FR-006, FR-007, FR-018, contracts/codex-usage-endpoint.md section 1.
@Suite struct CodexUsageClientTests {
    static let fetchedAt = isoDate("2026-10-14T14:00:00Z")

    /// A client on the stub session with a fixed clock, and the credential
    /// whose token keys the stub.
    static func client() -> CodexUsageClient {
        CodexUsageClient(session: StubURLProtocol.makeSession(), clock: { fetchedAt }, userAgent: "AgentTacho/test")
    }

    static func credential(_ token: String, accountId: String? = "acct-1") -> CodexCredential {
        CodexCredential(accessToken: token, accountId: accountId, expiresAt: nil)
    }

    static func withStub<T>(_ token: String, status: Int = 200, body: String = codexUsageSampleJSON,
                            headers: [String: String] = [:], _ run: () async throws -> T) async rethrows -> T {
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key, headers: headers) { _ in (status, Data(body.utf8)) }
        defer { StubURLProtocol.unregister(key: key) }
        return try await run()
    }

    @Test func requestShape() async throws {
        let token = "codex-request-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key) { _ in (200, Data(codexUsageSampleJSON.utf8)) }
        defer { StubURLProtocol.unregister(key: key) }
        // The default user agent.
        _ = try await CodexUsageClient(session: StubURLProtocol.makeSession(), clock: { Self.fetchedAt })
            .fetch(Self.credential(token), observedAt: Self.fetchedAt)
        let requests = StubURLProtocol.recordedRequests(key: key)
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-ID") == "acct-1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("AgentTacho/") == true)
    }

    @Test func noAccountIdHeaderWithoutAccountId() async throws {
        let token = "codex-noacct-\(UUID().uuidString)"
        try await Self.withStub(token) {
            _ = try await Self.client().fetch(Self.credential(token, accountId: nil), observedAt: Self.fetchedAt)
            let request = try #require(StubURLProtocol.recordedRequests(key: "Bearer \(token)").first)
            #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-ID") == nil)
        }
    }

    @Test func sampleDecodes() async throws {
        let token = "codex-sample-\(UUID().uuidString)"
        let observation = try await Self.withStub(token) { try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt) }
        #expect(observation.planType == "plus")
        #expect(observation.origin == .live)
        #expect(observation.observedAt == Self.fetchedAt)
        // `additional_rate_limits` and `credits` are ignored (FR-008).
        #expect(observation.windows == [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 20, resetsAt: Date(timeIntervalSince1970: 1791999819), limitReached: false),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: 11, resetsAt: Date(timeIntervalSince1970: 1792477782), limitReached: false),
        ])
    }

    /// research R2: lengths use the ceiling of seconds / 60; a zero-length
    /// window is dropped; `limit_reached` marks the highest window.
    @Test func reachedAndOddWindows() async throws {
        let token = "codex-reached-\(UUID().uuidString)"
        let body = """
        { "plan_type": "plus", "rate_limit": { "limit_reached": true,
          "primary_window": { "used_percent": 97.5, "limit_window_seconds": 17950, "reset_at": 1791999819 },
          "secondary_window": { "used_percent": 40, "limit_window_seconds": 0, "reset_at": 1792477782 } } }
        """
        let observation = try await Self.withStub(token, body: body) { try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt) }
        #expect(observation.windows == [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 97.5, resetsAt: Date(timeIntervalSince1970: 1791999819), limitReached: true),
        ])
    }

    @Test func answerWithoutWindowsIsNoLimits() async throws {
        let token = "codex-nolimits-\(UUID().uuidString)"
        await #expect(throws: CodexUsageError.noLimits) {
            try await Self.withStub(token, body: "{\"plan_type\": \"plus\", \"rate_limit\": null}") {
                try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt)
            }
        }
    }

    /// FR-006: garbage and a changed shape (a known field of another type)
    /// are decoding errors, not missing limits.
    @Test func garbageAndChangedShapeAreDecodingErrors() async throws {
        let bodies = [
            "<html>nope</html>",
            "{\"plan_type\": \"plus\", \"rate_limit\": []}",
            "{\"rate_limit\": {\"primary_window\": {\"used_percent\": \"20\", \"limit_window_seconds\": 18000}}}",
            "{\"rate_limit\": {\"primary_window\": {\"used_percent\": 20, \"limit_window_seconds\": 18000},"
                + " \"secondary_window\": {\"used_percent\": 11, \"limit_window_seconds\": \"weekly\"}}}",
        ]
        for body in bodies {
            let token = "codex-garbage-\(UUID().uuidString)"
            do {
                _ = try await Self.withStub(token, body: body) { try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt) }
                Issue.record("expected an error for \(body)")
            } catch let error as UsageEndpointError {
                guard case .decoding = error else { Issue.record("expected .decoding, got \(error)"); continue }
            }
        }
        // Null fields are absent, not a changed shape.
        let token = "codex-nulls-\(UUID().uuidString)"
        let nulls = "{\"plan_type\": null, \"rate_limit\": {\"limit_reached\": null, \"primary_window\": "
            + "{\"used_percent\": 3, \"limit_window_seconds\": 18000, \"reset_at\": null}, \"secondary_window\": null}}"
        let observation = try await Self.withStub(token, body: nulls) { try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt) }
        #expect(observation.planType == nil)
        #expect(observation.windows == [CodexLimitWindow(lengthMinutes: 300, usedPercent: 3, resetsAt: nil)])
    }

    @Test func httpStatusesMapToErrors() async throws {
        for (status, expected) in [(401, UsageEndpointError.httpStatus(401)), (403, .httpStatus(403)), (500, .httpStatus(500))] {
            let token = "codex-status-\(status)-\(UUID().uuidString)"
            await #expect(throws: expected) {
                try await Self.withStub(token, status: status, body: "{}") { try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt) }
            }
        }
    }

    @Test func rateLimitCarriesRetryAfter() async throws {
        let token = "codex-429-\(UUID().uuidString)"
        await #expect(throws: UsageEndpointError.rateLimited(retryAfter: 120)) {
            try await Self.withStub(token, status: 429, body: "{}", headers: ["Retry-After": "120"]) {
                try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt)
            }
        }
        let bare = "codex-429-bare-\(UUID().uuidString)"
        await #expect(throws: UsageEndpointError.rateLimited(retryAfter: nil)) {
            try await Self.withStub(bare, status: 429, body: "{}") { try await Self.client().fetch(Self.credential(bare), observedAt: Self.fetchedAt) }
        }
    }

    @Test func transportFailureIsNetwork() async throws {
        let token = "codex-offline-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key) { _ in throw URLError(.notConnectedToInternet) }
        defer { StubURLProtocol.unregister(key: key) }
        do {
            _ = try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt)
            Issue.record("expected an error")
        } catch let error as UsageEndpointError {
            guard case .network = error else { Issue.record("expected .network, got \(error)"); return }
        }
    }

    /// spec 021 FR-007: a transport failure carries the URL error's domain,
    /// code, underlying error and stream code; the message stays today's.
    @Test func transportFailureCarriesDetail() async throws {
        let token = "codex-detail-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key) { _ in throw offlineErrorWithDetail(secret: token) }
        defer { StubURLProtocol.unregister(key: key) }
        do {
            _ = try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt)
            Issue.record("expected an error")
        } catch let error as UsageEndpointError {
            guard case .network(let message, let detail) = error else { Issue.record("expected .network, got \(error)"); return }
            #expect(message == offlineDescription)
            #expect(detail?.description == "NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009; stream error 50")
            #expect(!error.logDescription.contains(token))
            #expect(!error.logDescription.contains("acct-1"))
        }
    }

    /// FR-018, FR-019: a redirect is refused, so the token never reaches
    /// another host; the refused redirect is an HTTP status error.
    @Test func redirectIsRefused() async throws {
        let token = "codex-redirect-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        let elsewhere = URL(string: "https://elsewhere.example/steal")!
        StubURLProtocol.register(key: key, redirectingTo: elsewhere) { _ in (200, Data(codexUsageSampleJSON.utf8)) }
        defer { StubURLProtocol.unregister(key: key) }
        await #expect(throws: UsageEndpointError.httpStatus(302)) {
            try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt)
        }
        let urls = StubURLProtocol.recordedRequests(key: key).map { $0.url?.absoluteString }
        #expect(urls == ["https://chatgpt.com/backend-api/wham/usage"])
    }

    /// spec 021 FR-001, SC-001: every request gets a session of its own;
    /// after a no-answer failure the next request runs on a new one.
    @Test func eachRequestUsesItsOwnSession() async throws {
        let token = "codex-fresh-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key) { _ in throw URLError(.notConnectedToInternet) }
        defer { StubURLProtocol.unregister(key: key) }
        let recorder = SessionRecorder()
        let client = CodexUsageClient(makeSession: { recorder.make() }, clock: { Self.fetchedAt }, userAgent: "AgentTacho/test")
        await #expect(throws: UsageEndpointError.self) {
            try await client.fetch(Self.credential(token), observedAt: Self.fetchedAt)
        }
        StubURLProtocol.register(key: key) { _ in (200, Data(codexUsageSampleJSON.utf8)) }
        let observation = try await client.fetch(Self.credential(token), observedAt: Self.fetchedAt)
        #expect(observation.planType == "plus")
        #expect(recorder.sessions.count == 2)
        #expect(recorder.distinctCount == 2)
    }

    /// spec 021 FR-001: the session of a request is invalidated after it, a
    /// failed one included.
    @Test func sessionIsInvalidatedAfterTheRequest() async throws {
        let token = "codex-invalidate-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key) { _ in (200, Data(codexUsageSampleJSON.utf8)) }
        defer { StubURLProtocol.unregister(key: key) }
        let probe = InvalidationProbe()
        let recorder = SessionRecorder(probe: probe)
        let client = CodexUsageClient(makeSession: { recorder.make() }, clock: { Self.fetchedAt }, userAgent: "AgentTacho/test")
        _ = try await client.fetch(Self.credential(token), observedAt: Self.fetchedAt)
        #expect(await probe.waitForInvalidations(1))
        StubURLProtocol.register(key: key) { _ in throw URLError(.timedOut) }
        await #expect(throws: UsageEndpointError.self) {
            try await client.fetch(Self.credential(token), observedAt: Self.fetchedAt)
        }
        #expect(await probe.waitForInvalidations(2))
        #expect(recorder.distinctCount == 2)
    }

    /// spec 021 FR-002: the Codex request uses the shared settings: no
    /// cache, no cookies, 45 s in total (spec 007 FR-018).
    @Test func freshSessionKeepsPrivacySettings() {
        let session = UsageSession.make()
        defer { session.invalidateAndCancel() }
        let configuration = session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.timeoutIntervalForResource == 45)
    }

    /// spec 021 FR-002: a per-request session still refuses redirects, so
    /// the token and account id only go to the usage URL (FR-018, FR-019).
    @Test func redirectStillRefusedWithFreshSession() async throws {
        let token = "codex-fresh-redirect-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key, redirectingTo: URL(string: "https://elsewhere.example/steal")!) { _ in
            (200, Data(codexUsageSampleJSON.utf8))
        }
        defer { StubURLProtocol.unregister(key: key) }
        let client = CodexUsageClient(makeSession: { StubURLProtocol.makeSession() }, clock: { Self.fetchedAt })
        await #expect(throws: UsageEndpointError.httpStatus(302)) {
            try await client.fetch(Self.credential(token), observedAt: Self.fetchedAt)
        }
        let urls = StubURLProtocol.recordedRequests(key: key).map { $0.url?.absoluteString }
        #expect(urls == ["https://chatgpt.com/backend-api/wham/usage"])
    }

    /// FR-018: no error names the token or the account id.
    @Test func errorsNeverContainTheToken() async throws {
        let token = "SECRET-CODEX-TOKEN-\(UUID().uuidString)"
        let credential = CodexCredential(accessToken: token, accountId: "SECRET-ACCOUNT-456", expiresAt: nil)
        for (status, body) in [(200, "garbage"), (200, "{}"), (401, "{}"), (429, "{}"), (502, "{}")] {
            do {
                _ = try await Self.withStub(token, status: status, body: body) { try await Self.client().fetch(credential, observedAt: Self.fetchedAt) }
                Issue.record("expected an error for \(status)")
            } catch {
                #expect(!String(describing: error).contains("SECRET"))
                #expect(!String(reflecting: error).contains("SECRET"))
            }
        }
    }
    /// spec 010 FR-001: an answer from another location means the service
    /// changed; it is not a transport failure and gets no quick retry.
    @Test func answerFromAnotherHostIsServiceChanged() async throws {
        let token = "codex-location-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key, respondingFrom: URL(string: "https://elsewhere.example/backend-api/wham/usage")!) { _ in
            (200, Data(codexUsageSampleJSON.utf8))
        }
        defer { StubURLProtocol.unregister(key: key) }
        await #expect(throws: UsageEndpointError.decoding("answer from an unexpected location")) {
            try await Self.client().fetch(Self.credential(token), observedAt: Self.fetchedAt)
        }
    }
}
