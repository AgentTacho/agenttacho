import Foundation
import Testing
@testable import UsageCore

@Suite struct DiagnosticLogTests {
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
