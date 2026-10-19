import Foundation

/// The compact number formats of the dropdown's narrow day columns and
/// their Σ column (spec 026 FR-009, research R2), moved from the app's
/// `UsageFormat` with unchanged outputs (spec 003 FR-013).
public enum CompactFormat {
    /// Tokens in whole millions without a suffix: "838", "1,000"; "<1" for
    /// counts that would round to 0, "0" for none.
    public static func millions(_ tokens: Int, locale: Locale) -> String {
        guard tokens > 0 else { return "0" }
        let millions = Double(tokens) / 1_000_000
        if millions < 0.5 { return "<1" }
        return Int(millions.rounded()).formatted(.number.locale(locale))
    }

    /// Whole US dollars without a currency suffix: "0", "409", "1.6K"; "<1"
    /// for amounts that would round to 0. The cut-offs use the whole-dollar
    /// value the format shows (rounding half to even, the format's default),
    /// so 0.50 reads "<1" rather than "0" and 999.50 reads "1K" rather than
    /// "1,000" (spec 026 FR-009).
    public static func usd(_ value: Decimal, locale: Locale) -> String {
        var amount = value
        var whole = Decimal()
        NSDecimalRound(&whole, &amount, 0, .bankers)
        if value > 0 && whole == 0 {
            return "<1"
        }
        if whole < 1000 {
            return whole.formatted(.number.precision(.fractionLength(0)).locale(locale))
        }
        return max(value, whole).formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
    }
}
