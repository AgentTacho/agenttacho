import Foundation
import Testing
@testable import UsageCore

let usageResponseJSON = """
{
  "five_hour": { "utilization": 8.0, "resets_at": "2026-10-13T10:49:59.706966+00:00" },
  "seven_day": { "utilization": 50.4, "resets_at": "2026-10-16T06:59:59.706992+00:00" },
  "seven_day_opus": null,
  "limits": [],
  "extra_usage": { "enabled": false }
}
"""

@Suite struct UsageEndpointClientTests {
    private func makeClient(key: String, handler: @escaping StubURLProtocol.Handler) -> UsageEndpointClient {
        StubURLProtocol.register(key: "Bearer \(key)", handler: handler)
        return UsageEndpointClient(session: StubURLProtocol.makeSession())
    }

    /// FR-011a: a redirect is refused, so the Claude token never reaches
    /// another host; the refused redirect is an HTTP status error.
    @Test func redirectIsRefused() async throws {
        let token = "claude-redirect-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        let elsewhere = URL(string: "https://elsewhere.example/steal")!
        StubURLProtocol.register(key: key, redirectingTo: elsewhere) { _ in (200, Data(usageResponseJSON.utf8)) }
        defer { StubURLProtocol.unregister(key: key) }
        let client = UsageEndpointClient(session: StubURLProtocol.makeSession())
        await #expect(throws: UsageEndpointError.httpStatus(302)) {
            try await client.fetch(token: token)
        }
        let urls = StubURLProtocol.recordedRequests(key: key).map { $0.url?.absoluteString }
        #expect(urls == ["https://api.anthropic.com/api/oauth/usage"])
    }

    @Test func decodesBothWindows() async throws {
        let token = "tok-decode"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let client = makeClient(key: token) { _ in (200, Data(usageResponseJSON.utf8)) }
        let status = try await client.fetch(token: token)
        #expect(status.fiveHour?.utilizationPercent == 8.0)
        #expect(status.sevenDay?.utilizationPercent == 50.4)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        // Reset times are rounded to the whole minute (see resetJitterIsNormalized).
        #expect(status.fiveHour?.resetsAt == iso.date(from: "2026-10-13T10:50:00Z"))
        #expect(status.sevenDay?.resetsAt == iso.date(from: "2026-10-16T07:00:00Z"))
        #expect(status.barPercent == 50)
    }

    /// Shape observed on 2026-10-13: a `weekly_scoped` limit for one model,
    /// with its allowance in `weekly_scoped_shares` keyed by the raw index.
    @Test func decodesModelScopedWeeklyLimits() async throws {
        let token = "tok-scoped"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let json = """
        {
          "five_hour": { "utilization": 22.0, "resets_at": "2026-10-13T15:49:59.593078+00:00" },
          "seven_day": { "utilization": 85.0, "resets_at": "2026-10-16T06:59:59.593103+00:00" },
          "limits": [
            { "kind": "session", "group": "session", "percent": 22, "resets_at": "2026-10-13T15:49:59.593078+00:00", "scope": null },
            { "kind": "weekly_all", "group": "weekly", "percent": 85, "resets_at": "2026-10-16T06:59:59.593103+00:00", "scope": null },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 100, "severity": "critical",
              "resets_at": "2026-10-16T06:59:59.593324+00:00",
              "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": true }
          ],
          "weekly_scoped_shares": [ { "limit_index": 2, "used_percent_of_weekly": 50, "allowance_percent_of_weekly": 50 } ]
        }
        """
        let client = makeClient(key: token) { _ in (200, Data(json.utf8)) }
        let status = try await client.fetch(token: token)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        #expect(status.modelLimits == [ModelLimit(modelName: "Fable", utilizationPercent: 100,
                                                  resetsAt: iso.date(from: "2026-10-16T07:00:00Z")!,
                                                  allowancePercentOfWeekly: 50)])
        #expect(status.barPercent == 85)
    }

    /// Unexpected shapes in the optional extras never break the main windows,
    /// and a malformed entry does not shift the share index of later ones.
    @Test func malformedLimitsAreIgnored() async throws {
        let token = "tok-malformed"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let json = """
        {
          "five_hour": null,
          "seven_day": { "utilization": 10.0, "resets_at": "2026-10-16T06:59:59+00:00" },
          "limits": [
            "not an object",
            { "kind": "weekly_scoped", "percent": 40, "resets_at": "2026-10-16T06:59:59+00:00",
              "scope": { "model": { "display_name": "Fable" } } },
            { "kind": "weekly_scoped", "percent": 5, "resets_at": "later", "scope": { "model": { "display_name": "Opus" } } }
          ],
          "weekly_scoped_shares": { "unexpected": true }
        }
        """
        let client = makeClient(key: token) { _ in (200, Data(json.utf8)) }
        let status = try await client.fetch(token: token)
        #expect(status.sevenDay?.utilizationPercent == 10)
        #expect(status.modelLimits.map(\.modelName) == ["Fable"])
        #expect(status.modelLimits.first?.allowancePercentOfWeekly == nil)

        let notAnArray = """
        { "five_hour": null, "seven_day": null, "limits": 7 }
        """
        StubURLProtocol.register(key: "Bearer \(token)") { _ in (200, Data(notAnArray.utf8)) }
        #expect(try await client.fetch(token: token).modelLimits.isEmpty)
    }

    /// The endpoint computes resets_at relative to the request time, so the
    /// same reset arrives as 06:59:59.7 on one call and 07:00:00.2 on the
    /// next. Both must decode to the same instant, or every refresh would
    /// move the window end and reset the threshold baseline.
    @Test func resetJitterIsNormalized() async throws {
        let token = "tok-jitter"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let before = """
        { "five_hour": null, "seven_day": { "utilization": 1.0, "resets_at": "2026-10-16T06:59:59.706992+00:00" } }
        """
        let after = """
        { "five_hour": null, "seven_day": { "utilization": 1.0, "resets_at": "2026-10-16T07:00:00.213004+00:00" } }
        """
        let client = makeClient(key: token) { _ in (200, Data(before.utf8)) }
        let first = try await client.fetch(token: token)
        StubURLProtocol.register(key: "Bearer \(token)") { _ in (200, Data(after.utf8)) }
        let second = try await client.fetch(token: token)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        #expect(first.sevenDay?.resetsAt == iso.date(from: "2026-10-16T07:00:00Z"))
        #expect(first.sevenDay?.resetsAt == second.sevenDay?.resetsAt)
    }

    @Test func nullWindowIsUnavailable() async throws {
        let token = "tok-null"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let json = """
        { "five_hour": null, "seven_day": { "utilization": 12.6, "resets_at": "2026-10-16T06:59:59+00:00" } }
        """
        let client = makeClient(key: token) { _ in (200, Data(json.utf8)) }
        let status = try await client.fetch(token: token)
        #expect(status.fiveHour == nil)
        #expect(status.sevenDay?.utilizationPercent == 12.6)
        #expect(status.barPercent == 13)

        let both = """
        { "five_hour": null, "seven_day": null }
        """
        StubURLProtocol.register(key: "Bearer \(token)") { _ in (200, Data(both.utf8)) }
        let none = try await client.fetch(token: token)
        #expect(none.fiveHour == nil)
        #expect(none.sevenDay == nil)
        #expect(none.barPercent == nil)
    }

    /// The bar follows the 7-day window only, even when the 5-hour window
    /// is higher, and never falls back to the 5-hour value.
    @Test func barShowsTheSevenDayWindowOnly() {
        let reset = isoDate("2026-10-16T07:00:00Z")
        let both = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 90, resetsAt: reset),
                                      sevenDay: LimitWindow(utilizationPercent: 40.4, resetsAt: reset), fetchedAt: reset)
        #expect(both.barPercent == 40)
        let noWeekly = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 90, resetsAt: reset),
                                          sevenDay: nil, fetchedAt: reset)
        #expect(noWeekly.barPercent == nil)
    }

    /// An unused window has no reset yet: the endpoint reports 0 % with
    /// `resets_at: null`. That is a real 0 %, not an unavailable window.
    @Test func unstartedWindowHasNoReset() async throws {
        let token = "tok-unstarted"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let json = """
        { "five_hour": { "utilization": 0.0, "resets_at": null },
          "seven_day": { "utilization": 0.0, "resets_at": null } }
        """
        let client = makeClient(key: token) { _ in (200, Data(json.utf8)) }
        let status = try await client.fetch(token: token)
        #expect(status.fiveHour == LimitWindow(utilizationPercent: 0, resetsAt: nil))
        #expect(status.sevenDay == LimitWindow(utilizationPercent: 0, resetsAt: nil))
        #expect(status.barPercent == 0)
    }

    @Test func mapsNon200ToHTTPStatus() async throws {
        for code in [401, 403, 500] {
            let token = "tok-\(code)"
            defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
            let client = makeClient(key: token) { _ in (code, Data("{\"error\":\"nope\"}".utf8)) }
            do {
                _ = try await client.fetch(token: token)
                Issue.record("expected failure for \(code)")
            } catch let error as UsageEndpointError {
                #expect(error == .httpStatus(code))
            }
        }
    }

    @Test func mapsUndecodableBodyToDecodingError() async throws {
        let token = "tok-garbage"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let client = makeClient(key: token) { _ in (200, Data("<html>".utf8)) }
        do {
            _ = try await client.fetch(token: token)
            Issue.record("expected decoding failure")
        } catch let error as UsageEndpointError {
            guard case .decoding = error else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
        }
    }

    @Test func mapsTransportFailureToNetworkError() async throws {
        let token = "tok-network"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let client = makeClient(key: token) { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.fetch(token: token)
            Issue.record("expected network failure")
        } catch let error as UsageEndpointError {
            guard case .network(let message, _) = error else {
                Issue.record("expected .network, got \(error)")
                return
            }
            #expect(!message.contains(token))
        }
    }

    /// spec 021 FR-007: a transport failure carries the URL error's domain,
    /// code, underlying error and stream code; the message stays today's.
    @Test func transportFailureCarriesDetail() async throws {
        let token = "tok-detail-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key) { _ in throw offlineErrorWithDetail(secret: token) }
        defer { StubURLProtocol.unregister(key: key) }
        let client = UsageEndpointClient(session: StubURLProtocol.makeSession())
        do {
            _ = try await client.fetch(token: token)
            Issue.record("expected network failure")
        } catch let error as UsageEndpointError {
            guard case .network(let message, let detail) = error else {
                Issue.record("expected .network, got \(error)")
                return
            }
            #expect(message == offlineDescription)
            #expect(detail?.description == "NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009; stream error 50")
            #expect(error.description == "usage endpoint unreachable: \(message)")
            #expect(!error.logDescription.contains(token))
            #expect(error.logDescription.hasSuffix("[NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009; stream error 50]"))
        }
    }

    @Test func defaultSessionNeverPersistsRequestsOrCookies() {
        let configuration = UsageSession.configuration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    /// Spec 015 FR-010: a total time limit of 45 seconds on the session, as
    /// for the Codex request, next to the 30-second timeout on the request.
    @Test func requestHasATotalTimeLimit() async throws {
        #expect(UsageSession.configuration().timeoutIntervalForResource == 45)
        let token = "tok-timeout"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let client = makeClient(key: token) { _ in (200, Data(usageResponseJSON.utf8)) }
        _ = try await client.fetch(token: token)
        let request = try #require(StubURLProtocol.recordedRequests(key: "Bearer \(token)").first)
        #expect(request.timeoutInterval == 30)
    }

    /// spec 021 FR-001, SC-001: every request gets a session of its own;
    /// after a no-answer failure the next request runs on a new one.
    @Test func eachRequestUsesItsOwnSession() async throws {
        let token = "tok-fresh-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key) { _ in throw URLError(.notConnectedToInternet) }
        defer { StubURLProtocol.unregister(key: key) }
        let recorder = SessionRecorder()
        let client = UsageEndpointClient(makeSession: { recorder.make() })
        await #expect(throws: UsageEndpointError.self) { try await client.fetch(token: token) }
        StubURLProtocol.register(key: key) { _ in (200, Data(usageResponseJSON.utf8)) }
        let status = try await client.fetch(token: token)
        #expect(status.sevenDay?.utilizationPercent == 50.4)
        #expect(recorder.sessions.count == 2)
        #expect(recorder.distinctCount == 2)
    }

    /// spec 021 FR-001: the session of a request is invalidated after it, a
    /// failed one included, so no network state outlives the request.
    @Test func sessionIsInvalidatedAfterTheRequest() async throws {
        let token = "tok-invalidate-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key) { _ in (200, Data(usageResponseJSON.utf8)) }
        defer { StubURLProtocol.unregister(key: key) }
        let probe = InvalidationProbe()
        let recorder = SessionRecorder(probe: probe)
        let client = UsageEndpointClient(makeSession: { recorder.make() })
        _ = try await client.fetch(token: token)
        #expect(await probe.waitForInvalidations(1))
        StubURLProtocol.register(key: key) { _ in throw URLError(.networkConnectionLost) }
        await #expect(throws: UsageEndpointError.self) { try await client.fetch(token: token) }
        #expect(await probe.waitForInvalidations(2))
        #expect(recorder.distinctCount == 2)
    }

    /// spec 021 FR-002: a fresh session keeps every privacy rule of the
    /// former shared one (spec 001 FR-011a, spec 015 FR-010).
    @Test func freshSessionKeepsPrivacySettings() {
        let first = UsageSession.make()
        let second = UsageSession.make()
        defer { first.invalidateAndCancel(); second.invalidateAndCancel() }
        #expect(first !== second)
        for configuration in [UsageSession.configuration(), first.configuration] {
            #expect(configuration.urlCache == nil)
            #expect(configuration.httpCookieStorage == nil)
            #expect(configuration.httpShouldSetCookies == false)
            #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
            #expect(configuration.timeoutIntervalForResource == 45)
        }
    }

    /// spec 021 FR-002: a per-request session still refuses redirects.
    @Test func redirectStillRefusedWithFreshSession() async throws {
        let token = "claude-fresh-redirect-\(UUID().uuidString)"
        let key = "Bearer \(token)"
        StubURLProtocol.register(key: key, redirectingTo: URL(string: "https://elsewhere.example/steal")!) { _ in
            (200, Data(usageResponseJSON.utf8))
        }
        defer { StubURLProtocol.unregister(key: key) }
        let client = UsageEndpointClient(makeSession: { StubURLProtocol.makeSession() })
        await #expect(throws: UsageEndpointError.httpStatus(302)) {
            try await client.fetch(token: token)
        }
        let urls = StubURLProtocol.recordedRequests(key: key).map { $0.url?.absoluteString }
        #expect(urls == ["https://api.anthropic.com/api/oauth/usage"])
    }

    @Test func unparsableResetDateIsADecodingError() async throws {
        let token = "tok-baddate"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let json = """
        { "five_hour": { "utilization": 1.0, "resets_at": "tomorrow" }, "seven_day": null }
        """
        let client = makeClient(key: token) { _ in (200, Data(json.utf8)) }
        do {
            _ = try await client.fetch(token: token)
            Issue.record("expected decoding failure")
        } catch let error as UsageEndpointError {
            guard case .decoding(let detail) = error else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
            #expect(detail.contains("resets_at"))
        }
    }

    @Test func sendsBearerAndBetaHeaders() async throws {
        let token = "tok-headers-SECRET"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let client = makeClient(key: token) { _ in (200, Data(usageResponseJSON.utf8)) }
        _ = try await client.fetch(token: token)
        let requests = StubURLProtocol.recordedRequests(key: "Bearer \(token)")
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    }

    private func rateLimitError(headers: [String: String], key: String, now: Date = Date()) async -> UsageEndpointError? {
        let token = "tok-429-\(key)" // notsecret
        StubURLProtocol.register(key: "Bearer \(token)", headers: headers) { _ in (429, Data("{}".utf8)) }
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let client = UsageEndpointClient(session: StubURLProtocol.makeSession(), clock: { now })
        do {
            _ = try await client.fetch(token: token)
            Issue.record("expected a 429 failure")
            return nil
        } catch let error as UsageEndpointError {
            return error
        } catch {
            Issue.record("unexpected error \(error)")
            return nil
        }
    }

    @Test func rateLimitWithDeltaSeconds() async {
        let error = await rateLimitError(headers: ["Retry-After": "120"], key: "delta")
        #expect(error == .rateLimited(retryAfter: 120))
        #expect(error?.description == "usage endpoint returned HTTP 429, retry after 120 s")
    }

    @Test func rateLimitWithHTTPDate() async {
        let now = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!
        let error = await rateLimitError(headers: ["Retry-After": "Tue, 13 Oct 2026 12:02:00 GMT"], key: "date", now: now)
        #expect(error == .rateLimited(retryAfter: 120))
    }

    @Test func rateLimitWithoutOrWithUnreadableHeader() async {
        #expect(await rateLimitError(headers: [:], key: "none") == .rateLimited(retryAfter: nil))
        #expect(await rateLimitError(headers: ["Retry-After": "soon"], key: "bad") == .rateLimited(retryAfter: nil))
        #expect(await rateLimitError(headers: ["Retry-After": "-5"], key: "neg") == .rateLimited(retryAfter: nil))
        let none = UsageEndpointError.rateLimited(retryAfter: nil)
        #expect(none.description == "usage endpoint returned HTTP 429")
    }

    @Test func httpDateInThePastMeansNoWait() {
        let now = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!
        #expect(UsageEndpointClient.parseRetryAfter("Tue, 13 Oct 2026 11:00:00 GMT", now: now) == 0)
    }
}

/// spec 033 FR-001, FR-003, research R1: the free-reset flag on the usage
/// request and the lenient decoding of its block next to the windows.
@Suite struct UsageEndpointTicketTests {
    static let now = isoDate("2026-10-12T12:00:00Z")

    private func client(token: String, json: String, status: Int = 200) -> UsageEndpointClient {
        StubURLProtocol.register(key: "Bearer \(token)") { _ in (status, Data(json.utf8)) }
        return UsageEndpointClient(session: StubURLProtocol.makeSession(), clock: { Self.now })
    }

    private func withBlock(_ block: String) -> String {
        """
        {
          "five_hour": { "utilization": 8.0, "resets_at": "2026-10-13T10:49:59.706966+00:00" },
          "seven_day": { "utilization": 50.4, "resets_at": "2026-10-16T06:59:59.706992+00:00" },
          "cedar_ember": \(block)
        }
        """
    }

    @Test func flagAddsTheQueryItemAndKeepsTheHeaders() async throws {
        let token = "tok-flag-\(UUID().uuidString)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let client = client(token: token, json: usageResponseJSON)
        _ = try await client.fetch(token: token, includeTickets: true)
        _ = try await client.fetch(token: token, includeTickets: false)
        let requests = StubURLProtocol.recordedRequests(key: "Bearer \(token)")
        #expect(requests.map { $0.url?.absoluteString } == ["https://api.anthropic.com/api/oauth/usage?cedar_ember=1",
                                                             "https://api.anthropic.com/api/oauth/usage"])
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
            #expect(request.value(forHTTPHeaderField: "anthropic-beta") == UsageEndpointClient.betaHeader)
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.httpMethod == "GET")
        }
    }

    @Test func validBlockComesWithTheWindows() async throws {
        let token = "tok-block-\(UUID().uuidString)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let json = withBlock("""
        { "eligible": true, "grants": [
          { "id": "g-1", "resets_left": 1, "resets_total": 1, "starts_at": "2026-10-10T08:00:00Z", "ends_at": "2026-10-14T08:00:00Z", "paused": false },
          { "id": "g-2", "resets_left": 1, "resets_total": 1, "starts_at": null, "ends_at": null, "paused": false } ] }
        """)
        let result = try await client(token: token, json: json).fetch(token: token, includeTickets: true)
        #expect(result.status.sevenDay?.utilizationPercent == 50.4)
        #expect(result.tickets == .tickets([ResetTicket(expiresAt: isoDate("2026-10-14T08:00:00Z")), ResetTicket(expiresAt: nil)]))
    }

    @Test func malformedBlockStillReturnsTheWindows() async throws {
        let token = "tok-bad-block-\(UUID().uuidString)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let result = try await client(token: token, json: withBlock("{ \"eligible\": \"yes\", \"grants\": 3 }"))
            .fetch(token: token, includeTickets: true)
        #expect(result.status.fiveHour?.utilizationPercent == 8.0)
        #expect(result.status.sevenDay?.utilizationPercent == 50.4)
        #expect(result.tickets == .clearingFailure("malformed"))
    }

    @Test func missingBlockIsNoTickets() async throws {
        let token = "tok-no-block-\(UUID().uuidString)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let result = try await client(token: token, json: usageResponseJSON).fetch(token: token, includeTickets: true)
        #expect(result.tickets == .tickets([]))
    }

    @Test func withoutTheFlagNoTicketsAreRead() async throws {
        let token = "tok-no-flag-\(UUID().uuidString)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let json = withBlock("{ \"eligible\": true, \"grants\": [ { \"resets_left\": 1, \"paused\": false } ] }")
        let result = try await client(token: token, json: json).fetch(token: token, includeTickets: false)
        #expect(result.tickets == nil)
        #expect(result.status.sevenDay?.utilizationPercent == 50.4)
    }

    @Test func plainFetchIsUnchanged() async throws {
        let token = "tok-plain-\(UUID().uuidString)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let client = client(token: token, json: withBlock("{ \"eligible\": true, \"grants\": [] }"))
        let status = try await client.fetch(token: token)
        #expect(status.sevenDay?.utilizationPercent == 50.4)
        #expect(StubURLProtocol.recordedRequests(key: "Bearer \(token)").map { $0.url?.absoluteString }
            == ["https://api.anthropic.com/api/oauth/usage"])
    }

    @Test func httpErrorsThrowAsBefore() async throws {
        let token = "tok-400-\(UUID().uuidString)"
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let client = client(token: token, json: "{}", status: 400)
        await #expect(throws: UsageEndpointError.httpStatus(400)) {
            _ = try await client.fetch(token: token, includeTickets: true)
        }
    }
}
