import Foundation

// MARK: - Import kind and provenance

/// The kind of a price import. At most one batch per kind is stored (FR-025).
/// Provider kinds share one layer below `csv` (FR-001).
public enum ImportKind: String, Codable, CaseIterable, Hashable, Sendable {
    case anthropic
    case openai
    case gemini
    case csv

    /// True for imports from the LiteLLM price list (FR-006).
    public var isProvider: Bool { self != .csv }

    public var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .csv: return "CSV"
        }
    }
}

/// Where an imported price comes from: import kind, origin (price list URL or
/// CSV file name) and the time the import was applied (FR-005).
public struct ImportProvenance: Hashable, Sendable {
    public var kind: ImportKind
    /// LiteLLM URL, or the CSV file name (last path component only).
    public var origin: String
    public var importedAt: Date

    public init(kind: ImportKind, origin: String, importedAt: Date) {
        self.kind = kind
        self.origin = origin
        self.importedAt = importedAt
    }
}

// MARK: - Batch

/// The prices of one import: kind, origin, import time and entries
/// (canonical, unique model ids, non-negative prices).
public struct PriceBatch: Codable, Equatable, Sendable {
    public var kind: ImportKind
    public var origin: String
    /// Whole seconds, so that the value survives the ISO 8601 round trip
    /// through the file unchanged.
    public var importedAt: Date
    public var entries: [PriceEntry]

    public init(kind: ImportKind, origin: String, importedAt: Date, entries: [PriceEntry]) {
        self.kind = kind
        self.origin = origin
        self.importedAt = Date(timeIntervalSince1970: importedAt.timeIntervalSince1970.rounded(.down))
        self.entries = entries
    }

    public var provenance: ImportProvenance {
        ImportProvenance(kind: kind, origin: origin, importedAt: importedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, origin, importedAt, entries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(ImportKind.self, forKey: .kind)
        origin = try c.decode(String.self, forKey: .origin)
        let text = try c.decode(String.self, forKey: .importedAt)
        guard let date = PriceBatch.parseDate(text) else {
            throw DecodingError.dataCorruptedError(forKey: .importedAt, in: c, debugDescription: "importedAt is not an ISO 8601 date: \(text)")
        }
        importedAt = date
        entries = try c.decode([PriceEntry].self, forKey: .entries)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(origin, forKey: .origin)
        try c.encode(PriceBatch.formatDate(importedAt), forKey: .importedAt)
        try c.encode(entries, forKey: .entries)
    }

    static func formatDate(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func parseDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text)
    }

    /// Throws when the batch breaks the file contract.
    func validate() throws {
        guard !origin.isEmpty else { throw ImportedPrices.InvalidFile(description: "\(kind.rawValue) batch has an empty origin") }
        var seen = Set<String>()
        for entry in entries {
            guard !entry.model.isEmpty, PriceTable.canonicalModel(entry.model) == entry.model else {
                throw ImportedPrices.InvalidFile(description: "\(kind.rawValue) batch has a non-canonical model id \"\(entry.model)\"")
            }
            guard seen.insert(entry.model).inserted else {
                throw ImportedPrices.InvalidFile(description: "\(kind.rawValue) batch lists \(entry.model) twice")
            }
            guard PriceField.allCases.allSatisfy({ entry[keyPath: $0.keyPath] >= 0 }) else {
                throw ImportedPrices.InvalidFile(description: "\(kind.rawValue) batch has a negative price for \(entry.model)")
            }
        }
    }
}

// MARK: - Stored imports

/// All stored imports, at most one batch per kind (FR-025). Operations are
/// pure and return a new value.
public struct ImportedPrices: Codable, Equatable, Sendable {
    public struct InvalidFile: Error, CustomStringConvertible {
        public let description: String
    }

    public static let currentVersion = 1
    public static let empty = ImportedPrices(version: currentVersion, batches: [])

    public var version: Int
    public var batches: [PriceBatch]

    public init(version: Int = ImportedPrices.currentVersion, batches: [PriceBatch]) {
        self.version = version
        self.batches = batches
    }

    /// Drops the batch of the same kind and appends the new one (FR-021).
    public func replacing(_ batch: PriceBatch) -> ImportedPrices {
        ImportedPrices(version: version, batches: batches.filter { $0.kind != batch.kind } + [batch])
    }

    public func removing(_ kind: ImportKind) -> ImportedPrices {
        ImportedPrices(version: version, batches: batches.filter { $0.kind != kind })
    }

    public func batch(for kind: ImportKind) -> PriceBatch? {
        batches.first { $0.kind == kind }
    }

    /// Throws when the value breaks the file contract: unknown version, two
    /// batches of one kind, or an invalid batch.
    public func validate() throws {
        guard version == ImportedPrices.currentVersion else {
            throw InvalidFile(description: "unsupported version \(version)")
        }
        var kinds = Set<ImportKind>()
        for batch in batches {
            guard kinds.insert(batch.kind).inserted else {
                throw InvalidFile(description: "more than one \(batch.kind.rawValue) batch")
            }
            try batch.validate()
        }
    }
}

// MARK: - Store

/// Owns `imported-prices.json` (FR-025 to FR-027). Lock-protected like
/// `ConfigStore`; a missing file means no imports, an unreadable or invalid
/// file is ignored and left in place until the next save replaces it.
public final class ImportedPriceStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var value: ImportedPrices = .empty
    private var error: String?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Last loaded or saved value.
    public var current: ImportedPrices {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    /// Reason the file could not be used at the last load, shown as a notice
    /// on the Prices tab (FR-027).
    public var loadError: String? {
        lock.lock(); defer { lock.unlock() }
        return error
    }

    /// Reads the file. Missing file: empty value, no error. Undecodable or
    /// invalid file: empty value, `loadError` set, file untouched (FR-027).
    @discardableResult
    public func load() -> ImportedPrices {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            value = .empty
            error = nil
            return value
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(ImportedPrices.self, from: data)
            try decoded.validate()
            value = decoded
            error = nil
        } catch let invalid as ImportedPrices.InvalidFile {
            value = .empty
            error = "Imported prices file is invalid: \(invalid.description)"
        } catch is DecodingError {
            value = .empty
            error = "Imported prices file could not be decoded"
        } catch {
            value = .empty
            self.error = "Imported prices file could not be read: \(error.localizedDescription)"
        }
        return value
    }

    /// Validates, then writes pretty-printed with sorted keys, atomically
    /// (FR-026). On failure throws and keeps `current` unchanged; on success
    /// clears `loadError`.
    public func save(_ prices: ImportedPrices) throws {
        try prices.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(prices)
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        value = prices
        error = nil
    }
}
