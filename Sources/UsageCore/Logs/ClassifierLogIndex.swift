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

    public init(canonicalPath: String, directory: String, size: Int, modificationDate: Date, parsedOffset: Int, rows: [ClassifierRow]) {
        self.canonicalPath = canonicalPath
        self.directory = directory
        self.size = size
        self.modificationDate = modificationDate
        self.parsedOffset = parsedOffset
        self.rows = rows
    }
}

/// What one update of the classifier index saw (spec 045 data-model
/// "ClassifierIndexStats", FR-013).
public struct ClassifierIndexStats: Equatable, Sendable {
    /// Working directories checked in this refresh, timed out and busy ones
    /// included; a second spelling of one directory counts once.
    public var checked = 0
    /// Decision logs found.
    public var logsFound = 0
    /// Decision logs whose new bytes were read and parsed.
    public var logsRead = 0
    public var timedOut = 0
    public var busy = 0
    /// Logs that are not regular files or too large (FR-001).
    public var skipped = 0
    /// The paths of the logs skipped as too large.
    public var tooLargePaths: [String] = []
    /// Valid lines with no counter above zero.
    public var withoutUsage = 0
    /// Lines that are not JSON, have no usable `ts` or `classifierModel`, or
    /// an invalid counter.
    public var malformed = 0
    public var bytesRead = 0

    public init() {}
}

/// In-memory incremental index over decision logs (spec 045 FR-003,
/// FR-008a, research R5, R6). It parses the bytes `DecisionLogProbe` read
/// and never opens a file itself. Not thread-safe; `SessionLogSource` owns
/// it.
public final class ClassifierLogIndex {
    public private(set) var entries: [String: DecisionLogEntry] = [:]
    /// Window start of the previous update; rows before it were pruned.
    private var lastWindowStart: Date?

    public init() {}

    /// The entries in a stable order, by canonical path.
    public var sortedEntries: [DecisionLogEntry] {
        entries.keys.sorted().map { entries[$0]! }
    }

    public func reset() {
        entries = [:]
        lastWindowStart = nil
    }

    /// Drops every entry when the window start moved earlier than the
    /// previous update's: rows before the old start were pruned, so the
    /// logs are read again from the start (as `LogIndex.update` does).
    /// Called before `known()`, so the probe reads those logs in full.
    public func prepare(window: DateInterval) {
        if let previous = lastWindowStart, window.start < previous {
            entries = [:]
        }
        lastWindowStart = window.start
    }

    /// The per-file state the probe needs to read only unread bytes, by
    /// canonical log path.
    public func known() -> [String: KnownLogState] {
        entries.mapValues { KnownLogState(size: $0.size, modificationDate: $0.modificationDate, parsedOffset: $0.parsedOffset) }
    }

    /// Applies the probe's report with the rules of `LogIndex` (FR-003):
    /// a chunk from the parsed offset appends, a chunk from 0 replaces the
    /// rows; a log that is gone, no regular file, too large or older than
    /// the window start stops counting (FR-001, FR-002); a timed-out or
    /// busy directory keeps its entry (FR-012). An entry is kept only while
    /// its directory is among the report's canonical directories.
    public func update(report: ProbeReport, window: DateInterval) -> ClassifierIndexStats {
        prepare(window: window)
        var stats = ClassifierIndexStats()
        for raw in report.results.keys.sorted() {
            let result = report.results[raw]!
            stats.checked += 1
            let directory = report.canonical[raw]
            switch result {
            case .found(let path, let size, let date, let chunk):
                stats.logsFound += 1
                guard date >= window.start, let directory else {
                    entries[path] = nil
                    continue
                }
                guard let chunk else { continue }
                stats.logsRead += 1
                stats.bytesRead += chunk.data.count
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
                let consumed = Self.parse(chunk, path: path, window: window, into: &entry.rows, stats: &stats)
                entry.parsedOffset = chunk.from + consumed
                entry.size = size
                entry.modificationDate = date
                entry.directory = directory
                entries[path] = entry
            case .absent, .notRegular:
                if let directory { entries[DecisionLogProbe.logPath(inDirectory: directory)] = nil }
                if case .notRegular = result { stats.skipped += 1 }
            case .tooLarge(let path, _):
                stats.skipped += 1
                stats.tooLargePaths.append(path)
                entries[path] = nil
            case .timedOut:
                stats.timedOut += 1
            case .busy:
                stats.busy += 1
            }
        }
        let directories = Set(report.canonical.values)
        for (path, entry) in entries {
            if !directories.contains(entry.directory) {
                entries[path] = nil
            } else {
                entries[path]!.rows.removeAll { $0.timestamp < window.start }
            }
        }
        return stats
    }

    /// Parses the complete lines of `chunk`, appending the rows at or after
    /// the window start to `rows`; returns the bytes consumed through the
    /// last complete line (FR-003, FR-004, FR-008a).
    static func parse(_ chunk: ReadChunk, path: String, window: DateInterval, into rows: inout [ClassifierRow],
                      stats: inout ClassifierIndexStats) -> Int {
        chunk.data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return 0 }
            return SessionLineReader.forEachLine(in: buffer) { line in
                // Lines are slices of the same buffer: their start is the
                // line's offset in the chunk.
                let start = line.baseAddress.map { base.distance(to: $0) } ?? 0
                switch ClassifierRowParser.parse(line: Data(line), offset: chunk.from + start, logPath: path) {
                case .row(let row):
                    if row.timestamp >= window.start { rows.append(row) }
                case .withoutUsage:
                    stats.withoutUsage += 1
                case .malformed:
                    stats.malformed += 1
                }
            }
        }
    }
}
