import Foundation

/// Parse state of one decision log (spec 045 data-model
/// "DecisionLogEntry").
public struct DecisionLogEntry: Equatable, Sendable {
    /// The log's canonical path, the entry's key.
    public var canonicalPath: String
    /// The canonical working directory the log lies in.
    public var directory: String
    /// Size at the last read.
    public var size: Int
    /// Modification date at the last read.
    public var modificationDate: Date
    /// End of the last complete line read.
    public var parsedOffset: Int
    /// Rows at or after the window start, in file order.
    public var rows: [ClassifierRow]
    /// The inode number of the file read, so a replaced file is read again
    /// from the start (FR-003).
    public var fileID: UInt64?
    /// The raw working directory spellings that resolved to this log, so a
    /// spelling whose check has not finished protects only the logs it may
    /// name (spec 045 FR-012, review decision 2026-11-13).
    public var spellings: Set<String>
    /// The distinct models of the rows read since the log was last read
    /// from the start (FR-001 model limit).
    public var models: Set<String>

    public init(canonicalPath: String, directory: String, size: Int, modificationDate: Date, parsedOffset: Int, rows: [ClassifierRow],
                fileID: UInt64? = nil, spellings: Set<String> = [], models: Set<String>? = nil) {
        self.canonicalPath = canonicalPath
        self.directory = directory
        self.size = size
        self.modificationDate = modificationDate
        self.parsedOffset = parsedOffset
        self.rows = rows
        self.fileID = fileID
        self.spellings = spellings
        self.models = models ?? Set(rows.map(\.model))
    }
}

/// What one update of the classifier index saw (spec 045 data-model
/// "ClassifierIndexStats", FR-013).
public struct ClassifierIndexStats: Equatable, Sendable {
    /// Working directories checked in this refresh, timed out and busy ones
    /// included. A second spelling of one directory counts once when its
    /// check finished; spellings that timed out or were busy count each.
    public var checked = 0
    /// Decision logs found.
    public var logsFound = 0
    /// Decision logs whose new bytes were read and parsed.
    public var logsRead = 0
    public var timedOut = 0
    public var busy = 0
    /// Logs that are not regular files, too large or with too many rows
    /// (FR-001).
    public var skipped = 0
    /// The paths of the logs skipped as too large.
    public var tooLargePaths: [String] = []
    /// The paths of the logs skipped for more than
    /// `ClassifierLogIndex.maximumRowsPerLog` rows.
    public var tooManyRowsPaths: [String] = []
    /// The paths of the logs skipped for more than
    /// `ClassifierLogIndex.maximumModelsPerLog` distinct models.
    public var tooManyModelsPaths: [String] = []
    /// Logs that exist but could not be read this time; their rows keep
    /// counting (FR-003, FR-012).
    public var unreadable = 0
    /// Valid lines with no counter above zero.
    public var withoutUsage = 0
    /// Lines that are not JSON, have no usable `ts` or `classifierModel`, or
    /// an invalid counter.
    public var malformed = 0

    public init() {}
}

/// In-memory incremental index over decision logs (spec 045 FR-003,
/// FR-008a, research R5, R6). It parses the bytes `DecisionLogProbe` read
/// and never opens a file itself. Not thread-safe; `SessionLogSource` owns
/// it.
public final class ClassifierLogIndex {
    /// A log with more rows is skipped like a too large one (FR-001): 64 MB
    /// at 256 bytes per row, where real rows take about 550 bytes. It bounds
    /// the memory of a log made of minimal lines, which the size limit
    /// alone does not (review finding of 2026-11-13).
    public static let defaultMaximumRowsPerLog = 262_144
    /// The row limit of this index; `defaultMaximumRowsPerLog` unless a
    /// test sets a smaller one.
    public let maximumRowsPerLog: Int
    /// A log naming more distinct models is skipped the same way: Claude
    /// Code uses one classifier model, a few at most, while thousands of
    /// made-up names would each cost a price lookup and a breakdown row on
    /// every refresh (review finding of 2026-11-13).
    public static let defaultMaximumModelsPerLog = 16
    public let maximumModelsPerLog: Int

    public private(set) var entries: [String: DecisionLogEntry] = [:]
    /// Logs skipped for too many rows, by canonical path, with the state at
    /// which they were skipped: handed to the probe as known, so an
    /// unchanged one is not read again, and continued while it grows.
    private var rejected: [String: KnownLogState] = [:]
    /// Window start of the previous update; rows before it were pruned.
    private var lastWindowStart: Date?

    public init(maximumRowsPerLog: Int = ClassifierLogIndex.defaultMaximumRowsPerLog,
                maximumModelsPerLog: Int = ClassifierLogIndex.defaultMaximumModelsPerLog) {
        self.maximumRowsPerLog = maximumRowsPerLog
        self.maximumModelsPerLog = maximumModelsPerLog
    }

    /// The entries in a stable order, by canonical path.
    public var sortedEntries: [DecisionLogEntry] {
        entries.keys.sorted().map { entries[$0]! }
    }

    public func reset() {
        entries = [:]
        rejected = [:]
        lastWindowStart = nil
    }

    /// Prepares a refresh over `window` and returns the per-file state the
    /// probe needs to read only unread bytes, by canonical log path; called
    /// before the probe and `update(report:window:)`. It changes the index:
    /// when the window start moved earlier than the previous refresh's,
    /// rows before the old start were pruned, so every entry is dropped
    /// first and the probe reads those logs in full (as `LogIndex.update`
    /// does; spec 045 FR-002, FR-003). `SessionLogSource.resetIndex` drops
    /// the index for the same event when it arrives from the coordinator.
    public func prepare(for window: DateInterval) -> [String: KnownLogState] {
        if let previous = lastWindowStart, window.start < previous {
            entries = [:]
        }
        lastWindowStart = window.start
        return entries.mapValues {
            KnownLogState(size: $0.size, modificationDate: $0.modificationDate, parsedOffset: $0.parsedOffset, fileID: $0.fileID)
        }.merging(rejected) { entry, _ in entry }
    }

    /// Applies the probe's report with the rules of `LogIndex` (FR-003):
    /// a chunk from the parsed offset appends, a chunk from 0 replaces the
    /// rows; a log that is gone, no regular file, too large or older than
    /// the window start stops counting (FR-001, FR-002); a timed-out or
    /// busy directory keeps its entry (FR-012). An entry is kept only while
    /// its directory is among the report's canonical directories, or while
    /// a spelling without a canonical directory might name it.
    public func update(report: ProbeReport, window: DateInterval) -> ClassifierIndexStats {
        var stats = ClassifierIndexStats()
        for (raw, result) in report.results {
            stats.checked += 1
            let directory = report.canonical[raw]
            switch result {
            case .found(let path, let size, let date, let chunk):
                stats.logsFound += 1
                guard date >= window.start else {
                    entries[path] = nil
                    rejected[path] = nil
                    continue
                }
                if let state = rejected[path] {
                    // Still too many rows: an unchanged log is not read, a
                    // grown one is only followed; one read from the start
                    // is counted afresh.
                    guard let chunk, chunk.from == 0 else {
                        stats.skipped += 1
                        if let chunk, chunk.from == state.parsedOffset {
                            rejected[path] = KnownLogState(size: size, modificationDate: date, parsedOffset: chunk.from + chunk.data.count,
                                                           fileID: chunk.fileID)
                        }
                        continue
                    }
                    rejected[path] = nil
                }
                guard let chunk else { continue }
                stats.logsRead += 1
                // A finished check always reports its canonical directory.
                guard let directory else {
                    assertionFailure("decision log \(path) found without its canonical directory")
                    continue
                }
                var entry: DecisionLogEntry
                if chunk.from == 0 {
                    entry = DecisionLogEntry(canonicalPath: path, directory: directory, size: 0, modificationDate: date,
                                             parsedOffset: 0, rows: [])
                } else if let existing = entries[path], existing.parsedOffset == chunk.from {
                    entry = existing
                } else {
                    // The bytes do not continue what is known (the window
                    // moved meanwhile): read the log in full next time.
                    entries[path] = nil
                    continue
                }
                var consumed = Self.parse(chunk, path: path, window: window, into: &entry.rows, models: &entry.models,
                                          limits: (rows: maximumRowsPerLog, models: maximumModelsPerLog), stats: &stats)
                // A line longer than the read limit can never complete in
                // one read: it is skipped as malformed rather than read
                // again forever.
                if chunk.isPartial && consumed == 0 {
                    consumed = chunk.data.count
                    stats.malformed += 1
                }
                let tooManyRows = entry.rows.count > maximumRowsPerLog
                guard !tooManyRows && entry.models.count <= maximumModelsPerLog else {
                    entries[path] = nil
                    rejected[path] = KnownLogState(size: size, modificationDate: date, parsedOffset: chunk.from + chunk.data.count,
                                                   fileID: chunk.fileID)
                    stats.skipped += 1
                    if tooManyRows { stats.tooManyRowsPaths.append(path) } else { stats.tooManyModelsPaths.append(path) }
                    continue
                }
                entry.parsedOffset = chunk.from + consumed
                entry.size = size
                entry.modificationDate = date
                entry.directory = directory
                entry.fileID = chunk.fileID
                entries[path] = entry
            case .absent, .notRegular:
                if let directory { entries[DecisionLogProbe.logPath(inDirectory: directory)] = nil }
                if case .notRegular = result { stats.skipped += 1 }
            case .tooLarge(let path, _):
                stats.skipped += 1
                stats.tooLargePaths.append(path)
                entries[path] = nil
            case .unreadable:
                stats.unreadable += 1
            case .timedOut:
                stats.timedOut += 1
            case .busy:
                stats.busy += 1
            }
        }
        // Remember which spellings resolved to each log.
        for (raw, directory) in report.canonical {
            let path = DecisionLogProbe.logPath(inDirectory: directory)
            entries[path]?.spellings.insert(raw)
        }
        // A spelling that timed out or was busy before any check of it
        // finished has no canonical directory yet and may name a directory
        // already read. It keeps a log whose directory or recorded spelling
        // has the same plain path form, so that log's rows keep counting;
        // other logs follow the usual rule (FR-012, review decision
        // 2026-11-13). The plain form needs no file system access.
        let unresolved = Set(report.results.keys.filter { report.canonical[$0] == nil }.map(Self.plainPath))
        let directories = Set(report.canonical.values)
        for path in Array(entries.keys) {
            guard let entry = entries[path] else { continue }
            let mayBeNamed = !unresolved.isEmpty
                && (unresolved.contains(Self.plainPath(entry.directory))
                    || entry.spellings.contains { unresolved.contains(Self.plainPath($0)) })
            if !mayBeNamed && !directories.contains(entry.directory) {
                entries[path] = nil
            } else if entry.rows.contains(where: { $0.timestamp < window.start }) {
                entries[path]!.rows.removeAll { $0.timestamp < window.start }
            }
        }
        for path in Array(rejected.keys) where !directories.contains((path as NSString).deletingLastPathComponent) {
            rejected[path] = nil
        }
        return stats
    }

    /// `path` with `.` and empty components dropped, `..` applied and no
    /// trailing slash, without touching the file system (symbolic links
    /// are not resolved; that needs the probe's timed check, FR-012).
    static func plainPath(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Parses the complete lines of `chunk`, appending the rows at or after
    /// the window start to `rows` and their models to `models`; returns the
    /// bytes consumed through the last complete line (FR-003, FR-004,
    /// FR-008a). It stops as soon as `rows` or `models` exceeds its limit,
    /// so a log of minimal lines never holds more than the limit plus one
    /// row while it is rejected (FR-001; review finding of 2026-11-13).
    static func parse(_ chunk: ReadChunk, path: String, window: DateInterval, into rows: inout [ClassifierRow],
                      models: inout Set<String>, limits: (rows: Int, models: Int) = (.max, .max),
                      stats: inout ClassifierIndexStats) -> Int {
        chunk.data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return 0 }
            let count = buffer.count
            var start = 0
            // The line splitting of `SessionLineReader.forEachLine`, which
            // cannot stop early.
            while start < count, let found = memchr(base + start, 0x0A, count - start) {
                let newline = base.distance(to: UnsafeRawPointer(found))
                var end = newline
                if end > start, buffer[end - 1] == 0x0D { end -= 1 }
                if end > start {
                    let line = Data(UnsafeRawBufferPointer(rebasing: buffer[start..<end]))
                    switch ClassifierRowParser.parse(line: line, offset: chunk.from + start, logPath: path) {
                    case .row(let row):
                        if row.timestamp >= window.start {
                            rows.append(row)
                            models.insert(row.model)
                        }
                    case .withoutUsage:
                        stats.withoutUsage += 1
                    case .malformed:
                        stats.malformed += 1
                    }
                }
                start = newline + 1
                if rows.count > limits.rows || models.count > limits.models { break }
            }
            return start
        }
    }
}
