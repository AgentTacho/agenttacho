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

/// spec 040 FR-014, US3 scenario 4, contracts/config-and-last-good.md: the
/// saved Claude window list, readable by the previous version and from its
/// files.
@Suite struct LastGoodWindowListTests {
    static let reset = isoDate("2026-11-06T07:00:00Z")
    static let fetched = isoDate("2026-11-02T06:34:18.354Z")

    static let daily = ClaudeLimit(identity: ClaudeWindow(rawValue: "limit:daily_all"), kind: "daily_all", group: "daily", length: nil,
                                   name: "daily", modelName: nil, allowancePercentOfWeekly: nil, utilizationPercent: 40, resetsAt: reset)
    static let furtherFable = ClaudeLimit(identity: ClaudeWindow(rawValue: "model:Fable:daily_scoped"), kind: "daily_scoped",
                                          group: "daily", length: nil, name: "Fable daily", modelName: "Fable",
                                          allowancePercentOfWeekly: nil, utilizationPercent: 22, resetsAt: nil)
    static let windows: [ClaudeLimit] = [
        ClaudeLimit(identity: .sevenDay, kind: "weekly_all", group: "weekly", length: 7 * 86400, name: "7-day", modelName: nil,
                    allowancePercentOfWeekly: nil, utilizationPercent: 11, resetsAt: reset),
        daily,
        ClaudeLimit(identity: .model("Fable"), kind: "weekly_scoped", group: "weekly", length: 7 * 86400, name: "Fable",
                    modelName: "Fable", allowancePercentOfWeekly: 50, utilizationPercent: 15, resetsAt: reset),
        furtherFable,
    ]

    static func written(_ values: SavedClaudeValues) throws -> [String: Any] {
        let data = try LastGoodStore.encoder.encode(LastGoodValues(claude: ["acc-max": values]))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        let claude = try #require(object["claude"] as? [String: Any])
        return try #require(claude["acc-max"] as? [String: Any])
    }

    static func decode(_ entry: [String: Any]) throws -> SavedClaudeValues {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "claude": ["acc-max": entry]])
        let values = try LastGoodStore.decoder.decode(LastGoodValues.self, from: data)
        return try #require(values.claude["acc-max"])
    }

    /// A file of the previous version loads as the equivalent list.
    @Test func previousVersionFileLoadsAsAList() throws {
        let root = try makeTempDirectory("lastgood-legacy")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = LastGoodStoreTests.fileURL(root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lastGoodContractJSON.utf8).write(to: url)
        let (loaded, problem) = LastGoodStore.load(from: url)
        #expect(problem == nil)
        let status = try #require(loaded?.claude["acc-max"]).status(now: isoDate("2026-10-15T10:00:00Z"))
        #expect(status.windows.map(\.identity) == [.fiveHour, .sevenDay, .model("Fable"), .model("Other")])
        #expect(status.windows.map(\.utilizationPercent) == [41, 63.5, 12, 0])
        let week: TimeInterval = 7 * 86400
        let lengths: [TimeInterval?] = [5 * 3600, week, week, week]
        #expect(status.windows.map(\.length) == lengths)
        #expect(status.windows.map(\.group) == ["five_hour", "weekly", "weekly", "weekly"])
        #expect(status.window(.model("Fable"))?.allowancePercentOfWeekly == 50)
        #expect(status.window(.model("Other"))?.resetsAt == nil)
    }

    /// A new file holds the list, the legacy keys for `sevenDay` and the
    /// `model:<name>` limits, and reads back as the same list.
    @Test func newFileHoldsTheListAndTheLegacyKeys() throws {
        let status = SubscriptionStatus(windows: Self.windows, fetchedAt: Self.fetched)
        let saved = SavedClaudeValues(credentialDirectory: "/Users/me/.claude", status: status)
        let entry = try Self.written(saved)
        let windows = try #require(entry["windows"] as? [[String: Any]])
        #expect(windows.map { $0["identity"] as? String } == ["sevenDay", "limit:daily_all", "model:Fable", "model:Fable:daily_scoped"])
        #expect(windows[0]["lengthSeconds"] as? Double == 604800)
        #expect(windows[1]["lengthSeconds"] == nil)
        #expect(windows[1]["group"] as? String == "daily")
        #expect(entry["fiveHour"] == nil)
        let seven = try #require(entry["sevenDay"] as? [String: Any])
        #expect(seven["utilizationPercent"] as? Double == 11)
        let models = try #require(entry["modelLimits"] as? [[String: Any]])
        #expect(models.map { $0["modelName"] as? String } == ["Fable"])
        #expect(models.first?["allowancePercentOfWeekly"] as? Int == 50)

        let back = try Self.decode(entry)
        #expect(back == saved)
        #expect(back.status(now: Self.fetched).windows == Self.windows)
    }

    /// The previous version reads only the legacy keys: it gets the same
    /// 7-day and model values after a downgrade.
    @Test func legacyKeysAloneGiveTheSameValues() throws {
        let status = SubscriptionStatus(windows: [.fiveHour(40, resetsAt: Self.reset)] + Self.windows, fetchedAt: Self.fetched)
        var entry = try Self.written(SavedClaudeValues(credentialDirectory: "/Users/me/.claude", status: status))
        entry["windows"] = nil
        let legacy = try Self.decode(entry).status(now: Self.fetched)
        #expect(legacy.window(.sevenDay)?.utilizationPercent == 11)
        #expect(legacy.window(.sevenDay)?.resetsAt == Self.reset)
        #expect(legacy.window(.fiveHour)?.utilizationPercent == 40)
        #expect(legacy.window(.model("Fable"))?.utilizationPercent == 15)
        #expect(legacy.window(.model("Fable"))?.allowancePercentOfWeekly == 50)
        #expect(legacy.modelLimitWindows.count == 1)
    }

    /// A legacy file with two model limits of one name gives one window, so
    /// identities stay unique as in a live answer (spec 040 FR-005, FR-014).
    @Test func legacyModelLimitsOfOneNameKeepTheFirst() {
        let saved = SavedClaudeValues(credentialDirectory: "/Users/me/.claude", fetchedAt: Self.fetched, fiveHour: nil,
                                      sevenDay: SavedWindow(utilizationPercent: 11, resetsAt: Self.reset),
                                      modelLimits: [SavedModelLimit(modelName: "Fable", utilizationPercent: 15, resetsAt: Self.reset),
                                                    SavedModelLimit(modelName: "Fable", utilizationPercent: 30, resetsAt: Self.reset)])
        let status = saved.status(now: Self.fetched)
        #expect(status.windows.map(\.identity) == [.sevenDay, .model("Fable")])
        #expect(status.window(.model("Fable"))?.utilizationPercent == 15)
    }

    /// A saved list with two windows of one identity keeps the first (spec
    /// 040 FR-005), for example a hand-edited file.
    @Test func savedListWithADuplicateIdentityKeepsTheFirst() throws {
        var entry = try Self.written(SavedClaudeValues(credentialDirectory: "/Users/me/.claude",
                                                       status: SubscriptionStatus(windows: Self.windows, fetchedAt: Self.fetched)))
        var windows = try #require(entry["windows"] as? [[String: Any]])
        var copy = windows[0]
        copy["utilizationPercent"] = 99.0
        windows.append(copy)
        entry["windows"] = windows
        let status = try Self.decode(entry).status(now: Self.fetched)
        #expect(status.windows.map(\.identity) == Self.windows.map(\.identity))
        #expect(status.window(.sevenDay)?.utilizationPercent == 11)
    }

    /// A `windows` list this version cannot read (a later format) falls back
    /// to the legacy keys next to it instead of dropping the file (spec 040
    /// FR-014).
    @Test func unreadableListFallsBackToTheLegacyKeys() throws {
        var entry = try Self.written(SavedClaudeValues(credentialDirectory: "/Users/me/.claude",
                                                       status: SubscriptionStatus(windows: Self.windows, fetchedAt: Self.fetched)))
        entry["windows"] = [["identity": "sevenDay", "unexpected": true]]
        let back = try Self.decode(entry)
        #expect(back.windows == nil)
        let status = back.status(now: Self.fetched)
        #expect(status.window(.sevenDay)?.utilizationPercent == 11)
        #expect(status.window(.model("Fable"))?.utilizationPercent == 15)
    }

    /// The legacy `modelLimits` key holds every model's first limit, also
    /// for a model name with a colon (spec 040 FR-004, FR-014).
    @Test func legacyKeyHoldsAModelNameWithAColon() throws {
        let colon = ClaudeLimit.model("Opus: Max", 20, resetsAt: Self.reset)
        let status = SubscriptionStatus(windows: Self.windows + [colon], fetchedAt: Self.fetched)
        let entry = try Self.written(SavedClaudeValues(credentialDirectory: "/Users/me/.claude", status: status))
        let models = try #require(entry["modelLimits"] as? [[String: Any]])
        #expect(models.map { $0["modelName"] as? String } == ["Fable", "Opus: Max"])
    }

    /// US3 scenario 4: a saved 5-hour value past its reset shows 0% without
    /// a reset time in the effective status.
    @Test func savedFiveHourPastItsResetShowsZero() throws {
        let saved = SavedClaudeValues(credentialDirectory: "/Users/me/.claude", fetchedAt: Self.fetched,
                                      fiveHour: SavedWindow(utilizationPercent: 58, resetsAt: Self.fetched.addingTimeInterval(3600)),
                                      sevenDay: SavedWindow(utilizationPercent: 11, resetsAt: Self.reset))
        let now = Self.fetched.addingTimeInterval(2 * 3600)
        let effective = saved.status(now: now).effective(now: now)
        #expect(effective.window(.fiveHour)?.utilizationPercent == 0)
        #expect(effective.window(.fiveHour)?.resetsAt == nil)
        #expect(effective.window(.sevenDay)?.utilizationPercent == 11)
    }
}
