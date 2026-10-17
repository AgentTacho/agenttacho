import Foundation
import SQLite3
import Testing
@testable import UsageCore

/// A writable OpenCode database with the `session` and `message` columns
/// AgentTacho reads (contracts/harness-formats.md). Test-only: AgentTacho
/// itself never writes to an OpenCode database.
final class OpenCodeFixtureDB {
    let url: URL
    private var db: OpaquePointer?

    /// `journalMode` is `WAL` like OpenCode itself, or `DELETE` where a test
    /// needs a writer lock that blocks readers.
    init(directory: URL, journalMode: String = "DELETE") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("opencode.db")
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw FixtureError(message: "cannot create \(url.path)")
        }
        try exec("PRAGMA journal_mode=\(journalMode)")
        try exec("PRAGMA wal_autocheckpoint=0")
        try exec("CREATE TABLE session (id text PRIMARY KEY, directory text NOT NULL)")
        try exec("""
        CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL,
                              time_updated integer NOT NULL, data text NOT NULL)
        """)
    }

    deinit { sqlite3_close(db) }

    struct FixtureError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw FixtureError(message: "\(sql): \(message)")
        }
    }

    func addSession(_ id: String, directory: String) throws {
        try run("INSERT OR REPLACE INTO session (id, directory) VALUES (?1, ?2)", [id, directory])
    }

    /// Inserts or replaces a message row.
    func putMessage(id: String, session: String = "ses_1", updated: Int64, data: String) throws {
        try run("INSERT OR REPLACE INTO message (id, session_id, time_created, time_updated, data) VALUES (?1, ?2, ?3, ?3, ?4)",
                [id, session, updated, data])
    }

    private func run(_ sql: String, _ values: [Any]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw FixtureError(message: "prepare \(sql)") }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, value) in values.enumerated() {
            if let text = value as? String {
                sqlite3_bind_text(stmt, Int32(i + 1), text, -1, transient)
            } else if let number = value as? Int64 {
                sqlite3_bind_int64(stmt, Int32(i + 1), number)
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw FixtureError(message: "step \(sql)") }
    }

    /// The JSON of an assistant message as OpenCode stores it.
    static func assistant(provider: String = "google-vertex", model: String = "claude-opus-4-6@default",
                          created: Int64, completed: Int64?, input: Int = 0, output: Int = 0, reasoning: Int = 0,
                          cacheRead: Int = 0, cacheWrite: Int = 0, cwd: String? = "/tmp/oc-project",
                          cost: Double = 99, error: Bool = false) -> String {
        var time: [String: Any] = ["created": created]
        if let completed { time["completed"] = completed }
        var object: [String: Any] = [
            "role": "assistant", "providerID": provider, "modelID": model, "time": time, "cost": cost,
            "tokens": ["total": input + output + reasoning + cacheRead + cacheWrite, "input": input, "output": output,
                       "reasoning": reasoning, "cache": ["read": cacheRead, "write": cacheWrite]],
            "mode": "build", "agent": "build", "parentID": "msg_parent",
        ]
        if let cwd { object["path"] = ["cwd": cwd, "root": cwd] }
        if error { object["error"] = ["name": "APIError", "data": ["message": "overloaded"]] }
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func user(created: Int64) -> String {
        "{\"role\":\"user\",\"time\":{\"created\":\(created)},\"agent\":\"build\"}"
    }
}

/// Milliseconds since 1970 for an ISO date.
func ms(_ text: String) -> Int64 { Int64(isoDate(text).timeIntervalSince1970 * 1000) }

@Suite struct OpenCodeSourceTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")

    struct Setup {
        let home: URL
        let dataDir: URL
        let db: OpenCodeFixtureDB
        let source: OpenCodeSource
        let logURL: URL
    }

    func setup(_ name: String) throws -> Setup {
        let home = try makeTempDirectory("opencode-\(name)")
        let dataDir = home.appendingPathComponent(".local/share/opencode")
        let db = try OpenCodeFixtureDB(directory: dataDir)
        try db.addSession("ses_1", directory: "/tmp/session-dir")
        let logURL = home.appendingPathComponent("usage.log")
        let source = try OpenCodeSource(paths: Paths(home: home), log: DiagnosticLog(fileURL: logURL))
        return Setup(home: home, dataDir: dataDir, db: db, source: source, logURL: logURL)
    }

    func vertexConfig() -> Configuration {
        Configuration(accounts: [
            Account(id: "acc-vertex", displayName: "Vertex",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 60)), provider: .vertex))),
        ])
    }

    func collect(_ source: OpenCodeSource, _ configuration: Configuration = Configuration()) async throws -> RecordBatch {
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window, now: now))
        guard case .recordBatch(let batch) = output else {
            Issue.record("expected a record batch")
            return RecordBatch()
        }
        return batch
    }

    @Test func onlyCompletedAssistantMessagesCount() async throws {
        let s = try setup("completed")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "msg_user", updated: t, data: OpenCodeFixtureDB.user(created: t))
        try s.db.putMessage(id: "msg_open", updated: t + 1, data: OpenCodeFixtureDB.assistant(created: t, completed: nil, input: 5))
        try s.db.putMessage(id: "msg_done", updated: t + 2,
                            data: OpenCodeFixtureDB.assistant(created: t, completed: t + 5_000, input: 3, output: 22, reasoning: 7,
                                                              cacheRead: 17_008, cacheWrite: 22))
        let batch = try await collect(s.source)
        #expect(batch.issues.isEmpty)
        #expect(batch.staleHarnesses.isEmpty)
        #expect(batch.records.count == 1)
        let r = try #require(batch.records.first)
        #expect(r.messageId == "msg_done")
        #expect(r.harness == .openCode)
        #expect(r.timestamp == Date(timeIntervalSince1970: TimeInterval(t + 5_000) / 1000))
        #expect(r.inputTokens == 3)
        #expect(r.outputTokens == 29)
        #expect(r.reasoningTokens == 7)
        #expect(r.cacheReadTokens == 17_008)
        #expect(r.cacheWrite5mTokens == 22)
        #expect(r.cacheWrite1hTokens == 0)
        #expect(r.requestId == "")
        #expect(r.model == "claude-opus-4-6@default")
        #expect(r.canonicalModel == "claude-opus-4-6")
    }

    /// FR-019: OpenCode's own cost is ignored.
    @Test func costComesFromThePriceTable() async throws {
        let s = try setup("cost")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "m1", updated: t,
                            data: OpenCodeFixtureDB.assistant(created: t, completed: t + 1, input: 1_000, output: 2_000, reasoning: 500,
                                                              cacheRead: 3_000, cacheWrite: 400, cost: 123.45))
        let batch = try await collect(s.source)
        let expected = try PriceTable.builtIn().cost(model: "claude-opus-4-6", input: 1_000, output: 2_500, cacheWrite5m: 400,
                                                     cacheWrite1h: 0, cacheRead: 3_000)
        #expect(expected != nil)
        #expect(batch.records.first?.costUSD == expected)
    }

    /// FR-019, FR-004: a price override added later re-prices the stored
    /// messages without reading rows again.
    @Test func priceOverrideRepricesStoredMessages() async throws {
        let s = try setup("reprice")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "m1", updated: t,
                            data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1_000, output: 2_000))
        var configuration = vertexConfig()
        let before = try await collect(s.source, configuration)
        let override = PriceEntry(model: "claude-opus-4-6", inputPerMTok: 1, outputPerMTok: 1, cacheWrite5mPerMTok: 1,
                                  cacheWrite1hPerMTok: 1, cacheReadPerMTok: 1)
        configuration.priceOverrides = [override]
        let after = try await collect(s.source, configuration)
        #expect(await s.source.lastRowsRead == 0)
        #expect(after.records.first?.costUSD == PriceTable.cost(input: 1_000, output: 2_000, cacheWrite5m: 0, cacheWrite1h: 0,
                                                                cacheRead: 0, price: override))
        #expect(after.records.first?.costUSD != before.records.first?.costUSD)
    }

    /// OpenCode runs in WAL mode: rows that are committed but not yet
    /// checkpointed are read, and an open write transaction neither blocks
    /// the refresh nor makes it stale (FR-005, SC-004).
    @Test func walDatabaseWithOpenWriterIsRead() async throws {
        let home = try makeTempDirectory("opencode-wal")
        defer { try? FileManager.default.removeItem(at: home) }
        let db = try OpenCodeFixtureDB(directory: home.appendingPathComponent(".local/share/opencode"), journalMode: "WAL")
        try db.addSession("ses_1", directory: "/tmp/session-dir")
        let t = ms("2026-10-12T10:00:00Z")
        try db.putMessage(id: "m1", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 10))
        let source = try OpenCodeSource(paths: Paths(home: home))
        let first = try await collect(source)
        #expect(first.records.map(\.messageId) == ["m1"])

        try db.exec("BEGIN IMMEDIATE")
        try db.putMessage(id: "m2", updated: t + 10, data: OpenCodeFixtureDB.assistant(created: t, completed: t + 10, input: 20))
        let during = try await collect(source)
        #expect(during.staleHarnesses.isEmpty)
        #expect(during.issues.isEmpty)
        #expect(during.records.map(\.messageId) == ["m1"])
        try db.exec("COMMIT")

        let after = try await collect(source)
        #expect(after.records.map(\.messageId) == ["m1", "m2"])
    }

    /// With OpenCode not running (no WAL file), reading creates no `-wal` or
    /// `-shm` side files in OpenCode's directory (contracts/harness-formats.md).
    @Test func readingAClosedWalDatabaseCreatesNoSideFiles() async throws {
        let home = try makeTempDirectory("opencode-closed")
        defer { try? FileManager.default.removeItem(at: home) }
        let dir = home.appendingPathComponent(".local/share/opencode")
        let t = ms("2026-10-12T10:00:00Z")
        do {
            // Closing the last writer checkpoints and removes the WAL files.
            let db = try OpenCodeFixtureDB(directory: dir, journalMode: "WAL")
            try db.addSession("ses_1", directory: "/tmp/session-dir")
            try db.putMessage(id: "m1", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 10))
            try db.exec("PRAGMA wal_checkpoint(TRUNCATE)")
        }
        let wal = dir.appendingPathComponent("opencode.db-wal").path
        let shm = dir.appendingPathComponent("opencode.db-shm").path
        // The checkpoint moved every row into the main file; remove what the
        // fixture writer left behind, as after OpenCode quits.
        try? FileManager.default.removeItem(atPath: wal)
        try? FileManager.default.removeItem(atPath: shm)
        #expect(OpenCodeSource.isWalDatabase(path: dir.appendingPathComponent("opencode.db").path))
        #expect(OpenCodeSource.openTarget(path: dir.appendingPathComponent("opencode.db").path).hasSuffix("?immutable=1"))

        let source = try OpenCodeSource(paths: Paths(home: home))
        let result = try await collect(source)
        #expect(result.records.map(\.messageId) == ["m1"])
        #expect(!FileManager.default.fileExists(atPath: wal))
        #expect(!FileManager.default.fileExists(atPath: shm))
    }

    /// The first read starts near the window start, not at the beginning of
    /// the history; rows around the boundary still count by completion time.
    @Test func firstReadSkipsHistoryBeforeTheWindow() async throws {
        let s = try setup("first-read")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let start = ms("2026-10-12T00:00:00Z")
        let old = start - 2 * OpenCodeSource.readMarginMilliseconds
        try s.db.putMessage(id: "old", updated: old, data: OpenCodeFixtureDB.assistant(created: old, completed: old, input: 1))
        try s.db.putMessage(id: "before", updated: start - 1, data: OpenCodeFixtureDB.assistant(created: start - 1, completed: start - 1, input: 2))
        try s.db.putMessage(id: "at", updated: start, data: OpenCodeFixtureDB.assistant(created: start, completed: start, input: 3))
        try s.db.putMessage(id: "after", updated: start + 1, data: OpenCodeFixtureDB.assistant(created: start, completed: start + 1, input: 4))
        let batch = try await collect(s.source)
        // The old row lies outside the read margin and is never handed over.
        #expect(await s.source.lastRowsRead == 3)
        #expect(batch.records.map(\.messageId) == ["at", "after"])
    }

    /// A row with out-of-range token values is clamped, not trapped on.
    @Test func hugeTokenValuesDoNotTrap() async throws {
        let s = try setup("huge")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        let data = """
        {"role":"assistant","providerID":"google-vertex","modelID":"claude-opus-4-6","time":{"created":\(t),"completed":\(t)},"tokens":{"input":1e300,"output":-1,"reasoning":1e19,"cache":{"read":1,"write":0}}}
        """
        try s.db.putMessage(id: "huge", updated: t, data: data)
        let batch = try await collect(s.source)
        #expect(batch.records.count == 1)
        #expect(batch.records.first?.cacheReadTokens == 1)
    }

    /// Edge case "Harness removed": a deleted database takes its records with it.
    @Test func removedDatabaseStopsCounting() async throws {
        let s = try setup("removed")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "m1", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 10))
        #expect(try await collect(s.source).records.count == 1)
        try FileManager.default.removeItem(at: s.dataDir)
        let batch = try await collect(s.source)
        #expect(batch.records.isEmpty)
        #expect(batch.issues.isEmpty)
    }

    @Test func cwdFallsBackToSessionDirectory() async throws {
        let s = try setup("cwd")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "with", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1, cwd: "/tmp/own-cwd"))
        try s.db.putMessage(id: "without", updated: t + 1, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1, cwd: nil))
        let batch = try await collect(s.source)
        let byId = Dictionary(uniqueKeysWithValues: batch.records.map { ($0.messageId, $0) })
        #expect(byId["with"]?.project?.rootPath == "/tmp/own-cwd")
        #expect(byId["without"]?.project?.rootPath == "/tmp/session-dir")
    }

    /// FR-010: a cwd inside a git repository resolves to the repository.
    @Test func cwdInsideGitRepositoryResolvesToProject() async throws {
        let s = try setup("git")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let repo = s.home.appendingPathComponent("work/myrepo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("src"), withIntermediateDirectories: true)
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "m", updated: t,
                            data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1, cwd: repo.appendingPathComponent("src").path))
        let batch = try await collect(s.source)
        #expect(batch.records.first?.project?.rootPath == repo.path)
        #expect(batch.records.first?.project?.name == "myrepo")
    }

    @Test func providerHintAndSessionIdComeFromTheRow() async throws {
        let s = try setup("hint")
        defer { try? FileManager.default.removeItem(at: s.home) }
        try s.db.addSession("ses_other", directory: "/tmp/other")
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "v", updated: t, data: OpenCodeFixtureDB.assistant(provider: "google-vertex", created: t, completed: t, input: 1))
        try s.db.putMessage(id: "l", session: "ses_other", updated: t + 1,
                            data: OpenCodeFixtureDB.assistant(provider: "litellm", created: t, completed: t, input: 1))
        _ = try await collect(s.source, vertexConfig())
        let raws = await s.source.rawRecords
        #expect(raws["v"]?.providerHint == "google-vertex")
        #expect(raws["v"]?.sessionId == "ses_1")
        #expect(raws["l"]?.providerHint == "litellm")
        #expect(raws["l"]?.sessionId == "ses_other")
        #expect(raws["l"]?.harness == .openCode)
    }

    @Test func vertexProviderIsAttributedToTheVertexAccount() async throws {
        let s = try setup("attribution")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "v", updated: t, data: OpenCodeFixtureDB.assistant(provider: "google-vertex", created: t, completed: t, input: 1))
        try s.db.putMessage(id: "l", updated: t + 1, data: OpenCodeFixtureDB.assistant(provider: "litellm", created: t, completed: t, input: 1))
        let batch = try await collect(s.source, vertexConfig())
        let byId = Dictionary(uniqueKeysWithValues: batch.records.map { ($0.messageId, $0) })
        #expect(byId["v"]?.accountId == "acc-vertex")
        #expect(byId["l"] != nil)
        #expect(byId["l"]?.accountId == nil)
    }

    @Test func updatedMessageReplacesItsRecord() async throws {
        let s = try setup("update")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "m", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: nil, input: 10))
        #expect(try await collect(s.source).records.isEmpty)
        try s.db.putMessage(id: "m", updated: t + 10, data: OpenCodeFixtureDB.assistant(created: t, completed: t + 9, input: 10, output: 5))
        let second = try await collect(s.source)
        #expect(second.records.count == 1)
        #expect(second.records.first?.outputTokens == 5)
        try s.db.putMessage(id: "m", updated: t + 20, data: OpenCodeFixtureDB.assistant(created: t, completed: t + 9, input: 10, output: 8))
        let third = try await collect(s.source)
        #expect(third.records.count == 1)
        #expect(third.records.first?.outputTokens == 8)
    }

    /// FR-004: after the first read only changed rows are read.
    @Test func unchangedDatabaseReadsNoRows() async throws {
        let s = try setup("watermark")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        for i in 0..<3 {
            try s.db.putMessage(id: "m\(i)", updated: t + Int64(i), data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1))
        }
        #expect(try await collect(s.source).records.count == 3)
        #expect(await s.source.lastRowsRead == 3)
        #expect(try await collect(s.source).records.count == 3)
        #expect(await s.source.lastRowsRead == 0)
        try s.db.putMessage(id: "m3", updated: t + 10, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1))
        #expect(try await collect(s.source).records.count == 4)
        #expect(await s.source.lastRowsRead == 1)
    }

    /// A row committed later in the same millisecond as the watermark is
    /// still read; rows already read at the watermark are not counted again.
    @Test func rowInTheWatermarkMillisecondIsNotMissed() async throws {
        let s = try setup("same-ms")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "a", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1))
        #expect(try await collect(s.source).records.count == 1)
        try s.db.putMessage(id: "b", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1))
        #expect(try await collect(s.source).records.count == 2)
        #expect(await s.source.lastRowsRead == 1)
        #expect(try await collect(s.source).records.count == 2)
        #expect(await s.source.lastRowsRead == 0)
    }

    /// Deleted messages (for example with their session) stop counting.
    @Test func deletedMessageStopsCounting() async throws {
        let s = try setup("deleted")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "keep", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1))
        try s.db.putMessage(id: "gone", updated: t + 1, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1))
        #expect(try await collect(s.source).records.count == 2)
        try s.db.exec("DELETE FROM message WHERE id = 'gone'")
        #expect(try await collect(s.source).records.map(\.messageId) == ["keep"])
    }

    /// FR-005, SC-004: a locked database keeps the previous records, stale.
    @Test func lockedDatabaseReturnsPreviousRecordsAsStale() async throws {
        let s = try setup("locked")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "m", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 4))
        #expect(try await collect(s.source).records.count == 1)

        try s.db.putMessage(id: "m2", updated: t + 1, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 4))
        try s.db.exec("BEGIN EXCLUSIVE")
        let locked = try await collect(s.source)
        #expect(locked.records.map(\.messageId) == ["m"])
        #expect(locked.staleHarnesses == [.openCode])
        #expect(locked.issues.count == 1)
        #expect(locked.issues.first?.contains("OpenCode") == true)
        try s.db.exec("COMMIT")

        let after = try await collect(s.source)
        #expect(after.records.count == 2)
        #expect(after.issues.isEmpty)
        #expect(after.staleHarnesses.isEmpty)
    }

    @Test func missingDatabaseYieldsNothing() async throws {
        let home = try makeTempDirectory("opencode-missing")
        defer { try? FileManager.default.removeItem(at: home) }
        let source = try OpenCodeSource(paths: Paths(home: home))
        let batch = try await collect(source)
        #expect(batch.records.isEmpty)
        #expect(batch.issues.isEmpty)
        #expect(batch.staleHarnesses.isEmpty)
    }

    @Test func erroredMessageCountsAndZeroTokenMessageDoesNot() async throws {
        let s = try setup("errors")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "err", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 12, error: true))
        try s.db.putMessage(id: "zero", updated: t + 1, data: OpenCodeFixtureDB.assistant(created: t, completed: t))
        let batch = try await collect(s.source)
        #expect(batch.records.map(\.messageId) == ["err"])
        #expect(batch.records.first?.inputTokens == 12)
    }

    @Test func recordsBeforeTheWindowArePruned() async throws {
        let s = try setup("prune")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let old = ms("2026-10-01T10:00:00Z")
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "old", updated: t, data: OpenCodeFixtureDB.assistant(created: old, completed: old, input: 1))
        try s.db.putMessage(id: "new", updated: t + 1, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1))
        #expect(try await collect(s.source).records.map(\.messageId) == ["new"])
    }

    /// Adding an account changes the attributor fingerprint: stored records
    /// are re-attributed without reading rows again.
    @Test func fingerprintChangeReattributesWithoutRereading() async throws {
        let s = try setup("fingerprint")
        defer { try? FileManager.default.removeItem(at: s.home) }
        let t = ms("2026-10-12T10:00:00Z")
        try s.db.putMessage(id: "v", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1))
        #expect(try await collect(s.source).records.first?.accountId == nil)
        let second = try await collect(s.source, vertexConfig())
        #expect(await s.source.lastRowsRead == 0)
        #expect(second.records.first?.accountId == "acc-vertex")
    }
}

/// spec 006 FR-003, FR-006, US4.
@Suite struct OpenCodeLocationTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")

    func collect(_ source: OpenCodeSource, _ configuration: Configuration) async throws -> RecordBatch {
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window, now: now))
        guard case .recordBatch(let batch) = output else { return RecordBatch() }
        return batch
    }

    @Test func missingConfiguredDirectoryIsAnIssue() async throws {
        let home = try makeTempDirectory("opencode-missing-extra")
        defer { try? FileManager.default.removeItem(at: home) }
        let db = try OpenCodeFixtureDB(directory: home.appendingPathComponent(".local/share/opencode"))
        try db.addSession("ses_1", directory: "/tmp/x")
        let t = ms("2026-10-12T10:00:00Z")
        try db.putMessage(id: "m", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1))
        let source = try OpenCodeSource(paths: Paths(home: home))
        var configuration = Configuration()
        configuration.openCodeDirectories = ["~/no-such-opencode"]
        let batch = try await collect(source, configuration)
        #expect(batch.records.count == 1)
        #expect(batch.issues.count == 1)
        #expect(batch.issues.first?.contains("OpenCode") == true)
        #expect(batch.issues.first?.contains("no-such-opencode") == true)
        #expect(batch.staleHarnesses.isEmpty)
    }

    @Test func twoPathsToTheSameDatabaseAreReadOnce() async throws {
        let home = try makeTempDirectory("opencode-twice")
        defer { try? FileManager.default.removeItem(at: home) }
        let dataDir = home.appendingPathComponent(".local/share/opencode")
        let db = try OpenCodeFixtureDB(directory: dataDir)
        try db.addSession("ses_1", directory: "/tmp/x")
        let t = ms("2026-10-12T10:00:00Z")
        try db.putMessage(id: "m", updated: t, data: OpenCodeFixtureDB.assistant(created: t, completed: t, input: 1))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("oc-link"), withDestinationURL: dataDir)
        let source = try OpenCodeSource(paths: Paths(home: home))
        var configuration = Configuration()
        configuration.openCodeDirectories = ["~/oc-link", "~/.local/share/opencode/"]
        let batch = try await collect(source, configuration)
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 1)
        #expect(await source.lastRowsRead == 1)
    }

    /// FR-022: one diagnostic line per location, with counts or the reason.
    @Test func logNamesEveryLocation() async throws {
        let home = try makeTempDirectory("opencode-log")
        defer { try? FileManager.default.removeItem(at: home) }
        let logURL = home.appendingPathComponent("usage.log")
        let source = try OpenCodeSource(paths: Paths(home: home), log: DiagnosticLog(fileURL: logURL))
        var configuration = Configuration()
        configuration.openCodeDirectories = ["~/no-such-opencode"]
        _ = try await collect(source, configuration)
        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text.contains("[opencode] \(home.path)/.local/share/opencode: skipped, OpenCode not installed"))
        #expect(text.contains("[opencode] \(home.path)/no-such-opencode: error: data directory not found"))
    }
}

/// Counts calls of the `counter` SQL function the hardening tests register.
final class SQLCallCounter: @unchecked Sendable {
    var calls = 0
}

/// Registers `counter(x)`, which returns `x` and counts its calls. It is
/// neither innocuous nor direct-only, so an untrusted schema must not call
/// it. Deterministic, as generated columns require. The connection keeps
/// `counter` alive until it closes.
@discardableResult
func registerCounter(_ db: OpaquePointer, _ counter: SQLCallCounter) -> Int32 {
    let function: @convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void = { context, argc, argv in
        if let data = sqlite3_user_data(context) {
            Unmanaged<SQLCallCounter>.fromOpaque(data).takeUnretainedValue().calls += 1
        }
        if argc > 0, let value = argv?[0] { sqlite3_result_value(context, value) } else { sqlite3_result_null(context) }
    }
    let destroy: @convention(c) (UnsafeMutableRawPointer?) -> Void = { data in
        if let data { Unmanaged<SQLCallCounter>.fromOpaque(data).release() }
    }
    return sqlite3_create_function_v2(db, "counter", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC,
                                      Unmanaged.passRetained(counter).toOpaque(), function, nil, nil, destroy)
}

/// A virtual table module `prob` whose connect counts its calls and fails.
/// SQLite keeps a pointer to the module, so it lives for the whole run.
private let probeModule: UnsafeMutablePointer<sqlite3_module> = {
    let module = UnsafeMutablePointer<sqlite3_module>.allocate(capacity: 1)
    module.initialize(to: sqlite3_module())
    module.pointee.xConnect = { _, aux, _, _, _, _ in
        if let aux { Unmanaged<SQLCallCounter>.fromOpaque(aux).takeUnretainedValue().calls += 1 }
        return SQLITE_ERROR
    }
    return module
}()

/// Registers `prob` on `db`, counting its connects in `counter`.
@discardableResult
func registerProbeModule(_ db: OpaquePointer, _ counter: SQLCallCounter) -> Int32 {
    let destroy: @convention(c) (UnsafeMutableRawPointer?) -> Void = { data in
        if let data { Unmanaged<SQLCallCounter>.fromOpaque(data).release() }
    }
    return sqlite3_create_module_v2(db, "prob", probeModule, Unmanaged.passRetained(counter).toOpaque(), destroy)
}

/// Spec 015 FR-008, FR-009, SC-004, research R4: the OpenCode database is
/// read with untrusted schema code disabled, and `message` and `session`
/// must be tables, not views.
@Suite struct OpenCodeHardeningTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")

    enum Craft { case messageView, sessionView, generatedData, virtualMessage }

    /// A crafted `opencode.db` in `directory` with one completed assistant
    /// message whose data passes through `counter`.
    func craft(_ kind: Craft, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("opencode.db")
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            throw OpenCodeFixtureDB.FixtureError(message: "cannot create \(url.path)")
        }
        defer { sqlite3_close(db) }
        registerCounter(db, SQLCallCounter())
        let t = ms("2026-10-12T10:00:00Z")
        let data = OpenCodeFixtureDB.assistant(created: t, completed: t + 1_000, input: 3, output: 5)
            .replacingOccurrences(of: "'", with: "''")
        let statements: [String]
        switch kind {
        case .messageView:
            statements = [
                "CREATE TABLE session (id text PRIMARY KEY, directory text NOT NULL)",
                "CREATE TABLE raw (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)",
                "CREATE VIEW message AS SELECT id, session_id, time_created, time_updated, counter(data) AS data FROM raw",
                "INSERT INTO raw VALUES ('msg_1', 'ses_1', \(t), \(t), '\(data)')",
            ]
        case .sessionView:
            statements = [
                "CREATE TABLE raw_session (id text PRIMARY KEY, directory text NOT NULL)",
                "CREATE VIEW session AS SELECT id, counter(directory) AS directory FROM raw_session",
                "CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)",
                "INSERT INTO raw_session VALUES ('ses_1', '/tmp/session-dir')",
                "INSERT INTO message VALUES ('msg_1', 'ses_1', \(t), \(t), '\(data)')",
            ]
        case .generatedData:
            statements = [
                "CREATE TABLE session (id text PRIMARY KEY, directory text NOT NULL)",
                "CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, raw text NOT NULL, data text GENERATED ALWAYS AS (counter(raw)) VIRTUAL)",
                "INSERT INTO message (id, session_id, time_created, time_updated, raw) VALUES ('msg_1', 'ses_1', \(t), \(t), '\(data)')",
            ]
        case .virtualMessage:
            statements = [
                "CREATE TABLE session (id text PRIMARY KEY, directory text NOT NULL)",
                "CREATE VIRTUAL TABLE message USING fts5(id, session_id, time_created, time_updated, data)",
                "INSERT INTO message VALUES ('msg_1', 'ses_1', \(t), \(t), '\(data)')",
            ]
        }
        for sql in statements {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw OpenCodeFixtureDB.FixtureError(message: "\(sql): \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        return url
    }

    /// Reads through `readRows` with `counter` registered on the reader's
    /// connection; returns the error, if any.
    func readWithCounter(_ url: URL, _ counter: SQLCallCounter) -> Error? {
        do {
            _ = try OpenCodeSource.readRows(path: url.path, from: 0, liveSince: 0) { db in
                guard registerCounter(db, counter) == SQLITE_OK else { throw OpenCodeFixtureDB.FixtureError(message: "register") }
            }
            return nil
        } catch {
            return error
        }
    }

    @Test(arguments: [Craft.messageView, .sessionView])
    func viewsInPlaceOfTheTablesAreRefused(_ kind: Craft) throws {
        let dir = try makeTempDirectory("opencode-view")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try craft(kind, in: dir)
        let counter = SQLCallCounter()
        let error = readWithCounter(url, counter)
        #expect(error is OpenCodeSource.SQLiteError)
        #expect("\(error.map { "\($0)" } ?? "")".contains(kind == .messageView ? "message" : "session"))
        #expect(counter.calls == 0)
    }

    /// A virtual table is listed with type `table` in `sqlite_schema`, but
    /// its module code runs on data from the file, so it is refused too.
    /// The kind comes from the parsed schema, so a stored text spelled to
    /// dodge a text check ("CREATE<TAB>VIRTUAL TABLE", patched into the file
    /// as SQLite refuses to change its schema table) is refused too.
    @Test(arguments: [false, true])
    func virtualTableInPlaceOfMessageIsRefused(oddSpelling: Bool) throws {
        let dir = try makeTempDirectory("opencode-virtual")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try craft(.virtualMessage, in: dir)
        if oddSpelling {
            var bytes = try Data(contentsOf: url)
            let canonical = Data("CREATE VIRTUAL TABLE message".utf8)
            let range = try #require(bytes.range(of: canonical))
            bytes[range.lowerBound + 6] = 0x09
            try bytes.write(to: url)
            #expect(bytes.range(of: canonical) == nil)
        }
        let error = readWithCounter(url, SQLCallCounter())
        #expect(error is OpenCodeSource.SQLiteError)
        #expect("\(error.map { "\($0)" } ?? "")".contains("message is a virtual table"))
    }

    /// No module code runs, not even while the table check lists the
    /// schema: the file's `message` uses a module registered on the
    /// reader's connection (patched from `fts5` to `prob`), and its connect
    /// is never called.
    @Test func virtualTableModuleCodeNeverRuns() throws {
        let dir = try makeTempDirectory("opencode-module")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try craft(.virtualMessage, in: dir)
        var bytes = try Data(contentsOf: url)
        let range = try #require(bytes.range(of: Data("USING fts5(".utf8)))
        bytes.replaceSubrange(range, with: Data("USING prob(".utf8))
        try bytes.write(to: url)
        let connects = SQLCallCounter()
        let error: Error?
        do {
            _ = try OpenCodeSource.readRows(path: url.path, from: 0, liveSince: 0) { db in
                guard registerProbeModule(db, connects) == SQLITE_OK else { throw OpenCodeFixtureDB.FixtureError(message: "register") }
            }
            error = nil
        } catch let caught {
            error = caught
        }
        #expect("\(error.map { "\($0)" } ?? "")".contains("message is a virtual table"))
        #expect(connects.calls == 0)
    }

    /// Control case: without the hardening, listing the schema connects the
    /// module, so the test above cannot pass vacuously.
    @Test func listingTheSchemaConnectsTheModuleOnAPlainConnection() throws {
        let dir = try makeTempDirectory("opencode-module-control")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try craft(.virtualMessage, in: dir)
        var bytes = try Data(contentsOf: url)
        let range = try #require(bytes.range(of: Data("USING fts5(".utf8)))
        bytes.replaceSubrange(range, with: Data("USING prob(".utf8))
        try bytes.write(to: url)
        var db: OpaquePointer?
        #expect(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let connects = SQLCallCounter()
        #expect(registerProbeModule(try #require(db), connects) == SQLITE_OK)
        _ = sqlite3_exec(db, "SELECT name FROM pragma_table_list", nil, nil, nil)
        #expect(connects.calls > 0)
    }

    @Test func generatedColumnCallingAFunctionIsRefused() throws {
        let dir = try makeTempDirectory("opencode-generated")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try craft(.generatedData, in: dir)
        let counter = SQLCallCounter()
        let error = readWithCounter(url, counter)
        #expect(error is OpenCodeSource.SQLiteError)
        #expect("\(error.map { "\($0)" } ?? "")".contains("unsafe use of"))
        #expect(counter.calls == 0)
    }

    /// Control case: on a plain connection with `trusted_schema` on, the
    /// same database runs the function, so the tests above cannot pass
    /// vacuously.
    @Test func plainConnectionRunsTheSchemaFunction() throws {
        let dir = try makeTempDirectory("opencode-control")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try craft(.generatedData, in: dir)
        var db: OpaquePointer?
        #expect(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let counter = SQLCallCounter()
        #expect(registerCounter(try #require(db), counter) == SQLITE_OK)
        var stmt: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT data FROM message", -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(counter.calls > 0)
    }

    /// The source reports a refused database through the existing failed
    /// read path (spec 006 FR-005): an issue and the stale marker.
    @Test func sourceReportsARefusedDatabaseAsAFailedRead() async throws {
        let home = try makeTempDirectory("opencode-refused")
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try craft(.messageView, in: home.appendingPathComponent(".local/share/opencode"))
        let source = try OpenCodeSource(paths: Paths(home: home))
        let output = try await source.collect(context: RefreshContext(configuration: Configuration(), window: window, now: now))
        guard case .recordBatch(let batch) = output else {
            Issue.record("expected a record batch")
            return
        }
        #expect(batch.records.isEmpty)
        #expect(batch.staleHarnesses == [.openCode])
        #expect(batch.issues.count == 1)
        #expect(batch.issues.first?.contains("message") == true)
    }

    /// FR-009: a normal database reads the same rows.
    @Test func normalDatabaseReadsItsRows() throws {
        let dir = try makeTempDirectory("opencode-normal")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = try OpenCodeFixtureDB(directory: dir)
        try fixture.addSession("ses_1", directory: "/tmp/session-dir")
        let t = ms("2026-10-12T10:00:00Z")
        let data = OpenCodeFixtureDB.assistant(created: t, completed: t + 1_000, input: 3, output: 5)
        try fixture.putMessage(id: "msg_1", updated: t, data: data)
        try fixture.putMessage(id: "msg_2", updated: t + 5, data: OpenCodeFixtureDB.user(created: t))
        let read = try OpenCodeSource.readRows(path: fixture.url.path, from: 0, liveSince: t)
        #expect(read.rows.map(\.id) == ["msg_1", "msg_2"])
        #expect(read.rows.first?.data == data)
        #expect(read.rows.first?.sessionDirectory == "/tmp/session-dir")
        #expect(read.liveIds == ["msg_1", "msg_2"])
    }

    /// A trigger may share a table's name; the table check must still see
    /// the table (FR-009).
    @Test func triggerNamedLikeATableDoesNotHideIt() throws {
        let dir = try makeTempDirectory("opencode-trigger")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = try OpenCodeFixtureDB(directory: dir)
        try fixture.addSession("ses_1", directory: "/tmp/session-dir")
        try fixture.exec("CREATE TABLE audit (id text)")
        try fixture.exec("CREATE TRIGGER message AFTER INSERT ON message BEGIN INSERT INTO audit VALUES (new.id); END")
        try fixture.exec("CREATE TRIGGER session AFTER INSERT ON session BEGIN INSERT INTO audit VALUES (new.id); END")
        let t = ms("2026-10-12T10:00:00Z")
        try fixture.putMessage(id: "msg_1", updated: t, data: OpenCodeFixtureDB.user(created: t))
        let read = try OpenCodeSource.readRows(path: fixture.url.path, from: 0, liveSince: nil)
        #expect(read.rows.map(\.id) == ["msg_1"])
    }
}
