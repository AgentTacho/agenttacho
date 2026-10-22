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

    /// When a capped wildcard entry is logged (spec 035 FR-005).
    private var capLog = WildcardCapLog()

    /// Files parsed by the last `collect` (for tests).
    public private(set) var lastFilesParsed = 0
    /// The resolved auth mode hint per session id of the last `collect` (for tests).
    private(set) var lastHints: [String: String] = [:]

    public init(paths: Paths = Paths(), log: DiagnosticLog? = nil, builtInPrices: PriceTable? = nil,
                importedPrices: ImportedPriceStore? = nil, projectResolver: ProjectResolver = ProjectResolver(),
                fileSystem: any DirectoryFileSystem = LocalDirectoryFileSystem()) throws {
        self.paths = paths
        self.log = log
        self.builtInPrices = try builtInPrices ?? PriceTable.builtIn()
        self.importedPrices = importedPrices
        self.projects = projectResolver
        self.fileSystem = fileSystem
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
        let started = Date()
        let configuration = context.configuration
        let window = context.window
        let pricer = PriceTable.effective(builtIn: builtInPrices, imported: importedPrices?.current ?? .empty,
                                          overrides: configuration.priceOverrides)
        let resolution = resolution(for: configuration)
        let attributor = Attributor(configuration: configuration, paths: paths,
                                    additionalDirectories: resolution.additionalByAccount)

        // A file is dropped once its modification date is before the window
        // start, so an earlier start needs a fresh scan (FR-023).
        if let previous = lastWindowStart, window.start < previous {
            reset()
        }
        lastWindowStart = window.start
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

        for location in locations(of: resolution) {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: location.directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                // An account's home that does not exist reads nothing and
                // fails nothing, like a missing Claude Code directory (spec
                // 034 research R8); an additional one is "not found" (spec
                // 035 FR-008).
                let reason = location.isDefault ? "Codex not installed" : location.isMain ? "home not found" : "not found"
                log?.append(source: name, message: "\(location.directory): skipped, \(reason)")
                continue
            }
            guard fm.isReadableFile(atPath: location.directory) else {
                // Only a main home adds an issue (spec 035 FR-008).
                if location.isMain { issues.append("Codex: home not readable: \(location.directory)") }
                log?.append(source: name, message: "\(location.directory): error: home not readable")
                continue
            }
            let home = Attributor.canonical(location.directory)
            // Two configured paths to the same home: scan it once (FR-003).
            guard seenHomes.insert(home).inserted else {
                log?.append(source: name, message: "\(location.directory): skipped, same home as an earlier location")
                continue
            }
            var filesRead = 0
            let sessions = URL(fileURLWithPath: home).appendingPathComponent("sessions")
            // An additional home, often a copy of a sandbox, is read only
            // below itself: a `sessions` link that leads elsewhere is
            // skipped (spec 035 FR-006, FR-009).
            if !location.isMain, fm.fileExists(atPath: sessions.path),
               !Attributor.canonical(sessions.path).hasPrefix(home == "/" ? "/" : home + "/") {
                log?.append(source: name, message: "\(location.directory): skipped, sessions is a link outside the directory")
                continue
            }
            var scanErrors: [String] = []
            let rollouts = Self.rolloutFiles(under: sessions, errors: &scanErrors)
            for error in scanErrors {
                log?.append(source: name, message: "\(location.directory): error: \(error)")
            }
            if location.isMain { issues += scanErrors }
            for file in rollouts {
                // The first home that reaches a file wins.
                guard present.insert(file.path).inserted else { continue }
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
                guard let data = fm.contents(atPath: file.path) else {
                    if location.isMain { issues.append("Codex: cannot read \(file.path)") }
                    log?.append(source: name, message: "\(location.directory): error: cannot read \(file.path)")
                    continue
                }
                let fallback = ((file.path as NSString).lastPathComponent as NSString).deletingPathExtension
                files[file.path] = FileEntry(size: file.size, modificationDate: file.modificationDate, home: home,
                                             session: parser.parse(data: data, fallbackSessionId: fallback))
                filesRead += 1
            }
            parsed += filesRead
            perHome.append((home, location.directory, filesRead, location.origin))
        }
        files = files.filter { present.contains($0.key) && $0.value.modificationDate >= window.start }
        lastFilesParsed = parsed

        // Auth mode per session: own marker, else the parent's mode when the
        // parent is known, else API key (FR-014).
        var sessionsById: [String: CodexSession] = [:]
        for entry in files.values { sessionsById[entry.session.sessionId] = entry.session }
        var modes: [String: Bool] = [:]
        /// A session by id: in the window, or found once in an older file
        /// whose name ends with the session id.
        func lookup(_ id: String) -> (planMarker: Bool, parent: String?)? {
            if let session = sessionsById[id] { return (session.planMarker, session.parentSessionId) }
            if let known = outsideSessions[id] { return known }
            guard let path = olderFiles.first(where: { ($0 as NSString).lastPathComponent.hasSuffix("-\(id).jsonl") }),
                  let data = fm.contents(atPath: path) else { return nil }
            let session = parser.parse(data: data)
            let found = (planMarker: session.planMarker, parent: session.parentSessionId)
            outsideSessions[id] = found
            return found
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
        let withLines = attributor.usesCustomMarkers
        var claims: [String: String] = [:]
        for path in files.keys.sorted() {
            guard var entry = files[path] else { continue }
            let hint = isPlan(entry.session.sessionId) ? Attributor.codexPlanHint : Attributor.codexAPIKeyHint
            hints[entry.session.sessionId] = hint
            let claim = claims[entry.home] ?? attributor.claimKey(forDirectory: entry.home)
            claims[entry.home] = claim
            // A session whose auth mode (FR-014) or home claims (spec 035
            // FR-012) changed is rebuilt; others reuse their records.
            if entry.built?.hint != hint || entry.built?.claim != claim {
                let built = entry.session.records.map { item -> UsageRecord in
                    var raw = item.raw
                    raw.providerHint = hint
                    let line = withLines ? entry.session.metaLine + "\n" + item.line : ""
                    return UsageRecord(raw: raw, canonicalModel: PriceTable.canonicalModel(raw.model),
                                       accountId: attributor.accountId(for: raw, rawLine: line, fileConfigDirectory: entry.home),
                                       costUSD: pricer.cost(of: raw), project: projects.project(forCwd: raw.cwd))
                }
                entry.built = (hint, claim, built)
                files[path] = entry
            }
            for record in entry.built?.records ?? [] where record.timestamp >= window.start {
                records.append(record)
                countByHome[entry.home, default: 0] += 1
            }
        }
        lastHints = hints

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
        // additional, tells whether a wildcard entry matched (FR-016).
        log?.append(source: name, message: String(format: "%ld home(s) read, %ld session(s), %ld record(s) since collection start, %ld file(s) parsed, %.3f s",
                                                  perHome.count, files.count, records.count, parsed, Date().timeIntervalSince(started)))
        return .recordBatch(RecordBatch(records: records, issues: issues))
    }

    public func resetForEarlierWindow() {
        reset()
        lastWindowStart = nil
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
