import Foundation

/// The Σ column at the end of a day row (spec 026 FR-009, research R2): the
/// sum of all shown days in the row's own format, and its exact value as
/// tooltip in a day column's wording prefixed with "Total".
public struct DayRowTotal: Equatable, Sendable {
    /// The column's value: whole millions of tokens for token rows
    /// (subscriptions, Unassigned), compact US dollars for cost rows
    /// (budgets); "0" without usage.
    public let text: String
    /// "Total: 188.7M tokens" or "Total: $430.12", plus "incomplete:
    /// some usage is unpriced" on a second line for an incomplete budget.
    public let tooltip: String

    public init(text: String, tooltip: String) {
        self.text = text
        self.tooltip = tooltip
    }

    /// Cost rows sum each day's cost, a day without one counting 0; token
    /// rows sum each day's tokens of all four kinds (spec 026 FR-009).
    public static func make(days: [DayUsage], showsCost: Bool, incomplete: Bool, locale: Locale) -> DayRowTotal {
        var text: String
        var tooltip: String
        if showsCost {
            let sum = days.reduce(Decimal(0)) { $0 + ($1.costUSD ?? 0) }
            text = CompactFormat.usd(sum, locale: locale)
            tooltip = "Total: " + sum.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(locale))
        } else {
            let sum = days.reduce(0) { $0 + $1.totalTokens }
            text = CompactFormat.millions(sum, locale: locale)
            tooltip = "Total: " + DayRowHeader.millionsText(sum, locale: locale)
        }
        if incomplete {
            tooltip += "\nincomplete: some usage is unpriced"
        }
        return DayRowTotal(text: text, tooltip: tooltip)
    }
}

/// How a day row splits into rows and which row ends with the Σ column
/// (spec 026 FR-009, FR-009a, research R3; spec 003 FR-013).
public enum DayRowLayout {
    /// Days per row of a monthly day row: a 31-day month wraps into at most
    /// 5 rows and, with Σ, stays within the dropdown's width (spec 003 SC-006).
    public static let monthlyDaysPerRow = 7

    /// The index ranges of the shown days per row: a weekly row (7 or 8
    /// local days) stays one row, a monthly row wraps after 7 days. A row
    /// without days is one empty row, so Σ still has a place.
    public static func rows(dayCount: Int, monthly: Bool) -> [Range<Int>] {
        guard dayCount > 0 else { return [0..<0] }
        let perRow = monthly ? monthlyDaysPerRow : dayCount
        return stride(from: 0, to: dayCount, by: perRow).map { $0..<min($0 + perRow, dayCount) }
    }

    /// The row that ends with Σ: the last one, also when it already holds 7
    /// days (spec 026 FR-009).
    public static func sumRowIndex(dayCount: Int, monthly: Bool) -> Int {
        rows(dayCount: dayCount, monthly: monthly).count - 1
    }
}

/// The header column in front of every day row and the day tooltips (spec
/// 026 FR-009b, FR-009c): "Day" over the unit ("Tok" for tokens, counted in
/// millions, "$" for US dollars), with the unit spelled out as tooltip.
public struct DayRowHeader: Equatable, Sendable {
    public let top: String
    public let bottom: String
    public let tooltip: String

    public init(top: String, bottom: String, tooltip: String) {
        self.top = top
        self.bottom = bottom
        self.tooltip = tooltip
    }

    public static func make(showsCost: Bool) -> DayRowHeader {
        showsCost
            ? DayRowHeader(top: "Day", bottom: "$", tooltip: "Cost per day, in US$")
            : DayRowHeader(top: "Day", bottom: "Tok", tooltip: "Tokens per day, in millions")
    }

    /// A day column's tooltip: the date, then the exact cost for a priced
    /// day of a cost row, otherwise the tokens in millions with at most one
    /// decimal ("Oct 19, 2026: 42.3M tokens").
    public static func dayTooltip(_ day: DayUsage, showsCost: Bool, locale: Locale, timeZone: TimeZone) -> String {
        let date = day.day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone))
        if showsCost, let cost = day.costUSD {
            return "\(date): " + cost.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(locale))
        }
        return "\(date): " + millionsText(day.totalTokens, locale: locale)
    }

    /// Tokens in millions with at most one decimal: "188.7M tokens",
    /// "0.1M tokens", "0M tokens".
    static func millionsText(_ tokens: Int, locale: Locale) -> String {
        let millions = Double(tokens) / 1_000_000
        return millions.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + "M tokens"
    }
}
