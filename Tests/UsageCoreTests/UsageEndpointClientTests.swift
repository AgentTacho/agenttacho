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
}
