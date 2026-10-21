import Foundation

/// The technical cause of a failed usage request, for the diagnostic log
/// only (spec 021 FR-007, FR-008, research R2). Only error domains and codes
/// are read, never a URL or any other user info text, so it can hold no
/// token, header value, account ID or email address.
public struct NetworkFailureDetail: Equatable, Sendable, CustomStringConvertible {
    public let domain: String
    public let code: Int
    public let underlyingDomain: String?
    public let underlyingCode: Int?
    public let streamErrorCode: Int?

    /// Reads the URL error's code, `NSUnderlyingErrorKey` (domain and code)
    /// and `_kCFStreamErrorCodeKey`.
    public init(_ error: URLError) {
        domain = URLError.errorDomain
        code = error.errorCode
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        underlyingDomain = underlying?.domain
        underlyingCode = underlying?.code
        streamErrorCode = error.userInfo["_kCFStreamErrorCodeKey"] as? Int
    }

    /// "NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009;
    /// stream error 50", parts omitted when absent.
    public var description: String {
        var parts = ["\(domain) \(code)"]
        if let underlyingDomain, let underlyingCode {
            parts.append("underlying \(underlyingDomain) \(underlyingCode)")
        }
        if let streamErrorCode {
            parts.append("stream error \(streamErrorCode)")
        }
        return parts.joined(separator: "; ")
    }
}

public enum UsageEndpointError: Error, Equatable, CustomStringConvertible {
    case httpStatus(Int)
    /// HTTP 429; `retryAfter` from the `Retry-After` header, nil when absent or unreadable.
    case rateLimited(retryAfter: TimeInterval?)
    case decoding(String)
    /// No answer arrived. `detail` names the technical cause for the log
    /// (spec 021 FR-007).
    case network(String, detail: NetworkFailureDetail? = nil)

    /// The text of the dropdown, source errors and notifications; never
    /// the technical detail (spec 021 FR-007).
    public var description: String {
        switch self {
        case .httpStatus(let code): return "usage endpoint returned HTTP \(code)"
        case .rateLimited(let wait):
            return "usage endpoint returned HTTP 429" + (wait.map { ", retry after \(Int($0.rounded(.up))) s" } ?? "")
        case .decoding(let detail): return "usage endpoint response could not be decoded: \(detail)"
        case .network(let detail, _): return "usage endpoint unreachable: \(detail)"
        }
    }

    /// The diagnostic log text: `description` plus " [detail]" when a
    /// technical detail is known (spec 021 FR-007, FR-008).
    public var logDescription: String {
        if case .network(_, let detail?) = self { return description + " [\(detail)]" }
        return description
    }
}

/// Refuses every HTTP redirect, so a bearer token is only ever sent to the
/// URL of its request (spec 001 FR-011a, spec 007 FR-018, FR-019). A refused
/// redirect surfaces as its 3xx status. Used by both usage clients.
final class RedirectRefuser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = RedirectRefuser()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

/// The session settings of both usage clients, and a new session per usage
/// request (spec 021 FR-001, FR-002).
public enum UsageSession {
    /// Ephemeral and cache-free so the bearer token in the request is never
    /// written to the on-disk URL cache or cookie store (spec 001 FR-011a,
    /// spec 007 FR-018). The whole transfer, from sending the request until
    /// the response is complete, is limited to 45 seconds, so a server that
    /// trickles its answer cannot hold the token in an open request;
    /// exceeding it is a transport error (spec 015 FR-010). The 30-second
    /// timeout between bytes is set on each request.
    public static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 45
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return configuration
    }

    /// A new session with `configuration()`. A usage client makes one per
    /// request and invalidates it afterwards, so no connection state of an
    /// earlier request (for example one broken by a network change) is ever
    /// reused (spec 021 FR-001).
    public static func make() -> URLSession {
        URLSession(configuration: configuration())
    }
}

/// Where a usage client takes the session of a request from (spec 021
/// FR-001, research R1).
enum SessionSource: Sendable {
    /// A new session per request, invalidated once the request finished
    /// (production).
    case perRequest(@Sendable () -> URLSession)
    /// One session for every request, never invalidated (tests).
    case shared(URLSession)

    /// Runs `request` with redirects refused, whatever session is used
    /// (spec 001 FR-011a, spec 007 FR-018, FR-019).
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        switch self {
        case .shared(let session):
            return try await session.data(for: request, delegate: RedirectRefuser.shared)
        case .perRequest(let make):
            let session = make()
            // Lets the finished task complete, then releases the session and
            // its connections (spec 021 FR-001).
            defer { session.finishTasksAndInvalidate() }
            return try await session.data(for: request, delegate: RedirectRefuser.shared)
        }
    }
}

/// `GET https://api.anthropic.com/api/oauth/usage` (contracts/external-sources.md).
public struct UsageEndpointClient: Sendable {
    public static let defaultURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let betaHeader = "oauth-2025-04-20"

    private let sessions: SessionSource
    private let url: URL
    private let clock: @Sendable () -> Date

    /// Production: a new session from `makeSession` for every request,
    /// invalidated after it (spec 021 FR-001, FR-002).
    public init(makeSession: @escaping @Sendable () -> URLSession = { UsageSession.make() }, url: URL = UsageEndpointClient.defaultURL,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.sessions = .perRequest(makeSession)
        self.url = url
        self.clock = clock
    }

    /// Tests: every request uses `session`, which is never invalidated.
    public init(session: URLSession, url: URL = UsageEndpointClient.defaultURL, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.sessions = .shared(session)
        self.url = url
        self.clock = clock
    }

    /// The usage request without the free-reset flag.
    public func fetch(token: String) async throws -> SubscriptionStatus {
        try await fetch(token: token, includeTickets: false).status
    }

    /// The usage request; with `includeTickets` it carries the query flag
    /// `cedar_ember=1` and also returns the free-reset block's ticket read,
    /// decoded leniently next to the windows so a bad block never fails the
    /// request (spec 033 FR-001, FR-003, research R1). Without the flag the
    /// read is nil.
    public func fetch(token: String, includeTickets: Bool) async throws -> (status: SubscriptionStatus, tickets: ResetTicketRead?) {
        var request = URLRequest(url: includeTickets ? Self.flagged(url) : url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UsageEndpointClient.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            // The task delegate refuses redirects whatever session is used.
            (data, response) = try await sessions.data(for: request)
        } catch let error as URLError {
            throw UsageEndpointError.network(error.localizedDescription, detail: NetworkFailureDetail(error))
        } catch {
            throw UsageEndpointError.network(String(describing: type(of: error)))
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageEndpointError.network("no HTTP response")
        }
        if http.statusCode == 429 {
            throw UsageEndpointError.rateLimited(
                retryAfter: Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: clock()))
        }
        guard http.statusCode == 200 else {
            throw UsageEndpointError.httpStatus(http.statusCode)
        }
        do {
            let body = try JSONDecoder().decode(Body.self, from: data)
            let status = SubscriptionStatus(fiveHour: try body.five_hour?.window(),
                                            sevenDay: try body.seven_day?.window(),
                                            modelLimits: body.modelLimits(),
                                            fetchedAt: clock())
            return (status, includeTickets ? Self.tickets(in: data, now: clock()) : nil)
        } catch let error as UsageEndpointError {
            throw error
        } catch {
            throw UsageEndpointError.decoding(Self.summarize(error))
        }
    }

    /// The query item that asks for the free-reset block (spec 033 FR-001).
    static let ticketFlag = URLQueryItem(name: "cedar_ember", value: "1")

    /// `url` with the free-reset flag added to its query.
    static func flagged(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []) + [ticketFlag]
        return components.url ?? url
    }

    /// The ticket read of the response's optional `cedar_ember` block; the
    /// body already decoded as a usage answer (spec 033 FR-003).
    private static func tickets(in data: Data, now: Date) -> ResetTicketRead {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return ResetTicketDecoding.claude(cedarEmber: object?["cedar_ember"], now: now)
    }

    /// `Retry-After` as delta-seconds or HTTP-date (RFC 9110); nil when
    /// absent, negative or unreadable. A date in the past means no wait.
    static func parseRetryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) {
            return seconds.isFinite && seconds >= 0 ? seconds : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: raw) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    private struct Body: Decodable {
        let five_hour: WindowBody?
        let seven_day: WindowBody?
        /// Optional extras, decoded leniently: a change in their shape must
        /// never break the 5-hour and 7-day values the app depends on.
        /// Malformed entries stay as nil so indices match the raw array.
        let limits: [LimitBody?]
        let weekly_scoped_shares: [ShareBody]

        enum CodingKeys: String, CodingKey {
            case five_hour, seven_day, limits, weekly_scoped_shares
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            five_hour = try container.decodeIfPresent(WindowBody.self, forKey: .five_hour)
            seven_day = try container.decodeIfPresent(WindowBody.self, forKey: .seven_day)
            limits = ((try? container.decodeIfPresent([Lenient<LimitBody>].self, forKey: .limits)) ?? nil)?
                .map(\.value) ?? []
            weekly_scoped_shares = ((try? container.decodeIfPresent([Lenient<ShareBody>].self, forKey: .weekly_scoped_shares)) ?? nil)?
                .compactMap(\.value) ?? []
        }

        /// `weekly_scoped` entries with a model scope, in response order.
        /// Shares refer to entries by their index in the raw `limits` array.
        func modelLimits() -> [ModelLimit] {
            limits.enumerated().compactMap { index, limit in
                guard let limit, limit.kind == "weekly_scoped",
                      let name = limit.scope?.model?.display_name, !name.isEmpty,
                      let percent = limit.percent,
                      let text = limit.resets_at, let date = UsageEndpointClient.parseDate(text) else { return nil }
                let share = weekly_scoped_shares.first { $0.limit_index == index }?.allowance_percent_of_weekly
                return ModelLimit(modelName: name, utilizationPercent: percent,
                                  resetsAt: UsageEndpointClient.normalizedReset(date),
                                  allowancePercentOfWeekly: share.map { Int($0.rounded()) })
            }
        }
    }

    /// Decodes an element or yields nil, so one malformed entry does not
    /// drop the whole array.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    private struct LimitBody: Decodable {
        let kind: String?
        let percent: Double?
        let resets_at: String?
        let scope: ScopeBody?
    }

    private struct ScopeBody: Decodable {
        let model: ModelBody?
    }

    private struct ModelBody: Decodable {
        let display_name: String?
    }

    private struct ShareBody: Decodable {
        let limit_index: Int
        let allowance_percent_of_weekly: Double?
    }

    private struct WindowBody: Decodable {
        let utilization: Double
        /// Null while the window has not started (0 % utilization).
        let resets_at: String?

        func window() throws -> LimitWindow {
            guard let resets_at else { return LimitWindow(utilizationPercent: utilization, resetsAt: nil) }
            guard let date = UsageEndpointClient.parseDate(resets_at) else {
                throw UsageEndpointError.decoding("unparsable resets_at \"\(resets_at)\"")
            }
            return LimitWindow(utilizationPercent: utilization, resetsAt: UsageEndpointClient.normalizedReset(date))
        }
    }

    /// The endpoint computes `resets_at` relative to the request time with
    /// sub-second jitter, so the same reset arrives as 06:59:59.7 on one call
    /// and 07:00:00.2 on the next. Rounding to the nearest minute keeps the
    /// window end stable across refreshes; otherwise every flip would reset
    /// the threshold baseline (FR-029) and move the group window.
    static func normalizedReset(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }

    private static func summarize(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .dataCorrupted(let ctx): return ctx.debugDescription.isEmpty ? "invalid JSON" : ctx.debugDescription
            case .keyNotFound(let key, _): return "missing key \(key.stringValue)"
            case .typeMismatch(let type, let ctx): return "type mismatch for \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            case .valueNotFound(let type, _): return "missing \(type)"
            @unknown default: return "decoding error"
            }
        }
        return String(describing: error)
    }
}
