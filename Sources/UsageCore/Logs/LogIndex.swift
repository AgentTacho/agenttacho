import Foundation

/// Per-file parse state (data-model.md, FileIndexEntry).
public struct FileIndexEntry: Equatable, Sendable {
    public var canonicalPath: String
    public var size: Int
    public var modificationDate: Date
    /// Bytes consumed up to the last complete line.
    public var parsedOffset: Int
    public var configDirectory: String
    /// Records with `timestamp >= window.start`; the upper bound is applied by the Aggregator.
    public var records: [UsageRecord]
}

public struct LogIndexStats: Equatable, Sendable {
    public var filesSeen = 0
    public var filesRead = 0
    public var bytesRead = 0
    public var recordsInWindow = 0

    public init() {}
}

/// In-memory incremental index over session log files (FR-018, research R8).
/// Not thread-safe by itself; `SessionLogSource` (an actor) owns it. Files
/// that need reading are parsed concurrently; merging is sequential.
public final class LogIndex {
    public private(set) var entries: [String: FileIndexEntry] = [:]
    private var priceTable: PriceTable?
    private var attributionFingerprint: String?
    /// Window start of the previous update; records before it were pruned.
    private var lastWindowStart: Date?
    /// Upper bound on the bytes read and parsed per batch. A full re-read
    /// over a month-long collection window (spec 003 research R2) would
    /// otherwise hold the raw lines of every changed file at once.
    private let batchBytes: Int

    public init(batchBytes: Int = 64 * 1024 * 1024) {
        self.batchBytes = max(1, batchBytes)
    }

    /// All indexed records, in a stable order (by file path, then timestamp).
    public var records: [UsageRecord] {
        entries.keys.sorted().flatMap { entries[$0]!.records }
    }

    public func reset() {
        entries = [:]
        lastWindowStart = nil
    }

    /// Work item for one file that changed since the last update.
    struct ReadJob {
        let file: ScannedFile
        let offset: Int
        let fresh: Bool
    }

    private struct ReadResult {
        var parsed: [(record: RawUsageRecord, rawLine: Data)] = []
        var consumed = 0
        var total = 0
    }

    public func update(files: [ScannedFile], window: DateInterval, parser: SessionRecordParser,
                       attributor: Attributor, pricer: PriceTable) -> LogIndexStats {
        var stats = LogIndexStats()
        stats.filesSeen = files.count

        // Attribution rules changed: raw lines are not kept, so start over.
        if let previous = attributionFingerprint, previous != attributor.fingerprint {
            entries = [:]
        }
        attributionFingerprint = attributor.fingerprint

        // Window start moved earlier (alignment account or fallback changed
        // between refreshes, or a monthly group widened the collection
        // window): records before the old start were pruned and unchanged
        // files would not be re-read, so start over (FR-023).
        if let previous = lastWindowStart, window.start < previous {
            entries = [:]
        }
        lastWindowStart = window.start

        // Prices changed: re-price what is already indexed (US2 scenario 3).
        if let previous = priceTable, previous != pricer {
            for key in entries.keys {
                entries[key]!.records = entries[key]!.records.map { record in
                    var r = record
                    r.costUSD = pricer.cost(model: record.model, input: record.inputTokens, output: record.outputTokens,
                                            cacheWrite5m: record.cacheWrite5mTokens, cacheWrite1h: record.cacheWrite1hTokens,
                                            cacheRead: record.cacheReadTokens)
                    return r
                }
            }
        }
        priceTable = pricer

        let present = Set(files.map(\.canonicalPath))
        for key in entries.keys where !present.contains(key) {
            entries[key] = nil
        }

        // Phase 1: decide per file.
        var jobs: [ReadJob] = []
        for file in files {
            if file.modificationDate < window.start {
                entries[file.canonicalPath] = nil
                continue
            }
            if let entry = entries[file.canonicalPath], entry.size == file.size, entry.modificationDate == file.modificationDate {
                continue
            }
            let existingOffset = entries[file.canonicalPath]?.parsedOffset ?? 0
            let fresh = entries[file.canonicalPath] == nil || file.size < existingOffset
            jobs.append(ReadJob(file: file, offset: fresh ? 0 : existingOffset, fresh: fresh))
        }

        // Phases 2 and 3 run per batch of at most `batchBytes` unread bytes,
        // so peak memory is bounded by one batch, not by every changed file.
        for batch in Self.batches(of: jobs, maxBytes: batchBytes) {
            readAndMerge(batch, parser: parser, attributor: attributor, pricer: pricer, stats: &stats)
        }

        // Prune and count.
        for key in entries.keys {
            entries[key]!.records.removeAll { $0.timestamp < window.start }
            stats.recordsInWindow += entries[key]!.records.count
        }
        return stats
    }

    /// Splits `jobs` into consecutive batches whose unread bytes stay within
    /// `maxBytes`; a single larger file forms its own batch.
    static func batches(of jobs: [ReadJob], maxBytes: Int) -> [ArraySlice<ReadJob>] {
        var result: [ArraySlice<ReadJob>] = []
        var start = jobs.startIndex
        var bytes = 0
        for i in jobs.indices {
            let size = max(0, jobs[i].file.size - jobs[i].offset)
            if i > start && bytes + size > maxBytes {
                result.append(jobs[start..<i])
                start = i
                bytes = 0
            }
            bytes += size
        }
        if start < jobs.endIndex {
            result.append(jobs[start..<jobs.endIndex])
        }
        return result
    }

    private func readAndMerge(_ jobs: ArraySlice<ReadJob>, parser: SessionRecordParser, attributor: Attributor,
                              pricer: PriceTable, stats: inout LogIndexStats) {
        let jobs = Array(jobs)
        // Phase 2: read and parse changed files concurrently.
        var results = [ReadResult?](repeating: nil, count: jobs.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
                let job = jobs[i]
                let (lines, consumed, total) = Self.readCompleteLines(path: job.file.canonicalPath, from: job.offset)
                var result = ReadResult(consumed: consumed, total: total)
                result.parsed = lines.compactMap { line in parser.parse(data: line).map { ($0, line) } }
                buffer[i] = result
            }
        }

        // Phase 3: merge sequentially (attribution, pricing, dedupe).
        for (i, job) in jobs.enumerated() {
            let result = results[i] ?? ReadResult()
            let file = job.file
            var entry = job.fresh
                ? FileIndexEntry(canonicalPath: file.canonicalPath, size: 0, modificationDate: file.modificationDate,
                                 parsedOffset: 0, configDirectory: file.configDirectory, records: [])
                : entries[file.canonicalPath]!
            stats.filesRead += 1
            stats.bytesRead += result.total
            if !result.parsed.isEmpty {
                let deduped = SessionRecordParser.dedupe(result.parsed.map(\.record))
                var rawByKey: [String: Data] = [:]
                for (raw, line) in result.parsed { rawByKey[Self.key(raw)] = line }
                var merged: [String: UsageRecord] = [:]
                for existing in entry.records { merged[Self.key(existing)] = existing }
                for raw in deduped {
                    let rawLine = rawByKey[Self.key(raw)].map { String(decoding: $0, as: UTF8.self) } ?? ""
                    let accountId = attributor.accountId(for: raw, rawLine: rawLine, fileConfigDirectory: file.configDirectory)
                    merged[Self.key(raw)] = UsageRecord(raw: raw, canonicalModel: PriceTable.canonicalModel(raw.model),
                                                        accountId: accountId, costUSD: pricer.cost(of: raw))
                }
                entry.records = merged.values.sorted { $0.timestamp < $1.timestamp }
            }
            entry.parsedOffset = job.offset + result.consumed
            entry.size = job.offset + result.total
            entry.modificationDate = file.modificationDate
            entry.configDirectory = file.configDirectory
            entries[file.canonicalPath] = entry
        }
    }

    private static func key(_ record: RawUsageRecord) -> String {
        record.messageId.isEmpty ? "req:" + record.requestId : "msg:" + record.messageId
    }

    private static func key(_ record: UsageRecord) -> String {
        record.messageId.isEmpty ? "req:" + record.requestId : "msg:" + record.messageId
    }

    /// Reads from `offset` to the end of the file and returns the complete
    /// lines (without their newline), the number of bytes they occupy
    /// (including newlines), and the total number of bytes read.
    static func readCompleteLines(path: String, from offset: Int) -> (lines: [Data], consumed: Int, total: Int) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return ([], 0, 0) }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
        } catch {
            return ([], 0, 0)
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return ([], 0, 0) }
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return ([], 0, data.count) }
        let complete = data[data.startIndex...lastNewline]
        var lines: [Data] = []
        var lineStart = complete.startIndex
        for i in complete.indices where complete[i] == 0x0A {
            if i > lineStart {
                var end = i
                if complete[end - 1] == 0x0D { end -= 1 }   // tolerate CRLF
                if end > lineStart { lines.append(Data(complete[lineStart..<end])) }
            }
            lineStart = complete.index(after: i)
        }
        return (lines, complete.count, data.count)
    }
}
