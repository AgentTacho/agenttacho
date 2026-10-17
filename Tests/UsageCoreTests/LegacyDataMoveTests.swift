import Foundation
import Testing
@testable import UsageCore

/// The one-time copy of AgentMeter's settings into AgentTacho's folders
/// (spec 023 FR-008 to FR-011, contracts/legacy-data-move.md).
@Suite struct LegacyDataMoveTests {
    /// A temporary home directory with helpers for AgentMeter's files,
    /// removed when the test no longer uses it.
    final class Home {
        let root: URL
        let paths: Paths

        init(_ name: String) throws {
            root = try makeTempDirectory("legacy-move-\(name)")
            paths = Paths(home: root)
        }

        deinit {
            // Folders a test made read-only must be writable to be removed.
            let fm = FileManager.default
            if let entries = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
                for case let url as URL in entries
                where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
            }
            try? fm.removeItem(at: root)
        }

        /// AgentMeter's three data folders, the tree the move must never change.
        var legacyFolders: [URL] {
            [".config/agentmeter", "Library/Logs/agentmeter", "Library/Application Support/agentmeter"]
                .map { root.appendingPathComponent($0) }
        }

        @discardableResult
        func write(_ url: URL, _ text: String) throws -> Data {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data(text.utf8)
            try data.write(to: url)
            return data
        }

        /// Every entry under the legacy folders, to compare before and after:
        /// `dir <mode> <mtime>` for a folder (the three roots included, so
        /// a file created and deleted again shows in the folder's
        /// modification time), `file <mode> <mtime> <base64 bytes>` for a
        /// file, and `link <destination>` for a symbolic link.
        func legacySnapshot() -> [String: String] {
            var result: [String: String] = [:]
            let fm = FileManager.default
            for folder in legacyFolders {
                guard let root = Self.describe(folder.path) else { continue }
                result[folder.path] = root
                let entries = (try? fm.subpathsOfDirectory(atPath: folder.path)) ?? []
                for entry in entries {
                    let path = folder.appendingPathComponent(entry).path
                    result[path] = Self.describe(path) ?? "?"
                }
            }
            return result
        }

        private static func describe(_ path: String) -> String? {
            let fm = FileManager.default
            guard let attributes = try? fm.attributesOfItem(atPath: path) else { return nil }
            let mode = (attributes[.posixPermissions] as? Int).map { String($0, radix: 8) } ?? "?"
            let mtime = (attributes[.modificationDate] as? Date).map { String($0.timeIntervalSince1970) } ?? "?"
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory?:
                return "dir \(mode) \(mtime)"
            case .typeSymbolicLink?:
                return "link " + ((try? fm.destinationOfSymbolicLink(atPath: path)) ?? "?")
            default:
                return "file \(mode) \(mtime) \(read(path).base64EncodedString())"
            }
        }

        private static func read(_ path: String) -> Data {
            if let data = FileManager.default.contents(atPath: path) { return data }
            let fm = FileManager.default
            let mode = (try? fm.attributesOfItem(atPath: path)[.posixPermissions] as? Int) ?? 0o644
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            defer { try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: path) }
            return fm.contents(atPath: path) ?? Data()
        }

        func exists(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
        }

        /// Files in a folder whose names are not the carried-over ones, such as
        /// leftover temporary files.
        func strayFiles(in folder: URL) -> [String] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter { !["config.json", "imported-prices.json", "last-good.json"].contains($0) }
        }
    }

    @Test func allThreeFilesAreCopiedByteForByte() throws {
        let home = try Home("all")
        let config = try home.write(home.paths.legacyConfigFileURL, #"{"accounts":[]}"#)
        let prices = try home.write(home.paths.legacyImportedPricesFileURL, #"{"batches":[]}"#)
        let lastGood = try home.write(home.paths.legacyLastGoodFileURL, #"{"limits":{}}"#)
        try home.write(home.root.appendingPathComponent("Library/Logs/agentmeter/usage.log"), "old log\n")
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: ["config.json", "imported-prices.json", "last-good.json"], failed: []))
        #expect(FileManager.default.contents(atPath: home.paths.configFileURL.path) == config)
        #expect(FileManager.default.contents(atPath: home.paths.importedPricesFileURL.path) == prices)
        #expect(FileManager.default.contents(atPath: home.paths.lastGoodFileURL.path) == lastGood)
        #expect(!home.exists(home.paths.logFileURL))
        #expect(home.legacySnapshot() == before)
    }

    @Test func onlyConfigIsCopiedWhenItIsTheOnlyFile() throws {
        let home = try Home("config-only")
        try home.write(home.paths.legacyConfigFileURL, "{}")
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: ["config.json"], failed: []))
        #expect(home.exists(home.paths.configFileURL))
        #expect(!home.exists(home.paths.importedPricesFileURL))
        #expect(!home.exists(home.paths.lastGoodFileURL))
        #expect(home.legacySnapshot() == before)
    }

    @Test func onlyLastGoodLeavesTheConfigurationFolderBehind() throws {
        let home = try Home("last-good-only")
        try home.write(home.paths.legacyLastGoodFileURL, "{}")
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: ["last-good.json"], failed: []))
        #expect(home.exists(home.paths.lastGoodFileURL))
        #expect(home.exists(home.paths.configDirectoryURL))
        #expect(!home.exists(home.paths.configFileURL))
        #expect(home.legacySnapshot() == before)
        // The folder now exists, so a second start copies nothing.
        #expect(LegacyDataMove.run(paths: home.paths) == .skipped)
    }

    @Test func anExistingEmptyConfigurationFolderSkipsTheMove() throws {
        let home = try Home("skipped")
        try home.write(home.paths.legacyConfigFileURL, "{}")
        try home.write(home.paths.legacyLastGoodFileURL, "{}")
        try FileManager.default.createDirectory(at: home.paths.configDirectoryURL, withIntermediateDirectories: true)
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .skipped)
        #expect(!home.exists(home.paths.configFileURL))
        #expect(!home.exists(home.paths.lastGoodFileURL))
        #expect(home.legacySnapshot() == before)
    }

    @Test func noLegacyFilesCreateNothing() throws {
        let home = try Home("nothing")

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .nothingToMove)
        #expect(!home.exists(home.paths.configDirectoryURL))
        #expect(!home.exists(home.paths.lastGoodFileURL.deletingLastPathComponent()))
        #expect(home.legacySnapshot().isEmpty)
    }

    @Test func anUnwritableDestinationIsAFailureWithoutAPartialFile() throws {
        let home = try Home("unwritable")
        try home.write(home.paths.legacyLastGoodFileURL, "{}")
        let destination = home.paths.lastGoodFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: destination.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path) }
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        guard case .moved(let copied, let failed) = outcome else {
            Issue.record("expected .moved, got \(outcome)")
            return
        }
        #expect(copied.isEmpty)
        #expect(failed.map(\.file) == ["last-good.json"])
        #expect(!home.exists(home.paths.lastGoodFileURL))
        #expect(home.strayFiles(in: destination).isEmpty)
        #expect(home.legacySnapshot() == before)
        // A failed copy still marks the move as done (contract guarantee 7).
        #expect(home.exists(home.paths.configDirectoryURL))
        #expect(LegacyDataMove.run(paths: home.paths) == .skipped)
    }

    @Test func aFailedMoveIntoPlaceRemovesTheTemporaryFile() throws {
        let home = try Home("failed-move")
        try home.write(home.paths.legacyConfigFileURL, "{}")
        try home.write(home.paths.legacyImportedPricesFileURL, "{}")
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths, fileManager: FailingMoveFileManager())

        #expect(outcome == .moved(copied: [], failed: [
            .init(file: "config.json", reason: FailingMoveFileManager.reason),
            .init(file: "imported-prices.json", reason: FailingMoveFileManager.reason),
        ]))
        #expect(!home.exists(home.paths.configFileURL))
        #expect(!home.exists(home.paths.importedPricesFileURL))
        #expect(home.exists(home.paths.configDirectoryURL))
        #expect(home.strayFiles(in: home.paths.configDirectoryURL).isEmpty)
        #expect(home.legacySnapshot() == before)
        #expect(LegacyDataMove.run(paths: home.paths) == .skipped)
    }

    @Test func anUnreadableLegacyFileFailsAloneAndTheOthersAreCopied() throws {
        let home = try Home("unreadable")
        try home.write(home.paths.legacyConfigFileURL, "{}")
        try home.write(home.paths.legacyImportedPricesFileURL, "{}")
        try home.write(home.paths.legacyLastGoodFileURL, "{}")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: home.paths.legacyConfigFileURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: home.paths.legacyConfigFileURL.path)
        }
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        guard case .moved(let copied, let failed) = outcome else {
            Issue.record("expected .moved, got \(outcome)")
            return
        }
        #expect(copied == ["imported-prices.json", "last-good.json"])
        #expect(failed.map(\.file) == ["config.json"])
        #expect(!home.exists(home.paths.configFileURL))
        #expect(home.exists(home.paths.importedPricesFileURL))
        #expect(home.exists(home.paths.lastGoodFileURL))
        #expect(home.strayFiles(in: home.paths.configDirectoryURL).isEmpty)
        #expect(home.legacySnapshot() == before)
    }

    @Test func copiesAreReadableOnlyByTheUser() throws {
        let home = try Home("modes")
        try home.write(home.paths.legacyConfigFileURL, "{}")
        try home.write(home.paths.legacyImportedPricesFileURL, "{}")
        try home.write(home.paths.legacyLastGoodFileURL, "{}")
        for url in [home.paths.legacyConfigFileURL, home.paths.legacyImportedPricesFileURL, home.paths.legacyLastGoodFileURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }

        _ = LegacyDataMove.run(paths: home.paths)

        for url in [home.paths.configFileURL, home.paths.importedPricesFileURL, home.paths.lastGoodFileURL] {
            #expect(Self.mode(of: url) == 0o600)
        }
        // README "What it writes": last-good.json lives in a 0700 directory.
        #expect(Self.mode(of: home.paths.lastGoodFileURL.deletingLastPathComponent()) == 0o700)
    }

    @Test func aSymlinkedLegacyFileIsCopiedAsTheBytesItPointsTo() throws {
        let home = try Home("symlink")
        let target = home.root.appendingPathComponent("dotfiles/config.json")
        let config = try home.write(target, #"{"from":"dotfiles"}"#)
        try FileManager.default.createDirectory(at: home.paths.legacyConfigFileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.paths.legacyConfigFileURL, withDestinationURL: target)
        // A relative link to a file next to it, as dotfile managers make.
        let prices = try home.write(home.paths.legacyImportedPricesFileURL.deletingLastPathComponent()
            .appendingPathComponent("prices.local.json"), #"{"batches":[]}"#)
        try FileManager.default.createSymbolicLink(atPath: home.paths.legacyImportedPricesFileURL.path,
                                                   withDestinationPath: "prices.local.json")
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: ["config.json", "imported-prices.json"], failed: []))
        for (url, bytes) in [(home.paths.configFileURL, config), (home.paths.importedPricesFileURL, prices)] {
            let type = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
            #expect(type == .typeRegular)
            #expect(FileManager.default.contents(atPath: url.path) == bytes)
        }
        #expect(home.legacySnapshot() == before)
    }

    // A blocking open of the FIFO would hang; the limit turns it into a failure.
    @Test(.timeLimit(.minutes(1)))
    func aFIFOFolderOrDanglingLinkAtALegacyNameIsAFailureAndDoesNotBlock() throws {
        let home = try Home("not-regular")
        try FileManager.default.createDirectory(at: home.paths.legacyConfigFileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        #expect(mkfifo(home.paths.legacyConfigFileURL.path, 0o644) == 0)
        try FileManager.default.createSymbolicLink(atPath: home.paths.legacyImportedPricesFileURL.path,
                                                   withDestinationPath: "gone.json")
        try FileManager.default.createDirectory(at: home.paths.legacyLastGoodFileURL, withIntermediateDirectories: true)
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: [], failed: [
            .init(file: "config.json", reason: LegacyDataMove.notARegularFile),
            .init(file: "imported-prices.json", reason: LegacyDataMove.notARegularFile),
            .init(file: "last-good.json", reason: LegacyDataMove.notARegularFile),
        ]))
        #expect(!home.exists(home.paths.importedPricesFileURL))
        #expect(!home.exists(home.paths.configFileURL))
        #expect(!home.exists(home.paths.lastGoodFileURL))
        #expect(home.legacySnapshot() == before)
    }

    @Test func aDestinationInsideALegacyFolderIsAFailure() throws {
        let home = try Home("destination-link")
        try home.write(home.paths.legacyLastGoodFileURL, "{}")
        // AgentTacho's Application Support folder linked to the legacy one.
        try FileManager.default.createSymbolicLink(at: home.paths.lastGoodFileURL.deletingLastPathComponent(),
                                                   withDestinationURL: home.paths.legacyLastGoodFileURL.deletingLastPathComponent())
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: [], failed: [
            .init(file: "last-good.json", reason: LegacyDataMove.destinationIsLegacy),
        ]))
        #expect(home.legacySnapshot() == before)
    }

    @Test func anExistingDestinationFileIsReplacedAsAWhole() throws {
        let home = try Home("replace")
        let fresh = try home.write(home.paths.legacyLastGoodFileURL, #"{"new":true}"#)
        try home.write(home.paths.lastGoodFileURL, #"{"old":true}"#)
        let folder = home.paths.lastGoodFileURL.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: home.paths.lastGoodFileURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: ["last-good.json"], failed: []))
        #expect(FileManager.default.contents(atPath: home.paths.lastGoodFileURL.path) == fresh)
        // The new file's mode, not the old one's, and the folder tightened.
        #expect(Self.mode(of: home.paths.lastGoodFileURL) == 0o600)
        #expect(Self.mode(of: folder) == 0o700)
        #expect(home.strayFiles(in: home.paths.lastGoodFileURL.deletingLastPathComponent()).isEmpty)
        #expect(home.legacySnapshot() == before)
    }

    @Test func aFileAboveTheLimitIsAFailure() throws {
        let home = try Home("too-large")
        try home.write(home.paths.legacyConfigFileURL, "")
        let handle = try FileHandle(forWritingTo: home.paths.legacyConfigFileURL)
        try handle.truncate(atOffset: UInt64(LegacyDataMove.maximumFileSize + 1))
        try handle.close()
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: [], failed: [.init(file: "config.json", reason: LegacyDataMove.tooLarge)]))
        #expect(!home.exists(home.paths.configFileURL))
        #expect(home.legacySnapshot() == before)
    }

    @Test func aDestinationLinkedToTheLegacyLogFolderIsAFailure() throws {
        let home = try Home("destination-logs")
        try home.write(home.paths.legacyLastGoodFileURL, "{}")
        try home.write(home.paths.legacyLogDirectoryURL.appendingPathComponent("usage.log"), "old log\n")
        try FileManager.default.createDirectory(at: home.paths.lastGoodFileURL.deletingLastPathComponent().deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.paths.lastGoodFileURL.deletingLastPathComponent(),
                                                   withDestinationURL: home.paths.legacyLogDirectoryURL)
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: [], failed: [.init(file: "last-good.json", reason: LegacyDataMove.destinationIsLegacy)]))
        #expect(home.legacySnapshot() == before)
    }

    @Test func aMissingDestinationUnderALinkedParentIsCheckedToo() throws {
        let home = try Home("destination-parent")
        // ~/Library/Application Support is a link into the legacy
        // configuration folder; the agenttacho folder under it is missing.
        let support = home.paths.lastGoodFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let legacyConfigFolder = home.paths.legacyConfigFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: legacyConfigFolder.appendingPathComponent("agentmeter"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: support, withDestinationURL: legacyConfigFolder)
        try home.write(home.paths.legacyLastGoodFileURL, "{}")
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: [], failed: [.init(file: "last-good.json", reason: LegacyDataMove.destinationIsLegacy)]))
        #expect(!FileManager.default.fileExists(atPath: legacyConfigFolder.appendingPathComponent("agenttacho").path))
        #expect(home.legacySnapshot() == before)
    }

    @Test func theMarkerFolderIsNeverCreatedInsideALegacyFolder() throws {
        let home = try Home("marker-link")
        try home.write(home.paths.legacyLastGoodFileURL, "{}")
        try FileManager.default.createDirectory(at: home.paths.legacyLogDirectoryURL, withIntermediateDirectories: true)
        // ~/.config is a link to the legacy log folder.
        try FileManager.default.createSymbolicLink(at: home.paths.configDirectoryURL.deletingLastPathComponent(),
                                                   withDestinationURL: home.paths.legacyLogDirectoryURL)
        let before = home.legacySnapshot()

        let outcome = LegacyDataMove.run(paths: home.paths)

        #expect(outcome == .moved(copied: ["last-good.json"], failed: []))
        #expect(!FileManager.default.fileExists(atPath: home.paths.legacyLogDirectoryURL.appendingPathComponent("agenttacho").path))
        #expect(home.legacySnapshot() == before)
    }

    static func mode(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? Int
    }

    @Test func logLinesNameTheCopiedFilesOnce() {
        let lines = LegacyDataMove.logLines(for: .moved(
            copied: ["config.json", "imported-prices.json", "last-good.json"], failed: []))
        #expect(lines == ["copied from AgentMeter: config.json, imported-prices.json, last-good.json"])
    }

    @Test func logLinesNameEachFailure() {
        let lines = LegacyDataMove.logLines(for: .moved(
            copied: ["last-good.json"],
            failed: [.init(file: "config.json", reason: "permission denied")]))
        #expect(lines == [
            "copied from AgentMeter: last-good.json",
            "could not copy config.json from AgentMeter: permission denied, starting with defaults",
        ])
        #expect(LegacyDataMove.logLines(for: .moved(copied: [], failed: [.init(file: "last-good.json", reason: "disk full")]))
            == ["could not copy last-good.json from AgentMeter: disk full, starting with defaults"])
    }

    @Test func noLogLinesWithoutAMove() {
        #expect(LegacyDataMove.logLines(for: .skipped).isEmpty)
        #expect(LegacyDataMove.logLines(for: .nothingToMove).isEmpty)
    }
}

/// A file manager whose final move into place always fails, to check that
/// no temporary file is left behind (contracts/legacy-data-move.md, guarantee 2).
final class FailingMoveFileManager: FileManager, @unchecked Sendable {
    static let reason = "simulated move failure"

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw NSError(domain: "LegacyDataMoveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: Self.reason])
    }
}
