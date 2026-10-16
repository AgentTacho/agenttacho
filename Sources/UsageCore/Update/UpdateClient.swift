import Foundation

/// Why an update request failed (spec 013 FR-004, FR-005, FR-014;
/// contracts/update-requests.md).
public enum UpdateClientError: Error, Equatable, CustomStringConvertible {
    case network(String)
    case httpStatus(Int)
    /// HTTP 403 or 429 from GitHub.
    case rateLimited
    /// A starting URL or a redirect left the host allowlist (spec 013 FR-005).
    case unexpectedHost
    /// A body exceeded its cap (1 MB, 64 KB or 100 MB).
    case tooLarge
    case decoding(String)

    /// Short text for the update line and the diagnostic log.
    public var description: String {
        switch self {
        case .network(let detail): return detail.isEmpty ? "GitHub is not reachable" : detail
        case .httpStatus(let code): return "GitHub returned HTTP \(code)"
        case .rateLimited: return "GitHub rate limit reached"
        case .unexpectedHost: return "redirected to an unexpected host"
        case .tooLarge: return "response too large"
        case .decoding(let detail): return "unexpected response from GitHub (\(detail))"
        }
    }
}

/// Allows a redirect only to an allowlisted https host and remembers a
/// refusal, so the caller can report `unexpectedHost` (spec 013 FR-005,
/// research R2). One instance per request.
final class UpdateRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var refusedFlag = false

    var refused: Bool {
        lock.lock(); defer { lock.unlock() }
        return refusedFlag
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        if let url = request.url, UpdateHostPolicy.allows(url) { return request }
        lock.lock(); refusedFlag = true; lock.unlock()
        return nil
    }
}

/// The update check and the disk image download (spec 013 FR-004, FR-005,
/// FR-014; contracts/update-requests.md). Requests carry no credentials,
/// cookies or identifiers; the user agent is `AgentMeter/X.Y.Z` only.
public struct UpdateClient: Sendable {
    /// Cap for the `releases/latest` body.
    public static let releaseBodyLimit = 1_048_576
    /// Per-request timeout of the check.
    public static let checkTimeout: TimeInterval = 30
    /// Idle timeout of the download.
    public static let downloadIdleTimeout: TimeInterval = 120

    /// Ephemeral, without URL cache or cookie storage, so nothing about the
    /// requests is written to disk (FR-005).
    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = checkTimeout
        return URLSession(configuration: configuration)
    }()

    private let owner: String
    private let repo: String
    private let appVersion: String
    private let session: URLSession

    /// `owner/repo` is `rhuss/agentmeter` except in an update-test build
    /// (FR-025); `appVersion` is the running `CFBundleShortVersionString`.
    public init(owner: String, repo: String, appVersion: String, session: URLSession = UpdateClient.defaultSession) {
        self.owner = owner
        self.repo = repo
        self.appVersion = appVersion
        self.session = session
    }

    /// `https://api.github.com/repos/<owner>/<repo>/releases/latest`.
    public var latestReleaseURL: URL? {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")
    }

    /// `https://github.com/<owner>/<repo>/releases/latest`: the release page
    /// offered after a failed install from the previous run, when only the
    /// source is known (spec 013 FR-019).
    public var latestReleasePageURL: URL? {
        URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")
    }

    /// Request 1 (latest release) and request 2 (its release-info.json),
    /// then `ReleaseEvaluator` (FR-004). HTTP 404 on request 1 means no
    /// published release.
    public func check(runningVersion: ReleaseVersion) async throws -> ReleaseCheckResult {
        guard let url = latestReleaseURL else { throw UpdateClientError.unexpectedHost }
        let (status, body) = try await fetch(url, accept: "application/vnd.github+json", limit: Self.releaseBodyLimit, apiHeaders: true)
        if status == 404 { return .notNewer }
        try Self.requireOK(status)
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: body)
        } catch {
            throw UpdateClientError.decoding("release")
        }
        var info: ReleaseInfo?
        // An asset without a usable URL counts as an unreadable file: the
        // release is ignored (FR-004). A URL outside the allowlist is never
        // requested and fails the check (FR-005).
        if !release.draft, !release.prerelease, let infoURL = release.releaseInfoAsset?.downloadURL {
            let (infoStatus, infoBody) = try await fetch(infoURL, accept: "application/octet-stream", limit: ReleaseInfo.maximumBytes, apiHeaders: false)
            if infoStatus != 404 {
                try Self.requireOK(infoStatus)
                info = ReleaseInfo.decode(infoBody)
            }
        }
        return ReleaseEvaluator.evaluate(release: release, info: info, runningVersion: runningVersion)
    }

    // MARK: Download

    /// Request 3 (Install only): streams the disk image into `destination`
    /// (FR-014, FR-018). Refused before any request when the API's size is
    /// above `maximumBytes`, aborted when more bytes arrive than that (the
    /// server's size could lie), and stopped when the task is cancelled. A
    /// partial file is removed on any failure. `progress` gets fractions from
    /// 0 to 1. Returns the number of bytes received.
    @discardableResult
    public func download(_ target: DownloadTarget, to destination: URL,
                         maximumBytes: Int = DownloadTarget.maximumBytes,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        try Task.checkCancellation()
        guard target.size <= maximumBytes else { throw UpdateClientError.tooLarge }
        let request = makeRequest(target.url, accept: "application/octet-stream",
                                  timeout: Self.downloadIdleTimeout, apiHeaders: false)
        let (bytes, http) = try await open(request)
        guard http.statusCode == 200 else {
            bytes.task.cancel()
            throw Self.statusError(http.statusCode)
        }
        if http.expectedContentLength > Int64(maximumBytes) {
            bytes.task.cancel()
            throw UpdateClientError.tooLarge
        }
        let total = http.expectedContentLength > 0 ? Int(http.expectedContentLength) : max(target.size, 1)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        guard fileManager.createFile(atPath: destination.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: destination) else {
            bytes.task.cancel()
            throw UpdateClientError.network("cannot write the download")
        }
        do {
            defer { try? handle.close() }
            let chunkSize = 65_536
            var buffer = Data(capacity: chunkSize)
            var received = 0
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= chunkSize {
                    received += buffer.count
                    if received > maximumBytes { throw UpdateClientError.tooLarge }
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    progress(min(Double(received) / Double(total), 1))
                    try Task.checkCancellation()
                }
            }
            received += buffer.count
            if received > maximumBytes { throw UpdateClientError.tooLarge }
            try handle.write(contentsOf: buffer)
            try Task.checkCancellation()
            progress(1)
            return received
        } catch {
            bytes.task.cancel()
            try? fileManager.removeItem(at: destination)
            throw Self.mapped(error)
        }
    }

    // MARK: Requests

    func makeRequest(_ url: URL, accept: String, timeout: TimeInterval, apiHeaders: Bool) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = timeout
        request.setValue("AgentMeter/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if apiHeaders {
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        return request
    }

    /// Opens a streaming request after checking the starting URL; a refused
    /// redirect becomes `unexpectedHost`.
    func open(_ request: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        guard let url = request.url, UpdateHostPolicy.allows(url) else { throw UpdateClientError.unexpectedHost }
        let redirectGuard = UpdateRedirectGuard()
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request, delegate: redirectGuard)
        } catch {
            throw Self.mapped(error)
        }
        if redirectGuard.refused {
            bytes.task.cancel()
            throw UpdateClientError.unexpectedHost
        }
        guard let http = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw UpdateClientError.network("no HTTP response")
        }
        return (bytes, http)
    }

    /// Status and body (read only for status 200, at most `limit` bytes).
    private func fetch(_ url: URL, accept: String, limit: Int, apiHeaders: Bool) async throws -> (Int, Data) {
        let request = makeRequest(url, accept: accept, timeout: Self.checkTimeout, apiHeaders: apiHeaders)
        let (bytes, http) = try await open(request)
        guard http.statusCode == 200 else {
            bytes.task.cancel()
            return (http.statusCode, Data())
        }
        if http.expectedContentLength > Int64(limit) {
            bytes.task.cancel()
            throw UpdateClientError.tooLarge
        }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit {
                    bytes.task.cancel()
                    throw UpdateClientError.tooLarge
                }
            }
        } catch {
            throw Self.mapped(error)
        }
        return (200, data)
    }

    static func requireOK(_ status: Int) throws {
        guard status == 200 else { throw statusError(status) }
    }

    /// The error for a status other than 200.
    static func statusError(_ status: Int) -> UpdateClientError {
        status == 403 || status == 429 ? .rateLimited : .httpStatus(status)
    }

    static func mapped(_ error: Error) -> Error {
        if error is UpdateClientError || error is CancellationError { return error }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return CancellationError() }
            return UpdateClientError.network(urlError.localizedDescription)
        }
        return UpdateClientError.network(String(describing: type(of: error)))
    }
}
