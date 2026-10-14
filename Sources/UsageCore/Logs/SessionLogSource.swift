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

    /// Default directory plus configured extra directories, expanded and deduplicated.
    public nonisolated func directories(for configuration: Configuration) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for dir in [Paths.defaultClaudeDirectory] + configuration.logDirectories {
            let expanded = paths.expand(dir)
            if seen.insert(expanded).inserted { result.append(expanded) }
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
        var message = String(format: "files seen %d, re-read %d (%d bytes), records since collection start %d, %.3f s",
                             stats.filesSeen, stats.filesRead, stats.bytesRead, stats.recordsInWindow, elapsed)
        if !scan.errors.isEmpty {
            message += ", scanner errors: " + scan.errors.joined(separator: "; ")
        }
        log?.append(source: name, message: message)
        return .records(records)
    }

    public func resetForEarlierWindow() {
        index.reset()
        log?.append(source: name, message: "collection start moved earlier, index reset")
    }
}
