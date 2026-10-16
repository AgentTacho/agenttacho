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

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
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
