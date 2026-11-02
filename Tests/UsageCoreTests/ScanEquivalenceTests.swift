import Foundation
import Testing
@testable import UsageCore

/// The reading rules the faster scan must keep, pinned on today's code:
/// a very long line, an incomplete last line and a record split across an
/// append (spec 039 FR-010, FR-012, User Story 2 scenario 4).
@Suite struct ScanEquivalenceTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let parser = SessionRecordParser()
    let pricer = try! PriceTable.builtIn()

    /// An assistant record as Claude Code writes it, the top-level `type`
    /// last; `padding` bytes of text in its content make it long.
    static func record(id: String, at timestamp: String = "2026-10-14T10:00:00.000Z", padding: Int = 0) -> String {
        let text = String(repeating: "p", count: max(1, padding))
        return #"{"parentUuid":"u-\#(id)","sessionId":"s-eq","cwd":"/fixture/proj-alpha","message":{"id":"msg_eq_\#(id)","model":"claude-opus-4-6","role":"assistant","content":[{"type":"text","text":"\#(text)"}],"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":20}},"requestId":"req_vrtx_\#(id)","timestamp":"\#(timestamp)","type":"assistant"}"#
    }

    func makeFile(_ name: String) throws -> (root: URL, file: URL) {
        let root = try makeTempDirectory("scan-eq-\(name)")
        let file = root.appendingPathComponent("projects/p/session.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (root, file)
    }

    func update(_ index: LogIndex, root: URL) -> LogIndexStats {
        let scan = LogDirectoryScanner().scan(directories: [root.path])
        return index.update(files: scan.files, window: window, parser: parser, attributor: Attributor(configuration: Configuration()),
                            pricer: pricer)
    }

    func append(_ text: String, to file: URL) throws {
        try FileHandle(forWritingTo: file).withAppend(Data(text.utf8))
    }

    @Test func recordPaddedToOnePointEightMegabytesIsParsedOnce() throws {
        let (root, file) = try makeFile("long")
        defer { try? FileManager.default.removeItem(at: root) }
        let line = Self.record(id: "long", padding: 1_800_000)
        #expect(line.utf8.count > 1_800_000)
        try Data((line + "\n").utf8).write(to: file)
        let index = LogIndex()
        let stats = update(index, root: root)
        #expect(stats.filesRead == 1)
        #expect(stats.linesVisited == 1)
        #expect(stats.bytesRead == line.utf8.count + 1)
        #expect(index.records.map(\.messageId) == ["msg_eq_long"])
        #expect(index.records.first?.outputTokens == 20)
    }

    @Test func incompleteLastLineWaitsForItsNewline() throws {
        let (root, file) = try makeFile("tail")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data((Self.record(id: "a") + "\n" + Self.record(id: "b", at: "2026-10-14T10:01:00.000Z")).utf8).write(to: file)
        let index = LogIndex()
        let first = update(index, root: root)
        #expect(first.linesVisited == 1)
        #expect(index.records.map(\.messageId) == ["msg_eq_a"])

        try append("\n", to: file)
        let second = update(index, root: root)
        // Only the completed line is read again.
        #expect(second.linesVisited == 1)
        #expect(index.records.map(\.messageId) == ["msg_eq_a", "msg_eq_b"])
        #expect(index.records.filter { $0.messageId == "msg_eq_b" }.count == 1)
    }

    @Test func recordSplitAcrossAnAppendIsCountedOnce() throws {
        let (root, file) = try makeFile("split")
        defer { try? FileManager.default.removeItem(at: root) }
        let line = Self.record(id: "split")
        let cut = line.index(line.startIndex, offsetBy: line.count / 2)
        try Data(line[..<cut].utf8).write(to: file)
        let index = LogIndex()
        _ = update(index, root: root)
        #expect(index.records.isEmpty)
        #expect(index.entries.values.first?.parsedOffset == 0)

        try append(String(line[cut...]) + "\n", to: file)
        _ = update(index, root: root)
        #expect(index.records.map(\.messageId) == ["msg_eq_split"])

        try append(Self.record(id: "next", at: "2026-10-14T10:02:00.000Z") + "\n", to: file)
        _ = update(index, root: root)
        #expect(index.records.map(\.messageId) == ["msg_eq_split", "msg_eq_next"])
        #expect(index.entries.values.first?.parsedOffset == (try Data(contentsOf: file)).count)
    }
}
