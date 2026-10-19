import Foundation

/// Loads and saves the configuration file, keeping the last valid
/// configuration when the file on disk is broken (FR-033).
public final class ConfigStore: @unchecked Sendable {
    public let fileURL: URL
    private let makeDefaultConfiguration: @Sendable () -> Configuration
    private let lock = NSLock()

    private var lastValid: Configuration?
    private var lastError: ConfigurationError?
    private var loadedModificationDate: Date?
    /// Notes of the most recent successful file read, not yet handed out
    /// (spec 012 FR-003).
    private var pendingLoadNotes: [String] = []

    public init(fileURL: URL, makeDefault: @escaping @Sendable () -> Configuration = { Configuration.default }) {
        self.fileURL = fileURL
        self.makeDefaultConfiguration = makeDefault
    }

    /// The last valid configuration, or the default when nothing was loaded yet.
    public var current: Configuration {
        lock.lock(); defer { lock.unlock() }
        return lastValid ?? Configuration.default
    }

    /// Returns the last valid configuration plus the error of the most recent
    /// failed read, if any. Re-reads the file only when its modification date
    /// changed. Creates the default file when none exists (FR-034).
    public func load() -> (Configuration, ConfigurationError?) {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()
    }

    /// Applies `change` to the configuration on disk and saves the result,
    /// in one step under the store's lock: a hand edit made since the last
    /// read is kept, and a broken file, or one gone missing after a load,
    /// is never written over (its read error is thrown). Before any load a
    /// missing file is created with the default first, as `load()` does.
    /// Returns the saved configuration, or nil when `change` leaves it as it
    /// is and nothing is written (spec 027 FR-010, FR-011). `change` runs
    /// under the lock and must not call into the store.
    public func update(_ change: (Configuration) -> Configuration) throws -> Configuration? {
        lock.lock(); defer { lock.unlock() }
        let (config, error) = loadLocked()
        if let error { throw error }
        let updated = change(config)
        guard updated != config else { return nil }
        try updated.validate()
        try write(updated)
        lastValid = updated
        lastError = nil
        loadedModificationDate = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? nil
        return updated
    }

    private func loadLocked() -> (Configuration, ConfigurationError?) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            if lastValid == nil {
                let config = makeDefaultConfiguration()
                lastValid = config
                do {
                    try write(config)
                    lastError = nil
                } catch let error as ConfigurationError {
                    lastError = error
                } catch {
                    lastError = ConfigurationError(kind: .io, message: "Could not write default configuration: \(error.localizedDescription)")
                }
            } else {
                lastError = ConfigurationError(kind: .io, message: "Configuration file \(fileURL.path) is missing; keeping the last valid configuration.")
            }
            return (lastValid ?? Configuration.default, lastError)
        }

        let modificationDate = (try? fm.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? nil
        // Attribute round trips through the file system can lose sub-microsecond
        // precision, so compare with a small tolerance instead of exact equality.
        if let loaded = loadedModificationDate, let current = modificationDate,
           abs(loaded.timeIntervalSinceReferenceDate - current.timeIntervalSinceReferenceDate) < 0.0001,
           lastValid != nil {
            return (lastValid!, lastError)
        }
        loadedModificationDate = modificationDate

        do {
            let data = try Data(contentsOf: fileURL)
            let notes = ConfigurationLoadNotes()
            let decoder = JSONDecoder()
            decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
            let config = try decoder.decode(Configuration.self, from: data)
            try config.validate()
            lastValid = config
            lastError = nil
            // Kept only when the whole file decodes and validates (spec 012 FR-003).
            pendingLoadNotes = notes.notes
        } catch let error as ConfigurationError {
            lastError = error
        } catch let error as DecodingError {
            lastError = ConfigurationError(kind: .decoding, message: "Configuration file could not be decoded: \(Self.describe(error))")
        } catch {
            lastError = ConfigurationError(kind: .io, message: "Configuration file could not be read: \(error.localizedDescription)")
        }
        if lastValid == nil {
            lastValid = makeDefaultConfiguration()
        }
        return (lastValid!, lastError)
    }

    /// Returns and clears the notes of the most recent file read, for
    /// example an unknown level color (spec 012 FR-003). Each read's notes
    /// are handed out once.
    public func takeLoadNotes() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let notes = pendingLoadNotes
        pendingLoadNotes = []
        return notes
    }

    /// Validates then writes the configuration atomically with the known keys only.
    public func save(_ config: Configuration) throws {
        try config.validate()
        lock.lock(); defer { lock.unlock() }
        try write(config)
        lastValid = config
        lastError = nil
        loadedModificationDate = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? nil
    }

    private func write(_ config: Configuration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    /// The FR-034 default: refresh 300 s, Monday 00:00 fallback, and one
    /// subscription account with the Claude icon when the default keychain
    /// item exists (spec 004 FR-002, research R9).
    public static func makeDefault(hasDefaultCredentials: Bool) -> Configuration {
        var config = Configuration()
        if hasDefaultCredentials {
            config.accounts = [
                Account(icon: IconDefaults.subscription, displayName: "Claude Max",
                        kind: .subscription(SubscriptionSettings(credentialDirectory: Paths.defaultClaudeDirectory,
                                                                 shownInBar: true, thresholds: [80, 100])))
            ]
        }
        return config
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "expected \(type) at \(path(context)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "missing \(type) at \(path(context))"
        case .keyNotFound(let key, let context):
            return "missing key \"\(key.stringValue)\" at \(path(context))"
        case .dataCorrupted(let context):
            return context.debugDescription.isEmpty ? "invalid JSON" : context.debugDescription
        @unknown default:
            return String(describing: error)
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let p = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        return p.isEmpty ? "root" : p
    }
}
