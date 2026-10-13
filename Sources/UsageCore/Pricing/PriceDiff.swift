import Foundation

// MARK: - Price fields

/// The five prices of a `PriceEntry`, for per-field diffs and for flagging
/// derived CSV values (FR-015, FR-020).
public enum PriceField: String, CaseIterable, Hashable, Sendable {
    case input
    case output
    case cacheWrite5m
    case cacheWrite1h
    case cacheRead

    public var keyPath: WritableKeyPath<PriceEntry, Decimal> {
        switch self {
        case .input: return \.inputPerMTok
        case .output: return \.outputPerMTok
        case .cacheWrite5m: return \.cacheWrite5mPerMTok
        case .cacheWrite1h: return \.cacheWrite1hPerMTok
        case .cacheRead: return \.cacheReadPerMTok
        }
    }

    /// Short label as used in the Prices tab header.
    public var displayName: String {
        switch self {
        case .input: return "Input"
        case .output: return "Output"
        case .cacheWrite5m: return "Cache 5m"
        case .cacheWrite1h: return "Cache 1h"
        case .cacheRead: return "Cache read"
        }
    }

    /// Column name in the price CSV (contracts/price-csv.md).
    public var csvColumn: String {
        switch self {
        case .input: return "input"
        case .output: return "output"
        case .cacheWrite5m: return "cache_write_5m"
        case .cacheWrite1h: return "cache_write_1h"
        case .cacheRead: return "cache_read"
        }
    }
}

// MARK: - Proposed import

/// A CSV line that could not be imported (FR-017).
public struct SkippedRow: Equatable, Hashable, Sendable {
    /// 1-based line number in the file; the header is line 1.
    public var line: Int
    public var reason: String

    public init(line: Int, reason: String) {
        self.line = line
        self.reason = reason
    }
}

/// An import that has been read but not applied yet: the batch plus, for
/// CSV, skipped rows and derived values (FR-015, FR-017).
public struct ProposedImport: Equatable, Sendable {
    public var batch: PriceBatch
    public var skippedRows: [SkippedRow]
    /// Model id to the fields derived from the input price.
    public var derived: [String: Set<PriceField>]

    public init(batch: PriceBatch, skippedRows: [SkippedRow] = [], derived: [String: Set<PriceField>] = [:]) {
        self.batch = batch
        self.skippedRows = skippedRows
        self.derived = derived
    }

    /// True when the proposal holds the same model ids with the same prices
    /// (`samePrices`) as the stored batch of its kind; provenance and
    /// `importedAt` are ignored. Together with `PriceDiff.isEmpty` this
    /// disables Apply (contracts/prices-tab-ui.md).
    public func matches(_ stored: PriceBatch?) -> Bool {
        guard let stored, stored.kind == batch.kind, stored.entries.count == batch.entries.count else { return false }
        let byModel = Dictionary(stored.entries.map { ($0.model, $0) }, uniquingKeysWith: { _, last in last })
        return batch.entries.allSatisfy { entry in byModel[entry.model].map(entry.samePrices) ?? false }
    }
}

// MARK: - Diff

public struct PriceChange: Equatable, Sendable, Identifiable {
    public var model: String
    public var before: PriceEntry
    public var after: PriceEntry
    public var changedFields: [PriceField]
    public var id: String { model }
}

public struct PriceRemoval: Equatable, Sendable, Identifiable {
    public var model: String
    public var before: PriceEntry
    /// The price the model falls back to; nil means unpriced.
    public var fallback: PriceEntry?
    public var id: String { model }
}

public struct PriceShadow: Equatable, Sendable, Identifiable {
    public var model: String
    /// The price in the proposed import.
    public var proposed: PriceEntry
    /// The effective price, which stays in effect.
    public var effective: PriceEntry
    /// The higher-ranked source that keeps winning (FR-020a).
    public var winner: PriceSource
    public var id: String { model }
}

/// The difference between the effective table before and after a proposed
/// import or a removal (FR-020 to FR-020c, FR-023). Each model of the old or
/// new batch of that kind lands in at most one category (research.md R6).
public struct PriceDiff: Equatable, Sendable {
    /// No price before (not even through the prefix fallback), priced
    /// after, sorted by model.
    public var newModels: [PriceEntry]
    /// New models that a used id resolves to (FR-020c).
    public var newUsed: [PriceEntry]
    /// The remaining new models, shown collapsed behind a count.
    public var newOther: [PriceEntry]
    public var changed: [PriceChange]
    public var removed: [PriceRemoval]
    public var shadowed: [PriceShadow]
    public var unchangedCount: Int

    /// No new, changed or removed models; shadowed and unchanged do not count.
    public var isEmpty: Bool {
        newModels.isEmpty && changed.isEmpty && removed.isEmpty
    }

    /// "12 new, 3 changed, 1 removed, 7 unchanged, 1 shadowed", zero
    /// categories omitted. "no changes" when every category is empty, and
    /// "no new, changed or removed models; ..." when only unchanged or
    /// shadowed models remain.
    public var summary: String {
        let parts = [(newModels.count, "new"), (changed.count, "changed"), (removed.count, "removed"),
                     (unchangedCount, "unchanged"), (shadowed.count, "shadowed")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)" }
        if parts.isEmpty { return "no changes" }
        if isEmpty { return "no new, changed or removed models; " + parts.joined(separator: ", ") }
        return parts.joined(separator: ", ")
    }

    /// Compares the effective table before and after replacing the batch of
    /// `kind` with `proposed`. `proposed == nil` describes a removal.
    /// `usedModels` are raw or canonical model ids from the current snapshot;
    /// nil when there is no snapshot yet.
    public static func compute(current: ImportedPrices, proposed: PriceBatch?, kind: ImportKind, builtIn: PriceTable,
                               overrides: [PriceEntry], usedModels: Set<String>?) -> PriceDiff {
        precondition(proposed == nil || proposed?.kind == kind, "a proposed batch must be of the compared kind")
        let before = PriceTable.effective(builtIn: builtIn, imported: current, overrides: overrides)
        let afterImports = proposed.map { current.replacing($0) } ?? current.removing(kind)
        let after = PriceTable.effective(builtIn: builtIn, imported: afterImports, overrides: overrides)

        var proposedByModel: [String: PriceEntry] = [:]
        for entry in proposed?.entries ?? [] {
            proposedByModel[PriceTable.canonicalModel(entry.model)] = entry
        }
        var models = Set(proposedByModel.keys)
        for entry in current.batch(for: kind)?.entries ?? [] {
            models.insert(PriceTable.canonicalModel(entry.model))
        }

        var newModels: [PriceEntry] = []
        var changed: [PriceChange] = []
        var removed: [PriceRemoval] = []
        var shadowed: [PriceShadow] = []
        var unchanged = 0

        for model in models.sorted() {
            let b = before.entry(exactly: model)
            let a = after.entry(exactly: model)
            let p = proposedByModel[model]
            switch (b, a) {
            case (nil, let a?):
                // A model without its own row may already be priced through
                // the prefix fallback (FR-003); then it is not new.
                if let fallback = before.price(for: model) {
                    if fallback.samePrices(as: a) {
                        unchanged += 1
                    } else {
                        let fields = PriceField.allCases.filter { fallback[keyPath: $0.keyPath] != a[keyPath: $0.keyPath] }
                        changed.append(PriceChange(model: model, before: fallback, after: a, changedFields: fields))
                    }
                } else {
                    newModels.append(a)
                }
            case (let b?, nil):
                // Without its own row the model is priced through the prefix
                // fallback of `price(for:)` (FR-003), if any row matches.
                let fallback = after.price(for: model)
                if let fallback, fallback.samePrices(as: b) { continue }
                removed.append(PriceRemoval(model: model, before: b, fallback: fallback))
            case (let b?, let a?) where !b.samePrices(as: a):
                if case .imported(let provenance) = a.source, provenance.kind == kind {
                    let fields = PriceField.allCases.filter { b[keyPath: $0.keyPath] != a[keyPath: $0.keyPath] }
                    changed.append(PriceChange(model: model, before: b, after: a, changedFields: fields))
                } else {
                    removed.append(PriceRemoval(model: model, before: b, fallback: a))
                }
            case (_, let a?):
                guard let p else { continue }
                if p.samePrices(as: a) {
                    unchanged += 1
                } else {
                    shadowed.append(PriceShadow(model: model, proposed: p, effective: a, winner: a.source))
                }
            case (nil, nil):
                continue
            }
        }

        let usedRows = usedModels.map { after.resolvedModels(for: $0) }
        let newUsed = usedRows.map { rows in newModels.filter { rows.contains($0.model) } } ?? []
        let newOther = newModels.filter { entry in !(usedRows?.contains(entry.model) ?? false) }
        return PriceDiff(newModels: newModels, newUsed: newUsed, newOther: newOther, changed: changed, removed: removed,
                         shadowed: shadowed, unchangedCount: unchanged)
    }
}
