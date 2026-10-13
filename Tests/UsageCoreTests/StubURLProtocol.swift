import Foundation

/// Intercepts every request on a session configured with it and answers from
/// a handler registered per test. Handlers are keyed by a token header (or,
/// without one, by the request URL) so that parallel tests do not interfere.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var requests: [String: [URLRequest]] = [:]

    static func register(key: String, handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        handlers[key] = handler
        requests[key] = []
    }

    static func unregister(key: String) {
        lock.lock(); defer { lock.unlock() }
        handlers[key] = nil
        requests[key] = nil
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
        Self.requests[key, default: []].append(request)
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
