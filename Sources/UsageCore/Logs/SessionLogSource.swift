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

    /// `importedPrices` supplies the imported layer of the price table; its
    /// current value is read on every refresh (FR-001, FR-021).
    public init(paths: Paths = Paths(), log: DiagnosticLog? = nil, builtInPrices: PriceTable? = nil,
                importedPrices: ImportedPriceStore? = nil,
                scanner: LogDirectoryScanner = LogDirectoryScanner(), index: LogIndex = LogIndex()) throws {
        self.paths = paths
        self.log = log
        self.scanner = scanner
        self.builtInPrices = try builtInPrices ?? PriceTable.builtIn()
        self.importedPrices = importedPrices
        self.index = index
    }

    /// Default directory, configured extra directories, then the credential
    /// directory of every Claude subscription account (spec 015 FR-006),
    /// expanded. Each directory appears once, compared by its canonical path
    /// (symlinks resolved, `..` removed), and keeps the expanded spelling it
    /// was first named with. A missing directory is skipped by the scanner
    /// like a missing extra directory (FR-007).
    public nonisolated func directories(for configuration: Configuration) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let credentialDirectories = configuration.subscriptionAccounts.compactMap { $0.kind.subscription?.credentialDirectory }
        for dir in [Paths.defaultClaudeDirectory] + configuration.logDirectories + credentialDirectories {
            let expanded = paths.expand(dir)
            if seen.insert(Attributor.canonical(expanded)).inserted { result.append(expanded) }
        }
        return result
    }

    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let started = Date()
        let dirs = directories(for: context.configuration)
        let scan = scanner.scan(directories: dirs)
        if scan.scannedDirectories == 0, !scan.errors.isEmpty {
            log?.append(source: name, message: "error: no log directory could be scanned: " + scan.errors.joined(separator: "; "))
            throw ScanFailure(description: "no log directory could be scanned: " + scan.errors.joined(separator: "; "))
        }
        let pricer = PriceTable.effective(builtIn: builtInPrices, imported: importedPrices?.current ?? .empty,
                                          overrides: context.configuration.priceOverrides)
        let attributor = Attributor(configuration: context.configuration, paths: paths)
        let stats = index.update(files: scan.files, window: context.window, parser: parser, attributor: attributor, pricer: pricer)
        let records = index.records
        let elapsed = Date().timeIntervalSince(started)
        var message = Self.statsLine(stats, elapsed: elapsed)
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
    static func statsLine(_ stats: LogIndexStats, elapsed: TimeInterval) -> String {
        String(format: "files seen %ld, re-read %ld (%ld bytes), records since collection start %ld, %.3f s",
               stats.filesSeen, stats.filesRead, stats.bytesRead, stats.recordsInWindow, elapsed)
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
