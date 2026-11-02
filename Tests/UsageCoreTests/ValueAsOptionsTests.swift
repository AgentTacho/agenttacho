import Foundation
import Testing
@testable import UsageCore

/// Spec 041 FR-017, clarification 2, research R8: the entries of the Value
/// as pop-up.
@Suite struct ValueAsOptionsTests {
    static func entry(_ model: String, _ source: PriceSource = .builtIn) -> PriceEntry {
        PriceEntry(model: model, inputPerMTok: 1, outputPerMTok: 2, cacheWrite5mPerMTok: 1, cacheWrite1hPerMTok: 2, cacheReadPerMTok: 0,
                   source: source)
    }

    static let at = isoDate("2026-10-01T00:00:00Z")

    /// Built-in `claude-opus-5-5` and `claude-haiku-4-5`; a provider import
    /// of `gpt-5` and `claude-haiku-4-5` (which then wins over built-in), a
    /// CSV import of `gateway-a/open-model-7b`; an override of `zz-local`
    /// and of `claude-opus-5-5`.
    static var prices: PriceTable {
        let builtIn = PriceTable(entries: [entry("claude-opus-5-5"), entry("claude-haiku-4-5")])
        let imported = ImportedPrices(batches: [
            PriceBatch(kind: .openai, origin: "https://example.invalid/prices.json", importedAt: at,
                       entries: [entry("gpt-5"), entry("claude-haiku-4-5")]),
            PriceBatch(kind: .csv, origin: "prices.csv", importedAt: at, entries: [entry("gateway-a/open-model-7b")]),
        ])
        return PriceTable.effective(builtIn: builtIn, imported: imported,
                                    overrides: [entry("zz-local", .override), entry("claude-opus-5-5", .override)])
    }

    @Test func primaryAndMoreBySourceSortedOnceEach() {
        let options = ValueAsOptions.make(prices: Self.prices, selected: nil)
        #expect(options.primary == ["claude-opus-5-5", "zz-local"])
        #expect(options.more == ["claude-haiku-4-5", "gateway-a/open-model-7b", "gpt-5"])
        #expect(options.unlisted == nil)
        #expect(options.missing == nil)
    }

    @Test func listedSelectionIsNeitherUnlistedNorMissing() {
        for selected in ["claude-opus-5-5", "gpt-5"] {
            let options = ValueAsOptions.make(prices: Self.prices, selected: selected)
            #expect(options.unlisted == nil)
            #expect(options.missing == nil)
        }
    }

    /// A stored id that resolves only through normalization or the prefix
    /// fallback is shown as stored.
    @Test(arguments: ["claude-opus-5-5@default", "claude-opus-5-5-eu"])
    func selectionResolvingByNormalizationIsUnlisted(selected: String) {
        let options = ValueAsOptions.make(prices: Self.prices, selected: selected)
        #expect(options.unlisted == selected)
        #expect(options.missing == nil)
    }

    @Test func selectionWithoutAPriceIsMissing() {
        let options = ValueAsOptions.make(prices: Self.prices, selected: "gateway-x/unknown")
        #expect(options.missing == "gateway-x/unknown")
        #expect(options.unlisted == nil)
        // contracts/ui-strings.md "Missing selection".
        #expect(ValueAsOptions.missingLabel("gateway-x/unknown") == "gateway-x/unknown (no price)")
    }
}
