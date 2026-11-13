import Foundation
import Testing
@testable import UsageCore

/// spec 045 FR-001, FR-003, FR-012: the probe finds and reads a working
/// directory's decision log.
@Suite struct DecisionLogProbeTests {
    static let fileName = ".automode_decisions.jsonl"

    func line(_ ts: Int, output: Int = 1) -> String {
        #"{"ts":\#(ts),"classifierModel":"m","outputTokens":\#(output)}"# + "\n"
    }

    func makeDirectory(_ name: String) throws -> URL {
        try makeTempDirectory(name).resolvingSymlinksInPath()
    }

    @Test func unknownFileIsReadFromTheStart() throws {
        let dir = try makeDirectory("probe-new")
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = line(1) + line(2)
        try Data(content.utf8).write(to: dir.appendingPathComponent(Self.fileName))

        let report = DecisionLogProbe().check(directories: [dir.path], known: [:])
        let canonical = Attributor.canonical(dir.path)
        #expect(report.canonical[dir.path] == canonical)
        guard case .found(let path, let size, _, let chunk) = report.results[dir.path] else {
            Issue.record("expected .found, got \(String(describing: report.results[dir.path]))")
            return
        }
        #expect(path == canonical + "/" + Self.fileName)
        #expect(size == content.utf8.count)
        #expect(chunk == ReadChunk(from: 0, data: Data(content.utf8)))
    }

    @Test func grownFileIsReadFromTheParsedOffset() throws {
        let dir = try makeDirectory("probe-grown")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(Self.fileName)
        let first = line(1)
        try Data((first + line(2)).utf8).write(to: url)
        let path = Attributor.canonical(dir.path) + "/" + Self.fileName
        let known = [path: KnownLogState(size: first.utf8.count, modificationDate: .distantPast, parsedOffset: first.utf8.count)]

        let report = DecisionLogProbe().check(directories: [dir.path], known: known)
        guard case .found(_, _, _, let chunk) = report.results[dir.path] else {
            Issue.record("expected .found")
            return
        }
        #expect(chunk == ReadChunk(from: first.utf8.count, data: Data(line(2).utf8)))
    }

    @Test func fileShorterThanTheParsedOffsetIsReadFromTheStart() throws {
        let dir = try makeDirectory("probe-shorter")
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = line(9)
        try Data(content.utf8).write(to: dir.appendingPathComponent(Self.fileName))
        let path = Attributor.canonical(dir.path) + "/" + Self.fileName
        let known = [path: KnownLogState(size: 1000, modificationDate: .distantPast, parsedOffset: 1000)]

        let report = DecisionLogProbe().check(directories: [dir.path], known: known)
        guard case .found(_, _, _, let chunk) = report.results[dir.path] else {
            Issue.record("expected .found")
            return
        }
        #expect(chunk == ReadChunk(from: 0, data: Data(content.utf8)))
    }

    @Test func unchangedFileIsNotRead() throws {
        let dir = try makeDirectory("probe-unchanged")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(Self.fileName)
        try Data(line(1).utf8).write(to: url)
        let first = DecisionLogProbe().check(directories: [dir.path], known: [:])
        guard case .found(let path, let size, let date, _) = first.results[dir.path] else {
            Issue.record("expected .found")
            return
        }
        let known = [path: KnownLogState(size: size, modificationDate: date, parsedOffset: size)]
        let second = DecisionLogProbe().check(directories: [dir.path], known: known)
        #expect(second.results[dir.path] == .found(path: path, size: size, modificationDate: date, chunk: nil))
    }

    @Test func missingLogOrDirectoryIsAbsent() throws {
        let dir = try makeDirectory("probe-absent")
        defer { try? FileManager.default.removeItem(at: dir) }
        let gone = dir.appendingPathComponent("removed-worktree").path
        let report = DecisionLogProbe().check(directories: [dir.path, gone], known: [:])
        #expect(report.results[dir.path] == .absent)
        #expect(report.results[gone] == .absent)
        #expect(report.canonical[dir.path] == Attributor.canonical(dir.path))
    }

    /// FR-001: two spellings of one directory (a trailing slash, a
    /// symlinked parent) are one directory, whose log is reported once.
    @Test func spellingsOfOneDirectoryAreReportedOnce() throws {
        let root = try makeDirectory("probe-spellings")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real/W")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"),
                                                   withDestinationURL: root.appendingPathComponent("real"))
        try Data(line(1).utf8).write(to: real.appendingPathComponent(Self.fileName))
        let spellings = [real.path, real.path + "/", root.appendingPathComponent("link/W").path]

        let report = DecisionLogProbe().check(directories: spellings, known: [:])
        let canonical = Attributor.canonical(real.path)
        #expect(spellings.allSatisfy { report.canonical[$0] == canonical })
        let found = report.results.values.filter { if case .found = $0 { return true } else { return false } }
        #expect(found.count == 1)
    }
}
