import Foundation
import Testing
@testable import UsageCore

/// The example of contracts/last-good-file.md.
let lastGoodContractJSON = """
{
  "version": 1,
  "claude": {
    "acc-max": {
      "credentialDirectory": "/Users/me/.claude",
      "fetchedAt": "2026-10-15T09:12:03.120Z",
      "fiveHour": { "utilizationPercent": 41.0, "resetsAt": "2026-10-15T11:00:00.000Z" },
      "sevenDay": { "utilizationPercent": 63.5, "resetsAt": "2026-10-18T07:00:00.000Z" },
      "modelLimits": [
        { "modelName": "Fable", "utilizationPercent": 12.0, "resetsAt": "2026-10-18T07:00:00.000Z", "allowancePercentOfWeekly": 50 },
        { "modelName": "Other", "utilizationPercent": 0.0 }
      ]
    }
  },
  "codex": {
    "acc-codex": {
      "codexHome": "/Users/me/.codex",
      "observedAt": "2026-10-15T09:12:04.500Z",
      "planType": "plus",
      "windows": [
        { "lengthMinutes": 300, "usedPercent": 20.0, "resetsAt": "2026-10-15T12:00:00.000Z", "limitReached": false },
        { "lengthMinutes": 10080, "usedPercent": 55.0, "resetsAt": "2026-10-20T08:00:00.000Z", "limitReached": false }
      ]
    }
  }
}
"""

/// spec 010 FR-013, FR-014, FR-018, SC-004, contracts/last-good-file.md.
@Suite struct LastGoodStoreTests {
    static func fileURL(_ root: URL) -> URL { Paths(home: root).lastGoodFileURL }

    static func permissions(_ path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    static let claude = SavedClaudeValues(credentialDirectory: "/Users/me/.claude", fetchedAt: isoDate("2026-10-15T09:12:03.120Z"),
                                          fiveHour: SavedWindow(utilizationPercent: 41, resetsAt: isoDate("2026-10-15T11:00:00Z")),
                                          sevenDay: nil, modelLimits: [SavedModelLimit(modelName: "Fable", utilizationPercent: 12, resetsAt: nil)])
    static let codex = SavedCodexValues(codexHome: "/Users/me/.codex", observedAt: isoDate("2026-10-15T09:12:04.500Z"), planType: nil,
                                        windows: [SavedCodexWindow(lengthMinutes: 300, usedPercent: 20, resetsAt: nil, limitReached: true)])

    @Test func pathIsInApplicationSupport() {
        let paths = Paths(home: URL(fileURLWithPath: "/Users/someone"))
        #expect(paths.lastGoodFileURL.path == "/Users/someone/Library/Application Support/agenttacho/last-good.json")
    }

    @Test func contractExampleRoundTrips() async throws {
        let root = try makeTempDirectory("lastgood-roundtrip")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = Self.fileURL(root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lastGoodContractJSON.utf8).write(to: url)
        let (loaded, problem) = LastGoodStore.load(from: url)
        #expect(problem == nil)
        let values = try #require(loaded)
        let claude = try #require(values.claude["acc-max"])
        #expect(claude.credentialDirectory == "/Users/me/.claude")
        #expect(claude.fetchedAt == isoDate("2026-10-15T09:12:03.120Z"))
        #expect(claude.sevenDay == SavedWindow(utilizationPercent: 63.5, resetsAt: isoDate("2026-10-18T07:00:00Z")))
        #expect(claude.modelLimits[0].allowancePercentOfWeekly == 50)
        #expect(claude.modelLimits[1].resetsAt == nil)
        #expect(values.codex["acc-codex"]?.planType == "plus")
        #expect(values.codex["acc-codex"]?.windows.map(\.lengthMinutes) == [300, 10080])

        // Written back and read again, the values are the same.
        let store = LastGoodStore(fileURL: url, initial: values, log: nil)
        await store.replace(claude: ["acc-max": claude, "acc-2": Self.claude])
        let (again, _) = LastGoodStore.load(from: url)
        #expect(again?.claude["acc-max"] == claude)
        #expect(again?.claude["acc-2"] == Self.claude)
        #expect(again?.codex == values.codex)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"2026-10-15T09:12:03.120Z\""))
        #expect(text.contains("\"version\" : 1"))
    }

    @Test func valuesIncludeTheLoadedOnesAndLaterReplaces() async throws {
        let root = try makeTempDirectory("lastgood-values")
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = LastGoodValues(claude: ["acc-a": Self.claude])
        let store = LastGoodStore(fileURL: Self.fileURL(root), initial: initial, log: nil)
        #expect(await store.values() == initial)
        await store.replace(codex: ["acc-codex": Self.codex])
        #expect(await store.values().claude == ["acc-a": Self.claude])
        #expect(await store.values().codex == ["acc-codex": Self.codex])
        await store.replace(claude: [:])
        #expect(await store.values().claude.isEmpty)
        #expect(await store.values().codex == ["acc-codex": Self.codex])
        let (loaded, _) = LastGoodStore.load(from: Self.fileURL(root))
        #expect(loaded?.claude.isEmpty == true)
        #expect(loaded?.codex == ["acc-codex": Self.codex])
    }

    @Test func fileIsOwnerOnlyAndTheDirectoryIsTightened() async throws {
        let root = try makeTempDirectory("lastgood-perms")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = Self.fileURL(root)
        let store = LastGoodStore(fileURL: url, initial: nil, log: nil)
        await store.replace(claude: ["acc-a": Self.claude])
        #expect(try Self.permissions(url.path) == 0o600)
        #expect(try Self.permissions(url.deletingLastPathComponent().path) == 0o700)
        await store.replace(codex: ["acc-codex": Self.codex])
        #expect(try Self.permissions(url.path) == 0o600)

        // An existing 0755 directory is tightened on the next write.
        let other = try makeTempDirectory("lastgood-perms-existing")
        defer { try? FileManager.default.removeItem(at: other) }
        let otherURL = Self.fileURL(other)
        try FileManager.default.createDirectory(at: otherURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        try Data("{}".utf8).write(to: otherURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: otherURL.path)
        let otherStore = LastGoodStore(fileURL: otherURL, initial: nil, log: nil)
        await otherStore.replace(claude: ["acc-a": Self.claude])
        #expect(try Self.permissions(otherURL.deletingLastPathComponent().path) == 0o700)
        #expect(try Self.permissions(otherURL.path) == 0o600)
    }

    @Test func writesReplaceTheFileAsAWhole() async throws {
        let root = try makeTempDirectory("lastgood-atomic")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = Self.fileURL(root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A longer old file: a partial overwrite would leave its tail behind.
        try Data((lastGoodContractJSON + String(repeating: " ", count: 4096)).utf8).write(to: url)
        let store = LastGoodStore(fileURL: url, initial: nil, log: nil)
        await store.replace(claude: ["acc-a": Self.claude])
        let (loaded, problem) = LastGoodStore.load(from: url)
        #expect(problem == nil)
        #expect(loaded == LastGoodValues(claude: ["acc-a": Self.claude]))
        // No temporary file is left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(leftovers == ["last-good.json"])
    }

    @Test func failedWriteIsLoggedOnceAndDoesNotThrow() async throws {
        let root = try makeTempDirectory("lastgood-readonly")
        let directory = root.appendingPathComponent("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let log = DiagnosticLog(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttacho-tests-lastgood-log-\(UUID().uuidString).log"))
        defer { try? FileManager.default.removeItem(at: log.fileURL) }
        let store = LastGoodStore(fileURL: directory.appendingPathComponent("sub/last-good.json"), initial: nil, log: log)
        await store.replace(claude: ["acc-a": Self.claude])
        await store.replace(codex: ["acc-codex": Self.codex])
        let text = (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
        #expect(text.components(separatedBy: "could not be written").count - 1 == 1)
        #expect(await store.values().claude == ["acc-a": Self.claude])
    }

    @Test func unusableFilesLoadAsNilWithAProblem() throws {
        let root = try makeTempDirectory("lastgood-bad")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = Self.fileURL(root)
        let (missing, missingProblem) = LastGoodStore.load(from: url)
        #expect(missing == nil)
        #expect(missingProblem != nil)

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let (invalid, invalidProblem) = LastGoodStore.load(from: url)
        #expect(invalid == nil)
        #expect(invalidProblem != nil)
        #expect(invalidProblem?.contains("not json") == false)

        try Data(lastGoodContractJSON.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2").utf8).write(to: url)
        let (future, futureProblem) = LastGoodStore.load(from: url)
        #expect(future == nil)
        #expect(futureProblem?.contains("version 2") == true)
    }

    /// Only a regular file of a sane size is read: a directory, a symlink
    /// (which could point at an endless device) or a huge file is ignored
    /// without reading it (FR-018).
    @Test func nonRegularOrHugeFilesAreIgnoredUnread() throws {
        let root = try makeTempDirectory("lastgood-odd")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = Self.fileURL(root)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let (directory, directoryProblem) = LastGoodStore.load(from: url)
        #expect(directory == nil)
        #expect(directoryProblem?.contains("not a regular file") == true)
        try FileManager.default.removeItem(at: url)

        let target = root.appendingPathComponent("elsewhere.json")
        try Data(lastGoodContractJSON.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let (link, linkProblem) = LastGoodStore.load(from: url)
        #expect(link == nil)
        #expect(linkProblem?.contains("not a regular file") == true)
        try FileManager.default.removeItem(at: url)

        try Data(count: LastGoodStore.maximumFileSize + 1).write(to: url)
        let (huge, hugeProblem) = LastGoodStore.load(from: url)
        #expect(huge == nil)
        #expect(hugeProblem?.contains("too large") == true)
    }

    /// SC-004: the saved values of a real refresh hold no token.
    @Test func writtenFileHoldsNoToken() async throws {
        let root = try makeTempDirectory("lastgood-token")
        defer { try? FileManager.default.removeItem(at: root) }
        let token = "SECRET-LASTGOOD-TOKEN-\(UUID().uuidString)"
        StubURLProtocol.register(key: "Bearer \(token)") { _ in (200, Data(usageResponseJSON.utf8)) }
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let reader = FakeCredentialReader()
        reader.credentials["~/.claude"] = OAuthCredential(accessToken: token, expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
                                                          subscriptionType: "max")
        let store = LastGoodStore(fileURL: Self.fileURL(root), initial: nil, log: nil)
        let source = SubscriptionSource(credentialReader: reader, client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                        store: store, paths: Paths(home: root))
        var config = Configuration()
        config.accounts = [Account(id: "acc-0", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude")))]
        _ = try await source.collect(context: RefreshContext(configuration: config, window: DateInterval(start: Date(), duration: 1), now: Date()))
        let text = try String(contentsOf: Self.fileURL(root), encoding: .utf8)
        #expect(text.contains("acc-0"))
        #expect(!text.contains("SECRET"))
        #expect(!text.contains("max"))
    }
}
