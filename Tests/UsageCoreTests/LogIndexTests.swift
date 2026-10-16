import Foundation
import Testing
@testable import UsageCore

extension FileHandle {
    /// Appends `data` and closes the handle.
    func withAppend(_ data: Data) throws {
        defer { try? close() }
        try seekToEnd()
        try write(contentsOf: data)
    }
}

@Suite struct LogIndexTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let parser = SessionRecordParser()
    let pricer = try! PriceTable.builtIn()

    private func vertexConfig() -> Configuration {
        var c = Configuration()
        c.accounts = [Account(id: "acc-vertex", displayName: "Vertex",
                              kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex)))]
        c.groups = [BudgetGroup(id: "grp", name: "Vertex", budgetUSD: 60)]
        return c
    }

    private func attributor() -> Attributor { Attributor(configuration: vertexConfig()) }

    private func writeRecords(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    private func record(id: String, at timestamp: String, output: Int = 10, cwd: String? = nil) -> String {
        let cwdField = cwd.map { #""cwd":"\#($0)","# } ?? ""
        return """
        {\(cwdField)"type":"assistant","timestamp":"\(timestamp)","requestId":"req_vrtx_\(id)","uuid":"\(id)","sessionId":"s","message":{"id":"msg_vrtx_\(id)","model":"claude-opus-4-6","role":"assistant","content":[],"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":\(output)}}}
        """
    }

    @Test func discoversSessionFilesIncludingSubagents() throws {
        let root = try makeTempDirectory("index-discover")
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.install("vertex-session.jsonl", into: root, as: "proj-a/s1.jsonl")
        try Fixtures.install("subagents/agent-x.jsonl", into: root, as: "proj-a/s1/subagents/agent-x.jsonl")
        try Data("not a log".utf8).write(to: root.appendingPathComponent("projects/proj-a/notes.txt"))

        let scan = LogDirectoryScanner().scan(directories: [root.path])
        #expect(scan.errors.isEmpty)
        #expect(scan.files.count == 2)
        #expect(scan.files.allSatisfy { $0.configDirectory == root.resolvingSymlinksInPath().path })

        let index = LogIndex()
        let stats = index.update(files: scan.files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(stats.filesSeen == 2)
        #expect(stats.filesRead == 2)
        #expect(index.records.count == 3)
        #expect(index.records.allSatisfy { $0.accountId == "acc-vertex" })
        #expect(index.records.allSatisfy { $0.costUSD != nil })
    }

    @Test func missingOrEmptyProjectsDirectoryIsNotAnError() throws {
        let root = try makeTempDirectory("index-empty")
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = LogDirectoryScanner().scan(directories: [root.path])
        #expect(missing.files.isEmpty)
        #expect(missing.errors.isEmpty)

        try FileManager.default.createDirectory(at: root.appendingPathComponent("projects"), withIntermediateDirectories: true)
        let empty = LogDirectoryScanner().scan(directories: [root.path])
        #expect(empty.files.isEmpty)
        #expect(empty.errors.isEmpty)
    }

    @Test func unreadableConfiguredDirectoryIsReportedButOthersAreScanned() throws {
        let root = try makeTempDirectory("index-unreadable")
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.install("vertex-session.jsonl", into: root, as: "p/s.jsonl")
        let missingDir = root.appendingPathComponent("does-not-exist").path
        let scan = LogDirectoryScanner().scan(directories: [missingDir, root.path])
        #expect(scan.errors.count == 1)
        #expect(scan.errors[0].contains("does-not-exist"))
        #expect(scan.files.count == 1)
        #expect(scan.scannedDirectories == 1)

        let none = LogDirectoryScanner().scan(directories: [missingDir])
        #expect(none.scannedDirectories == 0)
        #expect(none.errors.count == 1)
    }

    @Test func sourceThrowsOnlyWhenNoDirectoryCouldBeScanned() async throws {
        let root = try makeTempDirectory("source-throws")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(home: root)   // ~/.claude does not exist under this home
        let source = try SessionLogSource(paths: paths, builtInPrices: pricer)
        var config = vertexConfig()
        let context = { RefreshContext(configuration: config, window: self.window, now: Date()) }
        await #expect(throws: SessionLogSource.ScanFailure.self) {
            _ = try await source.collect(context: context())
        }

        // One extra directory that exists (even without a projects tree) is enough.
        let extra = root.appendingPathComponent("extra")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        config.logDirectories = [extra.path]
        let output = try await source.collect(context: context())
        if case .records(let records) = output {
            #expect(records.isEmpty)
        } else {
            Issue.record("expected records output")
        }
    }

    @Test func skipsFilesModifiedBeforeWindowStart() throws {
        let root = try makeTempDirectory("index-oldmtime")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try Fixtures.install("vertex-session.jsonl", into: root, as: "p/old.jsonl")
        try FileManager.default.setAttributes([.modificationDate: isoDate("2026-10-01T00:00:00Z")], ofItemAtPath: file.path)
        let scan = LogDirectoryScanner().scan(directories: [root.path])
        let index = LogIndex()
        let stats = index.update(files: scan.files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(stats.filesSeen == 1)
        #expect(stats.filesRead == 0)
        #expect(index.records.isEmpty)
    }

    @Test func rereadsOnlyAppendedBytes() throws {
        let root = try makeTempDirectory("index-append")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects/p/live.jsonl")
        try writeRecords([record(id: "1", at: "2026-10-12T10:00:00Z"), record(id: "2", at: "2026-10-12T10:01:00Z")], to: file)
        let index = LogIndex()
        let scanner = LogDirectoryScanner()

        let first = index.update(files: scanner.scan(directories: [root.path]).files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(first.filesRead == 1)
        #expect(index.records.count == 2)
        let offsetAfterFirst = index.entries.values.first?.parsedOffset ?? 0
        #expect(offsetAfterFirst > 0)

        let unchanged = index.update(files: scanner.scan(directories: [root.path]).files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(unchanged.filesRead == 0)

        // Append a third record plus a partial line, with a later mtime.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((record(id: "3", at: "2026-10-12T10:02:00Z") + "\n{\"type\":\"assistant\",\"partial").utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)

        let second = index.update(files: scanner.scan(directories: [root.path]).files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(second.filesRead == 1)
        #expect(second.bytesRead < offsetAfterFirst)
        #expect(index.records.count == 3)
        #expect(index.records.map(\.messageId).sorted() == ["msg_vrtx_1", "msg_vrtx_2", "msg_vrtx_3"])
        let entry = try #require(index.entries.values.first)
        #expect(entry.parsedOffset < entry.size)   // the partial line is not consumed
    }

    /// A tiny batch size splits the read into one batch per file and yields
    /// the same records and stats as a single batch (bounded peak memory for
    /// month-long collection windows, spec 003 SC-006).
    @Test func batchedReadMatchesSingleBatch() throws {
        let root = try makeTempDirectory("index-batches")
        defer { try? FileManager.default.removeItem(at: root) }
        for n in 1...5 {
            try writeRecords([record(id: "\(n)a", at: "2026-10-12T10:0\(n):00Z"), record(id: "\(n)b", at: "2026-10-13T10:0\(n):00Z")],
                             to: root.appendingPathComponent("projects/p/s\(n).jsonl"))
        }
        let files = LogDirectoryScanner().scan(directories: [root.path]).files
        #expect(files.count == 5)

        let single = LogIndex()
        let singleStats = single.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        let batched = LogIndex(batchBytes: 1)
        let batchedStats = batched.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)

        #expect(batchedStats == singleStats)
        #expect(batchedStats.filesRead == 5)
        #expect(batched.records.count == 10)
        #expect(batched.records == single.records)
        #expect(batched.entries == single.entries)
    }

    /// Batch boundaries: unread bytes (`size - offset`) add up to at most
    /// `maxBytes`, a larger file forms its own batch, and the count restarts
    /// at each boundary.
    @Test func batchesSplitJobsByUnreadBytes() {
        func job(_ size: Int, offset: Int = 0) -> LogIndex.ReadJob {
            LogIndex.ReadJob(file: ScannedFile(canonicalPath: "/f\(size)-\(offset)", configDirectory: "/c", size: size, modificationDate: Date()),
                             offset: offset, fresh: offset == 0)
        }
        func sizes(_ jobs: [LogIndex.ReadJob], max: Int) -> [[Int]] {
            LogIndex.batches(of: jobs, maxBytes: max).map { $0.map(\.file.size) }
        }
        #expect(sizes([job(30), job(30), job(30)], max: 64) == [[30, 30], [30]])
        #expect(sizes([job(100), job(10)], max: 64) == [[100], [10]])
        #expect(sizes([job(10), job(100), job(10)], max: 64) == [[10], [100], [10]])
        // Only the 5 appended bytes of an already indexed file count.
        #expect(sizes([job(60), job(100, offset: 96)], max: 64) == [[60, 100]])
        #expect(sizes([], max: 64) == [])
    }

    @Test func dedupesAcrossAppends() throws {
        let root = try makeTempDirectory("index-dedupe")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects/p/live.jsonl")
        try writeRecords([record(id: "1", at: "2026-10-12T10:00:00Z", output: 10)], to: file)
        let index = LogIndex()
        let scanner = LogDirectoryScanner()
        _ = index.update(files: scanner.scan(directories: [root.path]).files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(index.records.first?.outputTokens == 10)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((record(id: "1", at: "2026-10-12T10:00:01Z", output: 99) + "\n").utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        _ = index.update(files: scanner.scan(directories: [root.path]).files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(index.records.count == 1)
        #expect(index.records.first?.outputTokens == 99)
    }

    @Test func shrunkFileIsRereadFromStart() throws {
        let root = try makeTempDirectory("index-shrink")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects/p/live.jsonl")
        try writeRecords([record(id: "1", at: "2026-10-12T10:00:00Z"), record(id: "2", at: "2026-10-12T10:01:00Z")], to: file)
        let index = LogIndex()
        let scanner = LogDirectoryScanner()
        _ = index.update(files: scanner.scan(directories: [root.path]).files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(index.records.count == 2)

        try writeRecords([record(id: "9", at: "2026-10-12T10:05:00Z")], to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        let stats = index.update(files: scanner.scan(directories: [root.path]).files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(stats.filesRead == 1)
        #expect(index.records.map(\.messageId) == ["msg_vrtx_9"])
    }

    @Test func prunesRecordsBeforeWindowStartAndDropsOldEntries() throws {
        let root = try makeTempDirectory("index-prune")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects/p/live.jsonl")
        try writeRecords([record(id: "1", at: "2026-10-12T10:00:00Z"), record(id: "2", at: "2026-10-12T11:00:00Z")], to: file)
        let index = LogIndex()
        let files = LogDirectoryScanner().scan(directories: [root.path]).files
        _ = index.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(index.records.count == 2)

        let later = DateInterval(start: isoDate("2026-10-12T10:30:00Z"), end: isoDate("2026-10-19T10:30:00Z"))
        _ = index.update(files: files, window: later, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(index.records.map(\.messageId) == ["msg_vrtx_2"])

        // A window starting after the file's modification date drops the entry entirely.
        let future = DateInterval(start: Date().addingTimeInterval(3600), duration: 7 * 24 * 3600)
        _ = index.update(files: files, window: future, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(index.entries.isEmpty)
        #expect(index.records.isEmpty)
    }

    @Test func symlinkedTreeIsCountedOnce() throws {
        let rootA = try makeTempDirectory("index-link-a")
        let rootB = try makeTempDirectory("index-link-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        try Fixtures.install("vertex-session.jsonl", into: rootA, as: "p/s.jsonl")
        try FileManager.default.createSymbolicLink(at: rootB.appendingPathComponent("projects"),
                                                   withDestinationURL: rootA.appendingPathComponent("projects"))
        let scan = LogDirectoryScanner().scan(directories: [rootA.path, rootB.path])
        #expect(scan.errors.isEmpty)
        #expect(scan.files.count == 1)
        #expect(scan.files[0].configDirectory == rootA.resolvingSymlinksInPath().path)

        let reversed = LogDirectoryScanner().scan(directories: [rootB.path, rootA.path])
        #expect(reversed.files.count == 1)
        #expect(reversed.files[0].configDirectory == rootB.resolvingSymlinksInPath().path)
    }

    @Test func resetClearsEverything() throws {
        let root = try makeTempDirectory("index-reset")
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.install("vertex-session.jsonl", into: root, as: "p/s.jsonl")
        let index = LogIndex()
        let files = LogDirectoryScanner().scan(directories: [root.path]).files
        _ = index.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(!index.records.isEmpty)
        index.reset()
        #expect(index.entries.isEmpty)
        let again = index.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(again.filesRead == 1)
    }

    @Test func earlierWindowStartBetweenUpdatesRecoversPrunedRecords() throws {
        let root = try makeTempDirectory("index-earlier-window")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects/p/live.jsonl")
        try writeRecords([record(id: "1", at: "2026-10-12T10:00:00Z"), record(id: "2", at: "2026-10-12T11:00:00Z")], to: file)
        let index = LogIndex()
        let files = LogDirectoryScanner().scan(directories: [root.path]).files

        let late = DateInterval(start: isoDate("2026-10-12T10:30:00Z"), end: isoDate("2026-10-19T10:30:00Z"))
        _ = index.update(files: files, window: late, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(index.records.map(\.messageId) == ["msg_vrtx_2"])

        // The window start moves earlier on a later refresh (fallback weekday
        // or alignment account changed) while the file is unchanged.
        let stats = index.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(stats.filesRead == 1)
        #expect(index.records.map(\.messageId) == ["msg_vrtx_1", "msg_vrtx_2"])

        // Same window again: nothing is re-read.
        let again = index.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(again.filesRead == 0)
        #expect(index.records.count == 2)
    }

    @Test func attributionRuleChangeRereadsUnchangedFiles() throws {
        let root = try makeTempDirectory("index-attribution-change")
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.install("custom-marker.jsonl", into: root, as: "p/s.jsonl")
        let index = LogIndex()
        let files = LogDirectoryScanner().scan(directories: [root.path]).files
        _ = index.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(index.records.count == 2)
        #expect(index.records.allSatisfy { $0.accountId == "acc-vertex" })

        // An identical rule set does not trigger a re-read.
        let same = index.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(same.filesRead == 0)

        // A new account with a custom marker takes the EU record away from the
        // Vertex account although the file did not change (FR-013).
        var config = vertexConfig()
        config.accounts.append(Account(id: "acc-eu", displayName: "Vertex EU",
                                       kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex)),
                                       customMarker: "\"inference_geo\":\"eu\""))
        let stats = index.update(files: files, window: window, parser: parser, attributor: Attributor(configuration: config), pricer: pricer)
        #expect(stats.filesRead == 1)
        #expect(index.records.first { $0.messageId == "msg_vrtx_E1" }?.accountId == "acc-eu")
        #expect(index.records.first { $0.messageId == "msg_vrtx_E2" }?.accountId == "acc-vertex")
    }

    @Test func partialLastLineIsParsedOnceCompleted() throws {
        let root = try makeTempDirectory("index-partial-complete")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects/p/live.jsonl")
        let third = record(id: "3", at: "2026-10-12T10:02:00Z")
        let cut = third.index(third.startIndex, offsetBy: third.count / 2)
        let head = String(third[..<cut])
        let tail = String(third[cut...])
        try writeRecords([record(id: "1", at: "2026-10-12T10:00:00Z"), record(id: "2", at: "2026-10-12T10:01:00Z")], to: file)
        try FileHandle(forWritingTo: file).withAppend(Data(head.utf8))
        let index = LogIndex()
        let scanner = LogDirectoryScanner()

        _ = index.update(files: scanner.scan(directories: [root.path]).files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(index.records.count == 2)
        var entry = try #require(index.entries.values.first)
        #expect(entry.parsedOffset < entry.size)

        // The writer completes the line: the record is picked up from the rewound offset.
        try FileHandle(forWritingTo: file).withAppend(Data((tail + "\n").utf8))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        let completed = index.update(files: scanner.scan(directories: [root.path]).files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(completed.filesRead == 1)
        #expect(index.records.map(\.messageId).sorted() == ["msg_vrtx_1", "msg_vrtx_2", "msg_vrtx_3"])
        entry = try #require(index.entries.values.first)
        #expect(entry.parsedOffset == entry.size)
        let offsetAfterComplete = entry.parsedOffset

        // A newline-free fragment is read but not consumed.
        let fragment = Data("{\"type\":\"assistant\",\"partial".utf8)
        try FileHandle(forWritingTo: file).withAppend(fragment)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: file.path)
        let fragmentStats = index.update(files: scanner.scan(directories: [root.path]).files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(fragmentStats.filesRead == 1)
        #expect(fragmentStats.bytesRead == fragment.count)
        #expect(index.records.count == 3)
        entry = try #require(index.entries.values.first)
        #expect(entry.parsedOffset == offsetAfterComplete)
        #expect(entry.size == offsetAfterComplete + fragment.count)
    }

    @Test func sourceScansDefaultAndConfiguredDirectoriesAndBreaksTiesByDirectory() async throws {
        let root = try makeTempDirectory("source-directories")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent(".claude")
        let work = root.appendingPathComponent("work")
        let now = Date()
        for (dir, name) in [(home, "a.jsonl"), (work, "b.jsonl")] {
            let installed = try Fixtures.install("direct-session.jsonl", into: dir, as: "p/\(name)")
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: installed.path)
        }
        let paths = Paths(home: root)
        let logURL = root.appendingPathComponent("usage.log")
        let source = try SessionLogSource(paths: paths, log: DiagnosticLog(fileURL: logURL), builtInPrices: pricer)

        var config = Configuration()
        config.accounts = [
            Account(id: "acc-max", displayName: "Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: []))),
            Account(id: "acc-work", displayName: "Work",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: work.path, shownInBar: true, thresholds: []))),
        ]
        config.logDirectories = ["~/.claude", work.path]   // the default directory is listed twice and scanned once
        try config.validate()
        #expect(source.directories(for: config) == [home.path, work.path])

        let window = DateInterval(start: isoDate("2026-10-11T00:00:00Z"), end: isoDate("2026-10-18T00:00:00Z"))
        let output = try await source.collect(context: RefreshContext(configuration: config, window: window, now: now))
        guard case .records(let records) = output else {
            Issue.record("expected records output")
            return
        }
        #expect(records.count == 4)
        #expect(records.filter { $0.accountId == "acc-max" }.count == 2)
        #expect(records.filter { $0.accountId == "acc-work" }.count == 2)
        let logText = try String(contentsOf: logURL, encoding: .utf8)
        #expect(logText.contains("files seen 2, re-read 2"))
        #expect(logText.contains("records since collection start 4"))
    }

    @Test func recordsKeepTheirProjectAcrossIncrementalUpdates() throws {
        let root = try makeTempDirectory("index-project")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let file = root.appendingPathComponent("projects/p/s.jsonl")
        try writeRecords([record(id: "a", at: "2026-10-12T10:00:00Z", cwd: repo.path)], to: file)

        let index = LogIndex()
        _ = index.update(files: LogDirectoryScanner().scan(directories: [root.path]).files, window: window,
                         parser: parser, attributor: attributor(), pricer: pricer)
        try FileHandle(forWritingTo: file).withAppend(Data((record(id: "b", at: "2026-10-12T11:00:00Z", cwd: repo.path + "/sub") + "\n").utf8))
        _ = index.update(files: LogDirectoryScanner().scan(directories: [root.path]).files, window: window,
                         parser: parser, attributor: attributor(), pricer: pricer)

        let expected = Project(rootPath: (repo.path as NSString).standardizingPath)
        #expect(index.records.count == 2)
        #expect(index.records.allSatisfy { $0.project == expected })
    }

    @Test func sourceLogsProjectFallbacksAsOneSummaryLine() async throws {
        let root = try makeTempDirectory("source-project-notes")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(".claude/projects/p/s.jsonl")
        let lines = (1...7).map { record(id: "n\($0)", at: "2026-10-12T10:0\($0):00Z", cwd: "/nonexistent/scratch-\($0)") }
        try writeRecords(lines, to: file)
        try FileManager.default.setAttributes([.modificationDate: isoDate("2026-10-12T12:00:00Z")], ofItemAtPath: file.path)
        let logURL = root.appendingPathComponent("usage.log")
        let source = try SessionLogSource(paths: Paths(home: root), log: DiagnosticLog(fileURL: logURL), builtInPrices: pricer)

        _ = try await source.collect(context: RefreshContext(configuration: Configuration(), window: window, now: isoDate("2026-10-12T12:00:00Z")))

        let logLines = try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n")
        let fallback = logLines.filter { $0.contains("project fallback") }
        #expect(fallback.count == 1)
        #expect(fallback.first?.contains("7 working directories") == true)
        #expect(fallback.first?.contains("/nonexistent/scratch-1: directory not found") == true)
        #expect(fallback.first?.contains("and 2 more") == true)
    }

    @Test func repricesWhenPriceTableChanges() throws {
        let root = try makeTempDirectory("index-reprice")
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.install("unknown-model.jsonl", into: root, as: "p/s.jsonl")
        let index = LogIndex()
        let files = LogDirectoryScanner().scan(directories: [root.path]).files
        _ = index.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(index.records.first { $0.model == "claude-mystery-9" }?.costUSD == nil)

        let added = PriceEntry(model: "claude-mystery-9", inputPerMTok: 1, outputPerMTok: 1, cacheWrite5mPerMTok: 1, cacheWrite1hPerMTok: 1, cacheReadPerMTok: 1)
        let stats = index.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer.merging(overrides: [added]))
        #expect(stats.filesRead == 0)
        #expect(index.records.first { $0.model == "claude-mystery-9" }?.costUSD == Decimal(string: "0.003"))
    }
    @Test func sourceRepricesWithImportedPricesWithoutRereading() async throws {
        let root = try makeTempDirectory("source-imported")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent(".claude")
        let installed = try Fixtures.install("unknown-model.jsonl", into: home, as: "p/s.jsonl")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: installed.path)
        let store = ImportedPriceStore(fileURL: root.appendingPathComponent("imported-prices.json"))
        let logURL = root.appendingPathComponent("usage.log")
        let source = try SessionLogSource(paths: Paths(home: root), log: DiagnosticLog(fileURL: logURL), builtInPrices: pricer,
                                          importedPrices: store)
        let context = RefreshContext(configuration: Configuration(), window: window, now: Date())

        guard case .records(let first) = try await source.collect(context: context) else {
            Issue.record("expected records output")
            return
        }
        #expect(first.first { $0.model == "claude-mystery-9" }?.costUSD == nil)

        let batch = makeBatch(.csv, [PriceEntry(model: "claude-mystery-9", inputPerMTok: 1, outputPerMTok: 1, cacheWrite5mPerMTok: 1,
                                                cacheWrite1hPerMTok: 1, cacheReadPerMTok: 1)])
        try store.save(store.current.replacing(batch))
        guard case .records(let second) = try await source.collect(context: context) else {
            Issue.record("expected records output")
            return
        }
        #expect(second.first { $0.model == "claude-mystery-9" }?.costUSD == Decimal(string: "0.003"))
        let logText = try String(contentsOf: logURL, encoding: .utf8)
        #expect(logText.contains("files seen 1, re-read 0"))
    }
}

/// Spec 015 FR-006, FR-007, SC-003, research R3: the credential directory of
/// every Claude subscription account is scanned without being listed again.
extension LogIndexTests {
    /// `root/.claude` (the default, via `Paths(home: root)`) and `root/work`,
    /// each with one session file of two records.
    private func credentialFixture(_ name: String) throws -> (root: URL, home: URL, work: URL) {
        let root = try makeTempDirectory(name)
        let home = root.appendingPathComponent(".claude")
        let work = root.appendingPathComponent("work")
        let now = Date()
        for (dir, file) in [(home, "a.jsonl"), (work, "b.jsonl")] {
            let installed = try Fixtures.install("direct-session.jsonl", into: dir, as: "p/\(file)")
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: installed.path)
        }
        return (root, home, work)
    }

    private func credentialConfig(work: String, extra: [String] = [], more: [Account] = []) -> Configuration {
        var config = Configuration()
        config.accounts = [
            Account(id: "acc-max", displayName: "Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: []))),
            Account(id: "acc-work", displayName: "Work",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: work, shownInBar: true, thresholds: []))),
        ] + more
        config.logDirectories = extra
        return config
    }

    private func collectRecords(root: URL, config: Configuration) async throws -> [UsageRecord] {
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        let window = DateInterval(start: isoDate("2026-10-11T00:00:00Z"), end: isoDate("2026-10-18T00:00:00Z"))
        guard case .records(let records) = try await source.collect(context: RefreshContext(configuration: config, window: window, now: Date())) else {
            Issue.record("expected records output")
            return []
        }
        return records
    }

    @Test func credentialDirectoryIsScannedWithoutBeingListed() async throws {
        let (root, home, work) = try credentialFixture("credential-only")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = credentialConfig(work: work.path)
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config) == [home.path, work.path])

        // Attributed by the directory tie-breaker (spec 001 FR-013).
        let records = try await collectRecords(root: root, config: config)
        #expect(records.count == 4)
        #expect(records.filter { $0.accountId == "acc-max" }.count == 2)
        #expect(records.filter { $0.accountId == "acc-work" }.count == 2)
    }

    @Test func directoryNamedInBothSettingsAppearsOnce() throws {
        let (root, home, work) = try credentialFixture("credential-both")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: credentialConfig(work: work.path, extra: [work.path])) == [home.path, work.path])
        // The default directory as credential directory is scanned once.
        var defaultOnly = credentialConfig(work: work.path)
        defaultOnly.accounts.removeAll { $0.id == "acc-work" }
        #expect(source.directories(for: defaultOnly) == [home.path])
    }

    @Test func symlinkAndDotDotSpellingsOfAListedDirectoryAppearOnce() throws {
        let (root, home, work) = try credentialFixture("credential-spellings")
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: work)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let dotted = root.path + "/sub/../work/"
        let third = Account(id: "acc-third", displayName: "Third",
                            kind: .subscription(SubscriptionSettings(credentialDirectory: dotted, shownInBar: true, thresholds: [])))
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: credentialConfig(work: link.path, extra: [work.path], more: [third])) == [home.path, work.path])
        // Listed first under its symlink spelling, the symlink spelling is returned.
        #expect(source.directories(for: credentialConfig(work: work.path, extra: [link.path])) == [home.path, link.path])
    }

    /// FR-007: a missing credential directory is skipped silently.
    @Test func missingCredentialDirectoryIsSkipped() async throws {
        let (root, home, _) = try credentialFixture("credential-missing")
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing").path
        let config = credentialConfig(work: missing)
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config) == [home.path, missing])
        let records = try await collectRecords(root: root, config: config)
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.accountId == "acc-max" })
    }

    /// SC-003: the same totals whether the directory is a credential
    /// directory only or also an extra directory.
    @Test func totalsMatchWithAndWithoutTheExtraDirectory() async throws {
        let (root, _, work) = try credentialFixture("credential-totals")
        defer { try? FileManager.default.removeItem(at: root) }
        let only = try await collectRecords(root: root, config: credentialConfig(work: work.path))
        let both = try await collectRecords(root: root, config: credentialConfig(work: work.path, extra: [work.path]))
        func summary(_ records: [UsageRecord]) -> [String] {
            records.map { "\($0.accountId ?? "-") \($0.inputTokens) \($0.outputTokens)" }.sorted()
        }
        #expect(only.count == 4)
        #expect(summary(only) == summary(both))
    }
}
