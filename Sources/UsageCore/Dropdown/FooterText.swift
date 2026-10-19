import Foundation

/// The texts of the dropdown footer's "Last refreshed" line (spec 025
/// FR-024, FR-025, research R6).
public enum FooterText {
    /// "Last refreshed 16:54" for a refresh on the day of `now` in
    /// `calendar`'s time zone, "Last refreshed Oct 21, 16:54" for an earlier
    /// day. Without a refresh time: "Refreshing…" before the first result or
    /// while it is preliminary, "No successful refresh yet" otherwise. A
    /// known refresh time wins over "Refreshing…".
    public static func lastRefreshed(at: Date?, hasSnapshot: Bool, isPreliminary: Bool, now: Date, calendar: Calendar, locale: Locale) -> String {
        guard let at else {
            return !hasSnapshot || isPreliminary ? "Refreshing\u{2026}" : "No successful refresh yet"
        }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(at, inSameDayAs: now) {
            return "Last refreshed \(at.formatted(style.hour().minute()))"
        }
        return "Last refreshed \(at.formatted(style.month(.abbreviated).day().hour().minute()))"
    }

    /// The tooltip and accessibility value of the "Last refreshed" line: the
    /// pace line text of spec 019 while a pace is slower than its base
    /// (spec 016 FR-016), nil otherwise (spec 025 FR-025).
    public static func paceTooltip(_ status: RefreshPaceStatus?, now: Date, calendar: Calendar) -> String? {
        status?.text(now: now, calendar: calendar)
    }
}

/// The first line of a subscription section's expanded Details (spec 025
/// FR-014, clarification): the week's total tokens.
public enum DetailsTotal {
    /// "This week: 45.1M tokens", in the compact token format of the
    /// dropdown.
    public static func weekly(tokens: Int, locale: Locale) -> String {
        let total = tokens.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
        return "This week: \(total) tokens"
    }
}
