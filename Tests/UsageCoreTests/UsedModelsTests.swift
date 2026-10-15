import Foundation
import Testing
@testable import UsageCore

/// The models behind the Prices tab's "Used in this window" filter (spec 002
/// FR-030, research R9): every breakdown of the snapshot, including the
/// unpriced token counts of Codex subscription accounts (spec 006 FR-017).
@Suite struct UsedModelsTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))

    func breakdown(_ models: [String], unpriced: [String] = []) -> UsageBreakdown {
        UsageBreakdown(perModel: models.map { ModelUsage(model: $0, inputTokens: 1, costUSD: nil, priced: true) },
                       unpricedModels: unpriced)
    }

    @Test func collectsCanonicalModelsFromEveryBreakdown() {
        var snapshot = UsageSnapshot(generatedAt: window.start, window: window, windowSource: .fallback)
        snapshot.subscriptions["sub"] = SubscriptionEntry(status: nil, state: .ok, breakdown: breakdown(["claude-opus-5-5"]))
        snapshot.groups["grp"] = GroupEntry(spentUSD: 1, budgetUSD: 10, percent: 10, incomplete: false, window: window,
                                            breakdown: breakdown(["claude-fable-5-1"]), members: [], stale: false)
        snapshot.tokenAccounts["tok"] = TokenAccountEntry(breakdown: breakdown(["gpt-5", "new-model"], unpriced: ["new-model"]))
        snapshot.unassigned = TokenAccountEntry(breakdown: breakdown(["claude-haiku-5-5"]))

        #expect(snapshot.usedModels == ["claude-opus-5-5", "claude-fable-5-1", "gpt-5", "new-model", "claude-haiku-5-5"])
    }

    @Test func includesCodexSubscriptionModels() {
        var snapshot = UsageSnapshot(generatedAt: window.start, window: window, windowSource: .fallback)
        snapshot.codexPlanTokens["codex"] = TokenAccountEntry(breakdown: breakdown(["gpt-5.6-sol", "gpt-5-codex"]))

        #expect(snapshot.usedModels == ["gpt-5.6-sol", "gpt-5-codex"])
    }

    @Test func emptySnapshotHasNoModels() {
        let snapshot = UsageSnapshot(generatedAt: window.start, window: window, windowSource: .fallback)
        #expect(snapshot.usedModels.isEmpty)
    }
}
