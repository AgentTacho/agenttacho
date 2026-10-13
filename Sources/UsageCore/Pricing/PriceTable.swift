import Foundation

/// Built-in prices merged with user overrides (FR-014, FR-015). Prices are
/// USD per million tokens.
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
