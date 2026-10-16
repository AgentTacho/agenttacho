import Foundation
import Testing
@testable import UsageCore

func makeTempDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("agentmeter-tests-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct ConfigStoreTests {
    /// Spec 004 FR-007: loading a legacy file with labels does not rewrite
    /// it; saving writes no labels, and reloading gives the same entries
    /// (US4 scenario 3).
    @Test func legacyFileIsRewrittenOnlyOnSave() throws {
        let dir = try makeTempDirectory("store-legacy")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        let original = Data(LegacyIconDecodingTests.legacyJSON.utf8)
        try original.write(to: file)

        let store = ConfigStore(fileURL: file)
        let (loaded, error) = store.load()
        #expect(error == nil)
        #expect(try Data(contentsOf: file) == original)

        try store.save(loaded)
        let saved = try Data(contentsOf: file)
        #expect(!String(decoding: saved, as: UTF8.self).contains("\"label\""))

        let (reloaded, reloadError) = ConfigStore(fileURL: file).load()
        #expect(reloadError == nil)
        #expect(reloaded.accounts == loaded.accounts)
        #expect(reloaded.groups == loaded.groups)
    }

    @Test func saveThenLoadRoundTrip() throws {
        let dir = try makeTempDirectory("store")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: file)
        let config = try decodeConfig(contractExampleJSON)
        try store.save(config)
        #expect(FileManager.default.fileExists(atPath: file.path))

        let fresh = ConfigStore(fileURL: file)
        let (loaded, error) = fresh.load()
        #expect(error == nil)
        #expect(loaded == config)
    }

    @Test func saveRejectsInvalidConfiguration() throws {
        let dir = try makeTempDirectory("store-invalid")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: file)
        var config = try decodeConfig(contractExampleJSON)
        config.refreshIntervalSeconds = 10
        #expect(throws: ConfigurationError.self) { try store.save(config) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func invalidJSONKeepsLastValidConfiguration() throws {
        let dir = try makeTempDirectory("store-json")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: file)
        let config = try decodeConfig(contractExampleJSON)
        try store.save(config)
        _ = store.load()

        try Data("{ not json".utf8).write(to: file)
        try bumpModificationDate(file)
        let (kept, error) = store.load()
        #expect(kept == config)
        #expect(error?.kind == .decoding)

        // The error is reported again on the next load while the file stays broken.
        let (kept2, error2) = store.load()
        #expect(kept2 == config)
        #expect(error2 != nil)
    }

    @Test func validationFailureKeepsLastValidConfiguration() throws {
        let dir = try makeTempDirectory("store-validate")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: file)
        let config = try decodeConfig(contractExampleJSON)
        try store.save(config)
        _ = store.load()

        let broken = contractExampleJSON.replacingOccurrences(of: "\"refreshIntervalSeconds\": 300", with: "\"refreshIntervalSeconds\": 5")
        try Data(broken.utf8).write(to: file)
        try bumpModificationDate(file)
        let (kept, error) = store.load()
        #expect(kept == config)
        #expect(error?.kind == .refreshInterval)

        // Fixing the file clears the error.
        try Data(contractExampleJSON.utf8).write(to: file)
        try bumpModificationDate(file, by: 4)
        let (fixed, error3) = store.load()
        #expect(error3 == nil)
        #expect(fixed == config)
    }

    @Test func reloadsOnlyWhenModificationDateChanges() throws {
        let dir = try makeTempDirectory("store-mtime")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: file)
        try Data(contractExampleJSON.utf8).write(to: file)
        let (first, _) = store.load()
        #expect(first.refreshIntervalSeconds == 300)

        // Change the contents but restore the previous modification date.
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let mtime = attrs[.modificationDate] as! Date
        let edited = contractExampleJSON.replacingOccurrences(of: "\"refreshIntervalSeconds\": 300", with: "\"refreshIntervalSeconds\": 120")
        try Data(edited.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
        let (second, _) = store.load()
        #expect(second.refreshIntervalSeconds == 300)

        try bumpModificationDate(file)
        let (third, _) = store.load()
        #expect(third.refreshIntervalSeconds == 120)
    }

    @Test func createsDefaultWhenFileMissing() throws {
        let dir = try makeTempDirectory("store-default")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("nested/config.json")
        let store = ConfigStore(fileURL: file, makeDefault: {
            ConfigStore.makeDefault(hasDefaultCredentials: true)
        })
        let (config, error) = store.load()
        #expect(error == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(config.refreshIntervalSeconds == 300)
        #expect(config.weekFallback == .monday)
        #expect(config.accounts.count == 1)
        #expect(config.accounts[0].icon == IconDefaults.subscription)
        #expect(config.accounts[0].kind.subscription?.credentialDirectory == "~/.claude")
        #expect(config.accounts[0].kind.subscription?.shownInBar == true)

        let none = ConfigStore.makeDefault(hasDefaultCredentials: false)
        #expect(none.accounts.isEmpty)
        try none.validate()
    }

    /// Spec 003 FR-003, FR-004, US4 scenario 2: loading a legacy file does not
    /// rewrite it; saving writes the new form, which reloads to equal groups.
    @Test func legacyFileIsOnlyRewrittenOnSave() throws {
        let dir = try makeTempDirectory("store-legacy")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        let legacyBytes = Data(contractExampleJSON.utf8)
        try legacyBytes.write(to: file)

        let store = ConfigStore(fileURL: file)
        let (loaded, error) = store.load()
        #expect(error == nil)
        #expect(loaded.groups.map(\.period) == [.weekly])
        #expect(loaded.groups.map(\.budgetUSD) == [60])
        #expect(try Data(contentsOf: file) == legacyBytes)
        _ = store.load()
        #expect(try Data(contentsOf: file) == legacyBytes)

        try store.save(loaded)
        let saved = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(saved.contains("\"period\""))
        #expect(saved.contains("\"budgetUSD\""))
        #expect(!saved.contains("weeklyBudgetUSD"))

        let (reloaded, reloadError) = ConfigStore(fileURL: file).load()
        #expect(reloadError == nil)
        #expect(reloaded.groups == loaded.groups)
        #expect(reloaded == loaded)
    }

    /// Spec 012 FR-003: an unknown level color is a load note, handed out
    /// once per file read, never a configuration error.
    @Test func unknownLevelColorYieldsOneLoadNote() throws {
        let dir = try makeTempDirectory("store-notes")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        let json = contractExampleJSON.replacingOccurrences(of: "\"startAtLogin\": false,",
                                                            with: "\"startAtLogin\": false,\n  \"levelColor\": \"rainbow\",")
        try Data(json.utf8).write(to: file)

        let store = ConfigStore(fileURL: file)
        let (loaded, error) = store.load()
        #expect(error == nil)
        #expect(loaded.levelColor == .text)
        let notes = store.takeLoadNotes()
        #expect(notes.count == 1)
        #expect(notes.first?.contains("rainbow") == true)
        #expect(store.takeLoadNotes().isEmpty)

        // An unchanged file is not read again, so no new note.
        _ = store.load()
        #expect(store.takeLoadNotes().isEmpty)

        // A changed file is read again and yields its note again.
        try bumpModificationDate(file)
        _ = store.load()
        #expect(store.takeLoadNotes().count == 1)
    }

    @Test func validFileYieldsNoLoadNotes() throws {
        let dir = try makeTempDirectory("store-no-notes")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        try Data(contractExampleJSON.utf8).write(to: file)
        let store = ConfigStore(fileURL: file)
        let (_, error) = store.load()
        #expect(error == nil)
        #expect(store.takeLoadNotes().isEmpty)
    }

    /// Notes are kept only when the file decodes and validates.
    @Test func invalidFileWithUnknownLevelColorYieldsErrorAndNoNotes() throws {
        let dir = try makeTempDirectory("store-notes-invalid")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        let json = contractExampleJSON
            .replacingOccurrences(of: "\"startAtLogin\": false,", with: "\"startAtLogin\": false,\n  \"levelColor\": \"rainbow\",")
            .replacingOccurrences(of: "\"refreshIntervalSeconds\": 300", with: "\"refreshIntervalSeconds\": 5")
        try Data(json.utf8).write(to: file)
        let store = ConfigStore(fileURL: file)
        let (_, error) = store.load()
        #expect(error?.kind == .refreshInterval)
        #expect(store.takeLoadNotes().isEmpty)
    }

    private func bumpModificationDate(_ file: URL, by seconds: TimeInterval = 2) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let mtime = attrs[.modificationDate] as! Date
        try FileManager.default.setAttributes([.modificationDate: mtime.addingTimeInterval(seconds)], ofItemAtPath: file.path)
    }
}
