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
    /// The canonical configuration directory in effect at the end of the
    /// last read, carried to appended lines (spec 037 FR-001); nil when no
    /// shape line named one.
    public var profile: String? = nil
    /// True once any shape line was seen, named, none or ambiguous (spec 037
    /// data-model "FileIndexEntry"); a newly configured directory may make
    /// a named line ambiguous.
    public var sawShapeLine: Bool = false
    /// Every canonical directory a shape line of the file named, so a
    /// candidate change re-reads the file when any of them changes claimants
    /// (spec 037 FR-001).
    public var namedProfiles: Set<String> = []
    /// True once a shape line named no configured directory, so a new
    /// candidate may name one now (spec 037 FR-001).
    public var sawNoneShapeLine: Bool = false
    /// True once a shape line named several configured directories, so a
    /// removed candidate may leave one named (spec 037 FR-001).
    public var sawAmbiguousShapeLine: Bool = false
    /// True when a condition sat out while the file's records were
    /// attributed, so the next update reads it again from the start; its
    /// records count as attributed until then (spec 038 FR-007, research
    /// R5).
    public var reattribute: Bool = false
}

public struct LogIndexStats: Equatable, Sendable {
    public var filesSeen = 0
    public var filesRead = 0
    public var bytesRead = 0
    public var recordsInWindow = 0
    /// Files read in this refresh whose profile in effect at the end of the
    /// read is named, or nil (spec 037 FR-012).
    public var filesWithProfile = 0
    public var filesWithoutProfile = 0

    public init() {}
}

/// In-memory incremental index over session log files (FR-018, research R8).
/// Not thread-safe by itself; `SessionLogSource` (an actor) owns it. Files
/// that need reading are parsed concurrently; merging is sequential.
public final class LogIndex {
    public private(set) var entries: [String: FileIndexEntry] = [:]
    private var priceTable: PriceTable?
    private var attributionFingerprint: String?
    /// Per canonical directory, the `Attributor.claimKey(forDirectory:)` its
    /// records were attributed with (spec 035 FR-012).
    private var claimKeys: [String: String] = [:]
    /// Window start of the previous update; records before it were pruned.
    private var lastWindowStart: Date?
    /// The profile candidates the entries were read with (spec 037 plan
    /// "Re-read rules in LogIndex").
    private var profileCandidates: SessionProfile.Candidates?
    /// Upper bound on the bytes read and parsed per batch. A full re-read
    /// over a month-long collection window (spec 003 research R2) would
    /// otherwise hold the raw lines of every changed file at once.
    private let batchBytes: Int
    private let projects: ProjectResolver

    public init(batchBytes: Int = 64 * 1024 * 1024, projectResolver: ProjectResolver = ProjectResolver()) {
        self.batchBytes = max(1, batchBytes)
        self.projects = projectResolver
    }

    /// Fallback notes from project resolution since the last call.
    public func drainProjectNotes() -> [String] {
        projects.drainNotes()
    }

    /// All indexed records, in a stable order (by file path, then timestamp).
    public var records: [UsageRecord] {
        entries.keys.sorted().flatMap { entries[$0]!.records }
    }

    public func reset() {
        entries = [:]
        claimKeys = [:]
        lastWindowStart = nil
        profileCandidates = nil
    }

    /// Work item for one file that changed since the last update.
    struct ReadJob {
        let file: ScannedFile
        let offset: Int
        let fresh: Bool
        /// The profile in effect before the first unread line: the entry's
        /// stored profile for appended lines, nil for a fresh read.
        var startProfile: String? = nil
        /// True for a read again after a rule sat out: if the rule times
        /// out again in this file, it is not flagged again, so a record the
        /// rule is always slow on costs no further reads (spec 038 FR-007,
        /// SC-005).
        var retry: Bool = false
        /// True for a retry of a file that grew since: it runs after the
        /// retries of unchanged files, since its appended lines are new
        /// data (spec 038 FR-007).
        var grew: Bool = false

        /// The processing order: retries of unchanged files, then of grown
        /// files, then everything else.
        var rank: Int { retry ? (grew ? 1 : 0) : 2 }
    }

    private struct ReadResult {
        var parsed: [(record: RawUsageRecord, rawLine: Data, profile: String?)] = []
        var consumed = 0
        var total = 0
        /// The profile in effect at the end of the read.
        var profile: String?
        var sawShapeLine = false
        var namedProfiles: Set<String> = []
        var sawNoneShapeLine = false
        var sawAmbiguousShapeLine = false
        /// True when the read named a profile for the first time in a file
        /// read before without one: its earlier records must be attributed
        /// again (spec 037 FR-001).
        var namedLate = false
    }

    /// `profiles` are the configured Claude Code directories a session
    /// file's shape lines may name (spec 037 FR-001); with none, no file
    /// gets a profile and attribution is unchanged.
    public func update(files: [ScannedFile], window: DateInterval, parser: SessionRecordParser,
                       attributor: Attributor, pricer: PriceTable,
                       profiles: SessionProfile.Candidates = .empty) -> LogIndexStats {
        var stats = LogIndexStats()
        stats.filesSeen = files.count

        // Attribution rules changed: raw lines are not kept, so start over.
        if let previous = attributionFingerprint, previous != attributor.fingerprint {
            entries = [:]
        }
        attributionFingerprint = attributor.fingerprint

        // The additional claims on a directory changed (a wildcard match
        // appeared, disappeared or left the cap, or a list was edited), or a
        // file is now reached through another directory: only those files
        // are read again, never the whole index (spec 035 FR-012, research
        // R5).
        var keys: [String: String] = [:]
        var directoryOfFile: [String: String] = [:]
        for file in files {
            directoryOfFile[file.canonicalPath] = file.configDirectory
            if keys[file.configDirectory] == nil {
                keys[file.configDirectory] = attributor.claimKey(forDirectory: file.configDirectory)
            }
        }
        for (key, entry) in entries {
            if let directory = directoryOfFile[key], directory != entry.configDirectory
                || claimKeys[entry.configDirectory] != keys[entry.configDirectory] {
                entries[key] = nil
            }
        }
        claimKeys = keys

        // The profile candidates changed: only files whose profiles could
        // change are read again (spec 037 FR-001, plan "Re-read rules in
        // LogIndex"):
        // - a named profile that left the candidates or changed claimants;
        // - a new spelling, when a shape line named none, which it may
        //   name now;
        // - a newly configured spelling (main directory or literal entry),
        //   when the file has any shape line, which may now name two;
        // - a removed spelling, when a shape line named several, which may
        //   name one now, or named that spelling's directory, which it may
        //   no longer name.
        // Files without shape lines keep their records, and a wildcard match
        // that appears or disappears re-reads only the files it can affect
        // (spec 035 FR-012). A new wildcard match that also appears in a
        // line already named stays unnoticed until the file changes.
        if let previous = profileCandidates, previous.key != profiles.key {
            let grew = !profiles.spellings.isSubset(of: previous.spellings)
            let configuredGrew = !profiles.configuredSpellings.isSubset(of: previous.configuredSpellings)
            let removed = previous.spellings.subtracting(profiles.spellings)
            let shrank = !removed.isEmpty
            // Directories that lost a spelling: a line that named one through
            // it may name none now.
            let lostSpelling = Set(removed.map(\.canonical))
            for (key, entry) in entries {
                let claimChanged = entry.namedProfiles.contains {
                    profiles.claimKey(forDirectory: $0) != previous.claimKey(forDirectory: $0)
                }
                if claimChanged
                    || (grew && entry.sawNoneShapeLine)
                    || (configuredGrew && entry.sawShapeLine)
                    || (shrank && entry.sawAmbiguousShapeLine)
                    || !entry.namedProfiles.isDisjoint(with: lostSpelling) {
                    entries[key] = nil
                }
            }
        }
        profileCandidates = profiles

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
            let existing = entries[file.canonicalPath]
            if let entry = existing, entry.size == file.size, entry.modificationDate == file.modificationDate, !entry.reattribute {
                continue
            }
            let existingOffset = existing?.parsedOffset ?? 0
            // A file read while a condition sat out is read from the start
            // (spec 038 research R5). That read is the retry of the records
            // the condition sat out on, also when lines were appended since,
            // so a time-out in it gives the condition up and an actively
            // written file settles like the others; a file that was
            // replaced (shorter than its parsed offset) is new data (spec
            // 038 FR-007, SC-005).
            let flagged = existing?.reattribute == true
            let retry = flagged && file.size >= existingOffset
            let grew = existing?.size != file.size || existing?.modificationDate != file.modificationDate
            let fresh = existing == nil || file.size < existingOffset || flagged
            jobs.append(ReadJob(file: file, offset: fresh ? 0 : existingOffset, fresh: fresh,
                                startProfile: fresh ? nil : entries[file.canonicalPath]?.profile, retry: retry,
                                grew: retry && grew))
        }

        // Retries of unchanged files first, then of grown files, then new
        // or changed data, each in scan order: a time-out in appended or new
        // data then cannot make the condition sit out for an unchanged
        // file's retry, and a retry that times out gives the condition up,
        // so the retries settle (spec 038 FR-007, SC-005).
        jobs = (0...2).flatMap { rank in jobs.filter { $0.rank == rank } }

        // Phases 2 and 3 run per batch of at most `batchBytes` unread bytes,
        // so peak memory is bounded by one batch, not by every changed file.
        var readPaths = Set<String>()
        var late: [ReadJob] = []
        for batch in Self.batches(of: jobs, maxBytes: batchBytes) {
            late += readAndMerge(batch, parser: parser, attributor: attributor, pricer: pricer, profiles: profiles, stats: &stats)
            readPaths.formUnion(batch.map(\.file.canonicalPath))
        }
        // A file whose first profile arrived in this read is read again
        // from the start, so its earlier records take that profile (spec
        // 037 FR-001).
        if !late.isEmpty {
            for batch in Self.batches(of: late, maxBytes: batchBytes) {
                _ = readAndMerge(batch, parser: parser, attributor: attributor, pricer: pricer, profiles: profiles, stats: &stats)
            }
        }
        for path in readPaths {
            if entries[path]?.profile != nil { stats.filesWithProfile += 1 } else { stats.filesWithoutProfile += 1 }
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

    /// Returns the jobs whose file named its first profile late and must be
    /// read again from the start.
    private func readAndMerge(_ jobs: ArraySlice<ReadJob>, parser: SessionRecordParser, attributor: Attributor,
                              pricer: PriceTable, profiles: SessionProfile.Candidates, stats: inout LogIndexStats) -> [ReadJob] {
        let jobs = Array(jobs)
        // Phase 2: read and parse changed files concurrently. Shape lines
        // are detected in file order, so each record takes the profile of
        // the latest shape line before it; records before the first one
        // take the first (spec 037 FR-001). Nothing of a shape line but
        // the matched directory is kept (FR-004).
        var results = [ReadResult?](repeating: nil, count: jobs.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
                let job = jobs[i]
                let (lines, consumed, total) = Self.readCompleteLines(path: job.file.canonicalPath, from: job.offset)
                var result = ReadResult(consumed: consumed, total: total)
                var current = job.startProfile
                var first: String?
                for line in lines {
                    // A usage record line is never a shape line, so only
                    // the other lines are searched for one.
                    if let record = parser.parse(data: line) {
                        result.parsed.append((record, line, current))
                        continue
                    }
                    guard !profiles.isEmpty else { continue }
                    switch SessionProfile.detect(line: line, candidates: profiles) {
                    case .named(let directory):
                        result.sawShapeLine = true
                        result.namedProfiles.insert(directory)
                        current = directory
                        if first == nil { first = directory }
                    case .none:
                        result.sawShapeLine = true
                        result.sawNoneShapeLine = true
                    case .ambiguous:
                        result.sawShapeLine = true
                        result.sawAmbiguousShapeLine = true
                    case .notShape:
                        break
                    }
                }
                if job.startProfile == nil, let first {
                    result.parsed = result.parsed.map { ($0.record, $0.rawLine, $0.profile ?? first) }
                    result.namedLate = !job.fresh
                }
                result.profile = current
                buffer[i] = result
            }
        }

        // Phase 3: merge sequentially (attribution, pricing, dedupe).
        var late: [ReadJob] = []
        for (i, job) in jobs.enumerated() {
            let result = results[i] ?? ReadResult()
            let file = job.file
            if result.namedLate {
                // Read again from the start with the profile (FR-001). The
                // bytes of this read count too; the file counts once, with
                // the second read.
                stats.bytesRead += result.total
                entries[file.canonicalPath] = nil
                late.append(ReadJob(file: file, offset: 0, fresh: true))
                continue
            }
            var entry = job.fresh
                ? FileIndexEntry(canonicalPath: file.canonicalPath, size: 0, modificationDate: file.modificationDate,
                                 parsedOffset: 0, configDirectory: file.configDirectory, records: [])
                : entries[file.canonicalPath]!
            stats.filesRead += 1
            stats.bytesRead += result.total
            if !result.parsed.isEmpty {
                let deduped = SessionRecordParser.dedupe(result.parsed.map(\.record))
                var rawByKey: [String: Data] = [:]
                var profileByKey: [String: String] = [:]
                for (raw, line, profile) in result.parsed {
                    rawByKey[Self.key(raw)] = line
                    profileByKey[Self.key(raw)] = profile
                }
                var merged: [String: UsageRecord] = [:]
                for existing in entry.records { merged[Self.key(existing)] = existing }
                // A rule that sits out, or times out, while this file is
                // attributed may have decided some of its records
                // differently: read the file again next time; a retry whose
                // own record timed out again is not read again until the
                // rules change (spec 038 FR-007, SC-005).
                let tracked = attributor.tracking(retry: job.retry) {
                    for raw in deduped {
                        let rawLine = rawByKey[Self.key(raw)].map { String(decoding: $0, as: UTF8.self) } ?? ""
                        let accountId = attributor.accountId(for: raw, rawLine: rawLine, fileConfigDirectory: file.configDirectory,
                                                             profileDirectory: profileByKey[Self.key(raw)])
                        merged[Self.key(raw)] = UsageRecord(raw: raw, canonicalModel: PriceTable.canonicalModel(raw.model),
                                                            accountId: accountId, costUSD: pricer.cost(of: raw),
                                                            project: projects.project(forCwd: raw.cwd))
                    }
                }
                if tracked.reattribute { entry.reattribute = true }
                entry.records = merged.values.sorted { $0.timestamp < $1.timestamp }
            }
            entry.parsedOffset = job.offset + result.consumed
            entry.size = job.offset + result.total
            entry.modificationDate = file.modificationDate
            entry.configDirectory = file.configDirectory
            entry.profile = result.profile
            entry.sawShapeLine = entry.sawShapeLine || result.sawShapeLine
            entry.namedProfiles.formUnion(result.namedProfiles)
            entry.sawNoneShapeLine = entry.sawNoneShapeLine || result.sawNoneShapeLine
            entry.sawAmbiguousShapeLine = entry.sawAmbiguousShapeLine || result.sawAmbiguousShapeLine
            entries[file.canonicalPath] = entry
        }
        return late
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
