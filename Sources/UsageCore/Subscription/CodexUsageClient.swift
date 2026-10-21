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
///
/// Also `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`,
/// the read-only list of free limit resets, with the same sign-in and
/// headers and a 10-second limit (spec 033 FR-001, FR-005, research R3).
public struct CodexUsageClient: Sendable {
    public static let defaultURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    /// The reset credit list (spec 033 FR-001, contracts/external-sources.md).
    public static let defaultResetCreditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    /// The whole credit request, from sending until the answer is
    /// complete, is limited to this, shorter than the plan-limit request, so
    /// it never holds up the refresh (spec 033 FR-005).
    static let resetCreditsTimeout: TimeInterval = 10

    /// "AgentTacho/<version>", or "AgentTacho/dev" without a bundle version.
    public static let defaultUserAgent: String = {
        "AgentTacho/" + (AppVersionInfo(infoDictionary: Bundle.main.infoDictionary ?? [:]).version ?? "dev")
    }()

    private let sessions: SessionSource
    private let url: URL
    private let resetCreditsSessions: SessionSource
    private let resetCreditsURL: URL
    /// For reading a `Retry-After` date and for the usable rule of reset
    /// credits (spec 033 FR-002).
    private let clock: @Sendable () -> Date
    private let userAgent: String

    /// The session settings of the credit request: those of the usage
    /// clients (ephemeral, no cache, no cookies), with 10 seconds for the
    /// whole request (spec 033 FR-005, research R3).
    public static func resetCreditsSessionConfiguration() -> URLSessionConfiguration {
        let configuration = UsageSession.configuration()
        configuration.timeoutIntervalForRequest = resetCreditsTimeout
        configuration.timeoutIntervalForResource = resetCreditsTimeout
        return configuration
    }

    /// Production: a new session from `makeSession` for every request,
    /// invalidated after it. `UsageSession` is ephemeral and cache-free, so
    /// the bearer token is never written to an on-disk cache or cookie store
    /// (FR-018), with a total time limit per request so a stalled answer
    /// cannot hold up the refresh (spec 021 FR-001, FR-002).
    /// The credit request gets a new session from `makeResetCreditsSession`
    /// for every request, also invalidated after it (spec 033 FR-005).
    public init(makeSession: @escaping @Sendable () -> URLSession = { UsageSession.make() }, url: URL = CodexUsageClient.defaultURL,
                makeResetCreditsSession: @escaping @Sendable () -> URLSession = {
                    URLSession(configuration: CodexUsageClient.resetCreditsSessionConfiguration())
                },
                resetCreditsURL: URL = CodexUsageClient.defaultResetCreditsURL,
                clock: @escaping @Sendable () -> Date = { Date() }, userAgent: String = CodexUsageClient.defaultUserAgent) {
        self.sessions = .perRequest(makeSession)
        self.url = url
        self.resetCreditsSessions = .perRequest(makeResetCreditsSession)
        self.resetCreditsURL = resetCreditsURL
        self.clock = clock
        self.userAgent = userAgent
    }

    /// Tests: every request uses `session`, which is never invalidated.
    public init(session: URLSession, url: URL = CodexUsageClient.defaultURL,
                resetCreditsURL: URL = CodexUsageClient.defaultResetCreditsURL,
                clock: @escaping @Sendable () -> Date = { Date() }, userAgent: String = CodexUsageClient.defaultUserAgent) {
        self.sessions = .shared(session)
        self.url = url
        self.resetCreditsSessions = .shared(session)
        self.resetCreditsURL = resetCreditsURL
        self.clock = clock
        self.userAgent = userAgent
    }

    /// A GET of `target` with the headers of the usage request (spec 007
    /// FR-002, spec 033 FR-005).
    private func request(_ target: URL, credential: CodexCredential, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = credential.accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout
        return request
    }

    /// True when the answer comes from `target` itself (spec 007 FR-019).
    private static func isExpected(_ http: HTTPURLResponse, from target: URL) -> Bool {
        http.url == nil || (http.url?.scheme == target.scheme && http.url?.host == target.host && http.url?.path == target.path)
    }

    /// Reads the account's free limit resets (spec 033 FR-001 to FR-005).
    /// Never throws: a failed request (transport error, timeout, any HTTP
    /// status, a refused redirect or an answer from another location) is a
    /// temporary failure, an answer that is not a credit list a clearing
    /// one. Nothing from the answer or the sign-in reaches the result
    /// beyond the expiry times (FR-006).
    public func fetchResetCredits(_ credential: CodexCredential) async -> ResetTicketRead {
        let request = request(resetCreditsURL, credential: credential, timeout: Self.resetCreditsTimeout)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await resetCreditsSessions.data(for: request)
        } catch {
            return .temporaryFailure("transport")
        }
        guard let http = response as? HTTPURLResponse else { return .temporaryFailure("transport") }
        guard Self.isExpected(http, from: resetCreditsURL) else { return .temporaryFailure("unexpected-location") }
        guard http.statusCode == 200 else { return .temporaryFailure("http-\(http.statusCode)") }
        return ResetTicketDecoding.codex(data: data, now: clock())
    }

    /// Fetches the plan's current limits, stamped with `observedAt` (the
    /// refresh time, so one refresh shows one time). Throws
    /// `UsageEndpointError` for HTTP, rate-limit, transport and decoding
    /// failures and `CodexUsageError.noLimits` for an answer without windows.
    public func fetch(_ credential: CodexCredential, observedAt: Date) async throws -> CodexLimitObservation {
        let request = request(url, credential: credential, timeout: 30)

        let data: Data
        let response: URLResponse
        do {
            // The task delegate refuses redirects whatever session is used,
            // so the token and account id only ever go to `url` (FR-018, FR-019).
            (data, response) = try await sessions.data(for: request)
        } catch let error as URLError {
            // The detail is for the log only (spec 021 FR-007).
            throw UsageEndpointError.network(error.localizedDescription, detail: NetworkFailureDetail(error))
        } catch {
            throw UsageEndpointError.network(String(describing: type(of: error)))
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageEndpointError.network("no HTTP response")
        }
        // Belt and braces for FR-019: only an answer from the requested URL
        // counts. It means the service changed, not a connection problem,
        // so it gets no quick retry (spec 010 FR-001).
        guard Self.isExpected(http, from: url) else {
            throw UsageEndpointError.decoding("answer from an unexpected location")
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
