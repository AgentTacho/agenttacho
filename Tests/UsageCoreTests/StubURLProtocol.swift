import Foundation

/// Intercepts every request on a session configured with it and answers from
/// a handler registered per test. Handlers are keyed by a token header (or,
/// without one, by the request URL) so that parallel tests do not interfere.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var requests: [String: [URLRequest]] = [:]
    nonisolated(unsafe) private static var responseHeaders: [String: [String: String]] = [:]
    nonisolated(unsafe) private static var redirects: [String: URL] = [:]
    nonisolated(unsafe) private static var responseURLs: [String: URL] = [:]

    static func register(key: String, handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        handlers[key] = handler
        requests[key] = []
        responseURLs[key] = nil
    }

    /// Like `register(key:handler:)`, with extra response headers.
    static func register(key: String, headers: [String: String], handler: @escaping Handler) {
        register(key: key, handler: handler)
        lock.lock(); defer { lock.unlock() }
        responseHeaders[key] = headers
    }

    /// Answers requests of `key` for any URL other than `target` with a
    /// 302 redirect to `target`; requests to `target` go to the handler.
    static func register(key: String, redirectingTo target: URL, handler: @escaping Handler) {
        register(key: key, handler: handler)
        lock.lock(); defer { lock.unlock() }
        redirects[key] = target
    }

    /// Like `register(key:handler:)`, but the answer claims to come from
    /// `location` instead of the request URL.
    static func register(key: String, respondingFrom location: URL, handler: @escaping Handler) {
        register(key: key, handler: handler)
        lock.lock(); defer { lock.unlock() }
        responseURLs[key] = location
    }

    static func unregister(key: String) {
        lock.lock(); defer { lock.unlock() }
        responseURLs[key] = nil
        handlers[key] = nil
        requests[key] = nil
        responseHeaders[key] = nil
        redirects[key] = nil
    }

    static func recordedRequests(key: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests[key] ?? []
    }

    /// The recorded requests of `key` without the Codex reset credit
    /// requests, which follow every successful Codex plan-limit request
    /// (spec 033 FR-001): the usage requests that existing tests count.
    static func usageRequests(key: String) -> [URLRequest] {
        recordedRequests(key: key).filter { $0.url?.path.contains("rate-limit-reset-credits") != true }
    }

    /// The recorded Codex reset credit requests of `key` (spec 033 FR-001).
    static func resetCreditRequests(key: String) -> [URLRequest] {
        recordedRequests(key: key).filter { $0.url?.path.contains("rate-limit-reset-credits") == true }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// A stub session with a session delegate, such as an `InvalidationProbe`.
    static func makeSession(delegate: URLSessionDelegate) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    static let keyHeader = "X-Stub-Key"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Requests without a key header (the price list download) are keyed
        // by their URL; each test injects a unique URL.
        let key = request.value(forHTTPHeaderField: Self.keyHeader)
            ?? request.value(forHTTPHeaderField: "Authorization")
            ?? request.url?.absoluteString ?? ""
        Self.lock.lock()
        let handler = Self.handlers[key]
        let extraHeaders = Self.responseHeaders[key] ?? [:]
        let redirect = Self.redirects[key]
        let responseURL = Self.responseURLs[key]
        Self.requests[key, default: []].append(request)
        Self.lock.unlock()
        if let redirect, request.url != redirect {
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": redirect.absoluteString])!
            var next = request
            next.url = redirect
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, data) = try handler(request)
            let fields = ["Content-Type": "application/json"].merging(extraHeaders) { _, new in new }
            let response = HTTPURLResponse(url: responseURL ?? request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// A `makeSession` closure for the usage clients that builds a new stub
/// session per call and keeps every session it built, so their identities
/// can be compared (spec 021 FR-001, SC-001). The sessions are retained, so
/// an identifier is never reused by a later allocation.
final class SessionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var built: [URLSession] = []
    private let probe: InvalidationProbe?

    init(probe: InvalidationProbe? = nil) {
        self.probe = probe
    }

    func make() -> URLSession {
        let session = probe.map { StubURLProtocol.makeSession(delegate: $0) } ?? StubURLProtocol.makeSession()
        lock.lock(); defer { lock.unlock() }
        built.append(session)
        return session
    }

    var sessions: [URLSession] {
        lock.lock(); defer { lock.unlock() }
        return built
    }

    var distinctCount: Int {
        Set(sessions.map(ObjectIdentifier.init)).count
    }
}

/// Counts `didBecomeInvalidWithError` calls of the sessions it is the
/// delegate of (spec 021 FR-001).
final class InvalidationProbe: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var invalidations: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }

    /// Waits up to `timeout` seconds for `expected` invalidations.
    func waitForInvalidations(_ expected: Int, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while invalidations < expected {
            if Date() >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

/// The readable text URLSession puts into its offline error.
let offlineDescription = "The Internet connection appears to be offline."

/// "The Internet connection appears to be offline" as URLSession reports
/// it, with its readable text, an underlying CFNetwork error and a stream
/// error code (spec 021 FR-007). `secret` goes into user info that must never be logged: the
/// failing URL, a header-like key and the underlying error's own user info.
func offlineErrorWithDetail(secret: String = "SECRET-NOT-LOGGED") -> URLError {
    URLError(.notConnectedToInternet, userInfo: [
        NSLocalizedDescriptionKey: offlineDescription,
        NSUnderlyingErrorKey: NSError(domain: "kCFErrorDomainCFNetwork", code: -1009,
                                      userInfo: ["Authorization": "Bearer \(secret)"]),
        "_kCFStreamErrorCodeKey": 50,
        "_kCFStreamErrorDomainKey": 1,
        NSURLErrorFailingURLStringErrorKey: "https://leak.example/usage?token=\(secret)",
        "X-Header": secret,
    ])
}
