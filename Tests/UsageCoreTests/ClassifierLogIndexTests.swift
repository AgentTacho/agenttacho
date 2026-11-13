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

    /// FR-012: a timed-out or busy directory keeps its rows, while its last
    /// canonical directory is still reported.
    @Test(arguments: [ProbeResult.timedOut, .busy])
    func timedOutOrBusyDirectoryKeepsItsRows(_ result: ProbeResult) throws {
        let index = ClassifierLogIndex()
        _ = index.update(report: report(line()), window: window)
        let stats = index.update(report: ProbeReport(results: [Self.directory: result], canonical: [Self.directory: Self.directory]),
                                 window: window)
        #expect(index.entries[Self.path]?.rows.count == 1)
        #expect(stats.timedOut + stats.busy == 1)
    }

    /// FR-001: a log that is no regular file or too large stops counting.
    @Test(arguments: [ProbeResult.notRegular, .tooLarge(path: path, size: 70_000_000), .absent])
    func skippedOrGoneLogIsRemoved(_ result: ProbeResult) throws {
        let index = ClassifierLogIndex()
        _ = index.update(report: report(line()), window: window)
        let stats = index.update(report: ProbeReport(results: [Self.directory: result], canonical: [Self.directory: Self.directory]),
                                 window: window)
        #expect(index.entries.isEmpty)
        if case .tooLarge = result { #expect(stats.tooLargePaths == [Self.path]) }
        if case .absent = result { #expect(stats.skipped == 0) } else { #expect(stats.skipped == 1) }
    }

    /// FR-002, FR-003: a log whose directory is no longer checked (all its
    /// sessions left the window) stops counting.
    @Test func entryWhoseDirectoryIsNoLongerCheckedIsDropped() {
        let index = ClassifierLogIndex()
        _ = index.update(report: report(line()), window: window)
        _ = index.update(report: ProbeReport(), window: window)
        #expect(index.entries.isEmpty)
    }

    /// FR-012 (review finding): a new spelling whose first check times out
    /// may name a directory already read; when its plain path form (no
    /// file system access) matches the log's directory or a spelling seen
    /// for it, the log's rows keep counting.
    @Test(arguments: ["/fixture/W/", "/fixture/./W", "/fixture/X/../W//"])
    func unresolvedLexicalSpellingKeepsTheRows(_ spelling: String) {
        let index = ClassifierLogIndex()
        _ = index.update(report: report(line()), window: window)
        _ = index.update(report: ProbeReport(results: [spelling: .timedOut]), window: window)
        #expect(index.entries[Self.path]?.rows.count == 1)
        // Once every spelling is resolved, the unchecked directory goes.
        _ = index.update(report: ProbeReport(results: ["/other": .absent], canonical: ["/other": "/other"]), window: window)
        #expect(index.entries.isEmpty)
    }

    /// A spelling recorded for a log keeps protecting it while unresolved,
    /// even when it is a symbolic link that differs from the directory.
    @Test func unresolvedRecordedSpellingKeepsTheRows() {
        let index = ClassifierLogIndex()
        let data = Data(line().utf8)
        let found = ProbeResult.found(path: Self.path, size: data.count, modificationDate: isoDate("2026-11-12T18:00:00Z"),
                                      chunk: ReadChunk(from: 0, data: data))
        _ = index.update(report: ProbeReport(results: ["/fixture/link/W": found], canonical: ["/fixture/link/W": Self.directory]),
                         window: window)
        #expect(index.entries[Self.path]?.spellings == ["/fixture/link/W"])
        _ = index.update(report: ProbeReport(results: ["/fixture/link/W/": .timedOut]), window: window)
        #expect(index.entries[Self.path]?.rows.count == 1)
    }

    /// Review finding: an unresolved spelling protects only the logs it may
    /// name; a log whose sessions all left the window still goes.
    @Test func unresolvedSpellingDoesNotKeepUnrelatedLogs() {
        let index = ClassifierLogIndex()
        _ = index.update(report: report(line()), window: window)
        _ = index.update(report: ProbeReport(results: ["/elsewhere/link": .timedOut]), window: window)
        #expect(index.entries.isEmpty)
    }

    /// FR-003: bytes that do not continue the parsed offset drop the entry,
    /// so the log is read in full next time.
    @Test func nonContiguousChunkDropsTheEntry() {
        let index = ClassifierLogIndex()
        let first = line()
        _ = index.update(report: report(first), window: window)
        _ = index.update(report: report(line(output: 2), from: first.utf8.count + 10), window: window)
        #expect(index.entries.isEmpty)
        #expect(index.known().isEmpty)
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
        var stats = f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [1])
        // The unfinished line is left for later, not counted as malformed.
        #expect(stats.malformed == 0 && stats.withoutUsage == 0)
        try f.append(String(decoding: Data(full.utf8).dropFirst(cut), as: UTF8.self))
        stats = f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [1, 7])
        #expect(stats.malformed == 0 && stats.withoutUsage == 0)
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

    /// FR-003 (review finding): a log deleted and written again, longer
    /// than the old parsed offset, is another file: read from the start, and
    /// the old file's rows stop counting.
    @Test func replacedLongerFileIsReadAgainFromTheStart() throws {
        let f = try Fixture("cindex-replaced")
        try f.write(line(output: 1) + line(output: 2))
        f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [1, 2])
        try FileManager.default.removeItem(at: f.url)
        try f.write(line(output: 7) + line(output: 8) + line(output: 9))
        f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [7, 8, 9])
        #expect(f.rows.first?.id == "\(f.path)#0")
    }

    /// FR-003 (review finding): another file with the same size and
    /// modification date is still another file.
    @Test func replacedFileWithTheSameSizeAndDateIsReadAgain() throws {
        let f = try Fixture("cindex-replaced-same")
        try f.write(line(output: 1), date: f.date)
        f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [1])
        try FileManager.default.removeItem(at: f.url)
        try f.write(line(output: 2), date: f.date)
        f.refresh(window)
        #expect(f.rows.map(\.outputTokens) == [2])
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
/// Each directory has a realistic session of 200 records over 30 minutes
/// with the rows spread across it, so the per-record and per-row work is
/// measured. The median of five runs keeps a parallel test run from
/// deciding the result.
@Suite struct ClassifierStepTimingTests {
    @Test func steadyStateStepOverFiftyLogsTakesUnderFiftyMilliseconds() throws {
        let root = try makeTempDirectory("classifier-timing").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let window = DateInterval(start: isoDate("2026-11-12T00:00:00Z"), end: isoDate("2026-11-19T00:00:00Z"))
        let sessionTime = isoDate("2026-11-12T17:00:00Z")
        func line(_ i: Int) -> String {
            let ms = Int(sessionTime.timeIntervalSince1970 * 1000) + 1000 + i * 10_000
            return #"{"ts":\#(ms),"tool":"Bash","decision":"allowed","classifierModel":"rits/zai-org/glm-5-3[1m]","inputTokens":\#(400 + i),"outputTokens":23,"cacheReadInputTokens":34304,"cacheCreationInputTokens":0,"durationMs":1800,"costUSD":0,"stage":"fast","reason":"\#(String(repeating: "x", count: 300))"}"# + "\n"
        }
        var text = ""
        var lineCount = 0
        while text.utf8.count < 100 * 1024 {
            text += line(lineCount)
            lineCount += 1
        }
        var sessions: [UsageRecord] = []
        for i in 0..<50 {
            let dir = root.appendingPathComponent("W\(i)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let log = dir.appendingPathComponent(DecisionLogProbe.fileName)
            try Data(text.utf8).write(to: log)
            try FileManager.default.setAttributes([.modificationDate: isoDate("2026-11-12T18:00:00Z")], ofItemAtPath: log.path)
            for r in 0..<200 {
                sessions.append(UsageRecord(messageId: "m\(i)-\(r)", timestamp: sessionTime.addingTimeInterval(Double(r) * 9),
                                            model: "rits/zai-org/glm-5-3", canonicalModel: "rits/zai-org/glm-5-3",
                                            requestId: "gw_\(i)_\(r)", accountId: "acc", inputTokens: 1000 + r, outputTokens: 50,
                                            cacheWrite5mTokens: 0, cacheWrite1hTokens: 0, cacheReadTokens: 30_000, costUSD: nil,
                                            sessionKey: "s\(i)", cwd: dir.path))
            }
        }
        let index = ClassifierLogIndex()
        let probe = DecisionLogProbe()
        let pricer = try PriceTable.builtIn()

        let cold = SessionLogSource.classifierStep(sessionRecords: sessions, index: index, probe: probe, window: window, pricer: pricer)
        #expect(cold.indexStats.logsRead == 50)
        let rows = cold.attribution.records.count
        #expect(rows == 50 * lineCount)

        let clock = ContinuousClock()
        var runs: [Duration] = []
        var steady: SessionLogSource.ClassifierStepResult?
        for _ in 0..<5 {
            runs.append(clock.measure {
                steady = SessionLogSource.classifierStep(sessionRecords: sessions, index: index, probe: probe, window: window,
                                                         pricer: pricer)
            })
        }
        #expect(steady?.indexStats.bytesRead == 0)
        #expect(steady?.attribution.records.count == rows)
        #expect(steady?.attribution.assigned == rows)
        let median = runs.sorted()[2]
        #expect(median < .milliseconds(50), "steady-state classifier step took \(median) (runs \(runs))")
    }
}
