import Foundation
import Testing
@testable import UsageCore

func makeTempDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("llm-usage-tests-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct ConfigStoreTests {
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
        #expect(config.accounts[0].label == "M")
        #expect(config.accounts[0].kind.subscription?.credentialDirectory == "~/.claude")
        #expect(config.accounts[0].kind.subscription?.shownInBar == true)

        let none = ConfigStore.makeDefault(hasDefaultCredentials: false)
        #expect(none.accounts.isEmpty)
        try none.validate()
    }

    private func bumpModificationDate(_ file: URL, by seconds: TimeInterval = 2) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let mtime = attrs[.modificationDate] as! Date
        try FileManager.default.setAttributes([.modificationDate: mtime.addingTimeInterval(seconds)], ofItemAtPath: file.path)
    }
}
