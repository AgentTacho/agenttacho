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
        c.accounts = [Account(id: "acc-vertex", label: "VC", displayName: "Vertex",
                              kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex)))]
        c.groups = [BudgetGroup(id: "grp", name: "Vertex", label: "V", weeklyBudgetUSD: 60)]
        return c
    }

    private func attributor() -> Attributor { Attributor(configuration: vertexConfig()) }

    private func writeRecords(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    private func record(id: String, at timestamp: String, output: Int = 10) -> String {
        """
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"req_vrtx_\(id)","uuid":"\(id)","sessionId":"s","message":{"id":"msg_vrtx_\(id)","model":"claude-opus-4-6","role":"assistant","content":[],"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":\(output)}}}
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
        config.accounts.append(Account(id: "acc-eu", label: "EU", displayName: "Vertex EU",
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
            Account(id: "acc-max", label: "M", displayName: "Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: []))),
            Account(id: "acc-work", label: "W", displayName: "Work",
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
        #expect(logText.contains("records in window 4"))
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
