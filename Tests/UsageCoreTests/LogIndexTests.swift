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

    /// A Claude subscription with an empty directory, so `~/.claude` is
    /// read (spec 034 FR-008: only the accounts' directories are read).
    var onDefaultDirectory: Configuration {
        Configuration(accounts: [Account(id: "acc-max", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: "")))])
    }

    /// A Vertex account of group `grp` whose Claude Code directory is
    /// `directory` (spec 034 FR-007).
    func vertexAccount(_ id: String, directory: String?) -> Account {
        Account(id: id, displayName: id,
                kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: .vertex,
                                                     sessionDirectory: directory)))
    }

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

        // One account directory that exists (even without a projects tree)
        // is enough (spec 034 FR-008).
        let extra = root.appendingPathComponent("extra")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        config.accounts = [vertexAccount("acc-vertex", directory: extra.path)]
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
        // Vertex accounts naming the default directory and `work` again: each
        // directory is scanned once (spec 034 FR-008).
        config.accounts += [vertexAccount("acc-v1", directory: "~/.claude"), vertexAccount("acc-v2", directory: work.path)]
        config.groups = [BudgetGroup(id: "grp", name: "Vertex", budgetUSD: 60)]
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

        _ = try await source.collect(context: RefreshContext(configuration: onDefaultDirectory, window: window, now: isoDate("2026-10-12T12:00:00Z")))

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
        let context = RefreshContext(configuration: onDefaultDirectory, window: window, now: Date())

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

    private func credentialConfig(work: String, more: [Account] = []) -> Configuration {
        var config = Configuration()
        config.accounts = [
            Account(id: "acc-max", displayName: "Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: []))),
            Account(id: "acc-work", displayName: "Work",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: work, shownInBar: true, thresholds: []))),
        ] + more
        config.groups = [BudgetGroup(id: "grp", name: "Vertex", budgetUSD: 60)]
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
        let vertex = vertexAccount("acc-vertex", directory: work.path)
        #expect(source.directories(for: credentialConfig(work: work.path, more: [vertex])) == [home.path, work.path])
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
        let viaLink = vertexAccount("acc-vertex", directory: link.path)
        #expect(source.directories(for: credentialConfig(work: work.path, more: [viaLink, third])) == [home.path, work.path])
        // Listed first under its symlink spelling, the symlink spelling is returned.
        let direct = vertexAccount("acc-vertex", directory: work.path)
        #expect(source.directories(for: credentialConfig(work: link.path, more: [direct])) == [home.path, link.path])
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

    /// Spec 015 SC-003: the same totals whether the directory belongs to one
    /// account or to two (spec 034 FR-008).
    @Test func totalsMatchWithAndWithoutTheExtraDirectory() async throws {
        let (root, _, work) = try credentialFixture("credential-totals")
        defer { try? FileManager.default.removeItem(at: root) }
        let only = try await collectRecords(root: root, config: credentialConfig(work: work.path))
        let both = try await collectRecords(root: root, config: credentialConfig(work: work.path,
                                                                                 more: [vertexAccount("acc-vertex", directory: work.path)]))
        func summary(_ records: [UsageRecord]) -> [String] {
            records.map { "\($0.accountId ?? "-") \($0.inputTokens) \($0.outputTokens)" }.sorted()
        }
        #expect(only.count == 4)
        #expect(summary(only) == summary(both))
    }
}

extension LogIndexTests {
    /// The refresh log line shows byte counts above 2^31 as they are; a
    /// 32-bit format specifier once printed them as negative numbers.
    @Test func statsLineShowsLargeByteCounts() {
        var stats = LogIndexStats()
        stats.filesSeen = 10366
        stats.filesRead = 1479
        stats.bytesRead = 2_191_659_065
        stats.recordsInWindow = 56091
        #expect(SessionLogSource.statsLine(stats, directories: 3, elapsed: 5.282)
            == "directories read 3, files seen 10366, re-read 1479 (2191659065 bytes), records since collection start 56091, 5.282 s")
    }
}

/// Spec 034 FR-008, FR-009, SC-003 and edge cases: the Claude Code
/// directory of a Vertex account is read for its sessions, like the
/// directory of a Claude subscription.
extension LogIndexTests {
    private func accountRecords(root: URL, config: Configuration) async throws -> [UsageRecord] {
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        let window = DateInterval(start: isoDate("2026-10-11T00:00:00Z"), end: isoDate("2026-10-18T00:00:00Z"))
        guard case .records(let records) = try await source.collect(context: RefreshContext(configuration: config, window: window, now: Date())) else {
            Issue.record("expected records output")
            return []
        }
        return records
    }

    private func install(_ fixture: String, into dir: URL, as name: String) throws {
        let installed = try Fixtures.install(fixture, into: dir, as: "p/\(name)")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: installed.path)
    }

    private func vertexOnly(_ directory: String?) -> Configuration {
        var config = Configuration()
        config.accounts = [vertexAccount("acc-acme", directory: directory)]
        config.groups = [BudgetGroup(id: "grp", name: "Vertex", budgetUSD: 60)]
        return config
    }

    private func summary(_ records: [UsageRecord]) -> [String] {
        records.map { "\($0.accountId ?? "-") \($0.model) \($0.inputTokens) \($0.outputTokens) \($0.costUSD.map { "\($0)" } ?? "-")" }.sorted()
    }

    /// SC-003: Vertex sessions in `~/profiles/acme/claude` count for the
    /// Vertex account with the same totals as the same sessions in
    /// `~/.claude`.
    @Test func vertexAccountDirectoryCountsWithTheSameTotals() async throws {
        let root = try makeTempDirectory("vertex-account-dir")
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = root.appendingPathComponent("profiles/acme/claude")
        try install("vertex-session.jsonl", into: profile, as: "s.jsonl")
        // An empty `~/.claude`, read for the account without a directory.
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let config = vertexOnly("~/profiles/acme/claude")
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config) == [profile.path])
        let fromAccount = try await accountRecords(root: root, config: config)
        #expect(!fromAccount.isEmpty)
        #expect(fromAccount.allSatisfy { $0.accountId == "acc-acme" })

        // Without the directory the sessions are not read.
        #expect(try await accountRecords(root: root, config: vertexOnly(nil)).isEmpty)

        // The same file in the default directory gives the same totals.
        let other = try makeTempDirectory("vertex-default-dir")
        defer { try? FileManager.default.removeItem(at: other) }
        try install("vertex-session.jsonl", into: other.appendingPathComponent(".claude"), as: "s.jsonl")
        let fromDefault = try await accountRecords(root: other, config: vertexOnly(nil))
        #expect(summary(fromAccount) == summary(fromDefault))
    }

    /// A field that holds the home directory or `/`, for example while `~/`
    /// is being typed, adds no directory, so no refresh walks `~/projects`.
    @Test func homeAndRootAreNeverAClaudeCodeDirectory() throws {
        let root = try makeTempDirectory("vertex-home-guard")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        for entry in ["~", "~/", root.path + "/", "/"] {
            #expect(source.directories(for: vertexOnly(entry)).isEmpty)
        }
        var config = vertexOnly("~/profiles/acme/claude")
        config.accounts.append(Account(id: "acc-max", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: "~"))))
        #expect(source.directories(for: config) == [root.appendingPathComponent("profiles/acme/claude").path])
    }

    /// `~/.claude` named by an account, also as an absolute spelling with a
    /// trailing slash, is scanned once, as the default.
    @Test func defaultDirectoryNamedByAccountsIsScannedOnce() throws {
        let root = try makeTempDirectory("vertex-default-spellings")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var config = vertexOnly("~/.claude")
        config.accounts.append(vertexAccount("acc-second", directory: home.path + "/"))
        config.accounts.append(Account(id: "acc-max", displayName: "Max",
                                       kind: .subscription(SubscriptionSettings(credentialDirectory: home.path + "/"))))
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config) == [home.path])
    }

    /// FR-006a: a blank subscription directory reads `~/.claude`, once.
    @Test func blankSubscriptionDirectoryReadsTheDefaultOnce() async throws {
        let (root, home, work) = try credentialFixture("credential-blank")
        defer { try? FileManager.default.removeItem(at: root) }
        var config = credentialConfig(work: work.path)
        config.accounts[0].kind = .subscription(SubscriptionSettings(credentialDirectory: "  "))
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config) == [home.path, work.path])
        // The blank account still wins the tie-breaker for `~/.claude`.
        let records = try await accountRecords(root: root, config: config)
        #expect(records.filter { $0.accountId == "acc-max" }.count == 2)
        #expect(records.filter { $0.accountId == "acc-work" }.count == 2)
    }

    /// Two accounts with one directory: read once, attribution decides per
    /// session (FR-009).
    @Test func sharedDirectoryIsReadOnceAndAttributedPerSession() async throws {
        let (root, home, work) = try credentialFixture("credential-shared")
        defer { try? FileManager.default.removeItem(at: root) }
        try install("vertex-session.jsonl", into: work, as: "v.jsonl")
        let config = credentialConfig(work: work.path, more: [vertexAccount("acc-acme", directory: work.path)])
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config) == [home.path, work.path])
        let records = try await accountRecords(root: root, config: config)
        #expect(records.filter { $0.accountId == "acc-work" }.count == 2)
        #expect(records.filter { $0.accountId == "acc-max" }.count == 2)
        #expect(records.contains { $0.accountId == "acc-acme" })
        #expect(records.allSatisfy { $0.accountId != nil })
    }

    /// A Vertex directory that does not exist reads nothing and adds no
    /// source error.
    @Test func missingVertexDirectoryIsSkipped() async throws {
        let (root, _, work) = try credentialFixture("vertex-missing")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = credentialConfig(work: work.path,
                                      more: [vertexAccount("acc-acme", directory: root.appendingPathComponent("gone").path)])
        let records = try await accountRecords(root: root, config: config)
        #expect(records.count == 4)
        #expect(!records.contains { $0.accountId == "acc-acme" })
    }

    /// Removing the account stops reading its directory.
    @Test func removedAccountsDirectoryIsNoLongerRead() throws {
        let root = try makeTempDirectory("vertex-removed")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = vertexOnly("~/profiles/acme/claude")
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config).count == 1)
        #expect(source.directories(for: config.removingAccount(id: "acc-acme")).isEmpty)
    }
}

/// Spec 034 FR-008 (walkthrough 2026-10-22): only the directories the
/// accounts name are read; an empty field means `~/.claude`, and without a
/// Claude account no Claude Code session is read.
extension LogIndexTests {
    private func subscription(_ id: String, _ directory: String) -> Account {
        Account(id: id, displayName: id, kind: .subscription(SubscriptionSettings(credentialDirectory: directory)))
    }

    private func claudeConfig(_ accounts: [Account]) -> Configuration {
        Configuration(accounts: accounts, groups: [BudgetGroup(id: "grp", name: "Vertex", budgetUSD: 60)])
    }

    /// A home with a session in `~/.claude` and one in each invented profile.
    private func profilesFixture(_ name: String) throws -> URL {
        let root = try makeTempDirectory(name)
        for dir in [".claude", "profiles/personal/claude", "profiles/acme/claude"] {
            try install("direct-session.jsonl", into: root.appendingPathComponent(dir), as: "s.jsonl")
        }
        return root
    }

    @Test func accountsWithOwnDirectoriesDoNotReadTheDefault() async throws {
        let root = try profilesFixture("accounts-own-dirs")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = claudeConfig([subscription("acc-max", "~/profiles/personal/claude"),
                                   vertexAccount("acc-acme", directory: "~/profiles/acme/claude")])
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config)
                == ["profiles/personal/claude", "profiles/acme/claude"].map { root.appendingPathComponent($0).path })
        let records = try await accountRecords(root: root, config: config)
        #expect(records.count == 4)
        #expect(records.allSatisfy { $0.accountId != nil })
    }

    @Test func emptySubscriptionFieldReadsTheDefault() throws {
        let root = try makeTempDirectory("accounts-empty-subscription")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        let config = claudeConfig([subscription("acc-max", ""), vertexAccount("acc-acme", directory: "~/profiles/acme/claude")])
        #expect(source.directories(for: config)
                == [".claude", "profiles/acme/claude"].map { root.appendingPathComponent($0).path })
    }

    @Test func emptyVertexFieldReadsTheDefault() async throws {
        let root = try profilesFixture("accounts-empty-vertex")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        for entry in [nil, "", "  "] as [String?] {
            #expect(source.directories(for: vertexOnly(entry)) == [root.appendingPathComponent(".claude").path])
        }
        #expect(try await accountRecords(root: root, config: vertexOnly(nil)).count == 2)
    }

    @Test func noClaudeAccountReadsNoClaudeSessions() async throws {
        let root = try profilesFixture("accounts-none")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        let codexOnly = Configuration(accounts: [
            Account(id: "acc-plus", displayName: "Plus", harness: .codex, kind: .codexSubscription(CodexSubscriptionSettings(codexHome: ""))),
            Account(id: "acc-oai", displayName: "OpenAI", harness: .codex,
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), provider: .openai))),
        ])
        for config in [Configuration(), codexOnly] {
            #expect(source.directories(for: config).isEmpty)
            #expect(try await accountRecords(root: root, config: config).isEmpty)
        }
    }

    @Test func directoryNamedByTwoAccountsIsReadOnce() async throws {
        let root = try profilesFixture("accounts-duplicates")
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = root.appendingPathComponent("profiles/acme/claude")
        let config = claudeConfig([vertexAccount("acc-acme", directory: "~/profiles/acme/claude"),
                                   vertexAccount("acc-acme-2", directory: profile.path + "/"),
                                   subscription("acc-max", "~/profiles/acme/../acme/claude")])
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config) == [profile.path])
        #expect(try await accountRecords(root: root, config: config).count == 2)
    }
}

/// spec 035 FR-008, FR-012, research R6: main and additional scan targets.
extension LogIndexTests {
    @Test func additionalTargetsOnlyAddNotes() throws {
        let root = try makeTempDirectory("scan-targets")
        let locked = root.appendingPathComponent("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }
        let main = root.appendingPathComponent("main")
        let lab = root.appendingPathComponent("lab")
        try Fixtures.install("vertex-session.jsonl", into: main, as: "p/s.jsonl")
        try Fixtures.install("subagents/agent-x.jsonl", into: lab, as: "p/x.jsonl")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let missing = root.appendingPathComponent("missing").path

        let scan = LogDirectoryScanner().scan(targets: [
            ScanTarget(path: main.path, isMain: true), ScanTarget(path: lab.path, isMain: false),
            ScanTarget(path: missing, isMain: false), ScanTarget(path: locked.path, isMain: false),
        ])
        #expect(scan.errors.isEmpty)
        #expect(scan.additionalNotes == ["\(missing): skipped, not found", "\(locked.path): error: not readable"])
        #expect(scan.scannedDirectories == 2)
        #expect(scan.files.count == 2)
        #expect(scan.files.map(\.configDirectory).sorted() == [main, lab].map { Attributor.canonical($0.path) }.sorted())

        // Nothing readable but additional targets: no error either.
        let none = LogDirectoryScanner().scan(targets: [ScanTarget(path: missing, isMain: false)])
        #expect(none.scannedDirectories == 0)
        #expect(none.errors.isEmpty)
        // A missing main target keeps its error.
        let mainMissing = LogDirectoryScanner().scan(targets: [ScanTarget(path: missing, isMain: true)])
        #expect(mainMissing.errors == ["log directory not found: \(missing)"])
        #expect(mainMissing.additionalNotes.isEmpty)
    }

    /// A file reached through a main and an additional target is found in
    /// the main one, whichever spelling the additional target uses.
    @Test func fileReachedTwiceIsFoundInTheMainTarget() throws {
        let root = try makeTempDirectory("scan-targets-twice")
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("main")
        try Fixtures.install("vertex-session.jsonl", into: main, as: "p/s.jsonl")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: main)
        let scan = LogDirectoryScanner().scan(targets: [ScanTarget(path: main.path, isMain: true), ScanTarget(path: link.path, isMain: false)])
        #expect(scan.files.count == 1)
        #expect(scan.files.first?.configDirectory == Attributor.canonical(main.path))
        // The existing entry point treats every directory as a main target.
        let plain = LogDirectoryScanner().scan(directories: [root.appendingPathComponent("gone").path])
        #expect(plain.errors.count == 1)
    }
}

/// spec 035 FR-008, FR-009, US1 scenarios 4 and 6, SC-001, SC-003: literal
/// additional session directories of Claude subscription and Vertex
/// accounts.
extension LogIndexTests {
    private func extraSubscription(_ id: String, _ dir: String, extra: [String]) -> Account {
        Account(id: id, displayName: id, kind: .subscription(SubscriptionSettings(credentialDirectory: dir, additionalSessionDirectories: extra)))
    }

    private func extraVertex(_ id: String, _ dir: String?, extra: [String]) -> Account {
        Account(id: id, displayName: id,
                kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: .vertex,
                                                     sessionDirectory: dir, additionalSessionDirectories: extra)))
    }

    private func groupConfig(_ accounts: [Account]) -> Configuration {
        Configuration(accounts: accounts, groups: [BudgetGroup(id: "grp", name: "Vertex", budgetUSD: 60)])
    }

    private func logged(_ root: URL, _ config: Configuration) async throws -> (records: [UsageRecord], log: String) {
        let logURL = root.appendingPathComponent("usage-\(UUID().uuidString).log")
        let source = try SessionLogSource(paths: Paths(home: root), log: DiagnosticLog(fileURL: logURL), builtInPrices: pricer)
        let window = DateInterval(start: isoDate("2026-10-11T00:00:00Z"), end: isoDate("2026-10-18T00:00:00Z"))
        guard case .records(let records) = try await source.collect(context: RefreshContext(configuration: config, window: window, now: Date())) else {
            Issue.record("expected records output")
            return ([], "")
        }
        return (records, (try? String(contentsOf: logURL, encoding: .utf8)) ?? "")
    }

    /// SC-001: a Claude subscription's sessions in an additional directory
    /// count with the same totals as in its main directory.
    @Test func subscriptionAdditionalDirectoryCountsWithTheSameTotals() async throws {
        let root = try makeTempDirectory("additional-subscription")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try install("direct-session.jsonl", into: root.appendingPathComponent(".claude-lab"), as: "s.jsonl")
        let config = groupConfig([extraSubscription("acc-max", "~/.claude", extra: ["~/.claude-lab"])])
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config) == [".claude", ".claude-lab"].map { root.appendingPathComponent($0).path })
        let fromExtra = try await accountRecords(root: root, config: config)
        #expect(fromExtra.count == 2)
        #expect(fromExtra.allSatisfy { $0.accountId == "acc-max" })
        let fromMain = try await accountRecords(root: root, config: groupConfig([extraSubscription("acc-max", "~/.claude-lab", extra: [])]))
        #expect(summary(fromExtra) == summary(fromMain))
        // Without the entry the directory is not read.
        #expect(try await accountRecords(root: root, config: groupConfig([extraSubscription("acc-max", "~/.claude", extra: [])])).isEmpty)
    }

    /// SC-001: a Vertex account with an empty main directory reads
    /// `~/.claude` plus its additional directories, with the same totals.
    @Test func vertexAdditionalDirectoryCountsWithTheSameTotals() async throws {
        let root = try makeTempDirectory("additional-vertex")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try install("vertex-session.jsonl", into: root.appendingPathComponent("agent-sessions/acme"), as: "b.jsonl")
        let config = groupConfig([extraVertex("acc-acme", nil, extra: ["~/agent-sessions/acme"])])
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config) == [".claude", "agent-sessions/acme"].map { root.appendingPathComponent($0).path })
        let records = try await accountRecords(root: root, config: config)
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0.accountId == "acc-acme" })
        // The same file as the account's main directory gives the same totals.
        let asMain = try await accountRecords(root: root, config: groupConfig([extraVertex("acc-acme", "~/agent-sessions/acme", extra: [])]))
        #expect(summary(records) == summary(asMain))
        #expect(try await accountRecords(root: root, config: groupConfig([extraVertex("acc-acme", nil, extra: [])])).isEmpty)
    }

    /// SC-003 and the edge case "An additional directory equal to the
    /// account's main directory": read once.
    @Test func directoryNamedAsMainAndEntryCountsOnce() async throws {
        let (root, home, work) = try credentialFixture("additional-once")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = groupConfig([extraSubscription("acc-max", "~/.claude", extra: ["~/.claude", work.path + "/"]),
                                  extraSubscription("acc-work", work.path, extra: [home.path])])
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        #expect(source.directories(for: config) == [home.path, work.path])
        let records = try await accountRecords(root: root, config: config)
        #expect(records.count == 4)
        // Main beats additional in the tie-breaker (spec 035 FR-012).
        #expect(records.filter { $0.accountId == "acc-max" }.count == 2)
        #expect(records.filter { $0.accountId == "acc-work" }.count == 2)
    }

    /// FR-008: a missing or unreadable additional directory is logged only.
    @Test func missingOrUnreadableAdditionalDirectoryIsOnlyLogged() async throws {
        let (root, _, work) = try credentialFixture("additional-missing")
        let locked = root.appendingPathComponent("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let missing = root.appendingPathComponent("gone").path
        let config = groupConfig([extraSubscription("acc-max", "~/.claude", extra: [missing, "~/locked"]),
                                  extraSubscription("acc-work", work.path, extra: [])])
        let (records, log) = try await logged(root, config)
        #expect(records.count == 4)
        #expect(log.contains("[sessionLogs] \(missing): skipped, not found"))
        #expect(log.contains("[sessionLogs] \(locked.path): error: not readable"))
        #expect(!log.contains("scanner errors"))
    }

    /// FR-008: the source fails only when nothing at all could be scanned
    /// and a main directory reported the error.
    @Test func sourceFailsOnlyWhenNothingCouldBeScanned() async throws {
        let root = try makeTempDirectory("additional-fail-rule")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        let window = DateInterval(start: isoDate("2026-10-11T00:00:00Z"), end: isoDate("2026-10-18T00:00:00Z"))
        func run(_ config: Configuration) async throws {
            _ = try await source.collect(context: RefreshContext(configuration: config, window: window, now: Date()))
        }
        // Main missing, additional missing: fails.
        await #expect(throws: SessionLogSource.ScanFailure.self) {
            try await run(self.groupConfig([self.extraSubscription("acc-max", "~/.claude", extra: ["~/.claude-lab"])]))
        }
        // Main missing, additional readable: does not fail.
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude-lab"), withIntermediateDirectories: true)
        try await run(groupConfig([extraSubscription("acc-max", "~/.claude", extra: ["~/.claude-lab"])]))
    }

    /// US1 scenario 6 and "Removing an account": a removed entry or account
    /// is no longer read, unless another account still names it.
    @Test func removedEntryOrAccountIsNoLongerRead() throws {
        let root = try makeTempDirectory("additional-removed")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try SessionLogSource(paths: Paths(home: root), builtInPrices: pricer)
        let lab = root.appendingPathComponent(".claude-lab").path
        let both = groupConfig([extraSubscription("acc-max", "~/.claude", extra: ["~/.claude-lab"]),
                                extraVertex("acc-acme", "~/.claude", extra: ["~/.claude-lab"])])
        #expect(source.directories(for: both).contains(lab))
        var withoutEntry = both
        withoutEntry.accounts[0].kind.additionalSessionDirectories = []
        #expect(source.directories(for: withoutEntry).contains(lab))
        withoutEntry.accounts[1].kind.additionalSessionDirectories = []
        #expect(!source.directories(for: withoutEntry).contains(lab))
        #expect(!source.directories(for: both.removingAccount(id: "acc-max").removingAccount(id: "acc-acme")).contains(lab))
        #expect(source.directories(for: both.removingAccount(id: "acc-max")).contains(lab))
    }
}

/// spec 035 FR-004, FR-005, FR-008, FR-016, US2, SC-002, SC-003, SC-005:
/// wildcard entries on a Claude account.
extension LogIndexTests {
    private static let sandboxEntry = "~/agent-sessions/openshell/*/claude"

    private func sandboxFixture(_ name: String) throws -> URL {
        let root = try makeTempDirectory(name)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        for box in ["alpha", "beta", "team/alpha", ".cache"] {
            try install("direct-session.jsonl", into: root.appendingPathComponent("agent-sessions/openshell/\(box)/claude"), as: "s.jsonl")
        }
        return root
    }

    private func wildcardConfig(_ extra: [String] = [LogIndexTests.sandboxEntry], main: String = "~/.claude") -> Configuration {
        groupConfig([extraSubscription("acc-max", main, extra: extra)])
    }

    private struct Run {
        let source: SessionLogSource
        let logURL: URL
        let window = DateInterval(start: isoDate("2026-10-11T00:00:00Z"), end: isoDate("2026-10-18T00:00:00Z"))

        func refresh(_ config: Configuration) async throws -> [UsageRecord] {
            guard case .records(let records) = try await source.collect(context: RefreshContext(configuration: config, window: window, now: Date())) else {
                return []
            }
            return records
        }

        var log: String { (try? String(contentsOf: logURL, encoding: .utf8)) ?? "" }
        var lastStats: String { log.split(separator: "\n").last { $0.contains("directories read") }.map(String.init) ?? "" }
    }

    private func run(_ root: URL) throws -> Run {
        let logURL = root.appendingPathComponent("usage.log")
        return Run(source: try SessionLogSource(paths: Paths(home: root), log: DiagnosticLog(fileURL: logURL), builtInPrices: pricer),
                   logURL: logURL)
    }

    /// US2 scenarios 1 to 5: each refresh counts exactly the folders present.
    @Test func wildcardFollowsTheFoldersPresent() async throws {
        let root = try sandboxFixture("wildcard-follows")
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appendingPathComponent("agent-sessions/openshell")
        let r = try run(root)
        let first = try await r.refresh(wildcardConfig())
        #expect(first.count == 4)
        #expect(first.allSatisfy { $0.accountId == "acc-max" })
        #expect(r.log.contains(#"[sessionLogs] wildcard "~/agent-sessions/openshell/*/claude": 2 folder(s) matched"#))
        #expect(r.lastStats.contains("directories read 3, files seen 2, re-read 2"))

        // SC-005: nothing changed, nothing is read again.
        _ = try await r.refresh(wildcardConfig())
        #expect(r.lastStats.contains("directories read 3, files seen 2, re-read 0"))

        // A new folder counts from the next refresh, without rereading the
        // files already indexed.
        try install("direct-session.jsonl", into: base.appendingPathComponent("gamma/claude"), as: "s.jsonl")
        #expect(try await r.refresh(wildcardConfig()).count == 6)
        #expect(r.lastStats.contains("directories read 4, files seen 3, re-read 1"))

        // A deleted folder stops counting, and nothing fails.
        try FileManager.default.removeItem(at: base.appendingPathComponent("beta"))
        #expect(try await r.refresh(wildcardConfig()).count == 4)
        #expect(r.lastStats.contains("directories read 3, files seen 2, re-read 0"))
    }

    /// US2 scenario 7: an entry that matches nothing reads nothing and
    /// fails nothing.
    @Test func wildcardMatchingNothingFailsNothing() async throws {
        let root = try sandboxFixture("wildcard-nothing")
        defer { try? FileManager.default.removeItem(at: root) }
        let r = try run(root)
        #expect(try await r.refresh(wildcardConfig(["~/agent-sessions/none/*/claude"])).isEmpty)
        #expect(r.log.contains(#"wildcard "~/agent-sessions/none/*/claude": 0 folder(s) matched"#))
        #expect(!r.log.contains("error"))
    }

    /// SC-003: one folder as a main directory, a literal entry and a
    /// wildcard match counts each session once.
    @Test func folderReachedThreeWaysCountsOnce() async throws {
        let root = try sandboxFixture("wildcard-three-ways")
        defer { try? FileManager.default.removeItem(at: root) }
        let r = try run(root)
        let config = wildcardConfig([Self.sandboxEntry, "~/agent-sessions/openshell/alpha/claude"],
                                    main: "~/agent-sessions/openshell/alpha/claude")
        let records = try await r.refresh(config)
        #expect(records.count == 4)
        #expect(r.lastStats.contains("directories read 2"))
    }

    /// FR-005: a capped entry logs the cap line once across refreshes.
    @Test func capLineIsLoggedOnce() async throws {
        let root = try makeTempDirectory("wildcard-cap")
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0...100 {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("boxes/box-\(index)"), withIntermediateDirectories: true)
        }
        let r = try run(root)
        _ = try await r.refresh(wildcardConfig(["~/boxes/*"], main: "~/boxes/box-0"))
        _ = try await r.refresh(wildcardConfig(["~/boxes/*"], main: "~/boxes/box-0"))
        let cap = #"[sessionLogs] wildcard "~/boxes/*": 101 folders matched, only the first 100 are read"#
        #expect(r.log.components(separatedBy: cap).count - 1 == 1)
        #expect(r.log.components(separatedBy: #"wildcard "~/boxes/*": 101 folder(s) matched"#).count - 1 == 2)
    }

    /// FR-012 end to end: the resolver's claims reach the tie-breaker, so
    /// two Claude subscriptions keep apart the sessions of the folders they
    /// list; the same folder on both leaves them Unassigned.
    @Test func additionalClaimSeparatesTwoSubscriptionsEndToEnd() async throws {
        let root = try sandboxFixture("wildcard-two-subscriptions")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude-pro"), withIntermediateDirectories: true)
        let r = try run(root)
        let config = groupConfig([extraSubscription("acc-max", "~/.claude", extra: [Self.sandboxEntry]),
                                  extraSubscription("acc-pro", "~/.claude-pro", extra: [])])
        let first = try await r.refresh(config)
        #expect(first.count == 4)
        #expect(first.allSatisfy { $0.accountId == "acc-max" })
        // A new folder's sessions follow the same claim.
        try install("direct-session.jsonl", into: root.appendingPathComponent("agent-sessions/openshell/gamma/claude"), as: "s.jsonl")
        let second = try await r.refresh(config)
        #expect(second.count == 6)
        #expect(second.allSatisfy { $0.accountId == "acc-max" })
        let shared = groupConfig([extraSubscription("acc-max", "~/.claude", extra: [Self.sandboxEntry]),
                                  extraSubscription("acc-pro", "~/.claude-pro", extra: [Self.sandboxEntry])])
        let third = try await r.refresh(shared)
        #expect(third.count == 6)
        #expect(third.allSatisfy { $0.accountId == nil })
    }

    /// FR-012: when the claims on an indexed folder change without a
    /// configuration change (a matched link goes away), only that folder is
    /// read again and its sessions follow the new claims.
    @Test func changedClaimReattributesOnlyThatFolder() async throws {
        let root = try sandboxFixture("wildcard-claim-change")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude-pro"), withIntermediateDirectories: true)
        let links = root.appendingPathComponent("links")
        try FileManager.default.createDirectory(at: links, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: links.appendingPathComponent("a"),
                                                   withDestinationURL: root.appendingPathComponent("agent-sessions/openshell/alpha"))
        let config = groupConfig([extraSubscription("acc-max", "~/.claude", extra: [Self.sandboxEntry]),
                                  extraSubscription("acc-pro", "~/.claude-pro", extra: ["~/links/*/claude"])])
        let r = try run(root)
        let first = try await r.refresh(config)
        #expect(first.filter { $0.accountId == nil }.count == 2)
        #expect(first.filter { $0.accountId == "acc-max" }.count == 2)
        try FileManager.default.removeItem(at: links.appendingPathComponent("a"))
        let second = try await r.refresh(config)
        #expect(second.count == 4)
        #expect(second.allSatisfy { $0.accountId == "acc-max" })
        #expect(r.lastStats.contains("files seen 2, re-read 1"))
        // Editing a list rereads only the folders whose claims changed.
        var edited = config
        edited.accounts[1].kind.additionalSessionDirectories = ["~/agent-sessions/openshell/beta/claude"]
        let third = try await r.refresh(edited)
        #expect(third.filter { $0.accountId == nil }.count == 2)
        #expect(r.lastStats.contains("files seen 2, re-read 1"))
    }

    /// FR-006, FR-009: a `projects` link in an additional directory that
    /// leads outside it is not followed.
    @Test func projectsLinkOutsideAnAdditionalDirectoryIsSkipped() throws {
        let root = try makeTempDirectory("scan-targets-link")
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside")
        try Fixtures.install("vertex-session.jsonl", into: outside, as: "p/s.jsonl")
        let box = root.appendingPathComponent("box")
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: box.appendingPathComponent("projects"),
                                                   withDestinationURL: outside.appendingPathComponent("projects"))
        let scan = LogDirectoryScanner().scan(targets: [ScanTarget(path: box.path, isMain: false)])
        #expect(scan.files.isEmpty)
        #expect(scan.additionalNotes == ["\(box.path): skipped, projects is a link outside the directory"])
        // A main directory keeps following its link (spec 015 research R1).
        #expect(LogDirectoryScanner().scan(targets: [ScanTarget(path: box.path, isMain: true)]).files.count == 1)
        // A link inside the directory is followed.
        let inside = root.appendingPathComponent("inside")
        try Fixtures.install("vertex-session.jsonl", into: inside.appendingPathComponent("real"), as: "p/s.jsonl")
        try FileManager.default.createSymbolicLink(at: inside.appendingPathComponent("projects"),
                                                   withDestinationURL: inside.appendingPathComponent("real/projects"))
        #expect(LogDirectoryScanner().scan(targets: [ScanTarget(path: inside.path, isMain: false)]).files.count == 1)
    }

    /// FR-008: a folder under an additional `projects` tree that cannot be
    /// read is a log note, never a source error.
    @Test func unreadableFolderUnderAdditionalProjectsIsOnlyNoted() throws {
        let root = try makeTempDirectory("scan-targets-subfolder")
        let locked = root.appendingPathComponent("box/projects/p")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }
        try Fixtures.install("vertex-session.jsonl", into: root.appendingPathComponent("box"), as: "p/s.jsonl")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let box = root.appendingPathComponent("box").path
        let scan = LogDirectoryScanner().scan(targets: [ScanTarget(path: box, isMain: false)])
        #expect(scan.errors.isEmpty)
        #expect(scan.additionalNotes.count == 1)
        #expect(scan.additionalNotes.first?.hasPrefix("\(box): error: cannot read") == true)
    }
}
