import Foundation

/// Model prices in USD per million tokens, keyed by canonical model id.
///
/// The effective table has four layers; the first layer that has a model
/// decides its price (price import FR-001): manual overrides, the CSV import,
/// provider imports (the most recently imported one wins, FR-002), and the
/// built-in prices from `Resources/prices.json`. Model id normalization and
/// the prefix fallback in `price(for:)` apply to the merged table (FR-003).
/// See `effective(builtIn:imported:overrides:)`; `merging(overrides:)` is the
/// two-layer form without imports.
public struct PriceTable: Sendable, Equatable {
    public struct LoadError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Keyed by canonical model id.
    private let byModel: [String: PriceEntry]

    public init(entries: [PriceEntry]) {
        var map: [String: PriceEntry] = [:]
        for entry in entries { map[entry.model] = entry }
        self.byModel = map
    }

    /// All entries sorted by model id.
    public var entries: [PriceEntry] {
        byModel.values.sorted { $0.model < $1.model }
    }

    /// Loads `Resources/prices.json` from the module bundle.
    public static func builtIn() throws -> PriceTable {
        guard let url = Bundle.module.url(forResource: "prices", withExtension: "json") else {
            throw LoadError(description: "prices.json not found in the UsageCore resource bundle")
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([PriceEntry].self, from: data)
        return PriceTable(entries: decoded.map { entry in
            var e = entry
            e.source = .builtIn
            return e
        })
    }

    /// User entries replace built-in entries with the same canonical model.
    public func merging(overrides: [PriceEntry]) -> PriceTable {
        var map = byModel
        for override in overrides {
            var e = override
            e.model = PriceTable.canonicalModel(override.model)
            e.source = .override
            map[e.model] = e
        }
        return PriceTable(entries: Array(map.values))
    }

    /// The layered table (FR-001 to FR-005). Layers from lowest to highest:
    /// built-in, provider batches by ascending `importedAt` (the most recent
    /// import wins, FR-002), the CSV batch, manual overrides. Each layer
    /// replaces entries with the same canonical id and stamps `source`.
    /// Override entries are kept as they are apart from id and source (FR-004).
    public static func effective(builtIn: PriceTable, imported: ImportedPrices, overrides: [PriceEntry]) -> PriceTable {
        var map: [String: PriceEntry] = [:]
        for entry in builtIn.byModel.values {
            var e = entry
            e.source = .builtIn
            map[e.model] = e
        }
        let providers = imported.batches.filter { $0.kind.isProvider }.sorted { $0.importedAt < $1.importedAt }
        let csv = imported.batches.filter { $0.kind == .csv }
        for batch in providers + csv {
            let provenance = batch.provenance
            for entry in batch.entries {
                var e = entry
                e.model = canonicalModel(entry.model)
                e.source = .imported(provenance)
                map[e.model] = e
            }
        }
        return PriceTable(entries: Array(map.values)).merging(overrides: overrides)
    }

    /// Strips a trailing `-YYYYMMDD` or `@YYYYMMDD` snapshot suffix.
    public static func canonicalModel(_ raw: String) -> String {
        for separator in ["-", "@"] {
            guard let range = raw.range(of: separator, options: .backwards) else { continue }
            let suffix = raw[range.upperBound...]
            if suffix.count == 8, suffix.allSatisfy(\.isNumber) {
                return String(raw[..<range.lowerBound])
            }
        }
        return raw
    }

    /// Exact match on the canonical id, otherwise the longest key that is a
    /// prefix ending at a `-` boundary where the next segment is not a bare
    /// version number (`claude-opus-5-5-eu` matches `claude-opus-5-5`, but
    /// `claude-opus-5-55` is a different model and stays unpriced).
    public func price(for model: String) -> PriceEntry? {
        let canonical = PriceTable.canonicalModel(model)
        if let exact = byModel[canonical] { return exact }
        var best: PriceEntry?
        for (key, entry) in byModel where canonical.hasPrefix(key + "-") {
            let remainder = canonical.dropFirst(key.count + 1)
            let nextSegment = remainder.prefix { $0 != "-" }
            if nextSegment.isEmpty || nextSegment.allSatisfy(\.isNumber) { continue }
            if best == nil || key.count > best!.model.count {
                best = entry
            }
        }
        return best
    }

    /// Whether an imported model id is usable. Imported ids reach the Prices
    /// tab, the diagnostic log and CSV exports that are opened in
    /// spreadsheets, and an id with a line break can never match a log model
    /// id. An id with line breaks or control characters, longer than 200
    /// characters, or starting with a spreadsheet formula character (`=`,
    /// `+`, `-`, `@`) is rejected: LiteLLM entries with such ids are skipped
    /// as malformed (FR-013), CSV rows are skipped as "invalid model id".
    /// LiteLLM keys never contain spaces, so spaces are rejected there too;
    /// a hand-written CSV may use them (`allowingSpaces`).
    public static func isAcceptableImportedModelId(_ id: String, allowingSpaces: Bool = false) -> Bool {
        guard let first = id.unicodeScalars.first, id.unicodeScalars.count <= 200 else { return false }
        if "=+-@".unicodeScalars.contains(first) { return false }
        return !id.unicodeScalars.contains { scalar in
            if scalar == " " { return !allowingSpaces }
            return CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
        }
    }

    /// The row for a canonical model id, without prefix fallback.
    public func entry(exactly model: String) -> PriceEntry? {
        byModel[PriceTable.canonicalModel(model)]
    }

    /// The canonical ids of the rows that the given model ids resolve to with
    /// the rule of `price(for:)` (exact match or prefix fallback). Used for
    /// the "Used in this window" filter and the new-model split (research R9).
    public func resolvedModels(for models: Set<String>) -> Set<String> {
        Set(models.compactMap { price(for: $0)?.model })
    }

    /// Cost in USD, nil when the model has no price entry (FR-016).
    public func cost(of record: RawUsageRecord) -> Decimal? {
        cost(model: record.model, input: record.inputTokens, output: record.outputTokens,
             cacheWrite5m: record.cacheWrite5mTokens, cacheWrite1h: record.cacheWrite1hTokens,
             cacheRead: record.cacheReadTokens)
    }

    public func cost(model: String, input: Int, output: Int, cacheWrite5m: Int, cacheWrite1h: Int, cacheRead: Int) -> Decimal? {
        guard let p = price(for: model) else { return nil }
        return PriceTable.cost(input: input, output: output, cacheWrite5m: cacheWrite5m, cacheWrite1h: cacheWrite1h,
                               cacheRead: cacheRead, price: p)
    }

    public static func cost(input: Int, output: Int, cacheWrite5m: Int, cacheWrite1h: Int, cacheRead: Int, price p: PriceEntry) -> Decimal {
        let million = Decimal(1_000_000)
        let total = Decimal(input) * p.inputPerMTok
            + Decimal(output) * p.outputPerMTok
            + Decimal(cacheWrite5m) * p.cacheWrite5mPerMTok
            + Decimal(cacheWrite1h) * p.cacheWrite1hPerMTok
            + Decimal(cacheRead) * p.cacheReadPerMTok
        return total / million
    }
}
