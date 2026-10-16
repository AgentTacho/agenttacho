import Foundation
import Testing
@testable import UsageCore

/// contracts/update-requests.md; spec 013 FR-004, FR-005, FR-014, FR-018.
/// Each test uses its own owner name, so the stub handlers (keyed by URL)
/// do not interfere when tests run in parallel.
@Suite struct UpdateClientTests {
    static let sha = "3f7a1c9e5b2d4f6081a3c5e7f9b1d3e5a7c9e1f3b5d7f9a1c3e5b7d9f1a3c5e7"

    /// The page a failed install from the previous run offers, where only the
    /// source is known (spec 013 FR-019).
    @Test func latestReleasePageURL() {
        let client = UpdateClient(owner: "rhuss", repo: "agentmeter", appVersion: "0.3.0")
        #expect(client.latestReleasePageURL == URL(string: "https://github.com/rhuss/agentmeter/releases/latest"))
    }

    /// URLs of one test's fake release.
    struct Fake {
        let owner = "o" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        let repo = "agentmeter"
        var latestURL: URL { URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")! }
        var infoURL: URL { URL(string: "https://github.com/\(owner)/\(repo)/releases/download/v0.3.0/release-info.json")! }
        var dmgURL: URL { URL(string: "https://github.com/\(owner)/\(repo)/releases/download/v0.3.0/AgentMeter-0.3.0.dmg")! }
        var assetHostURL: URL { URL(string: "https://objects.githubusercontent.com/\(owner)/asset")! }
        private(set) var keys: [String] = []

        func client(version: String = "0.2.1") -> UpdateClient {
            UpdateClient(owner: owner, repo: repo, appVersion: version, session: StubURLProtocol.makeSession())
        }

        mutating func register(_ url: URL, handler: @escaping StubURLProtocol.Handler) {
            StubURLProtocol.register(key: url.absoluteString, handler: handler)
            keys.append(url.absoluteString)
        }

        mutating func register(_ url: URL, redirectingTo target: URL) {
            StubURLProtocol.register(key: url.absoluteString, redirectingTo: target) { _ in (500, Data()) }
            keys.append(url.absoluteString)
        }

        func requests(_ url: URL) -> [URLRequest] {
            StubURLProtocol.recordedRequests(key: url.absoluteString)
        }

        func cleanUp() {
            keys.forEach { StubURLProtocol.unregister(key: $0) }
        }

        func releaseJSON(infoURL: URL? = nil, dmgURL: URL? = nil, dmgSize: Int = 10_485_760, withInfo: Bool = true) -> Data {
            var assets: [[String: Any]] = [
                ["name": "AgentMeter-0.3.0.dmg", "size": dmgSize, "browser_download_url": (dmgURL ?? self.dmgURL).absoluteString],
            ]
            if withInfo {
                assets.append(["name": "release-info.json", "size": 180, "browser_download_url": (infoURL ?? self.infoURL).absoluteString])
            }
            let object: [String: Any] = [
                "tag_name": "v0.3.0", "html_url": "https://github.com/\(owner)/\(repo)/releases/tag/v0.3.0",
                "draft": false, "prerelease": false, "assets": assets,
            ]
            return try! JSONSerialization.data(withJSONObject: object)
        }

        static let infoJSON = Data("""
        {"version":"0.3.0","dmg":"AgentMeter-0.3.0.dmg","sha256":"\(UpdateClientTests.sha)","tier":"developer-id","notarized":true}
        """.utf8)
    }

    private func expectAvailableWithDownload(_ result: ReleaseCheckResult, _ fake: Fake) {
        guard case .available(let release) = result else {
            Issue.record("expected available, got \(result)")
            return
        }
        #expect(release.version == ReleaseVersion("0.3.0"))
        #expect(release.download?.url == fake.dmgURL)
        #expect(release.download?.sha256 == Self.sha)
    }

    // MARK: Check

    @Test func checkSendsOnlyTheAllowedHeaders() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let json = fake.releaseJSON()
        fake.register(fake.latestURL) { _ in (200, json) }
        fake.register(fake.infoURL) { _ in (200, Fake.infoJSON) }
        let result = try await fake.client().check(runningVersion: try #require(ReleaseVersion("0.2.1")))
        expectAvailableWithDownload(result, fake)

        let first = try #require(fake.requests(fake.latestURL).first)
        #expect(first.httpMethod == "GET")
        #expect(first.value(forHTTPHeaderField: "User-Agent") == "AgentMeter/0.2.1")
        #expect(first.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(first.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(Set(first.allHTTPHeaderFields?.keys ?? [:].keys) == ["User-Agent", "Accept", "X-GitHub-Api-Version"])
        #expect(first.httpShouldHandleCookies == false)

        let second = try #require(fake.requests(fake.infoURL).first)
        #expect(second.value(forHTTPHeaderField: "User-Agent") == "AgentMeter/0.2.1")
        #expect(Set(second.allHTTPHeaderFields?.keys ?? [:].keys) == ["User-Agent", "Accept"])
    }

    /// FR-004: a release whose release-info.json is not found is ignored,
    /// not a failed check (which would keep a known update, FR-007a).
    @Test func releaseInfoNotFoundIsIgnored() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let json = fake.releaseJSON()
        fake.register(fake.latestURL) { _ in (200, json) }
        fake.register(fake.infoURL) { _ in (404, Data()) }
        let result = try await fake.client().check(runningVersion: try #require(ReleaseVersion("0.2.1")))
        #expect(result == .ignored(.releaseInfoUnreadable))
    }

    @Test(arguments: [403, 429])
    func releaseInfoRateLimit(_ status: Int) async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let json = fake.releaseJSON()
        fake.register(fake.latestURL) { _ in (200, json) }
        fake.register(fake.infoURL) { _ in (status, Data()) }
        await #expect(throws: UpdateClientError.rateLimited) {
            try await fake.client().check(runningVersion: ReleaseVersion("0.2.1")!)
        }
    }

    @Test func notFoundMeansNoRelease() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        fake.register(fake.latestURL) { _ in (404, Data(#"{"message":"Not Found"}"#.utf8)) }
        let result = try await fake.client().check(runningVersion: try #require(ReleaseVersion("0.2.1")))
        #expect(result == .notNewer)
    }

    @Test(arguments: [403, 429])
    func rateLimit(_ status: Int) async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        fake.register(fake.latestURL) { _ in (status, Data()) }
        await #expect(throws: UpdateClientError.rateLimited) {
            try await fake.client().check(runningVersion: ReleaseVersion("0.2.1")!)
        }
    }

    @Test func serverError() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        fake.register(fake.latestURL) { _ in (500, Data()) }
        await #expect(throws: UpdateClientError.httpStatus(500)) {
            try await fake.client().check(runningVersion: ReleaseVersion("0.2.1")!)
        }
    }

    @Test func malformedReleaseIsADecodingError() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        fake.register(fake.latestURL) { _ in (200, Data("<html>".utf8)) }
        await #expect {
            try await fake.client().check(runningVersion: ReleaseVersion("0.2.1")!)
        } throws: { error in
            if case UpdateClientError.decoding = error { return true }
            return false
        }
    }

    @Test func redirectToAnAllowedHostIsFollowed() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let json = fake.releaseJSON()
        fake.register(fake.latestURL) { _ in (200, json) }
        fake.register(fake.infoURL, redirectingTo: fake.assetHostURL)
        fake.register(fake.assetHostURL) { _ in (200, Fake.infoJSON) }
        let result = try await fake.client().check(runningVersion: try #require(ReleaseVersion("0.2.1")))
        expectAvailableWithDownload(result, fake)
        #expect(fake.requests(fake.assetHostURL).count == 1)
        #expect(fake.requests(fake.assetHostURL).first?.value(forHTTPHeaderField: "User-Agent") == "AgentMeter/0.2.1")
    }

    @Test func redirectToAnotherHostFails() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let json = fake.releaseJSON()
        let elsewhere = URL(string: "https://example.com/\(fake.owner)/steal")!
        fake.register(fake.latestURL) { _ in (200, json) }
        fake.register(fake.infoURL, redirectingTo: elsewhere)
        fake.register(elsewhere) { _ in (200, Fake.infoJSON) }
        await #expect(throws: UpdateClientError.unexpectedHost) {
            try await fake.client().check(runningVersion: ReleaseVersion("0.2.1")!)
        }
        #expect(fake.requests(elsewhere).isEmpty)
    }

    @Test func startingURLOutsideTheAllowlistIsNeverRequested() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let outside = URL(string: "https://example.com/\(fake.owner)/release-info.json")!
        let json = fake.releaseJSON(infoURL: outside)
        fake.register(fake.latestURL) { _ in (200, json) }
        fake.register(outside) { _ in (200, Fake.infoJSON) }
        await #expect(throws: UpdateClientError.unexpectedHost) {
            try await fake.client().check(runningVersion: ReleaseVersion("0.2.1")!)
        }
        #expect(fake.requests(outside).isEmpty)
    }

    @Test func oversizedReleaseBodyFails() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let big = Data(repeating: 0x20, count: UpdateClient.releaseBodyLimit + 1)
        fake.register(fake.latestURL) { _ in (200, big) }
        await #expect(throws: UpdateClientError.tooLarge) {
            try await fake.client().check(runningVersion: ReleaseVersion("0.2.1")!)
        }
    }

    @Test func oversizedReleaseInfoFails() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let json = fake.releaseJSON()
        let big = Data(repeating: 0x20, count: ReleaseInfo.maximumBytes + 1)
        fake.register(fake.latestURL) { _ in (200, json) }
        fake.register(fake.infoURL) { _ in (200, big) }
        await #expect(throws: UpdateClientError.tooLarge) {
            try await fake.client().check(runningVersion: ReleaseVersion("0.2.1")!)
        }
    }

    @Test func missingReleaseInfoAssetReturnsTheReleaseWithoutInfo() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let json = fake.releaseJSON(withInfo: false)
        fake.register(fake.latestURL) { _ in (200, json) }
        let result = try await fake.client().check(runningVersion: try #require(ReleaseVersion("0.2.1")))
        #expect(result == .ignored(.noReleaseInfo))
        #expect(fake.requests(fake.infoURL).isEmpty)
    }

    /// FR-004: a release-info asset without a usable URL is an unreadable
    /// file, so the release is ignored rather than the check failing.
    @Test func releaseInfoAssetWithoutURLIsIgnored() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        var object = try #require(try JSONSerialization.jsonObject(with: fake.releaseJSON()) as? [String: Any])
        var assets = try #require(object["assets"] as? [[String: Any]])
        assets[1]["browser_download_url"] = nil
        object["assets"] = assets
        let json = try JSONSerialization.data(withJSONObject: object)
        fake.register(fake.latestURL) { _ in (200, json) }
        let result = try await fake.client().check(runningVersion: try #require(ReleaseVersion("0.2.1")))
        #expect(result == .ignored(.releaseInfoUnreadable))
    }

    @Test func unreadableReleaseInfoIsIgnored() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let json = fake.releaseJSON()
        fake.register(fake.latestURL) { _ in (200, json) }
        fake.register(fake.infoURL) { _ in (200, Data("nope".utf8)) }
        let result = try await fake.client().check(runningVersion: try #require(ReleaseVersion("0.2.1")))
        #expect(result == .ignored(.releaseInfoUnreadable))
    }

    // MARK: Download (FR-014, FR-018)

    final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        private var task: Task<Void, Error>?
        var cancelAfterFirst = false

        /// Set under the lock: progress may already arrive.
        func setTask(_ task: Task<Void, Error>) {
            lock.lock()
            self.task = task
            let cancel = cancelAfterFirst && !values.isEmpty
            lock.unlock()
            if cancel { task.cancel() }
        }

        func record(_ value: Double) {
            lock.lock()
            values.append(value)
            let cancel = cancelAfterFirst ? task : nil
            lock.unlock()
            cancel?.cancel()
        }

        var all: [Double] {
            lock.lock(); defer { lock.unlock() }
            return values
        }
    }

    private func destination() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("update-test-\(UUID().uuidString).dmg")
    }

    private func target(_ fake: Fake, url: URL? = nil, size: Int) -> DownloadTarget {
        DownloadTarget(url: url ?? fake.dmgURL, size: size, sha256: Self.sha)
    }

    @Test func downloadWritesTheBodyAndReportsProgress() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let body = Data((0..<300_000).map { UInt8($0 % 251) })
        fake.register(fake.dmgURL) { _ in (200, body) }
        let file = destination()
        defer { try? FileManager.default.removeItem(at: file) }
        let progress = ProgressLog()
        let received = try await fake.client().download(target(fake, size: body.count), to: file) { progress.record($0) }
        #expect(received == body.count)
        #expect(try Data(contentsOf: file) == body)
        let values = progress.all
        #expect(values.count >= 2)
        #expect(values == values.sorted())
        #expect(values.last == 1.0)

        let request = try #require(fake.requests(fake.dmgURL).first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "AgentMeter/0.2.1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test func downloadFollowsAnAllowedRedirect() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let body = Data(repeating: 7, count: 1000)
        fake.register(fake.dmgURL, redirectingTo: fake.assetHostURL)
        fake.register(fake.assetHostURL) { _ in (200, body) }
        let file = destination()
        defer { try? FileManager.default.removeItem(at: file) }
        try await fake.client().download(target(fake, size: body.count), to: file) { _ in }
        #expect(try Data(contentsOf: file) == body)
    }

    @Test func downloadRefusesAnotherHost() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let elsewhere = URL(string: "https://example.com/\(fake.owner)/evil.dmg")!
        fake.register(fake.dmgURL, redirectingTo: elsewhere)
        fake.register(elsewhere) { _ in (200, Data(repeating: 1, count: 10)) }
        let file = destination()
        defer { try? FileManager.default.removeItem(at: file) }
        await #expect(throws: UpdateClientError.unexpectedHost) {
            try await fake.client().download(target(fake, size: 10), to: file) { _ in }
        }
        #expect(fake.requests(elsewhere).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func downloadRefusesAStartingURLOutsideTheAllowlist() async throws {
        let fake = Fake()
        let outside = URL(string: "https://example.com/\(fake.owner)/x.dmg")!
        await #expect(throws: UpdateClientError.unexpectedHost) {
            try await fake.client().download(target(fake, url: outside, size: 10), to: destination()) { _ in }
        }
        #expect(fake.requests(outside).isEmpty)
    }

    @Test func downloadAboveTheLimitIsRefusedBeforeDownloading() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        fake.register(fake.dmgURL) { _ in (200, Data(repeating: 1, count: 10)) }
        await #expect(throws: UpdateClientError.tooLarge) {
            try await fake.client().download(target(fake, size: DownloadTarget.maximumBytes + 1), to: destination()) { _ in }
        }
        #expect(fake.requests(fake.dmgURL).isEmpty)
    }

    @Test func downloadStopsWhenTheBodyExceedsTheLimit() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let body = Data(repeating: 1, count: 200_000)
        fake.register(fake.dmgURL) { _ in (200, body) }
        let file = destination()
        defer { try? FileManager.default.removeItem(at: file) }
        // The API claimed a small file; the server sends more than the limit.
        await #expect(throws: UpdateClientError.tooLarge) {
            try await fake.client().download(target(fake, size: 1000), to: file, maximumBytes: 100_000) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// FR-014: exactly the limit downloads; one byte more in the last,
    /// partial chunk fails and removes the file.
    @Test func downloadLimitBoundary() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let exact = Data(repeating: 2, count: 100_000)
        fake.register(fake.dmgURL) { _ in (200, exact) }
        let file = destination()
        defer { try? FileManager.default.removeItem(at: file) }
        let received = try await fake.client().download(target(fake, size: 1000), to: file, maximumBytes: 100_000) { _ in }
        #expect(received == 100_000)

        var over = Fake()
        defer { over.cleanUp() }
        let body = Data(repeating: 2, count: 100_001)
        over.register(over.dmgURL) { _ in (200, body) }
        let overFile = destination()
        defer { try? FileManager.default.removeItem(at: overFile) }
        await #expect(throws: UpdateClientError.tooLarge) {
            try await over.client().download(target(over, size: 1000), to: overFile, maximumBytes: 100_000) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: overFile.path))
    }

    @Test func downloadHTTPErrors() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        fake.register(fake.dmgURL) { _ in (404, Data()) }
        await #expect(throws: UpdateClientError.httpStatus(404)) {
            try await fake.client().download(target(fake, size: 10), to: destination()) { _ in }
        }
    }

    @Test func downloadStopsWhenCancelled() async throws {
        var fake = Fake()
        defer { fake.cleanUp() }
        let body = Data(repeating: 3, count: 1_000_000)
        fake.register(fake.dmgURL) { _ in (200, body) }
        let file = destination()
        defer { try? FileManager.default.removeItem(at: file) }
        let progress = ProgressLog()
        progress.cancelAfterFirst = true
        let client = fake.client()
        let downloadTarget = target(fake, size: body.count)
        let task = Task {
            _ = try await client.download(downloadTarget, to: file) { progress.record($0) }
        }
        progress.setTask(task)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect((progress.all.last ?? 0) < 1)
    }

    @Test func defaultSessionStoresNothing() {
        let configuration = UpdateClient.defaultSession.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test func errorsHaveShortTexts() {
        #expect(UpdateClientError.rateLimited.description == "GitHub rate limit reached")
        #expect(UpdateClientError.httpStatus(500).description == "GitHub returned HTTP 500")
        #expect(UpdateClientError.unexpectedHost.description.contains("unexpected host"))
        #expect(UpdateClientError.tooLarge.description.contains("too large"))
    }
}
