import Foundation

/// `UsageSource` over the Claude Code session logs (FR-012, FR-018, FR-036).
public actor SessionLogSource: WindowSensitiveSource {
    public static let sourceName = "sessionLogs"
    public nonisolated let name = SessionLogSource.sourceName

    public struct ScanFailure: Error, CustomStringConvertible {
        public let description: String
    }

    private let paths: Paths
    private let log: DiagnosticLog?
    private let scanner: LogDirectoryScanner
    private let parser = SessionRecordParser()
    private let builtInPrices: PriceTable
    private let importedPrices: ImportedPriceStore?
    private let index: LogIndex
    private let fileSystem: any DirectoryFileSystem
    /// When a capped wildcard entry is logged (spec 035 FR-005).
    private var capLog = WildcardCapLog()

    /// `importedPrices` supplies the imported layer of the price table; its
    /// current value is read on every refresh (FR-001, FR-021).
    /// `fileSystem` lists folders for wildcard entries (spec 035 FR-004).
    public init(paths: Paths = Paths(), log: DiagnosticLog? = nil, builtInPrices: PriceTable? = nil,
                importedPrices: ImportedPriceStore? = nil,
                scanner: LogDirectoryScanner = LogDirectoryScanner(), index: LogIndex = LogIndex(),
                fileSystem: any DirectoryFileSystem = LocalDirectoryFileSystem()) throws {
        self.paths = paths
        self.log = log
        self.scanner = scanner
        self.builtInPrices = try builtInPrices ?? PriceTable.builtIn()
        self.importedPrices = importedPrices
        self.index = index
        self.fileSystem = fileSystem
    }

    /// The Claude Code directories of this refresh: the main directories,
    /// then the additional session directories of every Claude subscription
    /// and Vertex account with their wildcard matches, evaluated anew on
    /// every call (spec 035 FR-005, FR-008).
    public nonisolated func resolution(for configuration: Configuration) -> SessionDirectoryResolution {
        SessionDirectoryResolver(paths: paths, fileSystem: fileSystem).resolve(.claudeCode, configuration: configuration)
    }

    /// The paths of `resolution(for:)`, for tests: the main Claude Code
    /// directories of spec 034 FR-008, then the additional ones (spec 035
    /// FR-008). `SessionDirectoryResolver` owns the rules.
    nonisolated func directories(for configuration: Configuration) -> [String] {
        resolution(for: configuration).directories.map(\.path)
    }

    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let started = Date()
        let resolution = resolution(for: context.configuration)
        let scan = scanner.scan(targets: resolution.directories.map { ScanTarget(path: $0.path, isMain: $0.isMain, canonical: $0.canonical) })
        // An additional directory never fails the source or adds a problem:
        // its notes go to the log only (spec 035 FR-008).
        for note in scan.additionalNotes {
            log?.append(source: name, message: note)
        }
        // One line per wildcard entry, so a user can tell whether it matched
        // (spec 035 FR-016), and the cap line when it is due (FR-005).
        for report in resolution.wildcards {
            log?.append(source: name, message: "wildcard \"\(report.entry)\": \(report.matched) folder(s) matched")
            for line in report.listingLines {
                log?.append(source: name, message: line)
            }
        }
        for line in capLog.lines(for: resolution.wildcards, configuration: context.configuration) {
            log?.append(source: name, message: line)
        }
        // `errors` holds main directories only, so this fails only when
        // nothing could be scanned and a main directory reported the error.
        if scan.scannedDirectories == 0, !scan.errors.isEmpty {
            log?.append(source: name, message: "error: no log directory could be scanned: " + scan.errors.joined(separator: "; "))
            throw ScanFailure(description: "no log directory could be scanned: " + scan.errors.joined(separator: "; "))
        }
        let pricer = PriceTable.effective(builtIn: builtInPrices, imported: importedPrices?.current ?? .empty,
                                          overrides: context.configuration.priceOverrides)
        let attributor = Attributor(configuration: context.configuration, paths: paths,
                                    additionalDirectories: resolution.additionalByAccount)
        let stats = index.update(files: scan.files, window: context.window, parser: parser, attributor: attributor, pricer: pricer)
        let records = index.records
        let elapsed = Date().timeIntervalSince(started)
        var message = Self.statsLine(stats, directories: scan.scannedDirectories, elapsed: elapsed)
        if !scan.errors.isEmpty {
            message += ", scanner errors: " + scan.errors.joined(separator: "; ")
        }
        log?.append(source: name, message: message)
        let notes = index.drainProjectNotes()
        if !notes.isEmpty {
            log?.append(source: name, message: Self.summarizeProjectNotes(notes))
        }
        return .records(records)
    }

    /// The log line of a refresh. `%ld` because the counters are `Int`:
    /// `%d` reads 32 bits and turned byte counts above 2 GB negative.
    /// `directories` is the number of directories that existed and were
    /// read, main and additional (spec 035 FR-016).
    static func statsLine(_ stats: LogIndexStats, directories: Int, elapsed: TimeInterval) -> String {
        String(format: "directories read %ld, files seen %ld, re-read %ld (%ld bytes), records since collection start %ld, %.3f s",
               directories, stats.filesSeen, stats.filesRead, stats.bytesRead, stats.recordsInWindow, elapsed)
    }

    /// One line for all project fallbacks of a refresh: deleted scratch
    /// directories are common and must not flood the log.
    static func summarizeProjectNotes(_ notes: [String]) -> String {
        let shown = 5
        let details = notes.prefix(shown).map { $0.replacingOccurrences(of: "project fallback for ", with: "") }
        var text = "project fallback for \(notes.count) working director\(notes.count == 1 ? "y" : "ies"): "
            + details.joined(separator: "; ")
        if notes.count > shown { text += "; and \(notes.count - shown) more" }
        return text
    }

    public func resetForEarlierWindow() {
        index.reset()
        log?.append(source: name, message: "collection start moved earlier, index reset")
    }
}
