import Foundation
import SQLite3

/// `UsageSource` over OpenCode's local database (spec 006 FR-001 to FR-010,
/// research R6). Reads `<dataDir>/opencode.db` read-only for the default
/// data directory and every configured extra one.
///
/// Each completed assistant message is one record, keyed by message id, so a
/// later update replaces its record (FR-009). After the first read only rows
/// with a newer `time_updated` are read (FR-004). A busy, locked or
/// unreadable database never throws: its previous records are kept and
/// reported stale (FR-005).
public actor OpenCodeSource: WindowSensitiveSource {
    public static let sourceName = "opencode"
    public nonisolated let name = OpenCodeSource.sourceName
    /// The database file inside an OpenCode data directory.
    public static let databaseFileName = "opencode.db"
    /// Upper bound for waiting on a lock held by OpenCode (plan Global Constraints).
    static let busyTimeoutMilliseconds: Int32 = 250
    /// Rows updated up to this long before the window start are still read,
    /// in case a row's update time trails its completion time.
    static let readMarginMilliseconds: Int64 = 3_600_000

    /// One stored message: the raw record and its JSON for custom markers.
    struct StoredMessage {
        var raw: RawUsageRecord
        var line: String
        var record: UsageRecord
    }

    /// Per-database state, keyed by the canonical database path.
    struct DatabaseState {
        /// Highest `time_updated` read so far (ms since 1970). Rows at the
        /// watermark are read again, minus the ids already read at it, so a
        /// row committed later in the same millisecond is not missed.
        var watermark: Int64 = 0
        var idsAtWatermark: Set<String> = []
        var messages: [String: StoredMessage] = [:]
    }

    private let paths: Paths
    private let log: DiagnosticLog?
    private let builtInPrices: PriceTable
    private let importedPrices: ImportedPriceStore?
    private let projects: ProjectResolver

    private var databases: [String: DatabaseState] = [:]
    private var attributionFingerprint: String?
    private var priceTable: PriceTable?
    private var lastWindowStart: Date?

    /// Rows read from all databases by the last `collect` (for tests and the log).
    public private(set) var lastRowsRead = 0

    /// `importedPrices` supplies the imported layer of the price table; its
    /// current value is read on every refresh, as for `SessionLogSource`.
    public init(paths: Paths = Paths(), log: DiagnosticLog? = nil, builtInPrices: PriceTable? = nil,
                importedPrices: ImportedPriceStore? = nil, projectResolver: ProjectResolver = ProjectResolver()) throws {
        self.paths = paths
        self.log = log
        self.builtInPrices = try builtInPrices ?? PriceTable.builtIn()
        self.importedPrices = importedPrices
        self.projects = projectResolver
    }

    /// A configured data directory: expanded path and whether it is the
    /// default location (skipped silently when missing, FR-002).
    public struct Location: Equatable, Sendable {
        public let directory: String
        public let isDefault: Bool
    }

    /// The default directory plus configured extra directories, expanded and
    /// deduplicated by path (FR-003).
    public nonisolated func directories(for configuration: Configuration) -> [Location] {
        var seen = Set<String>()
        var result: [Location] = []
        let defaultDirectory = paths.expand(Paths.defaultOpenCodeDirectory)
        for dir in [Paths.defaultOpenCodeDirectory] + configuration.openCodeDirectories {
            let expanded = paths.expand(dir)
            if seen.insert(expanded).inserted {
                result.append(Location(directory: expanded, isDefault: expanded == defaultDirectory))
            }
        }
        return result
    }

    /// All stored raw records by message id (for tests).
    var rawRecords: [String: RawUsageRecord] {
        var result: [String: RawUsageRecord] = [:]
        for state in databases.values {
            for (id, message) in state.messages { result[id] = message.raw }
        }
        return result
    }

    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let started = Date()
        let configuration = context.configuration
        let window = context.window
        let pricer = PriceTable.effective(builtIn: builtInPrices, imported: importedPrices?.current ?? .empty,
                                          overrides: configuration.priceOverrides)
        let attributor = Attributor(configuration: configuration, paths: paths)

        // The collection start moved earlier: pruned records would be missing
        // and unchanged rows would not be read again, so start over (FR-023).
        if let previous = lastWindowStart, window.start < previous {
            databases = [:]
        }
        lastWindowStart = window.start

        // Rules or prices changed: re-attribute and re-price what is stored,
        // without reading rows again (as `LogIndex` does).
        let rulesChanged = attributionFingerprint.map { $0 != attributor.fingerprint } ?? false
        let pricesChanged = priceTable.map { $0 != pricer } ?? false
        attributionFingerprint = attributor.fingerprint
        priceTable = pricer

        var issues: [String] = []
        var stale = false
        var rowsRead = 0
        var present = Set<String>()

        for location in directories(for: configuration) {
            let dbPath = (location.directory as NSString).appendingPathComponent(Self.databaseFileName)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: location.directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                if location.isDefault {
                    log?.append(source: name, message: "\(location.directory): skipped, OpenCode not installed")
                } else {
                    issues.append("OpenCode: data directory not found: \(location.directory)")
                    log?.append(source: name, message: "\(location.directory): error: data directory not found")
                }
                continue
            }
            guard FileManager.default.fileExists(atPath: dbPath) else {
                if location.isDefault {
                    log?.append(source: name, message: "\(location.directory): skipped, no \(Self.databaseFileName)")
                } else {
                    issues.append("OpenCode: no \(Self.databaseFileName) in \(location.directory)")
                    log?.append(source: name, message: "\(location.directory): error: no \(Self.databaseFileName)")
                }
                continue
            }
            let key = Attributor.canonical(dbPath)
            // Two configured paths to the same database: read it once (FR-003).
            guard present.insert(key).inserted else {
                log?.append(source: name, message: "\(location.directory): skipped, same database as an earlier location")
                continue
            }

            var state = databases[key] ?? DatabaseState()
            if rulesChanged || pricesChanged {
                for (id, message) in state.messages {
                    state.messages[id]?.record = makeRecord(message.raw, line: message.line, location: location.directory,
                                                            attributor: attributor, pricer: pricer)
                }
            }
            do {
                let windowStartMs = Int64((window.start.timeIntervalSince1970 * 1000).rounded(.down))
                // A row is updated no earlier than it completed, so rows
                // updated before the window start hold no usage inside it:
                // the first read covers the window (with a margin), not the
                // whole history. Records outside the window are pruned below.
                let readFrom = max(state.watermark, windowStartMs - Self.readMarginMilliseconds)
                let read = try Self.readRows(path: dbPath, from: readFrom,
                                             liveSince: state.messages.isEmpty ? nil : windowStartMs)
                // Messages deleted in OpenCode (for example with their
                // session) stop counting ("Harness removed" edge case).
                if let live = read.liveIds {
                    state.messages = state.messages.filter { live.contains($0.key) }
                }
                var rowCount = 0
                for row in read.rows {
                    if row.timeUpdated == state.watermark && state.idsAtWatermark.contains(row.id) { continue }
                    rowCount += 1
                    if row.timeUpdated > state.watermark {
                        state.watermark = row.timeUpdated
                        state.idsAtWatermark = [row.id]
                    } else if row.timeUpdated == state.watermark {
                        state.idsAtWatermark.insert(row.id)
                    }
                    guard let raw = Self.parse(row) else {
                        state.messages[row.id] = nil
                        continue
                    }
                    state.messages[row.id] = StoredMessage(raw: raw, line: row.data,
                                                           record: makeRecord(raw, line: row.data, location: location.directory,
                                                                              attributor: attributor, pricer: pricer))
                }
                rowsRead += rowCount
                state.messages = state.messages.filter { $0.value.raw.timestamp >= window.start }
                log?.append(source: name, message: "\(dbPath): \(state.messages.count) record(s) in window, \(rowCount) row(s) read")
            } catch {
                // FR-005: keep the previous records, marked stale.
                state.messages = state.messages.filter { $0.value.raw.timestamp >= window.start }
                stale = true
                issues.append("OpenCode: \(dbPath): \(error)")
                log?.append(source: name, message: "\(dbPath): error: \(error), keeping \(state.messages.count) previous record(s)")
            }
            databases[key] = state
        }
        // A database that disappeared takes its records with it.
        databases = databases.filter { present.contains($0.key) }
        lastRowsRead = rowsRead

        let records = databases.keys.sorted().flatMap { key in
            databases[key]!.messages.values.map(\.record).sorted {
                $0.timestamp != $1.timestamp ? $0.timestamp < $1.timestamp : $0.messageId < $1.messageId
            }
        }
        let notes = projects.drainNotes()
        if !notes.isEmpty {
            log?.append(source: name, message: SessionLogSource.summarizeProjectNotes(notes))
        }
        log?.append(source: name, message: String(format: "%d record(s) since collection start, %d row(s) read, %.3f s",
                                                  records.count, rowsRead, Date().timeIntervalSince(started)))
        return .recordBatch(RecordBatch(records: records, issues: issues, staleHarnesses: stale ? [.openCode] : []))
    }

    public func resetForEarlierWindow() {
        databases = [:]
        lastWindowStart = nil
        log?.append(source: name, message: "collection start moved earlier, records reset")
    }

    private func makeRecord(_ raw: RawUsageRecord, line: String, location: String, attributor: Attributor, pricer: PriceTable) -> UsageRecord {
        UsageRecord(raw: raw, canonicalModel: PriceTable.canonicalModel(raw.model),
                    accountId: attributor.accountId(for: raw, rawLine: line, fileConfigDirectory: location),
                    costUSD: pricer.cost(of: raw), project: projects.project(forCwd: raw.cwd))
    }

    // MARK: - Rows

    struct Row {
        let id: String
        let sessionId: String
        let timeUpdated: Int64
        let data: String
        let sessionDirectory: String?
    }

    /// The fields used from `message.data` (contracts/harness-formats.md).
    /// Every field is optional so unknown shapes skip the row, not the read.
    private struct MessageData: Decodable {
        struct Path: Decodable { let cwd: String? }
        struct Time: Decodable { let completed: Double? }
        struct Cache: Decodable { let read: Double?; let write: Double? }
        struct Tokens: Decodable {
            let input: Double?
            let output: Double?
            let reasoning: Double?
            let cache: Cache?
        }
        let role: String?
        let providerID: String?
        let modelID: String?
        let path: Path?
        let time: Time?
        let tokens: Tokens?
    }

    /// One record for a completed assistant message with tokens, nil for
    /// anything else (FR-009). OpenCode's `cost` is ignored (FR-019).
    static func parse(_ row: Row) -> RawUsageRecord? {
        guard let message = try? JSONDecoder().decode(MessageData.self, from: Data(row.data.utf8)),
              message.role == "assistant",
              let completed = message.time?.completed,
              let tokens = message.tokens else { return nil }
        // `Int(Double)` traps outside Int's range: a corrupt value is clamped,
        // so one bad row cannot crash every refresh.
        func count(_ value: Double?) -> Int {
            guard let value, value.isFinite, value > 0 else { return 0 }
            return value >= Double(CodexSessionParser.maxTokenValue) ? CodexSessionParser.maxTokenValue : Int(value)
        }
        let input = count(tokens.input)
        let output = count(tokens.output)
        let reasoning = count(tokens.reasoning)
        let cacheRead = count(tokens.cache?.read)
        let cacheWrite = count(tokens.cache?.write)
        guard input + output + reasoning + cacheRead + cacheWrite > 0 else { return nil }
        let cwd = message.path?.cwd.flatMap { $0.isEmpty ? nil : $0 } ?? row.sessionDirectory
        // Reasoning is reported apart from output: priced as output (FR-020)
        // and kept for display (FR-008b). Cache writes are 5-minute writes (FR-020b).
        return RawUsageRecord(messageId: row.id, timestamp: Date(timeIntervalSince1970: completed / 1000),
                              model: message.modelID ?? "", requestId: "",
                              inputTokens: input, outputTokens: output + reasoning,
                              cacheWrite5mTokens: cacheWrite, cacheWrite1hTokens: 0, cacheReadTokens: cacheRead,
                              cwd: cwd, harness: .openCode, providerHint: message.providerID,
                              reasoningTokens: reasoning, sessionId: row.sessionId)
    }

    // MARK: - SQLite (read-only)

    /// The database to open. A WAL-mode database without a WAL file means
    /// OpenCode is not running: it is opened as immutable, so SQLite creates
    /// no `-wal` or `-shm` side files in OpenCode's directory
    /// (contracts/harness-formats.md: AgentTacho never writes there). While
    /// OpenCode runs, the WAL file holds recent writes and the plain path is
    /// opened read-only. Rollback-journal databases are always opened plainly:
    /// readers create no side files there, and immutable would ignore a
    /// writer's lock.
    static func openTarget(path: String, fileManager: FileManager = .default) -> String {
        guard isWalDatabase(path: path), !fileManager.fileExists(atPath: path + "-wal") else { return path }
        return URL(fileURLWithPath: path).absoluteString + "?immutable=1"
    }

    /// SQLite header bytes 18 and 19 (file format write and read versions)
    /// are 2 for a database in WAL mode.
    static func isWalDatabase(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 20), header.count == 20 else { return false }
        return header[header.startIndex + 18] == 2 && header[header.startIndex + 19] == 2
    }

    struct SQLiteError: Error, CustomStringConvertible {
        let code: Int32
        let message: String
        var description: String { "\(message) (SQLite code \(code))" }
    }

    /// Rows with `time_updated >= watermark`, oldest first, and, when
    /// `liveSince` is set, the ids of all messages updated since then (to
    /// notice deleted rows). Opens the database read-only with a short busy
    /// timeout and never writes to it.
    ///
    /// Hardened for untrusted files (spec 015 FR-008, research R4): with
    /// `trusted_schema=OFF`, views, generated columns, defaults and CHECK
    /// constraints in the file cannot call functions that are not marked
    /// innocuous (SQLite refuses with "unsafe use of"), and `message` and
    /// `session` must be ordinary tables, not views or virtual tables. All
    /// virtual table modules are removed from the connection first, so no
    /// virtual table in the file can run module code on the file's data,
    /// not even while the table check lists the schema; AgentTacho's
    /// queries use none. `SQLITE_DBCONFIG_DEFENSIVE` is not used:
    /// `sqlite3_db_config` is variadic, which Swift does not import, and it
    /// mainly guards writes, which the read-only connection already
    /// excludes. `connectionHook` runs right after opening, before the
    /// hardening; it is a test seam and `nil` in production.
    static func readRows(path: String, from watermark: Int64, liveSince: Int64?,
                         connectionHook: ((OpaquePointer) throws -> Void)? = nil) throws -> (rows: [Row], liveIds: Set<String>?) {
        var db: OpaquePointer?
        let openCode = sqlite3_open_v2(openTarget(path: path), &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        defer { sqlite3_close_v2(db) }
        guard openCode == SQLITE_OK, let db else {
            throw SQLiteError(code: openCode, message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database")
        }
        sqlite3_busy_timeout(db, busyTimeoutMilliseconds)
        try connectionHook?(db)
        let dropCode = sqlite3_drop_modules(db, nil)
        guard dropCode == SQLITE_OK else { throw SQLiteError(code: dropCode, message: String(cString: sqlite3_errmsg(db))) }
        try exec(db, "PRAGMA trusted_schema=OFF")

        let sql = """
        SELECT m.id, m.session_id, m.time_updated, m.data, s.directory
        FROM message m LEFT JOIN session s ON s.id = m.session_id
        WHERE m.time_updated >= ?1
        ORDER BY m.time_updated
        """
        // One read transaction, so the table check and both queries see the
        // same snapshot and schema.
        try exec(db, "BEGIN")
        defer { _ = sqlite3_exec(db, "COMMIT", nil, nil, nil) }
        try requireTables(db, ["message", "session"])
        var rows: [Row] = []
        try query(db, sql, bind: watermark) { stmt in
            guard let id = text(stmt, 0), let data = text(stmt, 3) else { return }
            rows.append(Row(id: id, sessionId: text(stmt, 1) ?? "", timeUpdated: sqlite3_column_int64(stmt, 2),
                            data: data, sessionDirectory: text(stmt, 4)))
        }
        guard let liveSince else { return (rows, nil) }
        var live = Set<String>()
        try query(db, "SELECT id FROM message WHERE time_updated >= ?1", bind: liveSince) { stmt in
            if let id = text(stmt, 0) { live.insert(id) }
        }
        return (rows, live)
    }

    /// Throws unless every name in `names` is an ordinary table of the main
    /// schema, not a view or a virtual table (spec 015 FR-008): a virtual
    /// table runs its module's code on data from the file. The kind comes
    /// from SQLite's parsed schema (`table_list`), not from the stored
    /// `CREATE` text, which a crafted file can spell so that a text check
    /// misses it. Table names are case-insensitive in SQLite,
    /// so the lookup is too. Triggers and indexes are not listed, so they
    /// cannot hide a table that shares their name.
    private static func requireTables(_ db: OpaquePointer, _ names: [String]) throws {
        var kinds: [String: String] = [:]
        try query(db, "SELECT lower(name), type FROM pragma_table_list WHERE schema = 'main'", bind: nil) { stmt in
            if let name = text(stmt, 0), let type = text(stmt, 1) { kinds[name] = type }
        }
        for name in names.map({ $0.lowercased() }) where kinds[name] != "table" {
            let kind = kinds[name].map { $0 == "view" ? "a view" : "a \($0) table" }
            throw SQLiteError(code: SQLITE_ERROR, message: kind.map { "\(name) is \($0), not an ordinary table" } ?? "no such table: \(name)")
        }
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: pointer)
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw SQLiteError(code: code, message: String(cString: sqlite3_errmsg(db))) }
    }

    /// Prepares `sql` with one integer parameter (none when `value` is
    /// nil), calls `row` per result row, and finalizes the statement.
    private static func query(_ db: OpaquePointer, _ sql: String, bind value: Int64?, row: (OpaquePointer?) -> Void) throws {
        var stmt: OpaquePointer?
        let prepareCode = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        guard prepareCode == SQLITE_OK else {
            throw SQLiteError(code: prepareCode, message: String(cString: sqlite3_errmsg(db)))
        }
        if let value { sqlite3_bind_int64(stmt, 1, value) }
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { return }
            guard step == SQLITE_ROW else {
                throw SQLiteError(code: step, message: String(cString: sqlite3_errmsg(db)))
            }
            row(stmt)
        }
    }
}
