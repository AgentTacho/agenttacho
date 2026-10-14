import Foundation

/// A Codex usage answer that is readable but holds no window for the main
/// Codex bucket (spec 007 FR-005).
public enum CodexUsageError: Error, Equatable, Sendable, CustomStringConvertible {
    case noLimits

    public var description: String {
        switch self {
        case .noLimits: return "usage service reported no limits"
        }
    }
}

/// `GET https://chatgpt.com/backend-api/wham/usage`, the request Codex itself
/// sends for its plan limits (spec 007 FR-002, research R1,
/// contracts/codex-usage-endpoint.md section 1). The only host this feature
/// contacts (FR-019); redirects are refused. Errors reuse `UsageEndpointError`
/// and never contain the token (FR-018).
public struct CodexUsageClient: Sendable {
    public static let defaultURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// "AgentMeter/<version>", or "AgentMeter/dev" without a bundle version.
    public static let defaultUserAgent: String = {
        "AgentMeter/" + (AppVersionInfo(infoDictionary: Bundle.main.infoDictionary ?? [:]).version ?? "dev")
    }()

    private let session: URLSession
    private let url: URL
    /// Only for reading a `Retry-After` date.
    private let clock: @Sendable () -> Date
    private let userAgent: String

    /// Ephemeral and cache-free, so the bearer token is never written to an
    /// on-disk cache or cookie store (FR-018), with a total time limit per
    /// request so a stalled answer cannot hold up the refresh.
    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration)
    }()

    /// Refuses every HTTP redirect, so the token and account id are only
    /// ever sent to `url` (FR-018, FR-019). A refused redirect surfaces as
    /// its 3xx status.
    final class RedirectRefuser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            nil
        }
    }

    static let redirectRefuser = RedirectRefuser()

    public init(session: URLSession = CodexUsageClient.defaultSession, url: URL = CodexUsageClient.defaultURL,
                clock: @escaping @Sendable () -> Date = { Date() }, userAgent: String = CodexUsageClient.defaultUserAgent) {
        self.session = session
        self.url = url
        self.clock = clock
        self.userAgent = userAgent
    }

    /// Fetches the plan's current limits, stamped with `observedAt` (the
    /// refresh time, so one refresh shows one time). Throws
    /// `UsageEndpointError` for HTTP, rate-limit, transport and decoding
    /// failures and `CodexUsageError.noLimits` for an answer without windows.
    public func fetch(_ credential: CodexCredential, observedAt: Date) async throws -> CodexLimitObservation {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = credential.accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            // The task delegate refuses redirects whatever session is used.
            (data, response) = try await session.data(for: request, delegate: Self.redirectRefuser)
        } catch let error as URLError {
            throw UsageEndpointError.network(error.localizedDescription)
        } catch {
            throw UsageEndpointError.network(String(describing: type(of: error)))
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageEndpointError.network("no HTTP response")
        }
        // Belt and braces for FR-019: only an answer from the requested URL counts.
        guard http.url == nil || (http.url?.scheme == url.scheme && http.url?.host == url.host && http.url?.path == url.path) else {
            throw UsageEndpointError.network("answer from an unexpected location")
        }
        if http.statusCode == 429 {
            throw UsageEndpointError.rateLimited(
                retryAfter: UsageEndpointClient.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: clock()))
        }
        guard http.statusCode == 200 else {
            throw UsageEndpointError.httpStatus(http.statusCode)
        }
        let body: Body
        do {
            body = try JSONDecoder().decode(Body.self, from: data)
        } catch {
            throw UsageEndpointError.decoding("not a usage answer")
        }
        let windows = [body.rate_limit?.primary_window, body.rate_limit?.secondary_window].compactMap { $0?.window() }
        guard !windows.isEmpty else { throw CodexUsageError.noLimits }
        let reached = body.rate_limit?.limit_reached == true
        return CodexLimitObservation(planType: body.plan_type.flatMap { $0.isEmpty ? nil : $0 }, observedAt: observedAt, origin: .live,
                                     windows: CodexLimitWindow.applyingReachedRule(windows, sourceReportsReached: reached))
    }

    // MARK: - Lenient answer (research R2)

    /// Every field is optional (absent or `null`), but a field of an
    /// unexpected type means the answer changed and fails to decode, so it
    /// is reported as a source error (FR-006). Unknown fields are ignored;
    /// `additional_rate_limits` and `credits` are not read (FR-008).
    private struct Body: Decodable {
        let plan_type: String?
        let rate_limit: RateLimit?

        enum CodingKeys: String, CodingKey { case plan_type, rate_limit }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            plan_type = try c.decodeIfPresent(String.self, forKey: .plan_type)
            rate_limit = try c.decodeIfPresent(RateLimit.self, forKey: .rate_limit)
        }
    }

    private struct RateLimit: Decodable {
        let limit_reached: Bool?
        let primary_window: Window?
        let secondary_window: Window?

        enum CodingKeys: String, CodingKey { case limit_reached, primary_window, secondary_window }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            limit_reached = try c.decodeIfPresent(Bool.self, forKey: .limit_reached)
            primary_window = try c.decodeIfPresent(Window.self, forKey: .primary_window)
            secondary_window = try c.decodeIfPresent(Window.self, forKey: .secondary_window)
        }
    }

    private struct Window: Decodable {
        let used_percent: Double?
        let limit_window_seconds: Double?
        let reset_at: Double?

        enum CodingKeys: String, CodingKey { case used_percent, limit_window_seconds, reset_at }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            used_percent = try c.decodeIfPresent(Double.self, forKey: .used_percent)
            limit_window_seconds = try c.decodeIfPresent(Double.self, forKey: .limit_window_seconds)
            reset_at = try c.decodeIfPresent(Double.self, forKey: .reset_at)
        }

        /// The length in minutes is `ceil(seconds / 60)`; see
        /// `CodexLimitWindow.init?(minutes:usedPercent:resetEpoch:)`.
        func window() -> CodexLimitWindow? {
            CodexLimitWindow(minutes: limit_window_seconds.map { $0 / 60 }, usedPercent: used_percent, resetEpoch: reset_at)
        }
    }
}
