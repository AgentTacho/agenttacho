import Foundation

/// The session reader a bench run measures (spec 039 FR-001).
public enum ScanBenchReader: String, Sendable {
    case claudeCode = "claude"
    case codex
}

/// One bench run's settings (spec 039 data-model "ScanBenchOptions").
public struct ScanBenchOptions: Sendable {
    public var reader: ScanBenchReader
    /// The session directory to scan, as given (relative or absolute, `~`
    /// allowed); nil runs over the configuration's directories, as the app
    /// does.
    public var directory: String?
    /// The configuration file; nil is the app's, `Paths().configFileURL`.
    public var configurationFile: URL?
    /// The window start; nil derives the window from the configuration as
    /// the app does.
    public var windowStart: Date?
    /// The digest keeps only records stamped before it.
    public var until: Date?
    /// Where to write the records digest.
    public var digestPath: URL?
    /// True for `run`: the app's imported price file prices the records,
    /// as in the app. False for `digest`, so the committed fixture digests
    /// hold built-in prices and the configuration's overrides only
    /// (research R8).
    public var useImportedPrices: Bool
    /// The commit the binary was built from (`SCAN_BENCH_COMMIT`).
    public var commit: String
    /// The worker count to measure (`--workers`), clamped to the cores; nil
    /// is the app's default (spec 039 research R7).
    public var workers: Int?

    public init(reader: ScanBenchReader, directory: String? = nil, configurationFile: URL? = nil, windowStart: Date? = nil,
                until: Date? = nil, digestPath: URL? = nil, useImportedPrices: Bool = true, commit: String = "unknown",
                workers: Int? = nil) {
        self.reader = reader
        self.directory = directory
        self.configurationFile = configurationFile
        self.windowStart = windowStart
        self.until = until
        self.digestPath = digestPath
        self.useImportedPrices = useImportedPrices
        self.commit = commit
        self.workers = workers
    }
}

/// The figures of one bench run (spec 039 FR-002, data-model
/// "ScanBenchReport"). Counts, sizes, times and paths with `~` only, never
/// a session line (FR-003).
public struct ScanBenchReport: Sendable {
    /// The second `collect` right after the first: an incremental refresh
    /// over the files that changed in between (SC-005).
    public struct SecondRefresh: Equatable, Sendable {
        public var wall: Duration
        public var cpuSeconds: Double
        public var filesRead: Int
    }

    public var commit: String
    public var reader: ScanBenchReader
    public var directory: String
    public var configurationFile: String
    public var windowStart: String
    public var filesSeen: Int
    public var corpusBytes: Int
    public var filesRead: Int
    public var bytesRead: Int
    public var linesVisited: Int
    public var records: Int
    public var resources: ProcessResources.Delta
    /// The number of threads that parse files.
    public var workers: Int
    /// How the files are parsed, when the count alone does not say it.
    public var workersNote: String?
    public var secondRefresh: SecondRefresh
    /// The digest written, with `~`, and its record count.
    public var digest: (path: String, records: Int)?

    /// The report as `scan-bench run` prints it (contracts/bench-cli.md).
    public var text: String {
        let r = resources
        let megabyte = 1024.0 * 1024.0
        var lines = [
            "scan-bench 1  commit \(commit)  reader \(reader.rawValue)",
            "directory      \(directory)",
            "config         \(configurationFile)",
            "window start   \(windowStart)",
            String(format: "files seen     %ld   corpus bytes %ld   files read %ld   bytes read %ld   lines %ld   records %ld",
                   filesSeen, corpusBytes, filesRead, bytesRead, linesVisited, records),
            String(format: "wall           %.3f s", ProcessResources.seconds(r.wall)),
            String(format: "cpu            user %.1f s   system %.1f s   average %.0f%%",
                   ProcessResources.seconds(r.userCPU), ProcessResources.seconds(r.systemCPU), r.averageCPU * 100),
            String(format: "peak memory    footprint %.0f MB   rss %.0f MB", Double(r.maxPhysicalFootprint) / megabyte, Double(r.maxRSS) / megabyte),
            String(format: "disk read      %.0f MB", Double(r.diskBytesRead) / megabyte),
            "workers        \(workers)" + (workersNote.map { " (\($0))" } ?? ""),
            String(format: "second refresh wall %.3f s   cpu %.1f s   files read %ld",
                   ProcessResources.seconds(secondRefresh.wall), secondRefresh.cpuSeconds, secondRefresh.filesRead),
        ]
        if let digest {
            lines.append("digest         \(digest.path) (\(digest.records) records)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// A problem with the bench's arguments or files: the bench exits with
/// code 2 and prints the text, one line naming the path with `~`
/// (contracts/bench-cli.md).
public enum ScanBenchError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message): return message
        }
    }
}

/// The maintainer bench: runs a reader's refresh code path over a session
/// directory with an empty index, measures it and writes a records digest
/// (spec 039 FR-001 to FR-005, research R8).
public enum ScanBench {
    /// Builds the source as `App.swift` does, runs two `collect` calls with
    /// `ProcessResources` snapshots around each, and writes the digest of
    /// the first when asked. Throws `ScanBenchError.invalid` before any
    /// scan for a missing or unreadable directory or configuration, and for
    /// a digest path under an agent's directory. Never writes under the
    /// agents' directories, and never creates or changes the
    /// configuration file (spec 039 FR-004, constitution III).
    public static func run(_ options: ScanBenchOptions, paths: Paths = Paths()) async throws -> ScanBenchReport {
        let text = PathText(paths: paths)
        let directory = try validatedDirectory(options, text: text)
        let configurationFile = options.configurationFile ?? paths.configFileURL
        let configuration = try loadConfiguration(configurationFile, text: text)
        let harness: Harness = options.reader == .claudeCode ? .claudeCode : .codex
        let resolver = SessionDirectoryResolver(paths: paths)
        let configured = resolver.resolve(harness, configuration: configuration).directories
        if let digest = options.digestPath {
            // Every configured session directory of both agents, whichever
            // reader runs: the digest never lands under an agent's
            // directory (FR-004).
            let agentDirectories = [Harness.claudeCode, .codex].flatMap { resolver.resolve($0, configuration: configuration).directories }
            let bases = [paths.home.appendingPathComponent(".claude").path, paths.home.appendingPathComponent(".codex").path]
                + (directory.map { [$0.absolute] } ?? [])
                + agentDirectories.flatMap { [$0.path, $0.canonical] }
            // The `projects` and `sessions` trees the readers walk may be
            // links that lead out of their directory; where they lead is
            // refused too.
            let trees = bases.flatMap { base in ["projects", "sessions"].map { (base as NSString).appendingPathComponent($0) } }
            try refuseDigest(digest, under: bases + trees, text: text)
        }

        let builtIn: PriceTable
        do {
            builtIn = try PriceTable.builtIn()
        } catch {
            throw ScanBenchError.invalid("cannot load the built-in prices: \(text.oneLine("\(error)"))")
        }
        var imported: ImportedPriceStore?
        if options.useImportedPrices {
            // Read only: a missing file means no imports (spec 017 FR-027).
            let store = ImportedPriceStore(fileURL: paths.importedPricesFileURL)
            store.load()
            imported = store
        }

        // The refresh line of FR-007 is written, but to a temporary file,
        // never to the app's log.
        let logDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttacho-scan-bench-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: logDirectory) }
        let log = DiagnosticLog(fileURL: logDirectory.appendingPathComponent("usage.log"))

        let now = Date()
        let window: DateInterval
        if let since = options.windowStart {
            window = DateInterval(start: since, end: max(now, since))
        } else {
            // As `RefreshCoordinator` derives it, without a fetched reset.
            let calendar = Calendar.current
            let resolver = WindowResolver()
            let (weekly, _) = resolver.resolve(now: now, alignmentReset: nil, fallback: configuration.weekFallback, calendar: calendar)
            window = resolver.collectionWindow(weekly: weekly, now: now, configuration: configuration, calendar: calendar)
        }
        let context = RefreshContext(configuration: configuration, window: window, now: now)

        // The workers of the measured source and its index: the app's
        // default, or the count of the worker-count step (research R7).
        let workers = options.workers.map { ScanWorkers(count: $0) } ?? .default
        let measured: Measurement
        do {
            switch options.reader {
            case .claudeCode:
                let source = try SessionLogSource(paths: paths, log: log, builtInPrices: builtIn, importedPrices: imported,
                                                  index: LogIndex(workers: workers), workers: workers,
                                                  scanTargets: directory.map { [ScanTarget(path: $0.absolute, isMain: true)] })
                measured = try await measure(collect: {
                    guard case .records(let records) = try await source.collect(context: context) else { return [] }
                    return records
                }, figures: { await source.lastScanFigures })
            case .codex:
                let source = try CodexSessionSource(paths: paths, log: log, builtInPrices: builtIn, importedPrices: imported,
                                                    workers: workers, homes: directory.map { [$0.absolute] })
                measured = try await measure(collect: {
                    guard case .recordBatch(let batch) = try await source.collect(context: context) else { return [] }
                    return batch.records
                }, figures: { await source.lastScanFigures })
            }
        } catch let error as ScanBenchError {
            throw error
        } catch {
            throw ScanBenchError.invalid("the scan failed: \(text.oneLine("\(error)"))")
        }

        let shownDirectory = directory?.shown ?? configured.map { text.shown($0.path) }.joined(separator: ", ")
        let shownConfiguration = text.shown(options.configurationFile.map(\.relativePath) ?? configurationFile.path)
        let windowStart = Self.isoText(window.start)
        var digestWritten: (path: String, records: Int)?
        if let digestURL = options.digestPath {
            let digest = RecordsDigest(records: measured.records,
                                       header: RecordsDigest.Header(configuration: shownConfiguration, windowStart: windowStart,
                                                                    directory: shownDirectory),
                                       until: options.until)
            do {
                try Data(digest.text.utf8).write(to: digestURL, options: .atomic)
            } catch {
                throw ScanBenchError.invalid("cannot write the digest \(text.shown(digestURL.relativePath))")
            }
            digestWritten = (text.shown(digestURL.relativePath), digest.lines.count)
        }

        return ScanBenchReport(commit: options.commit, reader: options.reader, directory: shownDirectory,
                               configurationFile: shownConfiguration, windowStart: windowStart,
                               filesSeen: measured.first.filesSeen, corpusBytes: measured.first.corpusBytes,
                               filesRead: measured.first.filesRead, bytesRead: measured.first.bytesRead,
                               linesVisited: measured.first.linesVisited, records: measured.records.count,
                               resources: measured.resources, workers: workers.count,
                               workersNote: options.workers == nil ? "default, \(workers.qos)" : "\(workers.qos)",
                               secondRefresh: measured.second, digest: digestWritten)
    }

    /// Loads two digest files and compares their record lines (spec 039
    /// FR-005). A missing or unreadable file, or one that is no digest,
    /// gives no verdict.
    public static func compare(_ a: URL, _ b: URL, paths: Paths = Paths()) throws -> RecordsDigest.Comparison {
        let text = PathText(paths: paths)
        return RecordsDigest.compare(try loadDigest(a, text: text), try loadDigest(b, text: text))
    }

    // MARK: - Steps

    private struct Measurement {
        var records: [UsageRecord]
        var first: ScanFigures
        var resources: ProcessResources.Delta
        var second: ScanBenchReport.SecondRefresh
    }

    /// Two `collect` calls on the same source: the first with an empty
    /// index is the measured scan, the second the incremental refresh.
    private static func measure(collect: () async throws -> [UsageRecord],
                                figures: () async -> ScanFigures) async throws -> Measurement {
        let before = ProcessResources.snapshot()
        let records = try await collect()
        let after = ProcessResources.snapshot()
        let first = await figures()
        let secondBefore = ProcessResources.snapshot()
        _ = try await collect()
        let secondDelta = ProcessResources.snapshot().delta(since: secondBefore)
        let second = await figures()
        return Measurement(records: records, first: first, resources: after.delta(since: before),
                           second: ScanBenchReport.SecondRefresh(wall: secondDelta.wall,
                                                                 cpuSeconds: ProcessResources.seconds(secondDelta.cpu),
                                                                 filesRead: second.filesRead))
    }

    private struct Directory {
        let absolute: String
        let shown: String
    }

    /// The directory must exist, be readable and hold the folder the reader
    /// scans: `projects` for Claude Code, `sessions` for Codex.
    private static func validatedDirectory(_ options: ScanBenchOptions, text: PathText) throws -> Directory? {
        guard let given = options.directory else { return nil }
        let absolute = text.absolute(given)
        let shown = text.shown(given)
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: absolute, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScanBenchError.invalid("directory not found: \(shown)")
        }
        guard fm.isReadableFile(atPath: absolute), (try? fm.contentsOfDirectory(atPath: absolute)) != nil else {
            throw ScanBenchError.invalid("directory not readable: \(shown)")
        }
        let folder = options.reader == .claudeCode ? "projects" : "sessions"
        let folderPath = (absolute as NSString).appendingPathComponent(folder)
        var folderIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folderPath, isDirectory: &folderIsDirectory), folderIsDirectory.boolValue else {
            throw ScanBenchError.invalid("no \(folder) folder in \(shown)")
        }
        // The readers note an unreadable tree and go on with no files, which
        // would read as a successful empty scan.
        guard fm.isReadableFile(atPath: folderPath), (try? fm.contentsOfDirectory(atPath: folderPath)) != nil else {
            throw ScanBenchError.invalid("\(folder) folder not readable in \(shown)")
        }
        return Directory(absolute: absolute, shown: shown)
    }

    /// Checks that the file exists and is readable before `ConfigStore`
    /// sees it: `load()` writes a default file where none exists (spec 001
    /// FR-034), and the bench must never create or change one. A file that
    /// does not decode or validate is an error, never a fallback to a
    /// default configuration.
    private static func loadConfiguration(_ url: URL, text: PathText) throws -> Configuration {
        let shown = text.shown(url.relativePath)
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ScanBenchError.invalid("configuration file not found: \(shown)")
        }
        guard fm.isReadableFile(atPath: url.path), (try? Data(contentsOf: url)) != nil else {
            throw ScanBenchError.invalid("configuration file not readable: \(shown)")
        }
        let (configuration, error) = ConfigStore(fileURL: url).load()
        if let error {
            throw ScanBenchError.invalid("configuration file \(shown) is not valid: \(text.oneLine(error.message))")
        }
        return configuration
    }

    /// Refuses a digest path at or below any of `roots`: the agents'
    /// directories, the scanned directory and the configured session
    /// directories (spec 039 FR-004).
    private static func refuseDigest(_ digest: URL, under roots: [String], text: PathText) throws {
        let target = text.absolute(digest.path)
        // `absolute` collapses a `..` as text, while the write climbs from
        // where a link before it leads: the path as the write reaches it is
        // checked too.
        let resolved = [canonicalPath(target)] + (physicalPath(digest.path, text: text).map { [$0] } ?? [])
        for root in roots where !root.isEmpty {
            let rootCanonical = canonicalPath(root)
            if isPath(target, under: root) || resolved.contains(where: { isPath($0, under: rootCanonical) }) {
                throw ScanBenchError.invalid("digest path under an agent or session directory: \(text.shown(digest.relativePath))")
            }
        }
    }

    /// The path with its folder resolved by the system, links and `..` in
    /// the order a write follows them; nil when the folder does not exist,
    /// so the write would fail anyway.
    static func physicalPath(_ path: String, text: PathText) -> String? {
        let expanded = text.paths.expand(path)
        let absolute = expanded.hasPrefix("/") ? expanded : FileManager.default.currentDirectoryPath + "/" + expanded
        guard let real = realpath((absolute as NSString).deletingLastPathComponent, nil) else { return nil }
        defer { free(real) }
        return (String(cString: real) as NSString).appendingPathComponent((absolute as NSString).lastPathComponent)
    }

    private static func isPath(_ path: String, under root: String) -> Bool {
        let base = root.count > 1 && root.hasSuffix("/") ? String(root.dropLast()) : root
        return path == base || path.hasPrefix(base == "/" ? "/" : base + "/")
    }

    /// The path with symlinks resolved, also for a path that does not
    /// exist yet: the longest existing ancestor is resolved and the rest
    /// appended.
    static func canonicalPath(_ path: String) -> String {
        var existing = (path as NSString).standardizingPath
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing), existing != "/", !existing.isEmpty {
            rest.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        var resolved = existing
        if let real = realpath(existing, nil) {
            resolved = String(cString: real)
            free(real)
        }
        return rest.reduce(resolved) { ($0 as NSString).appendingPathComponent($1) }
    }

    private static func loadDigest(_ url: URL, text: PathText) throws -> RecordsDigest {
        let shown = text.shown(url.relativePath)
        guard !url.relativePath.isEmpty, FileManager.default.fileExists(atPath: url.path) else {
            throw ScanBenchError.invalid("digest file not found: \(shown)")
        }
        guard let data = try? Data(contentsOf: url) else {
            throw ScanBenchError.invalid("digest file not readable: \(shown)")
        }
        do {
            return try RecordsDigest.parse(String(decoding: data, as: UTF8.self))
        } catch {
            throw ScanBenchError.invalid("not a records digest: \(shown)")
        }
    }

    static func isoText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// Paths as the bench shows them: with `~` for the home directory, a
/// relative path as given (spec 039 FR-003).
struct PathText {
    let paths: Paths

    /// `~` expanded, a relative path resolved against the current directory.
    func absolute(_ path: String) -> String {
        let expanded = paths.expand(path)
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(expanded)
        return url.standardizedFileURL.path
    }

    /// An absolute path below the home directory with `~`; a relative path
    /// or one already written with `~` as given.
    func shown(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        let home = paths.home.path
        let standardized = (path as NSString).standardizingPath
        if standardized == home { return "~" }
        if standardized.hasPrefix(home + "/") { return "~" + standardized.dropFirst(home.count) }
        return standardized
    }

    /// Error text from elsewhere as one line, with `~` for the home
    /// directory.
    func oneLine(_ message: String) -> String {
        message.replacingOccurrences(of: paths.home.path, with: "~")
            .components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
