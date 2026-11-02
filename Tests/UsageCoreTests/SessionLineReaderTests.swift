import Foundation
import Testing
@testable import UsageCore

/// Visiting a file's lines in place over its buffer (spec 039 FR-012,
/// research R3).
@Suite struct SessionLineReaderTests {
    /// The visited lines as byte arrays and the consumed byte count.
    static func visit(_ bytes: [UInt8]) -> (lines: [[UInt8]], consumed: Int) {
        var lines: [[UInt8]] = []
        let consumed = bytes.withUnsafeBytes { buffer in
            SessionLineReader.forEachLine(in: buffer) { lines.append(Array($0)) }
        }
        return (lines, consumed)
    }

    static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    /// Today's `LogIndex.readCompleteLines` split, inlined as the reference:
    /// complete lines only, one trailing CR trimmed, empty lines skipped.
    static func reference(_ data: [UInt8]) -> (lines: [[UInt8]], consumed: Int) {
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return ([], 0) }
        let complete = data[data.startIndex...lastNewline]
        var lines: [[UInt8]] = []
        var lineStart = complete.startIndex
        for i in complete.indices where complete[i] == 0x0A {
            if i > lineStart {
                var end = i
                if complete[end - 1] == 0x0D { end -= 1 }
                if end > lineStart { lines.append(Array(complete[lineStart..<end])) }
            }
            lineStart = i + 1
        }
        return (lines, complete.count)
    }

    @Test func visitsLinesTrimsOneCROfEachAndSkipsEmptyLines() {
        let result = Self.visit(Self.bytes("a\n\nbc\r\n\r\nd\r\r\n\n"))
        #expect(result.lines == [Self.bytes("a"), Self.bytes("bc"), Self.bytes("d\r")])
        #expect(result.consumed == 14)
    }

    @Test func neverVisitsALastLineWithoutANewline() {
        let result = Self.visit(Self.bytes("first\nsecond"))
        #expect(result.lines == [Self.bytes("first")])
        #expect(result.consumed == 6)
    }

    @Test func aBufferWithoutANewlineYieldsNothing() {
        #expect(Self.visit(Self.bytes("no newline at all")).lines.isEmpty)
        #expect(Self.visit(Self.bytes("no newline at all")).consumed == 0)
        #expect(Self.visit([]).lines.isEmpty)
        #expect(Self.visit([]).consumed == 0)
    }

    /// A long line is handed over as a slice of the buffer, not a copy.
    @Test func aLongLineIsVisitedInPlace() {
        var bytes = [UInt8](repeating: UInt8(ascii: "x"), count: 1_800_000)
        bytes.append(0x0A)
        bytes += Self.bytes("tail\n")
        var visited: [(offset: Int, count: Int)] = []
        let consumed = bytes.withUnsafeBytes { buffer -> Int in
            let base = buffer.baseAddress!
            return SessionLineReader.forEachLine(in: buffer) { line in
                visited.append((base.distance(to: line.baseAddress!), line.count))
            }
        }
        #expect(visited.count == 2)
        #expect(visited.first?.offset == 0)
        #expect(visited.first?.count == 1_800_000)
        #expect(visited.last?.offset == 1_800_001)
        #expect(consumed == bytes.count)
    }

    @Test func bytesThatAreNotUTF8PassThrough() {
        let line: [UInt8] = [0x7B, 0xFF, 0xFE, 0xC3, 0x7D]
        #expect(Self.visit(line + [0x0A]).lines == [line])
    }

    /// Random buffers of newlines, CRs, text and invalid bytes give the
    /// same lines and consumed count as today's split.
    @Test func randomBuffersMatchTodaysSplit() {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
        let alphabet: [UInt8] = [0x0A, 0x0A, 0x0D, 0x0D, 0x61, 0x62, 0xFF, 0x7B, 0x20]
        for _ in 0..<2000 {
            let length = Int(next() % 64)
            let bytes = (0..<length).map { _ in alphabet[Int(next() % UInt64(alphabet.count))] }
            let actual = Self.visit(bytes)
            let expected = Self.reference(bytes)
            #expect(actual.lines == expected.lines, "\(bytes)")
            #expect(actual.consumed == expected.consumed, "\(bytes)")
        }
    }
}
