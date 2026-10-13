import Foundation
import Testing
@testable import UsageCore

@Suite struct PriceTableTests {
    static let researchModels = [
        "claude-fable-5-1", "claude-fable-5", "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7",
        "claude-opus-4-6", "claude-sonnet-5-5", "claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-5-5", "claude-haiku-4-5",
    ]

    @Test func builtInTableLoadsFromBundle() throws {
        let table = try PriceTable.builtIn()
        for model in Self.researchModels {
            let entry = try #require(table.price(for: model), "missing \(model)")
            #expect(entry.source == .builtIn)
            #expect(entry.cacheWrite5mPerMTok == entry.inputPerMTok * Decimal(string: "1.25")!)
            #expect(entry.cacheWrite1hPerMTok == entry.inputPerMTok * 2)
        }
        #expect(table.entries.count == 12)
        #expect(table.price(for: "claude-opus-5-5")?.cacheReadPerMTok == Decimal(string: "0.2"))
        #expect(table.price(for: "claude-fable-5-1")?.outputPerMTok == 50)
    }

    @Test func normalizationStripsSnapshotSuffixes() {
        #expect(PriceTable.canonicalModel("claude-haiku-4-5-20251001") == "claude-haiku-4-5")
        #expect(PriceTable.canonicalModel("claude-opus-5-5@20251101") == "claude-opus-5-5")
        #expect(PriceTable.canonicalModel("claude-opus-5-5") == "claude-opus-5-5")
        #expect(PriceTable.canonicalModel("claude-opus-5-55") == "claude-opus-5-55")
        #expect(PriceTable.canonicalModel("") == "")
    }

    @Test func prefixFallbackMatchesOnlyAtDashBoundaryAndPrefersLongest() throws {
        let table = try PriceTable.builtIn()
        #expect(table.price(for: "claude-opus-5-5-eu")?.model == "claude-opus-5-5")
        #expect(table.price(for: "claude-opus-5-55") == nil)
        #expect(table.price(for: "claude-opus-5-5") != nil)
        #expect(table.price(for: "claude-haiku-4-5-20251001")?.model == "claude-haiku-4-5")
        #expect(table.price(for: "claude-opus-5-x")?.model == "claude-opus-5")
        #expect(table.price(for: "claude-opus") == nil)
        #expect(table.price(for: "claude-mystery-9") == nil)
    }

    @Test func overrideReplacesBuiltIn() throws {
        let override = PriceEntry(model: "claude-opus-5-5", inputPerMTok: 1, outputPerMTok: 2, cacheWrite5mPerMTok: 3, cacheWrite1hPerMTok: 4, cacheReadPerMTok: 5)
        let added = PriceEntry(model: "claude-mystery-9", inputPerMTok: 10, outputPerMTok: 20, cacheWrite5mPerMTok: 12, cacheWrite1hPerMTok: 20, cacheReadPerMTok: 1)
        let table = try PriceTable.builtIn().merging(overrides: [override, added])
        #expect(table.price(for: "claude-opus-5-5")?.inputPerMTok == 1)
        #expect(table.price(for: "claude-opus-5-5")?.source == .override)
        #expect(table.price(for: "claude-mystery-9")?.source == .override)
        #expect(table.price(for: "claude-opus-4-6")?.source == .builtIn)
        #expect(table.entries.count == 13)
    }

    @Test func costMatchesHandCalculation() throws {
        let table = try PriceTable.builtIn()
        // claude-opus-5-5: 4.00 in, 20.00 out, 5.00 cache 5m, 8.00 cache 1h, 0.20 cache read
        // 100k*4 + 20k*20 + 50k*5 + 10k*8 + 400k*0.2 = 0.40 + 0.40 + 0.25 + 0.08 + 0.08 = 1.21
        let record = makeRaw(model: "claude-opus-5-5", input: 100_000, output: 20_000, cw5m: 50_000, cw1h: 10_000, cr: 400_000)
        #expect(table.cost(of: record) == Decimal(string: "1.21"))

        // Snapshot suffix resolves to the same price.
        let snapshot = makeRaw(model: "claude-opus-5-5@20251101", input: 1_000_000)
        #expect(table.cost(of: snapshot) == 4)

        // Sonnet 4.6 from the vertex fixture: 1000*3 + 500*15 + 1500*3.75 + 500*6 + 5000*0.3 per MTok
        let sonnet = makeRaw(model: "claude-sonnet-4-6", input: 1000, output: 500, cw5m: 1500, cw1h: 500, cr: 5000)
        #expect(table.cost(of: sonnet) == Decimal(string: "0.020625"))

        #expect(table.cost(of: makeRaw(model: "claude-mystery-9", input: 10)) == nil)
    }
    // MARK: Layered table (FR-001 to FR-005)

    @Test func effectiveAppliesLayersInFixedOrder() throws {
        let builtIn = try PriceTable.builtIn()
        let anthropic = makeBatch(.anthropic, [makeEntry("claude-opus-5-5", input: 7), makeEntry("claude-sonnet-5-5", input: 8),
                                               makeEntry("claude-haiku-5-5", input: 9)])
        let csv = makeBatch(.csv, [makeEntry("claude-sonnet-5-5", input: 11), makeEntry("claude-opus-5-5", input: 12)],
                            at: "2026-10-01T00:00:00Z")
        let override = PriceEntry(model: "claude-opus-5-5-20251101", inputPerMTok: 13, outputPerMTok: 1, cacheWrite5mPerMTok: 1,
                                  cacheWrite1hPerMTok: 1, cacheReadPerMTok: 1)
        let imported = ImportedPrices.empty.replacing(anthropic).replacing(csv)
        let table = PriceTable.effective(builtIn: builtIn, imported: imported, overrides: [override])

        let opus = try #require(table.price(for: "claude-opus-5-5"))
        #expect(opus.inputPerMTok == 13)
        #expect(opus.source == .override)
        #expect(opus.model == "claude-opus-5-5")
        let sonnet = try #require(table.price(for: "claude-sonnet-5-5"))
        #expect(sonnet.inputPerMTok == 11)
        #expect(sonnet.source == .imported(csv.provenance))
        let haiku = try #require(table.price(for: "claude-haiku-5-5"))
        #expect(haiku.inputPerMTok == 9)
        #expect(haiku.source == .imported(anthropic.provenance))
        #expect(table.price(for: "claude-opus-4-6")?.source == .builtIn)
        #expect(table.entries.count == builtIn.entries.count)
    }

    @Test func csvWinsEvenWhenOlderThanProviderImport() throws {
        let provider = makeBatch(.anthropic, [makeEntry("claude-x", input: 1)], at: "2026-10-20T00:00:00Z")
        let csv = makeBatch(.csv, [makeEntry("claude-x", input: 2)], at: "2026-10-01T00:00:00Z")
        let table = PriceTable.effective(builtIn: PriceTable(entries: []),
                                         imported: ImportedPrices.empty.replacing(csv).replacing(provider), overrides: [])
        #expect(table.price(for: "claude-x")?.inputPerMTok == 2)
    }

    @Test func moreRecentProviderImportWins() {
        let older = makeBatch(.openai, [makeEntry("shared-model", input: 1)], at: "2026-10-01T00:00:00Z")
        let newer = makeBatch(.gemini, [makeEntry("shared-model", input: 2)], at: "2026-10-02T00:00:00Z")
        // Order in the file does not matter, only importedAt.
        let a = PriceTable.effective(builtIn: PriceTable(entries: []), imported: ImportedPrices(batches: [newer, older]), overrides: [])
        let b = PriceTable.effective(builtIn: PriceTable(entries: []), imported: ImportedPrices(batches: [older, newer]), overrides: [])
        #expect(a.price(for: "shared-model")?.inputPerMTok == 2)
        #expect(b.price(for: "shared-model")?.inputPerMTok == 2)
        #expect(a.price(for: "shared-model")?.source == .imported(newer.provenance))
    }

    @Test func prefixFallbackResolvesAgainstImportedEntries() {
        let batch = makeBatch(.anthropic, [makeEntry("claude-opus-5-5", input: 7)])
        let table = PriceTable.effective(builtIn: PriceTable(entries: []), imported: ImportedPrices.empty.replacing(batch), overrides: [])
        #expect(table.price(for: "claude-opus-5-5-eu")?.inputPerMTok == 7)
        #expect(table.price(for: "claude-opus-5-5-eu")?.source == .imported(batch.provenance))
        #expect(table.price(for: "claude-opus-5-55") == nil)
    }

    @Test func overridesStayUnchangedApartFromIdAndSource() throws {
        let override = PriceEntry(model: "claude-opus-5-5@20251101", inputPerMTok: 1, outputPerMTok: 2, cacheWrite5mPerMTok: 3,
                                  cacheWrite1hPerMTok: 4, cacheReadPerMTok: 5, source: .builtIn)
        let batch = makeBatch(.csv, [makeEntry("claude-opus-5-5", input: 99)])
        let table = PriceTable.effective(builtIn: try PriceTable.builtIn(), imported: ImportedPrices.empty.replacing(batch),
                                         overrides: [override])
        let entry = try #require(table.price(for: "claude-opus-5-5"))
        #expect(entry == PriceEntry(model: "claude-opus-5-5", inputPerMTok: 1, outputPerMTok: 2, cacheWrite5mPerMTok: 3,
                                    cacheWrite1hPerMTok: 4, cacheReadPerMTok: 5, source: .override))
    }

    @Test func samePricesIgnoresSource() {
        let a = makeEntry("m", input: 2)
        var b = a
        b.source = .imported(ImportProvenance(kind: .csv, origin: "x.csv", importedAt: Date()))
        #expect(a != b)
        #expect(a.samePrices(as: b))
        b.cacheReadPerMTok += 1
        #expect(!a.samePrices(as: b))
    }

    @Test func mergingWithoutImportsMatchesEffective() throws {
        let builtIn = try PriceTable.builtIn()
        let override = makeEntry("claude-mystery-9", input: 3)
        #expect(builtIn.merging(overrides: [override]) == PriceTable.effective(builtIn: builtIn, imported: .empty, overrides: [override]))
    }
}
