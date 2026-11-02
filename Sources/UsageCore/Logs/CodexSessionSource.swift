import Foundation

/// `UsageSource` over Codex rollout files (spec 006 FR-001 to FR-015,
/// research R4). Scans `<home>/sessions/**/rollout-*.jsonl` for the Codex
/// home of every Codex account, `~/.codex` for an empty field (spec 034
/// FR-008), read-only. Credential files in
/// the Codex home are never opened: the auth mode comes from the session
/// logs only.
///
/// A file is parsed again as a whole only when its size or modification
/// date changed (FR-004). Every refresh resolves each session's auth mode
/// from the stored sessions, so a plan marker that appears later
/// re-attributes the session's earlier turns (FR-014).
public actor CodexSessionSource: WindowSensitiveSource {
    public static let sourceName = "codex"
    public nonisolated let name = CodexSessionSource.sourceName

    /// A Codex home to scan: expanded path, whether it is the default
    /// location (skipped silently when missing, FR-002), and the route that
    /// named it: an account's main home or an additional session directory
    /// (spec 035 FR-008).
    public struct Location: Equatable, Sendable {
        public let directory: String
        public let isDefault: Bool
        public let origin: SessionDirectory.Origin

        public init(directory: String, isDefault: Bool, origin: SessionDirectory.Origin = .main) {
            self.directory = directory
            self.isDefault = isDefault
            self.origin = origin
        }

        /// Main homes keep their spec 006 issues; additional homes are only
        /// logged (spec 035 FR-008).
        public var isMain: Bool { origin == .main }
    }

    /// The parsed session of one file and what decided to parse it.
    struct FileEntry {
        var size: Int
        var modificationDate: Date
        /// Canonical Codex home the file was found in (FR-015 tie-breaker).
        var home: String
        var session: CodexSession
        /// The records built for `hint` and the home's additional claims
        /// (`Attributor.claimKey`), so an unchanged file costs nothing on the
        /// next refresh (FR-004). Rebuilt when either changes (spec 035
        /// FR-012); cleared when rules or prices change.
        var built: (hint: String, claim: String, records: [UsageRecord])?
        /// Set when a condition sat out or timed out while the records were
        /// built: the next refresh builds them again, once more unless the
        /// time-out happened in this session (spec 038 FR-007, SC-005).
        var reattribute = false
    }

    private let paths: Paths
    private let log: DiagnosticLog?
    private let builtInPrices: PriceTable
    private let importedPrices: ImportedPriceStore?
    private let parser = CodexSessionParser()
    private let projects: ProjectResolver
    private let fileSystem: any DirectoryFileSystem

    /// Keyed by canonical file path.
    private var files: [String: FileEntry] = [:]
    /// Plan marker and parent of sessions outside the window, by session
    /// id, read only to resolve a subagent's auth mode (FR-014).
    private var outsideSessions: [String: (planMarker: Bool, parent: String?)] = [:]
    private var lastWindowStart: Date?
    private var attributionFingerprint: String?
    private var priceTable: PriceTable?
    /// Slow regex values and given-up rules from the last refresh (spec
    /// 038 FR-007, SC-005).
    private var matchMemory = MatchMemory()
    /// True when a session waits for its records to be built again after a
    /// condition sat out (spec 038 FR-007).
    var reattributeNext: Bool { files.values.contains { $0.reattribute } }

    /// When a capped wildcard entry is logged (spec 035 FR-005).
    private var capLog = WildcardCapLog()

    /// Files parsed by the last `collect` (for tests).
    public private(set) var lastFilesParsed = 0
    /// The resolved auth mode hint per session id of the last `collect` (for tests).
    private(set) var lastHints: [String: String] = [:]
    /// What the last refresh read, for the bench; parent files read only
    /// for the auth mode do not count (spec 039 FR-002, research R6).
    private(set) var lastScanFigures = ScanFigures()
    /// The bench's home override; nil in the app (spec 039 research R8).
    private let homeOverride: [String]?
    /// Read and parse the changed files and the parents' files off the
    /// actor (spec 039 FR-017, FR-018).
    private let workers: ScanWorkers
    /// True while a scan runs; the actor is suspended while the workers
    /// parse and can take other calls: a `collect` waits for the scan to
    /// end, a reset is deferred, so two collects never decide the same
    /// files at once (spec 039 research R7).
    private var scanning = false
    /// The `collect` calls waiting for the running scan, resumed in order
    /// when it ends; each checks `scanning` again before it runs.
    private var scanWaiters: [CheckedContinuation<Void, Never>] = []
    /// A `resetForEarlierWindow()` that arrived during a scan, applied at
    /// the end of that scan's `collect`.
    private var resetPending = false

    /// `workers` reads and parses the files off the actor (spec 039
    /// FR-017). `homes`, set only by the bench, replaces the
    /// configuration's Codex homes for the scan; attribution and pricing
    /// still come from the configuration (spec 039 research R8).
    public init(paths: Paths = Paths(), log: DiagnosticLog? = nil, builtInPrices: PriceTable? = nil,
                importedPrices: ImportedPriceStore? = nil, projectResolver: ProjectResolver = ProjectResolver(),
                fileSystem: any DirectoryFileSystem = LocalDirectoryFileSystem(), workers: ScanWorkers = .default,
                homes: [String]? = nil) throws {
        self.paths = paths
        self.log = log
        self.builtInPrices = try builtInPrices ?? PriceTable.builtIn()
        self.importedPrices = importedPrices
        self.projects = projectResolver
        self.fileSystem = fileSystem
        self.workers = workers
        self.homeOverride = homes
    }

    /// The locations of `resolution(for:)`, for tests: the main Codex homes
    /// of spec 034 FR-008, then the additional ones, never the default
    /// location (spec 035 FR-008). `SessionDirectoryResolver` owns the
    /// rules; `collect` checks the canonical home again (FR-003).
    nonisolated func homes(for configuration: Configuration) -> [Location] {
        locations(of: resolution(for: configuration))
    }

    /// The Codex homes of this refresh, evaluated anew on every call (spec
    /// 035 FR-005, FR-008).
    nonisolated func resolution(for configuration: Configuration) -> SessionDirectoryResolution {
        SessionDirectoryResolver(paths: paths, fileSystem: fileSystem).resolve(.codex, configuration: configuration)
    }

    private nonisolated func locations(of resolution: SessionDirectoryResolution) -> [Location] {
        let defaultHome = fileSystem.canonicalPath(paths.expand(Paths.defaultCodexHome))
        return resolution.directories.map {
            Location(directory: $0.path, isDefault: $0.isMain && $0.canonical == defaultHome, origin: $0.origin)
        }
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
        let configuration = context.configuration
        let window = context.window
        let pricer = PriceTable.effective(builtIn: builtInPrices, imported: importedPrices?.current ?? .empty,
                                          overrides: configuration.priceOverrides)
        let resolution = resolution(for: configuration)
        let attributor = Attributor(configuration: configuration, paths: paths,
                                    additionalDirectories: resolution.additionalByAccount, matchMemory: matchMemory)

        // A file is dropped once its modification date is before the window
        // start, so an earlier start needs a fresh scan (FR-023).
        if let previous = lastWindowStart, window.start < previous {
            reset()
        }
        lastWindowStart = window.start
        // Sessions a condition sat out on in the last refresh are built
        // again, without reading files again; with unchanged rules that is a
        // retry (spec 038 FR-007, SC-005).
        let rulesUnchanged = attributionFingerprint == attributor.fingerprint
        var retries = Set<String>()
        // Retries of sessions that grew since: they run after the retries
        // of unchanged sessions, since their new lines are new data.
        var grownRetries = Set<String>()
        for (key, entry) in files where entry.reattribute {
            files[key]?.built = nil
            files[key]?.reattribute = false
            if rulesUnchanged { retries.insert(key) }
        }
        // Rules or prices changed: rebuild the records from the stored
        // sessions, without reading files again.
        if attributionFingerprint != attributor.fingerprint || priceTable != pricer {
            for key in files.keys { files[key]?.built = nil }
            attributionFingerprint = attributor.fingerprint
            priceTable = pricer
        }

        var issues: [String] = []
        var present = Set<String>()
        var seenHomes = Set<String>()
        var parsed = 0
        var perHome: [(home: String, location: String, filesRead: Int, origin: SessionDirectory.Origin)] = []
        /// Files modified before the window start: not counted, but a
        /// subagent's parent may live in one.
        var olderFiles: [String] = []
        let fm = FileManager.default
        var figures = ScanFigures()
        let scanned = homeOverride.map { $0.map { Location(directory: paths.expand($0), isDefault: false) } }
            ?? locations(of: resolution)

        // Step 1, on the actor: walk the homes and decide which files need
        // reading (spec 039 research R6). The log lines, issues and reads
        // are recorded in their order as steps, so step 3 replays them as
        // the reads happened before.
        var jobs: [ReadJob] = []
        var steps: [Step] = []
        for location in scanned {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: location.directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                // An account's home that does not exist reads nothing and
                // fails nothing, like a missing Claude Code directory (spec
                // 034 research R8); an additional one is "not found" (spec
                // 035 FR-008).
                let reason = location.isDefault ? "Codex not installed" : location.isMain ? "home not found" : "not found"
                steps.append(.log("\(location.directory): skipped, \(reason)"))
                continue
            }
            guard fm.isReadableFile(atPath: location.directory) else {
                // Only a main home adds an issue (spec 035 FR-008).
                if location.isMain { steps.append(.issue("Codex: home not readable: \(location.directory)")) }
                steps.append(.log("\(location.directory): error: home not readable"))
                continue
            }
            let home = Attributor.canonical(location.directory)
            // Two configured paths to the same home: scan it once (FR-003).
            guard seenHomes.insert(home).inserted else {
                steps.append(.log("\(location.directory): skipped, same home as an earlier location"))
                continue
            }
            let sessions = URL(fileURLWithPath: home).appendingPathComponent("sessions")
            // An additional home, often a copy of a sandbox, is read only
            // below itself: a `sessions` link that leads elsewhere is
            // skipped (spec 035 FR-006, FR-009).
            if !location.isMain, fm.fileExists(atPath: sessions.path),
               !Attributor.canonical(sessions.path).hasPrefix(home == "/" ? "/" : home + "/") {
                steps.append(.log("\(location.directory): skipped, sessions is a link outside the directory"))
                continue
            }
            var scanErrors: [String] = []
            let rollouts = Self.rolloutFiles(under: sessions, errors: &scanErrors)
            for error in scanErrors {
                steps.append(.log("\(location.directory): error: \(error)"))
            }
            if location.isMain { steps += scanErrors.map(Step.issue) }
            for file in rollouts {
                // The first home that reaches a file wins.
                guard present.insert(file.path).inserted else { continue }
                figures.filesSeen += 1
                figures.corpusBytes += file.size
                if file.modificationDate < window.start {
                    files[file.path] = nil
                    olderFiles.append(file.path)
                    continue
                }
                if var entry = files[file.path], entry.size == file.size, entry.modificationDate == file.modificationDate {
                    // Unchanged, but now reached through another home: its
                    // records are built again for that home (spec 035 FR-012).
                    if entry.home != home {
                        entry.home = home
                        entry.built = nil
                        files[file.path] = entry
                    }
                    continue
                }
                let fallback = ((file.path as NSString).lastPathComponent as NSString).deletingPathExtension
                steps.append(.read(jobs.count))
                jobs.append(ReadJob(file: file, home: home, location: location, fallbackSessionId: fallback))
            }
            steps.append(.endHome(home: home, location: location.directory, origin: location.origin))
        }

        // Step 2, off the actor: read and parse on the bounded workers, the
        // largest file first (spec 039 FR-017, FR-018).
        let results = await parse(jobs.map { (path: $0.file.path, size: $0.file.size, fallbackSessionId: $0.fallbackSessionId) })

        // Step 3, on the actor: apply the results in today's order.
        var filesRead = 0
        for step in steps {
            switch step {
            case .log(let message):
                log?.append(source: name, message: message)
            case .issue(let issue):
                issues.append(issue)
            case .read(let index):
                let job = jobs[index]
                let file = job.file
                guard let result = results[index] else {
                    if job.location.isMain { issues.append("Codex: cannot read \(file.path)") }
                    log?.append(source: name, message: "\(job.location.directory): error: cannot read \(file.path)")
                    continue
                }
                // A sat-out session that grew is still the retry of the
                // records the condition sat out on, so a time-out in it gives
                // the condition up and an active session settles; a replaced
                // (shorter) file is new data (spec 038 FR-007, SC-005).
                if let previous = files[file.path], file.size < previous.size {
                    retries.remove(file.path)
                } else if retries.contains(file.path) {
                    grownRetries.insert(file.path)
                }
                files[file.path] = FileEntry(size: file.size, modificationDate: file.modificationDate, home: job.home,
                                             session: result.session)
                figures.bytesRead += result.bytes
                figures.linesVisited += result.lines
                filesRead += 1
            case .endHome(let home, let location, let origin):
                parsed += filesRead
                perHome.append((home, location, filesRead, origin))
                filesRead = 0
            }
        }
        files = files.filter { present.contains($0.key) && $0.value.modificationDate >= window.start }
        lastFilesParsed = parsed
        figures.filesRead = parsed
        lastScanFigures = figures

        // Auth mode per session: own marker, else the parent's mode when the
        // parent is known, else API key (FR-014).
        var sessionsById: [String: CodexSession] = [:]
        for entry in files.values { sessionsById[entry.session.sessionId] = entry.session }
        await resolveParents(of: sessionsById, olderFiles: olderFiles)
        var modes: [String: Bool] = [:]
        /// A session by id: in the window, or found in an older file by
        /// `resolveParents`. Never reads a file (spec 039 research R6).
        func lookup(_ id: String) -> (planMarker: Bool, parent: String?)? {
            if let session = sessionsById[id] { return (session.planMarker, session.parentSessionId) }
            return outsideSessions[id]
        }
        func isPlan(_ id: String, visiting: Set<String> = []) -> Bool {
            if let known = modes[id] { return known }
            guard let session = lookup(id) else { return false }
            var plan = session.planMarker
            if !plan, let parent = session.parent, parent != id, !visiting.contains(parent) {
                plan = isPlan(parent, visiting: visiting.union([id]))
            }
            modes[id] = plan
            return plan
        }

        var records: [UsageRecord] = []
        var hints: [String: String] = [:]
        var countByHome: [String: Int] = [:]
        let withLines = attributor.needsRawLine
        var claims: [String: String] = [:]
        // As in `LogIndex`: retries of unchanged sessions first, then of
        // grown sessions, then new or changed data, so a time-out in new
        // lines cannot make the condition sit out for an unchanged
        // session's retry (spec 038 FR-007, SC-005).
        func rank(_ path: String) -> Int { retries.contains(path) ? (grownRetries.contains(path) ? 1 : 0) : 2 }
        let order = files.keys.sorted { (rank($0), $0) < (rank($1), $1) }
        for path in order {
            guard var entry = files[path] else { continue }
            let hint = isPlan(entry.session.sessionId) ? Attributor.codexPlanHint : Attributor.codexAPIKeyHint
            hints[entry.session.sessionId] = hint
            let claim = claims[entry.home] ?? attributor.claimKey(forDirectory: entry.home)
            claims[entry.home] = claim
            // A session whose auth mode (FR-014) or home claims (spec 035
            // FR-012) changed is rebuilt; others reuse their records.
            if entry.built?.hint != hint || entry.built?.claim != claim {
                let tracked = attributor.tracking(retry: retries.contains(path)) {
                    entry.session.records.map { item -> UsageRecord in
                        var raw = item.raw
                        raw.providerHint = hint
                        let line = withLines ? entry.session.metaLine + "\n" + item.line : ""
                        return UsageRecord(raw: raw, canonicalModel: PriceTable.canonicalModel(raw.model),
                                           accountId: attributor.accountId(for: raw, rawLine: line, fileConfigDirectory: entry.home),
                                           costUSD: pricer.cost(of: raw), project: projects.project(forCwd: raw.cwd))
                    }
                }
                entry.built = (hint, claim, tracked.result)
                entry.reattribute = tracked.reattribute
                files[path] = entry
            }
            for record in entry.built?.records ?? [] where record.timestamp >= window.start {
                records.append(record)
                countByHome[entry.home, default: 0] += 1
            }
        }
        lastHints = hints
        matchMemory = attributor.matchMemory
        for account in attributor.drainSitOutAccounts() {
            log?.append(source: name, message: Attributor.sitOutLogLine(account: account))
        }

        // Main homes and literal entries keep their line per home; the
        // homes matched by one wildcard entry share one line (spec 035
        // FR-016). A matched home that failed has its own line above.
        for home in perHome {
            if case .wildcard = home.origin { continue }
            log?.append(source: name, message: "\(home.location): \(countByHome[home.home] ?? 0) record(s) in window, \(home.filesRead) file(s) read")
        }
        for report in resolution.wildcards {
            let matched = perHome.filter { $0.origin == .wildcard(entry: report.entry) }
            let inWindow = matched.reduce(0) { $0 + (countByHome[$1.home] ?? 0) }
            let read = matched.reduce(0) { $0 + $1.filesRead }
            log?.append(source: name, message: "wildcard \"\(report.entry)\": \(report.matched) folder(s) matched, \(inWindow) record(s) in window, \(read) file(s) read")
            for line in report.listingLines {
                log?.append(source: name, message: line)
            }
        }
        for line in capLog.lines(for: resolution.wildcards, configuration: configuration) {
            log?.append(source: name, message: line)
        }
        let notes = projects.drainNotes()
        if !notes.isEmpty {
            log?.append(source: name, message: SessionLogSource.summarizeProjectNotes(notes))
        }
        // The number of homes that existed and were read, main and
        // additional, tells whether a wildcard entry matched (FR-016). The
        // CPU seconds close it (spec 039 FR-007).
        log?.append(source: name, message: String(format: "%ld home(s) read, %ld session(s), %ld record(s) since collection start, %ld file(s) parsed, %.3f s, cpu %.1f s",
                                                  perHome.count, files.count, records.count, parsed, Date().timeIntervalSince(started),
                                                  ProcessResources.cpuSeconds() - cpuStarted))
        return .recordBatch(RecordBatch(records: records, issues: issues))
    }

    /// Drops every cached session. During a scan the reset waits for the
    /// scan's end, so the running `collect` still returns its records and
    /// the next one reads every file again (spec 039 research R7).
    public func resetForEarlierWindow() {
        guard !scanning else {
            resetPending = true
            return
        }
        reset()
        lastWindowStart = nil
    }

    /// Ends a `collect`, after its records and log lines were taken:
    /// applies a deferred reset, then lets the waiting calls in.
    private func endScan() {
        if resetPending {
            resetPending = false
            reset()
            lastWindowStart = nil
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

    // MARK: - Reading on the workers (spec 039 research R6)

    /// One file to read and parse in step 2.
    private struct ReadJob {
        let file: RolloutFile
        let home: String
        let location: Location
        let fallbackSessionId: String
    }

    /// What step 1 decided, in order: replayed by step 3, so log lines,
    /// issues and per-home counts come out as before.
    private enum Step {
        case log(String)
        case issue(String)
        /// The read of `jobs[index]`.
        case read(Int)
        case endHome(home: String, location: String, origin: SessionDirectory.Origin)
    }

    /// One parsed file.
    private struct Parsed: Sendable {
        let session: CodexSession
        let bytes: Int
        let lines: Int
    }

    /// Reads and parses `files` on the workers, off the actor, the largest
    /// first; nil for a file that cannot be read. Zero files cost nothing,
    /// as in most incremental refreshes.
    private func parse(_ files: [(path: String, size: Int, fallbackSessionId: String)]) async -> [Parsed?] {
        guard !files.isEmpty else { return [] }
        let workers = workers
        let parser = parser
        return await workers.offload {
            var results = [Parsed?](repeating: nil, count: files.count)
            results.withUnsafeMutableBufferPointer { buffer in
                let slots = buffer
                workers.forEach(jobs: files.count, weight: { files[$0].size }) { index in
                    guard let data = FileManager.default.contents(atPath: files[index].path) else { return }
                    var lines = 0
                    let session = parser.parse(data: data, fallbackSessionId: files[index].fallbackSessionId, linesVisited: &lines)
                    slots[index] = Parsed(session: session, bytes: data.count, lines: lines)
                }
            }
            return results
        }
    }

    /// Reads the parents a subagent's auth mode needs from files older than
    /// the window, in rounds on the workers, so no file is parsed on the
    /// actor (FR-014, spec 039 FR-017, research R6). The walk starts from
    /// the window's sessions and follows a parent only from a session
    /// without a plan marker, and never a session's own id: the edges
    /// `isPlan` follows. A parent in neither the window nor
    /// `outsideSessions` whose file is found joins the round; its result is
    /// stored under the parent id that named the file, as before. A file
    /// that cannot be read stores nothing and is not tried again in this
    /// refresh.
    private func resolveParents(of sessionsById: [String: CodexSession], olderFiles: [String]) async {
        guard !olderFiles.isEmpty else { return }
        var tried = Set<String>()
        while true {
            var frontier: [(id: String, path: String)] = []
            var visited = Set<String>()
            for start in sessionsById.keys.sorted() {
                guard let session = sessionsById[start], visited.insert(start).inserted else { continue }
                var id = start
                var planMarker = session.planMarker
                var parent = session.parentSessionId
                while !planMarker, let next = parent, next != id, visited.insert(next).inserted {
                    if let known = sessionsById[next] {
                        (planMarker, parent) = (known.planMarker, known.parentSessionId)
                    } else if let known = outsideSessions[next] {
                        (planMarker, parent) = known
                    } else {
                        if tried.insert(next).inserted,
                           let path = olderFiles.first(where: { ($0 as NSString).lastPathComponent.hasSuffix("-\(next).jsonl") }) {
                            frontier.append((next, path))
                        }
                        break
                    }
                    id = next
                }
            }
            guard !frontier.isEmpty else { return }
            let results = await parse(frontier.map { (path: $0.path, size: 0, fallbackSessionId: "") })
            for (index, item) in frontier.enumerated() {
                guard let session = results[index]?.session else { continue }
                outsideSessions[item.id] = (planMarker: session.planMarker, parent: session.parentSessionId)
            }
        }
    }

    /// Drops every cached session, for a collection start that moved earlier.
    private func reset() {
        files = [:]
        outsideSessions = [:]
        log?.append(source: name, message: "collection start moved earlier, cache reset")
    }

    // MARK: - Scanning

    struct RolloutFile {
        let path: String
        let size: Int
        let modificationDate: Date
    }

    /// `rollout-*.jsonl` files under `sessions`, by canonical path. A missing
    /// `sessions` directory is not an error (no session yet).
    static func rolloutFiles(under sessions: URL, errors: inout [String]) -> [RolloutFile] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sessions.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        let root = sessions.resolvingSymlinksInPath().standardizedFileURL
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var enumerationErrors: [String] = []
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
                                             errorHandler: { url, error in
                                                 enumerationErrors.append("Codex: cannot read \(url.path): \(error.localizedDescription)")
                                                 return true
                                             }) else {
            errors.append("Codex: cannot enumerate \(sessions.path)")
            return []
        }
        var result: [RolloutFile] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-"),
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            result.append(RolloutFile(path: url.standardizedFileURL.path, size: values.fileSize ?? 0,
                                      modificationDate: values.contentModificationDate ?? .distantPast))
        }
        errors += enumerationErrors
        return result
    }
}
