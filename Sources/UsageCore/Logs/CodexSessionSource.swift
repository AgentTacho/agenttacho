import Foundation

/// `UsageSource` over Codex rollout files (spec 006 FR-001 to FR-015,
/// research R4). Scans `<home>/sessions/**/rollout-*.jsonl` for the default
/// Codex home and every configured extra one, read-only. Credential files in
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

    /// A Codex home to scan: expanded path and whether it is the default
    /// location (skipped silently when missing, FR-002).
    public struct Location: Equatable, Sendable {
        public let directory: String
        public let isDefault: Bool
    }

    /// The parsed session of one file and what decided to parse it.
    struct FileEntry {
        var size: Int
        var modificationDate: Date
        /// Canonical Codex home the file was found in (FR-015 tie-breaker).
        var home: String
        var session: CodexSession
        /// The records built for `hint`, so an unchanged file costs nothing
        /// on the next refresh (FR-004). Cleared when rules or prices change.
        var built: (hint: String, records: [UsageRecord])?
    }

    private let paths: Paths
    private let log: DiagnosticLog?
    private let builtInPrices: PriceTable
    private let importedPrices: ImportedPriceStore?
    private let parser = CodexSessionParser()
    private let projects: ProjectResolver

    /// Keyed by canonical file path.
    private var files: [String: FileEntry] = [:]
    /// Plan marker and parent of sessions outside the window, by session
    /// id, read only to resolve a subagent's auth mode (FR-014).
    private var outsideSessions: [String: (planMarker: Bool, parent: String?)] = [:]
    private var lastWindowStart: Date?
    private var attributionFingerprint: String?
    private var priceTable: PriceTable?

    /// Files parsed by the last `collect` (for tests).
    public private(set) var lastFilesParsed = 0
    /// The resolved auth mode hint per session id of the last `collect` (for tests).
    private(set) var lastHints: [String: String] = [:]

    public init(paths: Paths = Paths(), log: DiagnosticLog? = nil, builtInPrices: PriceTable? = nil,
                importedPrices: ImportedPriceStore? = nil, projectResolver: ProjectResolver = ProjectResolver()) throws {
        self.paths = paths
        self.log = log
        self.builtInPrices = try builtInPrices ?? PriceTable.builtIn()
        self.importedPrices = importedPrices
        self.projects = projectResolver
    }

    /// The default Codex home plus configured extra homes, expanded and
    /// deduplicated by path (FR-003).
    public nonisolated func homes(for configuration: Configuration) -> [Location] {
        var seen = Set<String>()
        var result: [Location] = []
        let defaultHome = paths.expand(Paths.defaultCodexHome)
        for dir in [Paths.defaultCodexHome] + configuration.codexHomes {
            let expanded = paths.expand(dir)
            if seen.insert(expanded).inserted {
                result.append(Location(directory: expanded, isDefault: expanded == defaultHome))
            }
        }
        return result
    }

    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let started = Date()
        let configuration = context.configuration
        let window = context.window
        let pricer = PriceTable.effective(builtIn: builtInPrices, imported: importedPrices?.current ?? .empty,
                                          overrides: configuration.priceOverrides)
        let attributor = Attributor(configuration: configuration, paths: paths)

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
        var perHome: [(home: String, location: String, filesRead: Int)] = []
        /// Files modified before the window start: not counted, but a
        /// subagent's parent may live in one.
        var olderFiles: [String] = []
        let fm = FileManager.default

        for location in homes(for: configuration) {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: location.directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                if location.isDefault {
                    log?.append(source: name, message: "\(location.directory): skipped, Codex not installed")
                } else {
                    issues.append("Codex: home not found: \(location.directory)")
                    log?.append(source: name, message: "\(location.directory): error: home not found")
                }
                continue
            }
            guard fm.isReadableFile(atPath: location.directory) else {
                issues.append("Codex: home not readable: \(location.directory)")
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
            var scanErrors: [String] = []
            let rollouts = Self.rolloutFiles(under: sessions, errors: &scanErrors)
            for error in scanErrors {
                log?.append(source: name, message: "\(location.directory): error: \(error)")
            }
            issues += scanErrors
            for file in rollouts {
                // The first home that reaches a file wins.
                guard present.insert(file.path).inserted else { continue }
                if file.modificationDate < window.start {
                    files[file.path] = nil
                    olderFiles.append(file.path)
                    continue
                }
                if let entry = files[file.path], entry.size == file.size, entry.modificationDate == file.modificationDate {
                    continue
                }
                guard let data = fm.contents(atPath: file.path) else {
                    issues.append("Codex: cannot read \(file.path)")
                    log?.append(source: name, message: "\(location.directory): error: cannot read \(file.path)")
                    continue
                }
                let fallback = ((file.path as NSString).lastPathComponent as NSString).deletingPathExtension
                files[file.path] = FileEntry(size: file.size, modificationDate: file.modificationDate, home: home,
                                             session: parser.parse(data: data, fallbackSessionId: fallback))
                filesRead += 1
            }
            parsed += filesRead
            perHome.append((home, location.directory, filesRead))
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
        for path in files.keys.sorted() {
            guard var entry = files[path] else { continue }
            let hint = isPlan(entry.session.sessionId) ? Attributor.codexPlanHint : Attributor.codexAPIKeyHint
            hints[entry.session.sessionId] = hint
            // A session whose auth mode changed (FR-014) is rebuilt; others
            // reuse their records.
            if entry.built?.hint != hint {
                let built = entry.session.records.map { item -> UsageRecord in
                    var raw = item.raw
                    raw.providerHint = hint
                    let line = withLines ? entry.session.metaLine + "\n" + item.line : ""
                    return UsageRecord(raw: raw, canonicalModel: PriceTable.canonicalModel(raw.model),
                                       accountId: attributor.accountId(for: raw, rawLine: line, fileConfigDirectory: entry.home),
                                       costUSD: pricer.cost(of: raw), project: projects.project(forCwd: raw.cwd))
                }
                entry.built = (hint, built)
                files[path] = entry
            }
            for record in entry.built?.records ?? [] where record.timestamp >= window.start {
                records.append(record)
                countByHome[entry.home, default: 0] += 1
            }
        }
        lastHints = hints

        for home in perHome {
            log?.append(source: name, message: "\(home.location): \(countByHome[home.home] ?? 0) record(s) in window, \(home.filesRead) file(s) read")
        }
        let notes = projects.drainNotes()
        if !notes.isEmpty {
            log?.append(source: name, message: SessionLogSource.summarizeProjectNotes(notes))
        }
        log?.append(source: name, message: String(format: "%d session(s), %d record(s) since collection start, %d file(s) parsed, %.3f s",
                                                  files.count, records.count, parsed, Date().timeIntervalSince(started)))
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
