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
    /// Slow regex values and given-up rules from the last refresh (spec
    /// 038 FR-007, SC-005).
    private var matchMemory = MatchMemory()
    /// The bench's directory override; nil in the app (spec 039 research
    /// R8).
    private let scanTargets: [ScanTarget]?
    /// What the last refresh read, for the bench (spec 039 FR-002).
    private(set) var lastScanFigures = ScanFigures()
    /// Runs the index update off the actor (spec 039 FR-018).
    private let workers: ScanWorkers
    /// True while a scan is offloaded. The actor is suspended meanwhile
    /// and can take other calls: a `collect` waits for the scan to end, a
    /// reset is deferred, so the index is never touched by two at once
    /// (spec 039 research R7).
    private var scanning = false
    /// The `collect` calls waiting for the running scan, resumed in order
    /// when it ends; each checks `scanning` again before it runs.
    private var scanWaiters: [CheckedContinuation<Void, Never>] = []
    /// A `resetForEarlierWindow()` that arrived during a scan, applied at
    /// the end of that scan's `collect`.
    private var resetPending = false
    /// Checks the sessions' working directories for decision logs (spec 045
    /// FR-001, FR-012).
    private let probe: DecisionLogProbe
    /// The classifier rows read so far (spec 045 FR-003).
    private let classifierIndex = ClassifierLogIndex()

    /// `importedPrices` supplies the imported layer of the price table; its
    /// current value is read on every refresh (FR-001, FR-021).
    /// `fileSystem` lists folders for wildcard entries (spec 035 FR-004).
    /// `workers` runs the index update off the actor; the index parses its
    /// files on its own workers (spec 039 FR-017, FR-018). `scanTargets`,
    /// set only by the bench, replaces the configuration's directories for
    /// the scan; the profile candidates and the attribution still come from
    /// the configuration (spec 039 research R8). `probe` checks working
    /// directories for decision logs (spec 045 FR-012).
    public init(paths: Paths = Paths(), log: DiagnosticLog? = nil, builtInPrices: PriceTable? = nil,
                importedPrices: ImportedPriceStore? = nil,
                scanner: LogDirectoryScanner = LogDirectoryScanner(), index: LogIndex = LogIndex(),
                fileSystem: any DirectoryFileSystem = LocalDirectoryFileSystem(),
                workers: ScanWorkers = .default, scanTargets: [ScanTarget]? = nil,
                probe: DecisionLogProbe = DecisionLogProbe()) throws {
        self.paths = paths
        self.log = log
        self.scanner = scanner
        self.builtInPrices = try builtInPrices ?? PriceTable.builtIn()
        self.importedPrices = importedPrices
        self.index = index
        self.fileSystem = fileSystem
        self.workers = workers
        self.scanTargets = scanTargets
        self.probe = probe
    }

    /// The Claude Code directories of this refresh: the main directories,
    /// then the additional session directories of every Claude subscription
    /// and token-based Claude Code account with their wildcard matches,
    /// evaluated anew on every call (spec 035 FR-005, FR-008, spec 037
    /// FR-006).
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
        // One scan at a time (spec 039 research R7): a call that arrives
        // during a scan waits for it and checks again when resumed.
        while scanning {
            await withCheckedContinuation { scanWaiters.append($0) }
        }
        scanning = true
        defer { endScan() }
        let started = Date()
        // The process's CPU seconds of this refresh, for its log line
        // (spec 039 FR-007).
        let cpuStarted = ProcessResources.cpuSeconds()
        let resolution = resolution(for: context.configuration)
        let scan = scanner.scan(targets: scanTargets
            ?? resolution.directories.map { ScanTarget(path: $0.path, isMain: $0.isMain, canonical: $0.canonical) })
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
                                    additionalDirectories: resolution.additionalByAccount,
                                    profileAdditionalDirectories: resolution.profileAdditionalByAccount,
                                    matchMemory: matchMemory)
        let profiles = Self.profileCandidates(configuration: context.configuration, resolution: resolution, paths: paths)
        // The update runs on a dispatch thread at the refresh's priority
        // while this actor waits suspended, so neither the actor nor the
        // cooperative pool is held (spec 039 FR-018); its parse jobs run at
        // utility, its merge and attribution at the refresh's priority (spec
        // 038 FR-007). The box carries the index there: `scanning`
        // keeps every other use of the index out until the update returns.
        let box = UncheckedSendableBox(index)
        let classifierBox = UncheckedSendableBox(classifierIndex)
        let files = scan.files
        let window = context.window
        let parser = parser
        let probe = probe
        // The classifier step runs in the same offloaded closure, after the
        // index update; the probe's checks run on their own threads (spec
        // 045 plan "Refresh flow").
        let (stats, sessionRecords, classifier) = await workers.offload {
            let stats = box.value.update(files: files, window: window, parser: parser, attributor: attributor, pricer: pricer,
                                         profiles: profiles)
            let sessionRecords = box.value.records
            let classifier = Self.classifierStep(sessionRecords: sessionRecords, index: classifierBox.value, probe: probe,
                                                 window: window, pricer: pricer)
            return (stats, sessionRecords, classifier)
        }
        lastScanFigures = ScanFigures(filesSeen: stats.filesSeen, filesRead: stats.filesRead, bytesRead: stats.bytesRead,
                                      linesVisited: stats.linesVisited, corpusBytes: scan.files.reduce(0) { $0 + $1.size })
        // The index reads the files a sat-out rule touched again next time;
        // the memory keeps that bounded (spec 038 FR-007, SC-005).
        matchMemory = attributor.matchMemory
        for account in attributor.drainSitOutAccounts() {
            log?.append(source: name, message: Attributor.sitOutLogLine(account: account))
        }
        let records = sessionRecords + classifier.attribution.records
        let elapsed = Date().timeIntervalSince(started)
        var message = Self.statsLine(stats, directories: scan.scannedDirectories, elapsed: elapsed,
                                     cpu: ProcessResources.cpuSeconds() - cpuStarted)
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

    /// What the classifier step of one refresh produced (spec 045 plan
    /// "Refresh flow").
    struct ClassifierStepResult {
        var report: ProbeReport
        var indexStats: ClassifierIndexStats
        var attribution: ClassifierAttributionResult
    }

    /// The classifier step (spec 045 plan "Refresh flow", steps 2 to 5): the
    /// distinct working directories of the in-window Claude Code session
    /// records are checked by the probe, the index parses what it read, and
    /// every counted row is attributed anew from the current session spans
    /// (FR-001, FR-002, FR-003, FR-006).
    static func classifierStep(sessionRecords: [UsageRecord], index: ClassifierLogIndex, probe: DecisionLogProbe,
                               window: DateInterval, pricer: PriceTable) -> ClassifierStepResult {
        var directories = Set<String>()
        for record in sessionRecords where record.origin == .session && record.harness == .claudeCode
            && record.timestamp >= window.start {
            if let cwd = record.cwd { directories.insert(cwd) }
        }
        let report = probe.check(directories: directories.sorted(), known: index.known(), notBefore: window.start)
        let indexStats = index.update(report: report, window: window)
        let attribution = ClassifierAttribution.records(entries: index.sortedEntries, sessionRecords: sessionRecords,
                                                        canonical: report.canonical, pricer: pricer)
        return ClassifierStepResult(report: report, indexStats: indexStats, attribution: attribution)
    }

    /// The directories a session file's shape lines may name: every
    /// account's main Claude Code directory (a Claude subscription's, a
    /// token-based Claude Code account's, `~/.claude` for an empty field)
    /// and every spelling of the additional directories of this refresh
    /// with their wildcard matches, each with its claimant (spec 037 FR-001,
    /// FR-002, FR-003).
    /// The home folder and `/` are no Claude Code directory (spec 034 FR-008).
    static func profileCandidates(configuration: Configuration, resolution: SessionDirectoryResolution,
                                  paths: Paths) -> SessionProfile.Candidates {
        let homeOrRoot: Set<String> = [Attributor.canonical(paths.home.path), "/"]
        var entries: [SessionProfile.Entry] = []
        for account in configuration.accounts {
            guard let main = account.agentDirectory(for: .claudeCode),
                  !homeOrRoot.contains(Attributor.canonical(paths.expand(main))) else { continue }
            entries.append(SessionProfile.Entry(accountId: account.id, path: main, rank: .main))
        }
        // Every listed or matched spelling, so an alias of a directory read
        // through another spelling is still found (FR-002).
        for item in resolution.profileSpellings {
            entries.append(SessionProfile.Entry(accountId: item.accountId, path: item.path, canonical: item.canonical,
                                                rank: .additional, isWildcardMatch: item.isWildcardMatch))
        }
        return SessionProfile.Candidates(entries: entries, paths: paths)
    }

    /// The log line of a refresh. `%ld` because the counters are `Int`:
    /// `%d` reads 32 bits and turned byte counts above 2 GB negative.
    /// `directories` is the number of directories that existed and were
    /// read, main and additional (spec 035 FR-016). The profile counts say
    /// how many files read in this refresh named a configured directory and
    /// how many named none, so a change of Claude Code's file format shows
    /// up (spec 037 FR-012). `cpu` is the process's CPU seconds between the
    /// start and the end of the refresh, whatever else the app did
    /// meanwhile (spec 039 FR-007).
    static func statsLine(_ stats: LogIndexStats, directories: Int, elapsed: TimeInterval, cpu: Double? = nil) -> String {
        let line = String(format: "directories read %ld, files seen %ld, re-read %ld (%ld bytes), records since collection start %ld, profile named %ld, none %ld, %.3f s",
                          directories, stats.filesSeen, stats.filesRead, stats.bytesRead, stats.recordsInWindow,
                          stats.filesWithProfile, stats.filesWithoutProfile, elapsed)
        return cpu.map { line + String(format: ", cpu %.1f s", $0) } ?? line
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

    /// Drops the index. During a scan the reset waits for the scan's end, so
    /// the running `collect` still returns its records and the next one
    /// reads every file again (spec 039 research R7).
    public func resetForEarlierWindow() {
        guard !scanning else {
            resetPending = true
            return
        }
        resetIndex()
    }

    private func resetIndex() {
        index.reset()
        classifierIndex.reset()
        log?.append(source: name, message: "collection start moved earlier, index reset")
    }

    /// Ends a `collect`, after its records, figures and log line were
    /// taken: applies a deferred reset, then lets the waiting calls in.
    private func endScan() {
        if resetPending {
            resetPending = false
            resetIndex()
        }
        scanning = false
        let waiters = scanWaiters
        scanWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// True while a scan runs, for the tests of spec 039 FR-018.
    func isScanning() -> Bool { scanning }

    /// The `collect` calls waiting for the running scan, for the tests.
    func waitingCollects() -> Int { scanWaiters.count }
}
