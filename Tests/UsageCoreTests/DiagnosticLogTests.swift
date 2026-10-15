import Foundation
import Testing
@testable import UsageCore

@Suite struct DiagnosticLogTests {
    /// The current file and its one rolled-over generation together stay
    /// within 5 MB.
    @Test func bothGenerationsTogetherStayWithinFiveMegabytes() {
        #expect(DiagnosticLog.defaultMaxBytes * 2 <= 5 * 1024 * 1024)
    }

    // MARK: Tail (Settings > Log)

    @Test func tailReturnsTheLastLinesInOrder() throws {
        let dir = try makeTempDirectory("log-tail")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = DiagnosticLog(fileURL: dir.appendingPathComponent("usage.log"))
        for i in 0..<10 { log.append(source: "s", message: "line \(i)") }
        let tail = log.tail(lines: 3)
        #expect(tail.count == 3)
        #expect(tail[0].hasSuffix("[s] line 7"))
        #expect(tail[2].hasSuffix("[s] line 9"))
    }

    @Test func tailReadsOnlyTheEndAndDropsTheCutFirstLine() throws {
        let dir = try makeTempDirectory("log-tail-window")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = DiagnosticLog(fileURL: dir.appendingPathComponent("usage.log"))
        for i in 0..<100 { log.append(source: "s", message: String(repeating: "x", count: 50) + " \(i)") }
        // A 300-byte window holds about four whole lines; the first, cut
        // line is dropped instead of shown as a fragment.
        let tail = log.tail(lines: 500, maxBytes: 300)
        #expect(!tail.isEmpty && tail.count < 6)
        #expect(tail.allSatisfy { $0.contains("[s] ") })
        #expect(tail.last?.hasSuffix(" 99") == true)
    }

    @Test func tailOfAMissingFileIsEmpty() throws {
        let dir = try makeTempDirectory("log-tail-missing")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = DiagnosticLog(fileURL: dir.appendingPathComponent("usage.log"))
        #expect(log.tail(lines: 10).isEmpty)
    }

    @Test func appendsTimestampedLines() throws {
        let dir = try makeTempDirectory("log")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = DiagnosticLog(fileURL: dir.appendingPathComponent("nested/usage.log"))
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        log.append(source: "subscription", message: "ok", at: date)
        log.append(source: "sessionLogs", message: "files=3", at: date)
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("[subscription] ok"))
        #expect(lines[0].hasPrefix("2025-10-09T"))
        #expect(lines[1].hasSuffix("[sessionLogs] files=3"))
    }

    @Test func controlCharactersCannotAddLines() throws {
        let dir = try makeTempDirectory("log-single-line")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = DiagnosticLog(fileURL: dir.appendingPathComponent("usage.log"))
        log.append(source: "prices", message: "CSV import of evil\n2026-01-01T00:00:00Z [subscription] ok\r\t\u{07}\u{2028}.csv failed")
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 1)
        #expect(lines[0].hasSuffix(#"[prices] CSV import of evil\n2026-01-01T00:00:00Z [subscription] ok\r\t\u{0007}\u{2028}.csv failed"#))
    }

    @Test func rollsOverWhenExceedingMaxBytes() throws {
        let dir = try makeTempDirectory("log-rollover")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("usage.log")
        let log = DiagnosticLog(fileURL: file, maxBytes: 200)
        for i in 0..<10 {
            log.append(source: "s", message: String(repeating: "x", count: 40) + " \(i)")
        }
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: file.path))
        #expect(fm.fileExists(atPath: log.rolledOverURL.path))
        let currentSize = try fm.attributesOfItem(atPath: file.path)[.size] as! Int
        let oldSize = try fm.attributesOfItem(atPath: log.rolledOverURL.path)[.size] as! Int
        #expect(currentSize <= 200)
        #expect(oldSize <= 200)
        let current = try String(contentsOf: file, encoding: .utf8)
        #expect(current.contains(" 9\n"))
    }
}
