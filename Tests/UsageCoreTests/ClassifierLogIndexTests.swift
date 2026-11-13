import Foundation
import Testing
@testable import UsageCore

/// spec 045 FR-003, FR-004, FR-008a: the classifier index parses the chunks
/// the probe read and keeps rows per decision log.
@Suite struct ClassifierLogIndexTests {
    static let directory = "/fixture/W"
    static let path = DecisionLogProbe.logPath(inDirectory: directory)
    let window = DateInterval(start: isoDate("2026-11-12T00:00:00Z"), end: isoDate("2026-11-19T00:00:00Z"))

    /// A line at `time` (inside the window unless given otherwise).
    func line(_ time: String = "2026-11-12T17:38:34Z", output: Int = 1) -> String {
        let ms = Int(isoDate(time).timeIntervalSince1970 * 1000)
        return #"{"ts":\#(ms),"classifierModel":"m[1m]","outputTokens":\#(output)}"# + "\n"
    }

    func report(_ text: String, from: Int = 0, size: Int? = nil, date: Date = isoDate("2026-11-12T18:00:00Z")) -> ProbeReport {
        let data = Data(text.utf8)
        return ProbeReport(results: [Self.directory: .found(path: Self.path, size: size ?? from + data.count, modificationDate: date,
                                                            chunk: ReadChunk(from: from, data: data))],
                           canonical: [Self.directory: Self.directory])
    }

    @Test func firstReadStoresCompleteInWindowRowsInFileOrder() throws {
        let first = line(output: 1)
        let second = line("2026-11-12T17:38:44Z", output: 2)
        let before = line("2026-11-11T23:59:59Z", output: 3)
        let partial = #"{"ts":1794505114575,"classifierModel":"m","#
        let text = first + before + second + partial

        let index = ClassifierLogIndex()
        _ = index.update(report: report(text), window: window)

        let entry = try #require(index.entries[Self.path])
        #expect(entry.canonicalPath == Self.path)
        #expect(entry.directory == Self.directory)
        #expect(entry.rows.map(\.outputTokens) == [1, 2])
        #expect(entry.rows.map(\.id) == ["\(Self.path)#0", "\(Self.path)#\(first.utf8.count + before.utf8.count)"])
        #expect(entry.rows.allSatisfy { $0.model == "m" })
        #expect(entry.parsedOffset == text.utf8.count - partial.utf8.count)
        #expect(entry.size == text.utf8.count)
        #expect(entry.modificationDate == isoDate("2026-11-12T18:00:00Z"))
    }

    @Test func knownStateIsTheSnapshotForTheProbe() {
        let text = line()
        let index = ClassifierLogIndex()
        _ = index.update(report: report(text), window: window)
        #expect(index.known() == [Self.path: KnownLogState(size: text.utf8.count, modificationDate: isoDate("2026-11-12T18:00:00Z"),
                                                            parsedOffset: text.utf8.count)])
    }
}
