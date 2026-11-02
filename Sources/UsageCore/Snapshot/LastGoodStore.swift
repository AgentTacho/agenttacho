import Foundation

// MARK: - Saved values (contracts/last-good-file.md)

/// A saved Claude 5-hour or 7-day window, the legacy form (spec 010 FR-013, spec 040 FR-014).
public struct SavedWindow: Codable, Equatable, Sendable {
    public var utilizationPercent: Double
    public var resetsAt: Date?

    public init(utilizationPercent: Double, resetsAt: Date?) {
        self.utilizationPercent = utilizationPercent
        self.resetsAt = resetsAt
    }
}

/// A saved model-specific weekly limit, the legacy form (spec 010 FR-013, spec 040 FR-014).
public struct SavedModelLimit: Codable, Equatable, Sendable {
    public var modelName: String
    public var utilizationPercent: Double
    public var resetsAt: Date?
    public var allowancePercentOfWeekly: Int?

    public init(modelName: String, utilizationPercent: Double, resetsAt: Date?, allowancePercentOfWeekly: Int? = nil) {
        self.modelName = modelName
        self.utilizationPercent = utilizationPercent
        self.resetsAt = resetsAt
        self.allowancePercentOfWeekly = allowancePercentOfWeekly
    }
}

/// A saved Claude window of the list (spec 040 FR-014,
/// contracts/config-and-last-good.md). Kind, group and names are strings
/// from the answer, as model names already were.
public struct SavedClaudeLimit: Codable, Equatable, Sendable {
    public var identity: String
    public var kind: String
    public var group: String?
    /// Nil for an unknown group, which has no pace.
    public var lengthSeconds: Double?
    public var name: String
    public var modelName: String?
    public var utilizationPercent: Double
    public var resetsAt: Date?
    public var allowancePercentOfWeekly: Int?

    public init(_ limit: ClaudeLimit) {
        identity = limit.identity.rawValue
        kind = limit.kind
        group = limit.group
        lengthSeconds = limit.length
        name = limit.name
        modelName = limit.modelName
        utilizationPercent = limit.utilizationPercent
        resetsAt = limit.resetsAt
        allowancePercentOfWeekly = limit.allowancePercentOfWeekly
    }

    public var limit: ClaudeLimit {
        ClaudeLimit(identity: ClaudeWindow(rawValue: identity), kind: kind, group: group, length: lengthSeconds, name: name,
                    modelName: modelName, allowancePercentOfWeekly: allowancePercentOfWeekly,
                    utilizationPercent: utilizationPercent, resetsAt: resetsAt)
    }
}

/// The last good values of one Claude subscription account. Never holds a
/// token or the plan type (spec 010 FR-013, FR-014). The window list is the
/// `windows` key (spec 040 FR-014); the legacy `fiveHour`, `sevenDay` and
/// `modelLimits` keys are still written for the windows with those
/// identities and the `model:<name>` limits, so the previous version reads
/// its values after a downgrade, and they are read when `windows` is absent.
public struct SavedClaudeValues: Codable, Equatable, Sendable {
    /// The canonical credential directory the values were fetched with.
    public var credentialDirectory: String
    public var fetchedAt: Date
    public var fiveHour: SavedWindow?
    public var sevenDay: SavedWindow?
    public var modelLimits: [SavedModelLimit]
    /// The window list; nil in a file of the previous version.
    public var windows: [SavedClaudeLimit]?

    public init(credentialDirectory: String, fetchedAt: Date, fiveHour: SavedWindow?, sevenDay: SavedWindow?,
                modelLimits: [SavedModelLimit] = [], windows: [SavedClaudeLimit]? = nil) {
        self.credentialDirectory = credentialDirectory
        self.fetchedAt = fetchedAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.modelLimits = modelLimits
        self.windows = windows
    }

    /// The values of `status`, without its plan type: the list and the
    /// legacy keys (spec 040 FR-014).
    public init(credentialDirectory: String, status: SubscriptionStatus) {
        func saved(_ id: ClaudeWindow) -> SavedWindow? {
            status.window(id).map { SavedWindow(utilizationPercent: $0.utilizationPercent, resetsAt: $0.resetsAt) }
        }
        // Every model's first limit (spec 040 FR-004), a name with a colon included.
        let models = status.modelLimitWindows.filter(\.isPrimaryModelLimit).compactMap { limit in
            limit.modelName.map {
                SavedModelLimit(modelName: $0, utilizationPercent: limit.utilizationPercent, resetsAt: limit.resetsAt,
                                allowancePercentOfWeekly: limit.allowancePercentOfWeekly)
            }
        }
        self.init(credentialDirectory: credentialDirectory, fetchedAt: status.fetchedAt, fiveHour: saved(.fiveHour),
                  sevenDay: saved(.sevenDay), modelLimits: models, windows: status.windows.map(SavedClaudeLimit.init))
    }

    /// The saved values as a status fetched at `fetchedAt` (clamped to
    /// `now` when it lies in the future), without a plan type: the list,
    /// or for a file of the previous version the legacy values as a 5-hour
    /// group window, a weekly window and weekly model limits (spec 040 FR-014).
    /// Of two windows with the same identity only the first is kept, as in
    /// a live answer (spec 040 FR-005).
    public func status(now: Date) -> SubscriptionStatus {
        let list: [ClaudeLimit]
        if let windows {
            list = windows.map(\.limit)
        } else {
            var legacy: [ClaudeLimit] = []
            if let fiveHour { legacy.append(.fiveHour(fiveHour.utilizationPercent, resetsAt: fiveHour.resetsAt)) }
            if let sevenDay { legacy.append(.sevenDay(sevenDay.utilizationPercent, resetsAt: sevenDay.resetsAt)) }
            legacy += modelLimits.map {
                .model($0.modelName, $0.utilizationPercent, resetsAt: $0.resetsAt, allowance: $0.allowancePercentOfWeekly)
            }
            list = legacy
        }
        var seen: Set<ClaudeWindow> = []
        return SubscriptionStatus(windows: list.filter { seen.insert($0.identity).inserted }, fetchedAt: min(fetchedAt, now))
    }

    enum CodingKeys: String, CodingKey { case credentialDirectory, fetchedAt, fiveHour, sevenDay, modelLimits, windows }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        credentialDirectory = try c.decode(String.self, forKey: .credentialDirectory)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        fiveHour = try c.decodeIfPresent(SavedWindow.self, forKey: .fiveHour)
        sevenDay = try c.decodeIfPresent(SavedWindow.self, forKey: .sevenDay)
        modelLimits = try c.decodeIfPresent([SavedModelLimit].self, forKey: .modelLimits) ?? []
        // A list this version cannot read (a later format) leaves the legacy
        // keys next to it in charge instead of dropping the file (spec 040 FR-014).
        windows = (try? c.decodeIfPresent([SavedClaudeLimit].self, forKey: .windows)) ?? nil
    }
}

/// A saved Codex plan window (spec 010 FR-013).
public struct SavedCodexWindow: Codable, Equatable, Sendable {
    public var lengthMinutes: Int
    public var usedPercent: Double
    public var resetsAt: Date?
    public var limitReached: Bool

    public init(lengthMinutes: Int, usedPercent: Double, resetsAt: Date?, limitReached: Bool) {
        self.lengthMinutes = lengthMinutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.limitReached = limitReached
    }
}

/// The last live result of one Codex subscription account (spec 010
/// FR-013, FR-017).
public struct SavedCodexValues: Codable, Equatable, Sendable {
    /// The canonical Codex home the values were fetched with.
    public var codexHome: String
    public var observedAt: Date
    public var planType: String?
    public var windows: [SavedCodexWindow]

    public init(codexHome: String, observedAt: Date, planType: String?, windows: [SavedCodexWindow]) {
        self.codexHome = codexHome
        self.observedAt = observedAt
        self.planType = planType
        self.windows = windows
    }

    public init(codexHome: String, observation: CodexLimitObservation) {
        self.init(codexHome: codexHome, observedAt: observation.observedAt, planType: observation.planType,
                  windows: observation.windows.map {
                      SavedCodexWindow(lengthMinutes: $0.lengthMinutes, usedPercent: $0.usedPercent,
                                       resetsAt: $0.resetsAt, limitReached: $0.limitReached)
                  })
    }

    /// The saved result as a live observation at `observedAt` (clamped to
    /// `now` when it lies in the future).
    public func observation(now: Date) -> CodexLimitObservation {
        CodexLimitObservation(planType: planType, observedAt: min(observedAt, now), origin: .live,
                              windows: windows.map {
                                  CodexLimitWindow(lengthMinutes: $0.lengthMinutes, usedPercent: $0.usedPercent,
                                                   resetsAt: $0.resetsAt, limitReached: $0.limitReached)
                              })
    }
}

/// The content of `last-good.json`, version 1 (contracts/last-good-file.md).
public struct LastGoodValues: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Keyed by account id.
    public var claude: [String: SavedClaudeValues]
    /// Keyed by account id.
    public var codex: [String: SavedCodexValues]

    public init(version: Int = LastGoodValues.currentVersion, claude: [String: SavedClaudeValues] = [:],
                codex: [String: SavedCodexValues] = [:]) {
        self.version = version
        self.claude = claude
        self.codex = codex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        claude = try c.decodeIfPresent([String: SavedClaudeValues].self, forKey: .claude) ?? [:]
        codex = try c.decodeIfPresent([String: SavedCodexValues].self, forKey: .codex) ?? [:]
    }
}

// MARK: - Store

/// Owns `~/Library/Application Support/agenttacho/last-good.json`, the last
/// good plan limits per account across launches (spec 010 FR-013 to FR-018,
/// research R5). One writer for the file: both sources hand their full map
/// to it after every collect that changed it. Each write replaces the file
/// atomically with owner-only permissions; a failed write is logged once
/// and never shown to the user.
public actor LastGoodStore {
    public let fileURL: URL
    private let log: DiagnosticLog?
    private var current: LastGoodValues
    private var loggedWriteFailure = false

    public init(fileURL: URL, initial: LastGoodValues?, log: DiagnosticLog?) {
        self.fileURL = fileURL
        self.current = initial ?? LastGoodValues()
        self.log = log
    }

    /// Largest file read at launch; a real file is a few KB.
    public static let maximumFileSize = 1_048_576

    /// Reads the file once at launch. Returns nil and a problem for the log
    /// when the file is missing, not a regular file (a directory, or a
    /// symlink that could point at an endless device), larger than
    /// `maximumFileSize`, unreadable, not valid JSON or of another version
    /// (spec 010 FR-018). The problem never contains file content.
    public static func load(from url: URL) -> (LastGoodValues?, problem: String?) {
        let data: Data
        do {
            data = try RegularFile.read(url, maximumSize: maximumFileSize)
        } catch let failure as RegularFile.Failure {
            switch failure {
            case .missing: return (nil, "no saved last good values at \(url.path)")
            case .notRegular: return (nil, "saved last good values ignored: not a regular file")
            case .tooLarge(let size): return (nil, "saved last good values ignored: too large (\(size) bytes)")
            case .unreadable: return (nil, "saved last good values could not be read")
            }
        } catch {
            return (nil, "saved last good values could not be read")
        }
        let values: LastGoodValues
        do {
            values = try decoder.decode(LastGoodValues.self, from: data)
        } catch {
            return (nil, "saved last good values ignored: not a valid file")
        }
        guard values.version == LastGoodValues.currentVersion else {
            return (nil, "saved last good values ignored: unknown version \(values.version)")
        }
        return (values, nil)
    }

    /// The values loaded at launch plus every replace since; sources seed
    /// from it.
    public func values() -> LastGoodValues {
        current
    }

    /// Replaces the Claude section, keeping the Codex one.
    public func replace(claude: [String: SavedClaudeValues]) {
        guard claude != current.claude else { return }
        current.claude = claude
        write()
    }

    /// Replaces the Codex section, keeping the Claude one.
    public func replace(codex: [String: SavedCodexValues]) {
        guard codex != current.codex else { return }
        current.codex = codex
        write()
    }

    /// Writes the whole file: a temporary file created with 0600 in the same
    /// directory, renamed over the old one, then 0600 set again; the
    /// directory is created or tightened to 0700 (spec 010 FR-014).
    private func write() {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        do {
            let data = try Self.encoder.encode(current)
            if manager.fileExists(atPath: directory.path) {
                try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            } else {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            }
            let temporary = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
            guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                try? manager.removeItem(at: temporary)
                throw CocoaError(.fileWriteNoPermission)
            }
            guard rename(temporary.path, fileURL.path) == 0 else {
                let code = errno
                try? manager.removeItem(at: temporary)
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            guard !loggedWriteFailure else { return }
            loggedWriteFailure = true
            log?.append(source: "lastGood", message: "saved last good values could not be written: \(Self.describe(error))")
        }
    }

    private static func describe(_ error: Error) -> String {
        if let posix = error as? POSIXError { return "POSIX error \(posix.code.rawValue)" }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(formatter.string(from: date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let text = try c.decode(String.self)
            guard let date = formatter.date(from: text) ?? plainFormatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "not an ISO 8601 date")
            }
            return date
        }
        return d
    }()
}
