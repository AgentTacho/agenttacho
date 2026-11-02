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
                              kind: .tokenBased(TokenBasedSettings(groupId: "grp", harness: .claudeCode, sessionKind: .claudeCodeVertex)))]
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
                kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), harness: .claudeCode,
                                                     sessionKind: .claudeCodeVertex, sessionDirectory: directory)))
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
                                       kind: .tokenBased(TokenBasedSettings(groupId: "grp", harness: .claudeCode,
                                                                            sessionKind: .claudeCodeVertex, condition: MatchCondition(field: .anywhere, operator: .contains, text: "\"inference_geo\":\"eu\"")))))
        let stats = index.update(files: files, window: window, parser: parser, attributor: Attributor(configuration: config), pricer: pricer)
        #expect(stats.filesRead == 1)
        #expect(index.records.first { $0.messageId == "msg_vrtx_E1" }?.accountId == "acc-eu")
        #expect(index.records.first { $0.messageId == "msg_vrtx_E2" }?.accountId == "acc-vertex")
    }

    /// spec 038 FR-006, SC-004: files read while a rule sat out keep their
    /// records for this refresh and are read again on the next one,
    /// including a file merged after the time-out; a file whose records
    /// never reached the skipped rule keeps its entry. The retry skips the
    /// value the rule ran out of time on (the source's match memory), so
    /// the file that only sat out gets the rule's verdict, and nothing is
    /// read after that.
    @Test func filesTouchedDuringASitOutAreReadAgain() throws {
        let root = try makeTempDirectory("index-sit-out")
        defer { try? FileManager.default.removeItem(at: root) }
        let slowDirectory = "/Users/tester/" + String(repeating: "a", count: 40) + "/proj"
        try writeRecords([record(id: "A1", at: "2026-10-12T10:00:00Z")], to: root.appendingPathComponent("projects/p/a.jsonl"))
        try writeRecords([record(id: "B1", at: "2026-10-12T10:01:00Z", cwd: slowDirectory),
                          record(id: "B2", at: "2026-10-12T10:02:00Z")], to: root.appendingPathComponent("projects/p/b.jsonl"))
        try writeRecords([record(id: "C1", at: "2026-10-12T10:03:00Z", cwd: "/Users/tester/proj-c")],
                         to: root.appendingPathComponent("projects/p/c.jsonl"))
        var config = vertexConfig()
        config.accounts.append(Account(id: "acc-slow", displayName: "Slow", kind: .tokenBased(TokenBasedSettings(
            groupId: "grp", harness: .claudeCode, sessionKind: .claudeCodeVertex, condition: MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$|proj-c")))))
        var memory = MatchMemory()
        func attributor() -> Attributor { Attributor(configuration: config, matchTimeLimit: .milliseconds(20), matchMemory: memory) }
        // a before the time-out, b holds it, c after it.
        let files = LogDirectoryScanner().scan(directories: [root.path]).files.sorted { $0.canonicalPath < $1.canonicalPath }
        #expect(files.map { ($0.canonicalPath as NSString).lastPathComponent } == ["a.jsonl", "b.jsonl", "c.jsonl"])
        let index = LogIndex()
        func account(_ id: String) -> String? { index.records.first { $0.messageId == "msg_vrtx_\(id)" }?.accountId }

        let first = attributor()
        let stats = index.update(files: files, window: window, parser: parser, attributor: first, pricer: pricer)
        memory = first.matchMemory
        #expect(stats.filesRead == 3)
        #expect(first.timeOuts == 1)
        // The records stay, attributed through the remaining rules.
        #expect(index.records.count == 4)
        #expect(index.records.allSatisfy { $0.accountId == "acc-vertex" })

        // Only b and c are read again, from the start; B1 counts as no
        // match without running, so the rule does not sit out and claims C1.
        let retry = attributor()
        let second = index.update(files: files, window: window, parser: parser, attributor: retry, pricer: pricer)
        memory = retry.matchMemory
        #expect(second.filesRead == 2)
        #expect(retry.timeOuts == 0)
        #expect(account("C1") == "acc-slow")
        #expect(account("B1") == "acc-vertex")
        #expect(account("B2") == "acc-vertex")

        // Nothing more is read while the rules stay the same (SC-004).
        let steady = index.update(files: files, window: window, parser: parser, attributor: attributor(), pricer: pricer)
        #expect(steady.filesRead == 0)
        #expect(index.records.count == 4)
    }

    /// spec 038 FR-006, SC-004: a pattern that is slow on every record of
    /// many files settles after one retry: the retry times out on another
    /// record, the rule is given up for these rules, and no file is read
    /// again.
    @Test func ruleSlowOnEveryRecordSettlesAfterOneRetry() throws {
        let root = try makeTempDirectory("index-all-slow")
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a", "b", "c", "d", "e"] {
            let slow = "/Users/tester/" + String(repeating: "a", count: 40) + "/\(name)"
            try writeRecords([record(id: "\(name)1", at: "2026-10-12T10:00:00Z", cwd: slow + "1"),
                              record(id: "\(name)2", at: "2026-10-12T10:01:00Z", cwd: slow + "2")],
                             to: root.appendingPathComponent("projects/p/\(name).jsonl"))
        }
        var config = vertexConfig()
        config.accounts.append(Account(id: "acc-slow", displayName: "Slow", kind: .tokenBased(TokenBasedSettings(
            groupId: "grp", harness: .claudeCode, sessionKind: .claudeCodeVertex, condition: MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$")))))
        var memory = MatchMemory()
        let files = LogDirectoryScanner().scan(directories: [root.path]).files
        let index = LogIndex()
        var reads: [Int] = []
        for _ in 0..<4 {
            let attributor = Attributor(configuration: config, matchTimeLimit: .milliseconds(20), matchMemory: memory)
            reads.append(index.update(files: files, window: window, parser: parser, attributor: attributor, pricer: pricer).filesRead)
            memory = attributor.matchMemory
        }
        #expect(reads == [5, 5, 0, 0])
        #expect(memory.givenUp == ["acc-slow"])
        #expect(index.records.count == 10)
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

    /// spec 038 FR-006, SC-004: an active session file that comes first and
    /// gets a new slow record before every refresh does not keep the other
    /// files reading again: retries run first, the rule is given up in one,
    /// and from then on only the growing file is read.
    @Test func activeSlowFileDoesNotKeepRetriesGoing() throws {
        let root = try makeTempDirectory("index-active-slow")
        defer { try? FileManager.default.removeItem(at: root) }
        func slow(_ id: String) -> String {
            record(id: id, at: "2026-10-12T10:00:00Z", cwd: "/Users/tester/" + String(repeating: "a", count: 40) + "/" + id)
        }
        let active = root.appendingPathComponent("projects/p/a.jsonl")
        try writeRecords([slow("A1")], to: active)
        try writeRecords([slow("F1"), slow("F2")], to: root.appendingPathComponent("projects/p/f1.jsonl"))
        try writeRecords([slow("G1"), slow("G2")], to: root.appendingPathComponent("projects/p/f2.jsonl"))
        var config = vertexConfig()
        config.accounts.append(Account(id: "acc-slow", displayName: "Slow", kind: .tokenBased(TokenBasedSettings(
            groupId: "grp", harness: .claudeCode, sessionKind: .claudeCodeVertex, condition: MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$")))))
        var memory = MatchMemory()
        let index = LogIndex()
        var reads: [Int] = []
        for refresh in 0..<5 {
            if refresh > 0 {
                let handle = try FileHandle(forWritingTo: active)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((slow("A\(refresh + 1)") + "\n").utf8))
                try handle.close()
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(refresh))],
                                                      ofItemAtPath: active.path)
            }
            // The active file first in processing order.
            let files = LogDirectoryScanner().scan(directories: [root.path]).files.sorted { $0.canonicalPath < $1.canonicalPath }
            let attributor = Attributor(configuration: config, matchTimeLimit: .milliseconds(20), matchMemory: memory)
            reads.append(index.update(files: files, window: window, parser: parser, attributor: attributor, pricer: pricer).filesRead)
            memory = attributor.matchMemory
        }
        #expect(reads == [3, 3, 1, 1, 1])
        #expect(memory.givenUp == ["acc-slow"])
        #expect(index.records.count == 9)
    }

    /// spec 038 FR-007: unchanged sat-out files are retried before sat-out
    /// files that grew, so a time-out on a newly appended line cannot make
    /// the condition sit out for another file's retry: the unchanged file
    /// gets the condition's verdict although the grown one comes first.
    @Test func unchangedRetriesRunBeforeGrownOnes() throws {
        let root = try makeTempDirectory("index-grown-retry")
        defer { try? FileManager.default.removeItem(at: root) }
        func slow(_ id: String) -> String {
            record(id: id, at: "2026-10-12T10:00:00Z", cwd: "/Users/tester/" + String(repeating: "a", count: 40) + "/" + id)
        }
        let grown = root.appendingPathComponent("projects/p/a.jsonl")
        try writeRecords([slow("X1")], to: grown)
        try writeRecords([record(id: "Y1", at: "2026-10-12T10:03:00Z", cwd: "/Users/tester/proj-c")],
                         to: root.appendingPathComponent("projects/p/b.jsonl"))
        var config = vertexConfig()
        config.accounts.append(Account(id: "acc-slow", displayName: "Slow", kind: .tokenBased(TokenBasedSettings(
            groupId: "grp", harness: .claudeCode, sessionKind: .claudeCodeVertex, condition: MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$|proj-c")))))
        var memory = MatchMemory()
        let index = LogIndex()
        func refresh() {
            let files = LogDirectoryScanner().scan(directories: [root.path]).files.sorted { $0.canonicalPath < $1.canonicalPath }
            let attributor = Attributor(configuration: config, matchTimeLimit: .milliseconds(20), matchMemory: memory)
            _ = index.update(files: files, window: window, parser: parser, attributor: attributor, pricer: pricer)
            memory = attributor.matchMemory
        }
        refresh()
        // X1 timed out first, so Y1 was sat out.
        #expect(index.records.first { $0.messageId == "msg_vrtx_Y1" }?.accountId == "acc-vertex")
        let handle = try FileHandle(forWritingTo: grown)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((slow("X2") + "\n").utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: grown.path)
        refresh()
        #expect(index.records.first { $0.messageId == "msg_vrtx_Y1" }?.accountId == "acc-slow")
        #expect(memory.givenUp == ["acc-slow"])
    }

    /// spec 038 FR-007, SC-005: an active session file that is the only file
    /// of the condition's kind and gets a new slow record before every
    /// refresh settles too: its read after a sit-out is the retry of the
    /// records the condition sat out on, so a time-out there gives the
    /// condition up, and from then on only the appended lines are read.
    @Test func loneActiveSlowFileSettlesAfterOneRetry() throws {
        let root = try makeTempDirectory("index-lone-active-slow")
        defer { try? FileManager.default.removeItem(at: root) }
        func slow(_ id: String) -> String {
            record(id: id, at: "2026-10-12T10:00:00Z", cwd: "/Users/tester/" + String(repeating: "a", count: 40) + "/" + id)
        }
        let active = root.appendingPathComponent("projects/p/a.jsonl")
        try writeRecords([slow("A1"), slow("A2")], to: active)
        var config = vertexConfig()
        config.accounts.append(Account(id: "acc-slow", displayName: "Slow", kind: .tokenBased(TokenBasedSettings(
            groupId: "grp", harness: .claudeCode, sessionKind: .claudeCodeVertex, condition: MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$")))))
        var memory = MatchMemory()
        let index = LogIndex()
        var bytes: [Int] = []
        var appended: [Int] = [0]
        for refresh in 0..<4 {
            if refresh > 0 {
                let line = Data((slow("A\(refresh + 2)") + "\n").utf8)
                appended.append(line.count)
                let handle = try FileHandle(forWritingTo: active)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(refresh))],
                                                      ofItemAtPath: active.path)
            }
            let files = LogDirectoryScanner().scan(directories: [root.path]).files
            let attributor = Attributor(configuration: config, matchTimeLimit: .milliseconds(20), matchMemory: memory)
            bytes.append(index.update(files: files, window: window, parser: parser, attributor: attributor, pricer: pricer).bytesRead)
            memory = attributor.matchMemory
        }
        #expect(memory.givenUp == ["acc-slow"])
        #expect(index.entries.values.allSatisfy { !$0.reattribute })
        // The first two refreshes read the whole file; after that only the
        // appended line is read.
        #expect(bytes[2] == appended[2])
        #expect(bytes[3] == appended[3])
        #expect(index.records.count == 5)
    }

    /// spec 038 FR-006, SC-004: the Claude Code source logs a sat-out rule
    /// with the account's name, and keeps its match memory between
    /// refreshes: the retry skips the slow value, logs nothing and reads
    /// nothing after that.
    @Test func sourceLogsASitOutAndRemembersTheSlowValue() async throws {
        let root = try makeTempDirectory("source-sit-out")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(".claude/projects/p/s.jsonl")
        let slowDirectory = "/Users/tester/" + String(repeating: "a", count: 40) + "/proj"
        try writeRecords([record(id: "S1", at: "2026-10-12T10:01:00Z", cwd: slowDirectory),
                          record(id: "S2", at: "2026-10-12T10:02:00Z")], to: file)
        try FileManager.default.setAttributes([.modificationDate: isoDate("2026-10-12T12:00:00Z")], ofItemAtPath: file.path)
        let logURL = root.appendingPathComponent("usage.log")
        let source = try SessionLogSource(paths: Paths(home: root), log: DiagnosticLog(fileURL: logURL), builtInPrices: pricer)
        var config = onDefaultDirectory
        config.accounts.append(Account(id: "acc-slow", displayName: "Slow", kind: .tokenBased(TokenBasedSettings(
            membership: .ownBudget(BudgetSettings(budgetUSD: 50)), harness: .claudeCode,
            sessionKind: .claudeCodeVertex, condition: MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$")))))
        let context = RefreshContext(configuration: config, window: window, now: isoDate("2026-10-12T12:00:00Z"))
        let line = Attributor.sitOutLogLine(account: "Slow")
        func logged() throws -> Int {
            try String(contentsOf: logURL, encoding: .utf8).components(separatedBy: line).count - 1
        }

        _ = try await source.collect(context: context)
        #expect(try logged() == 1)
        // The retry reads the file again and skips the slow value.
        _ = try await source.collect(context: context)
        #expect(try logged() == 1)
        _ = try await source.collect(context: context)
        #expect(try logged() == 1)
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
        stats.filesWithProfile = 1400
        stats.filesWithoutProfile = 79
        #expect(SessionLogSource.statsLine(stats, directories: 3, elapsed: 5.282)
            == "directories read 3, files seen 10366, re-read 1479 (2191659065 bytes), records since collection start 56091, profile named 1400, none 79, 5.282 s")
    }

    /// The refresh line states the process's CPU seconds of the refresh
    /// next to its elapsed time, with one decimal (spec 039 FR-007).
    @Test func statsLineShowsTheCPUSeconds() {
        var stats = LogIndexStats()
        stats.filesSeen = 11197
        stats.filesRead = 2310
        stats.bytesRead = 3_513_654_740
        stats.recordsInWindow = 85796
        stats.filesWithProfile = 210
        stats.filesWithoutProfile = 2100
        let line = SessionLogSource.statsLine(stats, directories: 3, elapsed: 9.22, cpu: 38.04)
        #expect(line == "directories read 3, files seen 11197, re-read 2310 (3513654740 bytes), records since collection start 85796, profile named 210, none 2100, 9.220 s, cpu 38.0 s")
        #expect(line.hasSuffix(", 9.220 s, cpu 38.0 s"))
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
            Account(id: "acc-plus", displayName: "Plus", kind: .codexSubscription(CodexSubscriptionSettings(codexHome: ""))),
            Account(id: "acc-oai", displayName: "OpenAI",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), harness: .codex))),
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
                kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), harness: .claudeCode,
                                                     sessionKind: .claudeCodeVertex, sessionDirectory: dir, additionalSessionDirectories: extra)))
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
        // The refresh line closes with its CPU seconds (spec 039 FR-007).
        #expect(r.lastStats.range(of: #", [0-9]+\.[0-9]{3} s, cpu [0-9]+\.[0-9] s$"#, options: .regularExpression) != nil,
                "\(r.lastStats)")

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

// MARK: - Spec 037: profiles in the index

/// spec 037 FR-001, FR-004, FR-012, SC-001, SC-004, SC-005, plan "Re-read
/// rules in LogIndex": the profile of each session file and when files are
/// read again.
@Suite struct LogIndexProfileTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let parser = SessionRecordParser()
    let pricer = try! PriceTable.builtIn()
    static let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    static let personal = "/Users/tester/agent-profiles/personal/claude"
    static let work = "/Users/tester/agent-profiles/work/claude"
    static let lab = "/Users/tester/agent-profiles/lab/claude"
    static let marker = "SECRET-PROMPT-MARKER-4711"

    /// Max on personal, Vertex on work, the gateway on lab as Directory only.
    static let configuration = Configuration(accounts: [
        Account(id: "max", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: "~/agent-profiles/personal/claude"))),
        Account(id: "vertex", displayName: "Vertex",
                kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), sessionKind: .claudeCodeVertex, sessionDirectory: "~/agent-profiles/work/claude"))),
        Account(id: "lab", displayName: "Lab",
                kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), sessionKind: .claudeCodeDirectoryOnly,
                                                     sessionDirectory: "~/agent-profiles/lab/claude"))),
    ], groups: [BudgetGroup(id: "grp", name: "Team", budgetUSD: 100)])

    static func candidates(extra: [SessionProfile.Entry] = []) -> SessionProfile.Candidates {
        SessionProfile.Candidates(entries: [
            .init(accountId: "max", path: "~/agent-profiles/personal/claude", rank: .main),
            .init(accountId: "vertex", path: "~/agent-profiles/work/claude", rank: .main),
            .init(accountId: "lab", path: "~/agent-profiles/lab/claude", rank: .main),
        ] + extra, paths: paths)
    }

    var attributor: Attributor { Attributor(configuration: Self.configuration, paths: Self.paths) }

    static func shape(_ dir: String) -> String {
        #"{"type":"api-request-shape","sessionId":"s","shape":{"system":[{"type":"text","text":"You have a persistent file-based memory at `\#(dir)/projects/-Users-tester-proj/memory/`. \#(marker)"}]}}"#
    }

    static func record(_ id: String, requestId: String? = nil, model: String = "claude-opus-4-6") -> String {
        let request = requestId.map { #""requestId":"\#($0)","# } ?? ""
        return #"{"type":"assistant","timestamp":"2026-10-13T10:00:00Z",\#(request)"uuid":"\#(id)","sessionId":"s","message":{"id":"msg_\#(id)","model":"\#(model)","role":"assistant","content":[],"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}}"#
    }

    static func write(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    static func append(_ lines: [String], to url: URL) throws {
        try FileHandle(forWritingTo: url).withAppend(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    func scan(_ root: URL) -> [ScannedFile] {
        LogDirectoryScanner().scan(directories: [root.path]).files
    }

    func account(_ index: LogIndex, _ id: String) -> String?? {
        index.records.first { $0.messageId == "msg_\(id)" }.map(\.accountId)
    }

    /// SC-001: three profiles share one `projects` folder; every record
    /// counts for its profile's account and none is Unassigned.
    @Test func threeProfilesShareOneProjectsFolder() throws {
        let root = try makeTempDirectory("profile-three")
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = root.appendingPathComponent("projects/-Users-tester-proj")
        try Self.write([Self.shape(Self.personal), Self.record("p1", requestId: "req_011abc"), Self.record("p2", requestId: "req_vrtx_p2")],
                       to: proj.appendingPathComponent("a.jsonl"))
        try Self.write([Self.shape(Self.work), Self.record("w1", requestId: "req_vrtx_w1"), Self.record("w2", requestId: "req_011w2")],
                       to: proj.appendingPathComponent("b.jsonl"))
        try Self.write([Self.shape(Self.lab), Self.record("l1", model: "intranet/glm-5"), Self.record("l2", requestId: "req_vrtx_l2")],
                       to: proj.appendingPathComponent("c.jsonl"))
        let index = LogIndex()
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(index.records.count == 6)
        #expect(index.records.allSatisfy { $0.accountId != nil })
        #expect(account(index, "p1") == "max")
        #expect(account(index, "p2") == "max")
        #expect(account(index, "w1") == "vertex")
        #expect(account(index, "w2") == "vertex")
        #expect(account(index, "l1") == "lab")
        #expect(account(index, "l2") == "lab")
        #expect(index.entries.values.compactMap(\.profile).sorted() == [Self.lab, Self.personal, Self.work])
        // FR-012: every file read named a configured directory.
        #expect(stats.filesWithProfile == 3)
        #expect(stats.filesWithoutProfile == 0)
        // SC-005: an unchanged refresh reads no file again.
        let again = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(again.filesRead == 0)
        #expect(again.filesWithProfile == 0 && again.filesWithoutProfile == 0)
    }

    /// A shape line whose own `type` sits outside both bounded windows is
    /// left to today's path (spec 039 FR-013, FR-014): decoded, then
    /// searched, so the records after it still take its profile.
    @Test func aShapeLineLeftToTheFallbackStillNamesTheProfile() throws {
        let root = try makeTempDirectory("profile-fallback-shape")
        defer { try? FileManager.default.removeItem(at: root) }
        let text = "You have a persistent file-based memory at `\(Self.work)/projects/-Users-tester-proj/memory/`. "
            + String(repeating: "y", count: 300)
        let line = #"{"shape":{"system":[{"type":"text","text":"\#(text)"}]},"type":"api-request-shape","pad":"\#(String(repeating: "x", count: 5000))"}"#
        #expect(Data(line.utf8).withUnsafeBytes { SessionLineClassifier.classify($0) } == .undecided)
        let proj = root.appendingPathComponent("projects/-Users-tester-proj")
        try Self.write([line, Self.record("w1", requestId: "req_vrtx_w1")], to: proj.appendingPathComponent("a.jsonl"))
        let index = LogIndex()
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(account(index, "w1") == "vertex")
        #expect(index.entries.values.compactMap(\.profile) == [Self.work])
        #expect(stats.filesWithProfile == 1)
    }

    /// A shape object nested in a user line's content does not make a shape
    /// line: only the line's own `type` counts (spec 039 FR-013).
    @Test func aNestedShapeObjectInAUserLineNamesNoProfile() throws {
        let root = try makeTempDirectory("profile-nested-shape")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = #"{"type":"user","sessionId":"s","message":{"role":"user","content":[{"type":"tool_result","content":{"type":"api-request-shape","shape":{"system":[{"type":"text","text":"memory at `\#(Self.lab)/projects/-Users-tester-proj/memory/`"}]}}}]}}"#
        #expect(Data(nested.utf8).withUnsafeBytes { SessionLineClassifier.classify($0) } == .other)
        let proj = root.appendingPathComponent("projects/-Users-tester-proj")
        try Self.write([nested, Self.record("u1", requestId: "req_011u1")], to: proj.appendingPathComponent("a.jsonl"))
        let index = LogIndex()
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(index.records.count == 1)
        #expect(index.entries.values.compactMap(\.profile).isEmpty)
        #expect(stats.filesWithProfile == 0)
    }

    /// US1 scenario 6: a subagent file is matched by its own shape lines.
    @Test func subagentFileUsesItsOwnShapeLines() throws {
        let root = try makeTempDirectory("profile-subagent")
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = root.appendingPathComponent("projects/-Users-tester-proj")
        try Self.write([Self.shape(Self.work), Self.record("w1", requestId: "req_011w1")], to: proj.appendingPathComponent("s1.jsonl"))
        try Self.write([Self.shape(Self.lab), Self.record("a1", requestId: "req_011a1")],
                       to: proj.appendingPathComponent("s1/subagents/agent-x.jsonl"))
        let index = LogIndex()
        _ = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer, profiles: Self.candidates())
        #expect(account(index, "w1") == "vertex")
        #expect(account(index, "a1") == "lab")
    }

    /// FR-001: appended lines keep the profile in effect at the end.
    @Test func appendedLinesKeepTheProfile() throws {
        let root = try makeTempDirectory("profile-append")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects/p/s.jsonl")
        try Self.write([Self.shape(Self.lab), Self.record("l1", requestId: "req_vrtx_1")], to: file)
        let index = LogIndex()
        _ = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer, profiles: Self.candidates())
        try Self.append([Self.record("l2", requestId: "req_vrtx_2")], to: file)
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(stats.filesRead == 1)
        #expect(account(index, "l1") == "lab")
        #expect(account(index, "l2") == "lab")
    }

    /// FR-001: when a file's first shape line arrives in a later refresh,
    /// the records read before it are attributed again with that profile.
    @Test func lateFirstShapeLineReattributesEarlierRecords() throws {
        let root = try makeTempDirectory("profile-late")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects/p/s.jsonl")
        try Self.write([Self.record("r1", requestId: "req_vrtx_1"), Self.record("r2", model: "intranet/glm-5")], to: file)
        let index = LogIndex()
        let first = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(account(index, "r1") == "vertex")
        #expect(account(index, "r2") == .some(nil))
        #expect(first.filesWithoutProfile == 1)
        try Self.append([Self.shape(Self.lab), Self.record("r3", requestId: "req_vrtx_3")], to: file)
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(stats.filesRead == 1)
        #expect(stats.filesWithProfile == 1)
        // Both reads of this refresh count: the appended part, then the
        // whole file again.
        let size = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        #expect(stats.bytesRead > size)
        #expect(account(index, "r1") == "lab")
        #expect(account(index, "r2") == "lab")
        #expect(account(index, "r3") == "lab")
    }

    /// FR-001: each record takes the latest shape line before it; records
    /// before the first take the first.
    @Test func twoProfilesInOneFile() throws {
        let root = try makeTempDirectory("profile-two")
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.write([Self.record("r0", requestId: "req_011r0"), Self.shape(Self.work), Self.record("r1", requestId: "req_011r1"),
                        Self.shape(Self.lab), Self.record("r2", requestId: "req_011r2")],
                       to: root.appendingPathComponent("projects/p/s.jsonl"))
        let index = LogIndex()
        _ = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer, profiles: Self.candidates())
        #expect(account(index, "r0") == "vertex")
        #expect(account(index, "r1") == "vertex")
        #expect(account(index, "r2") == "lab")
        #expect(index.entries.values.first?.profile == Self.lab)
    }

    /// FR-001, plan "Re-read rules": a change of the candidates re-reads
    /// only files whose result can change; files without shape lines and
    /// files whose profile keeps its claimants are not read again.
    @Test func candidateChangeRereadsOnlyAffectedFiles() throws {
        let root = try makeTempDirectory("profile-rekey")
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = root.appendingPathComponent("projects/p")
        try Self.write([Self.record("plain", requestId: "req_vrtx_p")], to: proj.appendingPathComponent("plain.jsonl"))
        try Self.write([Self.shape(Self.work), Self.record("named", requestId: "req_011n")], to: proj.appendingPathComponent("named.jsonl"))
        let sandbox = "/Users/tester/agent-sessions/openshell/alpha/claude"
        try Self.write([Self.shape(sandbox), Self.record("box", requestId: "req_011b")], to: proj.appendingPathComponent("box.jsonl"))
        let index = LogIndex()
        let first = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(first.filesWithProfile == 1 && first.filesWithoutProfile == 2)
        #expect(account(index, "box") == "max")

        // A new wildcard match claims the sandbox for the lab account.
        let extra = [SessionProfile.Entry(accountId: "lab", path: sandbox, rank: .additional, isWildcardMatch: true)]
        let labAttributor = Attributor(configuration: Self.configuration, paths: Self.paths,
                                       profileAdditionalDirectories: ["lab": [sandbox]])
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: labAttributor, pricer: pricer,
                                 profiles: Self.candidates(extra: extra))
        #expect(stats.filesRead == 1)
        #expect(account(index, "box") == "lab")
        #expect(account(index, "named") == "vertex")
        #expect(account(index, "plain") == "vertex")

        // The sandbox moves to another account: its file is read again.
        let moved = [SessionProfile.Entry(accountId: "vertex", path: sandbox, rank: .additional, isWildcardMatch: true)]
        let vertexAttributor = Attributor(configuration: Self.configuration, paths: Self.paths,
                                          profileAdditionalDirectories: ["vertex": [sandbox]])
        let again = index.update(files: scan(root), window: window, parser: parser, attributor: vertexAttributor, pricer: pricer,
                                 profiles: Self.candidates(extra: moved))
        #expect(again.filesRead == 1)
        #expect(account(index, "box") == "vertex")
    }

    /// FR-004, SC-004: nothing of a shape line but the directory reaches an
    /// index entry, a record or the stats.
    @Test func shapeLineTextIsNotKept() throws {
        let root = try makeTempDirectory("profile-privacy")
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.write([Self.shape(Self.work), Self.record("w1", requestId: "req_011w1")], to: root.appendingPathComponent("projects/p/s.jsonl"))
        let index = LogIndex()
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(!String(reflecting: index.entries).contains(Self.marker))
        #expect(!String(reflecting: index.records).contains(Self.marker))
        #expect(!String(reflecting: stats).contains(Self.marker))
        #expect(!String(reflecting: index.entries).contains("persistent file-based memory"))
        #expect(index.entries.values.first?.profile == Self.work)
    }
}

/// spec 037 FR-001, FR-003, FR-012: the source builds the profile
/// candidates from the accounts' directories and logs the profile counts.
extension LogIndexProfileTests {
    @Test func sourceAttributesByProfileAndLogsTheCounts() async throws {
        let root = try makeTempDirectory("profile-source")
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appendingPathComponent(".claude/projects/-proj")
        let work = root.appendingPathComponent("agent-profiles/work/claude").path
        try Self.write([Self.shape(work), Self.record("w1", requestId: "req_011w1")], to: shared.appendingPathComponent("a.jsonl"))
        try Self.write([Self.record("m1", requestId: "req_011m1")], to: shared.appendingPathComponent("b.jsonl"))
        let box = root.appendingPathComponent("agent-sessions/openshell/alpha/claude").path
        try FileManager.default.createDirectory(atPath: box, withIntermediateDirectories: true)
        try Self.write([Self.shape(box), Self.record("x1", requestId: "req_011x1")], to: shared.appendingPathComponent("c.jsonl"))
        let config = Configuration(accounts: [
            Account(id: "max", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: ""))),
            Account(id: "vertex", displayName: "Vertex",
                    kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), sessionKind: .claudeCodeVertex,
                                                         sessionDirectory: "~/agent-profiles/work/claude",
                                                         additionalSessionDirectories: ["~/agent-sessions/openshell/*/claude"]))),
        ], groups: [BudgetGroup(id: "grp", name: "Team", budgetUSD: 100)])
        let logURL = root.appendingPathComponent("usage.log")
        let source = try SessionLogSource(paths: Paths(home: root), log: DiagnosticLog(fileURL: logURL), builtInPrices: pricer)
        let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
        guard case .records(let records) = try await source.collect(context: RefreshContext(configuration: config, window: window, now: Date())) else {
            Issue.record("expected records")
            return
        }
        // The profile beats the direct request id; the wildcard match of a
        // token-based account's additional directory claims its profile.
        #expect(records.first { $0.messageId == "msg_w1" }?.accountId == "vertex")
        #expect(records.first { $0.messageId == "msg_x1" }?.accountId == "vertex")
        #expect(records.first { $0.messageId == "msg_m1" }?.accountId == "max")
        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("profile named 2, none 1"))
        #expect(!log.contains(Self.marker))
    }
}

/// spec 037 FR-001, checkpoint review: a candidate change re-determines the
/// profile of every record in a file that names several directories, not
/// only of the records after its last shape line.
extension LogIndexProfileTests {
    /// An earlier profile loses its claimant: its records move on.
    @Test func earlierProfileLosingItsClaimantIsReread() throws {
        let root = try makeTempDirectory("profile-earlier")
        defer { try? FileManager.default.removeItem(at: root) }
        let box = "/Users/tester/agent-sessions/openshell/alpha/claude"
        try Self.write([Self.shape(box), Self.record("r1", requestId: "req_011r1"), Self.shape(Self.work), Self.record("r2", requestId: "req_011r2")],
                       to: root.appendingPathComponent("projects/p/s.jsonl"))
        let index = LogIndex()
        let labBox = Attributor(configuration: Self.configuration, paths: Self.paths, profileAdditionalDirectories: ["lab": [box]])
        _ = index.update(files: scan(root), window: window, parser: parser, attributor: labBox, pricer: pricer,
                         profiles: Self.candidates(extra: [.init(accountId: "lab", path: box, rank: .additional)]))
        #expect(account(index, "r1") == "lab")
        #expect(account(index, "r2") == "vertex")
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(stats.filesRead == 1)
        // The box line now names nothing configured: r1 takes the first named profile.
        #expect(account(index, "r1") == "vertex")
        #expect(account(index, "r2") == "vertex")
    }

    /// A directory named earlier in the file becomes configured: its
    /// records move to the new claimant.
    @Test func newlyConfiguredEarlierDirectoryIsPickedUp() throws {
        let root = try makeTempDirectory("profile-newly")
        defer { try? FileManager.default.removeItem(at: root) }
        let box = "/Users/tester/agent-sessions/openshell/beta/claude"
        try Self.write([Self.shape(box), Self.record("r1", requestId: "req_011r1"), Self.shape(Self.work), Self.record("r2", requestId: "req_011r2")],
                       to: root.appendingPathComponent("projects/p/s.jsonl"))
        let index = LogIndex()
        _ = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer, profiles: Self.candidates())
        #expect(account(index, "r1") == "vertex")
        let labBox = Attributor(configuration: Self.configuration, paths: Self.paths, profileAdditionalDirectories: ["lab": [box]])
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: labBox, pricer: pricer,
                                 profiles: Self.candidates(extra: [.init(accountId: "lab", path: box, rank: .additional)]))
        #expect(stats.filesRead == 1)
        #expect(account(index, "r1") == "lab")
        #expect(account(index, "r2") == "vertex")
    }
}

/// spec 037 FR-001, deep review: shape lines that name several configured
/// directories, and the re-read rules for added or removed spellings.
extension LogIndexProfileTests {
    static func shapeNaming(_ dirs: [String]) -> String {
        let memory = dirs.map { "memory at `\($0)/projects/-Users-tester-proj/memory/`." }.joined(separator: " ")
        return #"{"type":"api-request-shape","sessionId":"s","shape":{"system":[{"type":"text","text":"\#(memory) \#(marker)"}]}}"#
    }

    /// An ambiguous line is skipped: records after it keep the earlier
    /// profile, and a file whose only shape line is ambiguous falls back to
    /// the rules and counts as naming none (FR-012).
    @Test func ambiguousShapeLinesAreSkipped() throws {
        let root = try makeTempDirectory("profile-ambiguous")
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = root.appendingPathComponent("projects/p")
        try Self.write([Self.shape(Self.work), Self.record("r1", requestId: "req_011r1"),
                        Self.shapeNaming([Self.work, Self.lab]), Self.record("r2", requestId: "req_011r2")],
                       to: proj.appendingPathComponent("mixed.jsonl"))
        try Self.write([Self.shapeNaming([Self.work, Self.lab]), Self.record("r3", requestId: "req_011r3")],
                       to: proj.appendingPathComponent("only.jsonl"))
        let index = LogIndex()
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(account(index, "r1") == "vertex")
        #expect(account(index, "r2") == "vertex")
        #expect(account(index, "r3") == "max")
        #expect(stats.filesWithProfile == 1 && stats.filesWithoutProfile == 1)
    }

    /// CodeRabbit review: a newly configured directory that a named line
    /// also mentions makes the line ambiguous, so the file is read again
    /// and its records fall back to the rules.
    @Test func newlyConfiguredDirectoryCanMakeANamedLineAmbiguous() throws {
        let root = try makeTempDirectory("profile-becomes-ambiguous")
        defer { try? FileManager.default.removeItem(at: root) }
        let extra = "/Users/tester/agent-profiles/extra/claude"
        try Self.write([Self.shapeNaming([Self.work, extra]), Self.record("r1", requestId: "req_011r1")],
                       to: root.appendingPathComponent("projects/p/s.jsonl"))
        let index = LogIndex()
        _ = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer, profiles: Self.candidates())
        #expect(account(index, "r1") == "vertex")
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates(extra: [.init(accountId: "lab", path: extra, rank: .additional)]))
        #expect(stats.filesRead == 1)
        #expect(account(index, "r1") == "max")
    }

    /// Codex review: a new alias of an already configured directory is a
    /// new spelling, so a line that named none through that alias is read
    /// again and now names the directory.
    @Test func newAliasSpellingRereadsUnnamedFiles() throws {
        let root = try makeTempDirectory("profile-alias-reread")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = "/Users/tester/agent-sessions/real/claude"
        let alias = "/Users/tester/agent-sessions/alias/claude"
        try Self.write([Self.shape(alias), Self.record("r1", requestId: "req_011r1")], to: root.appendingPathComponent("projects/p/s.jsonl"))
        let index = LogIndex()
        let labReal = Attributor(configuration: Self.configuration, paths: Self.paths, profileAdditionalDirectories: ["lab": [real]])
        let before = Self.candidates(extra: [.init(accountId: "lab", path: real, canonical: real, rank: .additional)])
        _ = index.update(files: scan(root), window: window, parser: parser, attributor: labReal, pricer: pricer, profiles: before)
        #expect(account(index, "r1") == "max")
        let after = Self.candidates(extra: [.init(accountId: "lab", path: real, canonical: real, rank: .additional),
                                            .init(accountId: "lab", path: alias, canonical: real, rank: .additional)])
        #expect(after.key != before.key)
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: labReal, pricer: pricer, profiles: after)
        #expect(stats.filesRead == 1)
        #expect(account(index, "r1") == "lab")
    }

    /// US1, SC-001, SC-005 end to end: three profile directories whose
    /// `projects` link to one shared folder, refreshed through the source.
    @Test func sharedProjectsFolderThroughTheSource() async throws {
        let root = try makeTempDirectory("profile-shared-source")
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appendingPathComponent(".claude/projects")
        let proj = shared.appendingPathComponent("-proj")
        var dirs: [String: String] = [:]
        for name in ["personal", "work", "lab"] {
            let dir = root.appendingPathComponent("agent-profiles/\(name)/claude")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("projects"), withDestinationURL: shared)
            dirs[name] = dir.path
        }
        try Self.write([Self.shape(dirs["personal"]!), Self.record("p1", requestId: "req_vrtx_p1")], to: proj.appendingPathComponent("a.jsonl"))
        try Self.write([Self.shape(dirs["work"]!), Self.record("w1", requestId: "req_vrtx_w1")], to: proj.appendingPathComponent("b.jsonl"))
        try Self.write([Self.shape(dirs["lab"]!), Self.record("l1", model: "intranet/glm-5")], to: proj.appendingPathComponent("c.jsonl"))
        let config = Configuration(accounts: [
            Account(id: "max", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: "~/agent-profiles/personal/claude"))),
            Account(id: "vertex", displayName: "Vertex",
                    kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), sessionKind: .claudeCodeVertex, sessionDirectory: "~/agent-profiles/work/claude"))),
            Account(id: "lab", displayName: "Lab",
                    kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), sessionKind: .claudeCodeDirectoryOnly,
                                                         sessionDirectory: "~/agent-profiles/lab/claude"))),
        ], groups: [BudgetGroup(id: "grp", name: "Team", budgetUSD: 100)])
        let logURL = root.appendingPathComponent("usage.log")
        let source = try SessionLogSource(paths: Paths(home: root), log: DiagnosticLog(fileURL: logURL), builtInPrices: pricer)
        let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
        let context = RefreshContext(configuration: config, window: window, now: Date())
        guard case .records(let records) = try await source.collect(context: context) else {
            Issue.record("expected records")
            return
        }
        #expect(records.count == 3)
        #expect(records.first { $0.messageId == "msg_p1" }?.accountId == "max")
        #expect(records.first { $0.messageId == "msg_w1" }?.accountId == "vertex")
        #expect(records.first { $0.messageId == "msg_l1" }?.accountId == "lab")
        _ = try await source.collect(context: context)
        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("profile named 3, none 0"))
        #expect(log.contains("re-read 0 (0 bytes)"))
        #expect(!log.contains(Self.marker))
    }

    /// Re-review: a removed directory lets a line that named two name one,
    /// so the file is read again.
    @Test func removedDirectoryLetsAnAmbiguousLineNameOne() throws {
        let root = try makeTempDirectory("profile-ambiguous-shrinks")
        defer { try? FileManager.default.removeItem(at: root) }
        let extra = "/Users/tester/agent-profiles/extra/claude"
        try Self.write([Self.shapeNaming([Self.work, extra]), Self.record("r1", requestId: "req_011r1")],
                       to: root.appendingPathComponent("projects/p/s.jsonl"))
        let index = LogIndex()
        _ = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                         profiles: Self.candidates(extra: [.init(accountId: "lab", path: extra, rank: .additional)]))
        #expect(account(index, "r1") == "max")
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: attributor, pricer: pricer,
                                 profiles: Self.candidates())
        #expect(stats.filesRead == 1)
        #expect(account(index, "r1") == "vertex")
    }

    /// Re-review: a directory keeps its claimants but loses the spelling a
    /// line named it through, so the file is read again and its records
    /// fall back to the rules.
    @Test func lostSpellingRereadsFilesThatNamedIt() throws {
        let root = try makeTempDirectory("profile-lost-spelling")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = "/Users/tester/agent-sessions/real/claude"
        let alias = "/Users/tester/agent-sessions/alias/claude"
        try Self.write([Self.shape(alias), Self.record("r1", requestId: "req_011r1")], to: root.appendingPathComponent("projects/p/s.jsonl"))
        let index = LogIndex()
        let labReal = Attributor(configuration: Self.configuration, paths: Self.paths, profileAdditionalDirectories: ["lab": [real]])
        let withAlias = Self.candidates(extra: [.init(accountId: "lab", path: real, canonical: real, rank: .additional),
                                                .init(accountId: "lab", path: alias, canonical: real, rank: .additional)])
        _ = index.update(files: scan(root), window: window, parser: parser, attributor: labReal, pricer: pricer, profiles: withAlias)
        #expect(account(index, "r1") == "lab")
        let withoutAlias = Self.candidates(extra: [.init(accountId: "lab", path: real, canonical: real, rank: .additional)])
        #expect(withoutAlias.claimKey(forDirectory: real) == withAlias.claimKey(forDirectory: real))
        let stats = index.update(files: scan(root), window: window, parser: parser, attributor: labReal, pricer: pricer,
                                 profiles: withoutAlias)
        #expect(stats.filesRead == 1)
        #expect(account(index, "r1") == "max")
    }
}

/// spec 038 US2 scenarios 1 to 4, research R9: records of a company gateway
/// (no request id) read through `SessionLogSource` count for kind Other
/// provider; Directory only counts only sessions from its directory.
@Suite struct GatewaySessionTests {
    let pricer = try! PriceTable.builtIn()

    private func records(_ accounts: [Account], file: (URL) throws -> Void) async throws -> [UsageRecord] {
        let root = try makeTempDirectory("gateway-session")
        defer { try? FileManager.default.removeItem(at: root) }
        try file(root)
        let config = Configuration(accounts: accounts, groups: [BudgetGroup(id: "grp", name: "Team", budgetUSD: 100)])
        let source = try SessionLogSource(paths: Paths(home: root), log: DiagnosticLog(fileURL: root.appendingPathComponent("usage.log")),
                                          builtInPrices: pricer)
        let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
        guard case .records(let records) = try await source.collect(context: RefreshContext(configuration: config, window: window, now: Date())) else {
            Issue.record("expected records")
            return []
        }
        return records
    }

    private func token(_ id: String, _ kind: SessionKind, _ dir: String? = nil) -> Account {
        Account(id: id, displayName: id, kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false),
                                                                              sessionKind: kind, sessionDirectory: dir)))
    }

    /// The fixture in `~/.claude/projects`, read by the Vertex account on
    /// the default directory.
    private func installDefault(_ root: URL) throws {
        try Fixtures.install("gateway-session.jsonl", into: root.appendingPathComponent(".claude"), as: "-proj/gw.jsonl")
    }

    @Test func gatewayRecordsCountForOtherProvider() async throws {
        let all = try await records([token("gw", .claudeCodeOtherProvider, "~/.claude-gateway"), token("vertex", .claudeCodeVertex)],
                                    file: installDefault)
        // The parser drops the zero-usage `<synthetic>` placeholder.
        #expect(all.count == 4)
        #expect(!all.contains { $0.model == "<synthetic>" })
        #expect(all.filter { $0.model == "intranet/glm-5" }.allSatisfy { $0.accountId == "gw" })
        #expect(all.filter { $0.model == "intranet/glm-5" }.count == 2)
        #expect(all.first { $0.requestId == "req_vrtx_g1" }?.accountId == "vertex")
        // A direct record without a Claude subscription stays Unassigned.
        #expect(all.first { $0.requestId == "req_011g1" }?.accountId == nil)
    }

    @Test func directoryOnlyCountsOnlyItsDirectory() async throws {
        let all = try await records([token("lab", .claudeCodeDirectoryOnly, "~/.claude-gateway"), token("vertex", .claudeCodeVertex)],
                                    file: installDefault)
        #expect(!all.contains { $0.accountId == "lab" })
        #expect(all.first { $0.requestId == "req_vrtx_g1" }?.accountId == "vertex")
        // A session file whose request shape line names the account's
        // directory counts for it, whatever its records' kinds.
        let named = try await records([token("lab", .claudeCodeDirectoryOnly, "~/.claude-gateway"), token("vertex", .claudeCodeVertex)]) { root in
            let lab = root.appendingPathComponent(".claude-gateway")
            let lines = try Fixtures.lines("gateway-session.jsonl")
            try LogIndexProfileTests.write([LogIndexProfileTests.shape(lab.path)] + lines,
                                           to: lab.appendingPathComponent("projects/-proj/gw.jsonl"))
        }
        #expect(named.count == 4)
        #expect(named.allSatisfy { $0.accountId == "lab" })
    }
}
