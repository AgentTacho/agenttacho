import Foundation

/// What a No limit account's tokens would have cost at its Value as model's
/// prices (spec 041 FR-007, research R4). Notional: it never counts as
/// spend anywhere. Computed at presentation time from the effective price
/// table, so it follows an import or override change at once (story 2,
/// scenario 4).
public enum ReferenceValue: Equatable, Sendable {
    /// No Value as model (FR-007).
    case none
    /// The Value as model, as stored, has no price in the table (FR-013).
    case missing(model: String)
    /// The amount in US dollars and the price table's model id it was
    /// priced at, as the Prices tab shows it (FR-012).
    case value(Decimal, model: String)

    /// Each model's tokens priced at the reference model's rates, every
    /// rate it has including the separate 5-minute and 1-hour cache writes,
    /// and summed. Cost is linear in tokens, so this equals summing per
    /// record as if each had named the reference model (FR-007). The model
    /// is looked up with the normalization and prefix fallback of records
    /// (FR-003, spec 006 FR-020a).
    public static func make(breakdown: [ModelUsage], valueAs: String?, prices: PriceTable) -> ReferenceValue {
        guard let valueAs else { return .none }
        guard let price = prices.price(for: valueAs) else { return .missing(model: valueAs) }
        let amount = breakdown.reduce(Decimal(0)) { sum, usage in
            sum + PriceTable.cost(input: usage.inputTokens, output: usage.outputTokens, cacheWrite5m: usage.cacheWrite5mTokens,
                                  cacheWrite1h: usage.cacheWrite1hTokens, cacheRead: usage.cacheReadTokens, price: price)
        }
        return .value(amount, model: price.model)
    }
}
