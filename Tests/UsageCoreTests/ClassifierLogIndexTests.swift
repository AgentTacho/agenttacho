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

    // MARK: Incremental reading through a real probe (US2, FR-002, FR-003, FR-008a)

    /// A temporary working directory with a decision log, refreshed through
    /// a real probe.
    final class Fixture {
        let dir: URL
        let index = ClassifierLogIndex()
        let probe = DecisionLogProbe()
        var date = isoDate("2026-11-12T18:00:00Z")

        init(_ name: String) throws {
            dir = try makeTempDirectory(name).resolvingSymlinksInPath()
        }

        deinit { try? FileManager.default.removeItem(at: dir) }

        var url: URL { dir.appendingPathComponent(DecisionLogProbe.fileName) }
        var path: String { DecisionLogProbe.logPath(inDirectory: Attributor.canonical(dir.path)) }
        var rows: [ClassifierRow] { index.entries[path]?.rows ?? [] }

        /// Each change gets a later modification date.
        func touch(_ date: Date? = nil) throws {
            self.date = date ?? self.date.addingTimeInterval(60)
            try FileManager.default.setAttributes([.modificationDate: self.date], ofItemAtPath: url.path)
        }

        func write(_ text: String, date: Date? = nil) throws {
            try Data(text.utf8).write(to: url)
            try touch(date)
        }

        func append(_ text: String) throws {
            try FileHandle(forWritingTo: url).withAppend(Data(text.utf8))
            try touch()
        }

        @discardableResult
        func refresh(_ window: DateInterval) -> ClassifierIndexStats {
            index.prepare(window: window)
            let report = probe.check(directories: [dir.path], known: index.known(), notBefore: window.start)
            return index.update(report: report, window: window)
        }
    }

    @Test func unchangedFileIsNotReadAgain() throws {
        let f = try Fixture("cindex-unchanged")
        try f.write(line() + line(output: 2))
        let first = f.refresh(window)
        #expect(first.bytesRead > 0)
        let second = f.refresh(window)
        #expect(second.bytesRead == 0)
        #expect(second.logsFound == 1)
        #expect(f.rows.map(\.outputTokens) == [1, 2])
    }

    @Test func appendedRowIsReadAlone() throws {
        let f = try Fixture("cindex-append")
        try f.write(line())
        f.refresh(window)
        let appended = line(output: 5)
        try f.append(appended)
        let stats = f.refresh(window)
        #expect(stats.bytesRead == appended.utf8.count)
        #expect(f.rows.map(\.outputTokens) == [1, 5])
    }

    @Test func incompleteLastLineCountsOnceWhenCompleted() throws {
        let f = try Fixture("cindex-partial")
        let full = line(output: 7)
        let cut = full.utf8.count / 2
        try f.write(line() + String(decoding: Data(full.utf8).prefix(cut), as: UTF8.self))
        f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [1])
        try f.append(String(decoding: Data(full.utf8).dropFirst(cut), as: UTF8.self))
        f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [1, 7])
        f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [1, 7])
    }

    @Test func shorterFileIsReadAgainFromTheStart() throws {
        let f = try Fixture("cindex-shorter")
        try f.write(line(output: 1) + line(output: 2) + line(output: 3))
        f.refresh(window)
        try f.write(line(output: 9))
        f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [9])
        #expect(f.rows.first?.id == "\(f.path)#0")
    }

    @Test func deletedFileStopsCounting() throws {
        let f = try Fixture("cindex-deleted")
        try f.write(line())
        f.refresh(window)
        try FileManager.default.removeItem(at: f.url)
        f.refresh(window)
        #expect(f.index.entries.isEmpty)
    }

    /// FR-002: a log modified before the window start is not read, and an
    /// entry whose log falls before it is removed.
    @Test func fileOlderThanTheWindowIsNotRead() throws {
        let f = try Fixture("cindex-old")
        try f.write(line(), date: isoDate("2026-11-11T12:00:00Z"))
        let stats = f.refresh(window)
        #expect(stats.bytesRead == 0)
        #expect(f.index.entries.isEmpty)

        try f.touch(isoDate("2026-11-12T12:00:00Z"))
        f.refresh(window)
        #expect(f.rows.count == 1)
        try f.touch(isoDate("2026-11-11T12:00:00Z"))
        f.refresh(window)
        #expect(f.index.entries.isEmpty)
    }

    /// FR-008a: identical lines are two calls.
    @Test func identicalLinesCountTwice() throws {
        let f = try Fixture("cindex-identical")
        try f.write(line() + line())
        f.refresh(window)
        #expect(f.rows.count == 2)
        #expect(Set(f.rows.map(\.id)).count == 2)
    }

    @Test func rowsBeforeTheWindowArePrunedAndComeBackWhenItMovesEarlier() throws {
        let f = try Fixture("cindex-window")
        // Modified inside both windows, so FR-002 keeps it.
        try f.write(line("2026-11-12T10:00:00Z", output: 1) + line("2026-11-13T10:00:00Z", output: 2),
                    date: isoDate("2026-11-13T12:00:00Z"))
        f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [1, 2])

        let later = DateInterval(start: isoDate("2026-11-13T00:00:00Z"), end: window.end)
        f.refresh(later)
        #expect(f.rows.map(\.outputTokens) == [2])

        f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [1, 2])
    }
}

/// spec 045 SC-004, research R8: the whole classifier step over 50 working
/// directories with 100 KB decision logs already read stays under 50 ms.
/// Serialized, so other tests of this suite do not compete for the time.
@Suite(.serialized) struct ClassifierStepTimingTests {
    @Test func steadyStateStepOverFiftyLogsTakesUnderFiftyMilliseconds() throws {
        let root = try makeTempDirectory("classifier-timing").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let window = DateInterval(start: isoDate("2026-11-12T00:00:00Z"), end: isoDate("2026-11-19T00:00:00Z"))
        let sessionTime = isoDate("2026-11-12T17:00:00Z")
        let ms = Int(sessionTime.timeIntervalSince1970 * 1000) + 1000
        let line = #"{"ts":\#(ms),"tool":"Bash","decision":"allowed","classifierModel":"rits/zai-org/glm-5-3[1m]","inputTokens":484,"outputTokens":23,"cacheReadInputTokens":34304,"cacheCreationInputTokens":0,"durationMs":1800,"costUSD":0,"stage":"fast","reason":"\#(String(repeating: "x", count: 300))"}"# + "\n"
        let text = String(repeating: line, count: 100 * 1024 / line.utf8.count)
        var sessions: [UsageRecord] = []
        for i in 0..<50 {
            let dir = root.appendingPathComponent("W\(i)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let log = dir.appendingPathComponent(DecisionLogProbe.fileName)
            try Data(text.utf8).write(to: log)
            try FileManager.default.setAttributes([.modificationDate: isoDate("2026-11-12T18:00:00Z")], ofItemAtPath: log.path)
            sessions.append(UsageRecord(messageId: "m\(i)", timestamp: sessionTime, model: "rits/zai-org/glm-5-3",
                                        canonicalModel: "rits/zai-org/glm-5-3", requestId: "gw_\(i)", accountId: "acc",
                                        inputTokens: 1, outputTokens: 1, cacheWrite5mTokens: 0, cacheWrite1hTokens: 0,
                                        cacheReadTokens: 0, costUSD: nil, sessionKey: "s\(i)", cwd: dir.path))
        }
        let index = ClassifierLogIndex()
        let probe = DecisionLogProbe()
        let pricer = try PriceTable.builtIn()

        let cold = SessionLogSource.classifierStep(sessionRecords: sessions, index: index, probe: probe, window: window, pricer: pricer)
        #expect(cold.indexStats.logsRead == 50)
        let rows = cold.attribution.records.count
        #expect(rows >= 50 * 100)

        let clock = ContinuousClock()
        var steady: SessionLogSource.ClassifierStepResult?
        let elapsed = clock.measure {
            steady = SessionLogSource.classifierStep(sessionRecords: sessions, index: index, probe: probe, window: window, pricer: pricer)
        }
        #expect(steady?.indexStats.bytesRead == 0)
        #expect(steady?.attribution.records.count == rows)
        #expect(steady?.attribution.assigned == rows)
        #expect(elapsed < .milliseconds(50), "steady-state classifier step took \(elapsed)")
    }
}
