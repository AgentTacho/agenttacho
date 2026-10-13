import Foundation
import Testing
@testable import UsageCore

/// Classification per research.md R6 (FR-020 to FR-020c, FR-023).
@Suite struct PriceDiffTests {
    /// Two built-in models: claude-a (input 1) and claude-b (input 2).
    static let builtIn = PriceTable(entries: [makeEntry("claude-a", input: 1), makeEntry("claude-b", input: 2)].map {
        var e = $0
        e.source = .builtIn
        return e
    })

    private func diff(current: ImportedPrices = .empty, proposed: PriceBatch?, kind: ImportKind? = nil,
                      overrides: [PriceEntry] = [], used: Set<String>? = nil) -> PriceDiff {
        PriceDiff.compute(current: current, proposed: proposed, kind: kind ?? proposed!.kind, builtIn: Self.builtIn,
                          overrides: overrides, usedModels: used)
    }

    @Test func newChangedAndUnchanged() {
        let batch = makeBatch(.anthropic, [makeEntry("claude-a", input: 1), makeEntry("claude-b", input: 3, cr: Decimal(string: "0.2")!),
                                           makeEntry("claude-c", input: 4)])
        let d = diff(proposed: batch)
        #expect(d.newModels.map(\.model) == ["claude-c"])
        #expect(d.changed.map(\.model) == ["claude-b"])
        let change = d.changed[0]
        #expect(change.before.inputPerMTok == 2)
        #expect(change.after.inputPerMTok == 3)
        #expect(change.changedFields == [.input, .cacheWrite5m, .cacheWrite1h])
        #expect(d.unchangedCount == 1)
        #expect(d.removed.isEmpty)
        #expect(d.shadowed.isEmpty)
        #expect(!d.isEmpty)
        #expect(d.summary == "1 new, 1 changed, 1 unchanged")
    }

    @Test func changedFieldsListOnlyDifferingFields() {
        // claude-b built in: input 2, output 5, cw5m 2.5, cw1h 4, cr 0.2. Only cache read differs.
        let batch = makeBatch(.anthropic, [makeEntry("claude-b", input: 2, cr: Decimal(string: "0.1")!)])
        let d = diff(proposed: batch)
        #expect(d.changed.first?.changedFields == [.cacheRead])
    }

    @Test func shadowedByOverride() {
        let override = makeEntry("claude-a", input: 10)
        let batch = makeBatch(.anthropic, [makeEntry("claude-a", input: 5)])
        let d = diff(proposed: batch, overrides: [override])
        #expect(d.shadowed.map(\.model) == ["claude-a"])
        #expect(d.shadowed[0].winner == .override)
        #expect(d.shadowed[0].proposed.inputPerMTok == 5)
        #expect(d.shadowed[0].effective.inputPerMTok == 10)
        #expect(d.changed.isEmpty)
        #expect(d.unchangedCount == 0)
        #expect(d.isEmpty)
    }

    @Test func shadowedByCSVForProviderImport() {
        let csv = makeBatch(.csv, [makeEntry("claude-a", input: 7)])
        let current = ImportedPrices.empty.replacing(csv)
        let batch = makeBatch(.anthropic, [makeEntry("claude-a", input: 5)])
        let d = diff(current: current, proposed: batch)
        #expect(d.shadowed.map(\.model) == ["claude-a"])
        #expect(d.shadowed[0].winner == .imported(csv.provenance))
        #expect(d.changed.isEmpty)
    }

    @Test func proposedPriceEqualToWinningOverrideIsUnchanged() {
        let override = makeEntry("claude-a", input: 5)
        let batch = makeBatch(.anthropic, [makeEntry("claude-a", input: 5)])
        let d = diff(proposed: batch, overrides: [override])
        #expect(d.shadowed.isEmpty)
        #expect(d.unchangedCount == 1)
    }

    @Test func removedFallsBackToLowerLayer() {
        let old = makeBatch(.anthropic, [makeEntry("claude-a", input: 9), makeEntry("claude-x", input: 9)])
        let current = ImportedPrices.empty.replacing(old)
        let batch = makeBatch(.anthropic, [makeEntry("claude-x", input: 9)], at: "2026-10-14T00:00:00Z")
        let d = diff(current: current, proposed: batch)
        #expect(d.removed.map(\.model) == ["claude-a"])
        #expect(d.removed[0].before.inputPerMTok == 9)
        #expect(d.removed[0].fallback?.inputPerMTok == 1)
        #expect(d.removed[0].fallback?.source == .builtIn)
        #expect(d.unchangedCount == 1)
        #expect(d.summary == "1 removed, 1 unchanged")
    }

    @Test func removedToUnpriced() {
        let old = makeBatch(.csv, [makeEntry("claude-z", input: 9), makeEntry("claude-y", input: 1)])
        let current = ImportedPrices.empty.replacing(old)
        let batch = makeBatch(.csv, [makeEntry("claude-y", input: 1)], at: "2026-10-14T00:00:00Z")
        let d = diff(current: current, proposed: batch)
        #expect(d.removed.map(\.model) == ["claude-z"])
        #expect(d.removed[0].fallback == nil)
    }

    @Test func removalImpactWithoutProposedBatch() {
        let csv = makeBatch(.csv, [makeEntry("claude-a", input: 9), makeEntry("claude-new", input: 3), makeEntry("claude-b", input: 2)])
        let current = ImportedPrices.empty.replacing(csv)
        let d = diff(current: current, proposed: nil, kind: .csv)
        #expect(d.removed.map(\.model) == ["claude-a", "claude-new"])
        #expect(d.removed.first { $0.model == "claude-new" }?.fallback == nil)
        #expect(d.removed.first { $0.model == "claude-a" }?.fallback?.inputPerMTok == 1)
        #expect(d.newModels.isEmpty)
        #expect(d.changed.isEmpty)
        #expect(d.unchangedCount == 0)
    }

    @Test func removingProviderShadowedByCSVAffectsNothing() {
        let provider = makeBatch(.anthropic, [makeEntry("claude-a", input: 5)])
        let csv = makeBatch(.csv, [makeEntry("claude-a", input: 7)])
        let current = ImportedPrices.empty.replacing(provider).replacing(csv)
        let d = diff(current: current, proposed: nil, kind: .anthropic)
        #expect(d.removed.isEmpty)
        #expect(d.isEmpty)
    }

    @Test func modelsOutsideBothBatchesAreIgnored() {
        let csv = makeBatch(.csv, [makeEntry("claude-q", input: 7)])
        let current = ImportedPrices.empty.replacing(csv)
        let batch = makeBatch(.anthropic, [makeEntry("claude-a", input: 1)])
        let d = diff(current: current, proposed: batch, overrides: [makeEntry("claude-o", input: 3)])
        #expect(d.unchangedCount == 1)
        #expect(d.newModels.isEmpty && d.changed.isEmpty && d.removed.isEmpty && d.shadowed.isEmpty)
    }

    @Test func modelOnlyInReplacedBatchWithUnchangedPriceIsNotListed() {
        // claude-a in the old batch equals built-in, so dropping it changes nothing.
        let old = makeBatch(.anthropic, [makeEntry("claude-a", input: 1)])
        let current = ImportedPrices.empty.replacing(old)
        let batch = makeBatch(.anthropic, [makeEntry("claude-c", input: 4)], at: "2026-10-14T00:00:00Z")
        let d = diff(current: current, proposed: batch)
        #expect(d.removed.isEmpty)
        #expect(d.newModels.map(\.model) == ["claude-c"])
        #expect(d.unchangedCount == 0)
    }

    @Test func reimportWithLaterDateIsUnchanged() {
        let entries = [makeEntry("claude-a", input: 3), makeEntry("claude-c", input: 4)]
        let old = makeBatch(.anthropic, entries)
        let current = ImportedPrices.empty.replacing(old)
        let batch = makeBatch(.anthropic, entries, at: "2026-10-20T00:00:00Z")
        let d = diff(current: current, proposed: batch)
        #expect(d.unchangedCount == 2)
        #expect(d.changed.isEmpty)
        #expect(d.isEmpty)
        #expect(d.summary == "no new, changed or removed models; 2 unchanged")
    }

    @Test func everyModelLandsInExactlyOneCategory() {
        let old = makeBatch(.anthropic, [makeEntry("claude-a", input: 9), makeEntry("claude-gone", input: 1), makeEntry("claude-o", input: 2)])
        let current = ImportedPrices.empty.replacing(old)
        let batch = makeBatch(.anthropic, [makeEntry("claude-a", input: 8), makeEntry("claude-b", input: 2), makeEntry("claude-new", input: 1),
                                           makeEntry("claude-o", input: 4)], at: "2026-10-14T00:00:00Z")
        let d = diff(current: current, proposed: batch, overrides: [makeEntry("claude-o", input: 5)])
        let lists = [d.newModels.map(\.model), d.changed.map(\.model), d.removed.map(\.model), d.shadowed.map(\.model)]
        let all = lists.flatMap { $0 }
        #expect(Set(all).count == all.count)
        #expect(d.changed.map(\.model) == ["claude-a"])
        #expect(d.newModels.map(\.model) == ["claude-new"])
        #expect(d.removed.map(\.model) == ["claude-gone"])
        #expect(d.shadowed.map(\.model) == ["claude-o"])
        #expect(d.unchangedCount == 1) // claude-b equals built-in
        #expect(all.count + d.unchangedCount == 5)
    }

    @Test func newModelsSplitByUsage() {
        let batch = makeBatch(.anthropic, [makeEntry("claude-new-1", input: 1), makeEntry("claude-new-2", input: 1),
                                           makeEntry("claude-new-3", input: 1)])
        let d = diff(proposed: batch, used: ["claude-new-1-eu", "claude-new-3-20260101", "claude-a"])
        #expect(d.newUsed.map(\.model) == ["claude-new-1", "claude-new-3"])
        #expect(d.newOther.map(\.model) == ["claude-new-2"])
        #expect(d.newModels.count == 3)

        let noSnapshot = diff(proposed: batch, used: nil)
        #expect(noSnapshot.newUsed.isEmpty)
        #expect(noSnapshot.newOther.count == 3)
    }

    @Test func summaryForNoChanges() {
        let d = diff(current: .empty, proposed: nil, kind: .gemini)
        #expect(d.isEmpty)
        #expect(d.summary == "no changes")
    }

    @Test func summaryListsAllNonZeroCategories() {
        let old = makeBatch(.anthropic, [makeEntry("claude-gone", input: 1)])
        let batch = makeBatch(.anthropic, [makeEntry("claude-a", input: 2), makeEntry("claude-b", input: 2), makeEntry("claude-n", input: 1),
                                           makeEntry("claude-s", input: 1)], at: "2026-10-14T00:00:00Z")
        let d = diff(current: ImportedPrices.empty.replacing(old), proposed: batch, overrides: [makeEntry("claude-s", input: 9)])
        #expect(d.summary == "1 new, 1 changed, 1 removed, 1 unchanged, 1 shadowed")
    }
    @Test func proposalMatchesStoredBatchIgnoringProvenance() {
        let stored = makeBatch(.anthropic, [makeEntry("claude-a", input: 3), makeEntry("claude-c", input: 4)])
        let same = ProposedImport(batch: makeBatch(.anthropic, [makeEntry("claude-c", input: 4), makeEntry("claude-a", input: 3)],
                                                   origin: "other", at: "2026-10-20T00:00:00Z"))
        #expect(same.matches(stored))
        #expect(!same.matches(nil))
        let fewer = ProposedImport(batch: makeBatch(.anthropic, [makeEntry("claude-a", input: 3)]))
        #expect(!fewer.matches(stored))
        let different = ProposedImport(batch: makeBatch(.anthropic, [makeEntry("claude-a", input: 3), makeEntry("claude-c", input: 5)]))
        #expect(!different.matches(stored))
    }

    // MARK: Other providers and the prefix fallback

    @Test func reimportWithoutAModelFallsBackToAnotherProvider() {
        let openai = makeBatch(.openai, [makeEntry("shared", input: 2)], at: "2026-10-13T10:00:00Z")
        let anthropic = makeBatch(.anthropic, [makeEntry("shared", input: 3), makeEntry("claude-x", input: 1)], at: "2026-10-13T11:00:00Z")
        let current = ImportedPrices.empty.replacing(openai).replacing(anthropic)
        let proposed = makeBatch(.anthropic, [makeEntry("claude-x", input: 1)], at: "2026-10-13T15:00:00Z")
        let d = diff(current: current, proposed: proposed)
        #expect(d.removed.map(\.model) == ["shared"])
        #expect(d.removed.first?.fallback?.inputPerMTok == 2)
        #expect(d.removed.first?.fallback?.source == .imported(openai.provenance))
        #expect(d.changed.isEmpty)
        #expect(d.unchangedCount == 1)
    }

    @Test func importRepricingAModelOfAnotherProviderIsChanged() {
        let openai = makeBatch(.openai, [makeEntry("shared", input: 2)], at: "2026-10-13T10:00:00Z")
        let current = ImportedPrices.empty.replacing(openai)
        let proposed = makeBatch(.anthropic, [makeEntry("shared", input: 3)], at: "2026-10-13T15:00:00Z")
        let d = diff(current: current, proposed: proposed)
        #expect(d.changed.map(\.model) == ["shared"])
        #expect(d.changed.first?.before.source == .imported(openai.provenance))
        #expect(d.removed.isEmpty)
    }

    /// A model priced through the prefix fallback before the import is not
    /// new: same prices count as unchanged, different ones as changed.
    @Test func modelPricedThroughThePrefixFallbackIsNotNew() {
        let same = diff(proposed: makeBatch(.anthropic, [makeEntry("claude-a-latest", input: 1)]))
        #expect(same.newModels.isEmpty)
        #expect(same.unchangedCount == 1)

        let differs = diff(proposed: makeBatch(.anthropic, [makeEntry("claude-a-latest", input: 9)]))
        #expect(differs.newModels.isEmpty)
        #expect(differs.changed.map(\.model) == ["claude-a-latest"])
        #expect(differs.changed.first?.before.model == "claude-a")
        // Built-in claude-a: input 1, output 5; only the output stays.
        #expect(differs.changed.first?.changedFields == [.input, .cacheWrite5m, .cacheWrite1h, .cacheRead])
    }

    /// Without its own row a model is still priced through the prefix
    /// fallback (FR-003); the removal shows that row, or nothing when the
    /// price stays the same.
    @Test func removalUsesThePrefixFallback() {
        let differs = ImportedPrices.empty.replacing(makeBatch(.anthropic, [makeEntry("claude-a-latest", input: 9)]))
        let d = diff(current: differs, proposed: nil, kind: .anthropic)
        #expect(d.removed.map(\.model) == ["claude-a-latest"])
        #expect(d.removed.first?.fallback?.model == "claude-a")
        #expect(d.removed.first?.fallback?.source == .builtIn)

        let same = ImportedPrices.empty.replacing(makeBatch(.anthropic, [makeEntry("claude-a-latest", input: 1)]))
        let unchanged = diff(current: same, proposed: nil, kind: .anthropic)
        #expect(unchanged.removed.isEmpty)
        #expect(unchanged.isEmpty)
    }
}
