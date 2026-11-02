import Foundation
import Testing
@testable import UsageCore

/// Spec 041 FR-003, FR-007, SC-003, research R4: the value of a No limit
/// account's tokens at the Value as model's prices.
@Suite struct ReferenceValueTests {
    /// `claude-opus-5-5`: input 4.00, output 20.00, cache write 5m 5.00, 1h
    /// 8.00, cache read 0.20 per MTok.
    static let prices = PriceTable(entries: [
        PriceEntry(model: "claude-opus-5-5", inputPerMTok: 4, outputPerMTok: 20, cacheWrite5mPerMTok: 5, cacheWrite1hPerMTok: 8,
                   cacheReadPerMTok: Decimal(string: "0.2")!, source: .builtIn),
        PriceEntry(model: "gateway-a/open-model-7b", inputPerMTok: 1000, outputPerMTok: 1000, cacheWrite5mPerMTok: 1000,
                   cacheWrite1hPerMTok: 1000, cacheReadPerMTok: 1000, source: .override),
    ])

    /// 2,000,000 input, 500,000 output, 600,000 5-minute and 400,000 1-hour
    /// cache write and 30,000,000 cache read tokens, over two models.
    static let breakdown = [
        ModelUsage(model: "gateway-a/open-model-7b", inputTokens: 1_500_000, outputTokens: 300_000, cacheWrite5mTokens: 600_000,
                   cacheReadTokens: 20_000_000),
        ModelUsage(model: "gateway-a/other-model", inputTokens: 500_000, outputTokens: 200_000, cacheWrite1hTokens: 400_000,
                   cacheReadTokens: 10_000_000),
    ]

    /// 8.00 + 10.00 + 3.00 + 3.20 + 6.00 = 30.20, to the cent (SC-003).
    @Test func handComputedValue() {
        #expect(ReferenceValue.make(breakdown: Self.breakdown, valueAs: "claude-opus-5-5", prices: Self.prices)
                == .value(Decimal(string: "30.2")!, model: "claude-opus-5-5"))
    }

    /// The account's own model prices are never used (FR-008).
    @Test func ownModelPricesAreIgnored() {
        guard case .value(let amount, _) = ReferenceValue.make(breakdown: Self.breakdown, valueAs: "claude-opus-5-5", prices: Self.prices) else {
            Issue.record("expected a value")
            return
        }
        #expect(amount < 100)
    }

    @Test func noValueAsModelIsNone() {
        #expect(ReferenceValue.make(breakdown: Self.breakdown, valueAs: nil, prices: Self.prices) == .none)
    }

    @Test func modelWithoutAPriceIsMissing() {
        #expect(ReferenceValue.make(breakdown: Self.breakdown, valueAs: "gateway-x/unknown", prices: Self.prices)
                == .missing(model: "gateway-x/unknown"))
    }

    /// The same normalization and fallback as records (FR-003); the value
    /// names the price table's model id.
    @Test(arguments: ["claude-opus-5-5@default", "claude-opus-5-5-20261001", "claude-opus-5-5-eu"])
    func valueAsResolvesLikeARecord(valueAs: String) {
        #expect(ReferenceValue.make(breakdown: Self.breakdown, valueAs: valueAs, prices: Self.prices)
                == .value(Decimal(string: "30.2")!, model: "claude-opus-5-5"))
    }

    /// No usage is worth exactly 0.
    @Test func emptyBreakdownIsZero() {
        #expect(ReferenceValue.make(breakdown: [], valueAs: "claude-opus-5-5", prices: Self.prices) == .value(0, model: "claude-opus-5-5"))
    }

    /// Summing per model equals summing per record priced as the reference
    /// model (FR-007).
    @Test func sameAsPerRecordCosts() {
        let records: [(Int, Int, Int, Int, Int)] = [
            (1_000_000, 100_000, 300_000, 0, 10_000_000), (500_000, 200_000, 300_000, 0, 10_000_000),
            (500_000, 200_000, 0, 400_000, 10_000_000),
        ]
        let perRecord = records.reduce(Decimal(0)) { sum, r in
            sum + Self.prices.cost(model: "claude-opus-5-5", input: r.0, output: r.1, cacheWrite5m: r.2, cacheWrite1h: r.3, cacheRead: r.4)!
        }
        #expect(ReferenceValue.make(breakdown: Self.breakdown, valueAs: "claude-opus-5-5", prices: Self.prices)
                == .value(perRecord, model: "claude-opus-5-5"))
    }
}
