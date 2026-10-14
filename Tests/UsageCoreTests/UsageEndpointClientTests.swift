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
            guard case .network(let message) = error else {
                Issue.record("expected .network, got \(error)")
                return
            }
            #expect(!message.contains(token))
        }
    }

    @Test func defaultSessionNeverPersistsRequestsOrCookies() {
        let configuration = UsageEndpointClient.defaultSession.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
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
