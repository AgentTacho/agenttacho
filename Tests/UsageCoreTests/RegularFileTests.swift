import Foundation
import Testing
@testable import UsageCore

/// The safe read shared by LastGoodStore (spec 010 FR-018) and
/// LegacyDataMove (spec 023 FR-008, FR-010).
@Suite struct RegularFileTests {
    @Test func readsARegularFile() throws {
        let root = try makeTempDirectory("regular-file-ok")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a.json")
        try Data("{}".utf8).write(to: url)
        #expect(try RegularFile.read(url, maximumSize: 10) == Data("{}".utf8))
    }

    @Test func aMissingFileIsMissing() throws {
        let root = try makeTempDirectory("regular-file-missing")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: RegularFile.Failure.missing) {
            try RegularFile.read(root.appendingPathComponent("none.json"), maximumSize: 10)
        }
    }

    // A blocking open of the FIFO would hang; the limit turns it into a failure.
    @Test(.timeLimit(.minutes(1)))
    func aFolderLinkOrFIFOIsNotRegular() throws {
        let root = try makeTempDirectory("regular-file-odd")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let dangling = root.appendingPathComponent("dangling.json")
        try FileManager.default.createSymbolicLink(atPath: dangling.path, withDestinationPath: "nowhere.json")
        let fifo = root.appendingPathComponent("fifo.json")
        #expect(mkfifo(fifo.path, 0o644) == 0)

        for url in [folder, link, dangling, fifo] {
            #expect(throws: RegularFile.Failure.notRegular) { try RegularFile.read(url, maximumSize: 10) }
        }
    }

    @Test func aFileAboveTheLimitIsTooLargeAndNotRead() throws {
        let root = try makeTempDirectory("regular-file-large")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("large.json")
        try Data(count: 11).write(to: url)
        #expect(throws: RegularFile.Failure.tooLarge(11)) { try RegularFile.read(url, maximumSize: 10) }
        try Data(count: 10).write(to: url)
        #expect(try RegularFile.read(url, maximumSize: 10).count == 10)
    }

    @Test func anUnreadableFileNamesTheReason() throws {
        let root = try makeTempDirectory("regular-file-unreadable")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("secret.json")
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        #expect(throws: RegularFile.Failure.unreadable(EACCES)) { try RegularFile.read(url, maximumSize: 10) }
        #expect(RegularFile.Failure.unreadable(EACCES).reason == "Permission denied")
    }
}
