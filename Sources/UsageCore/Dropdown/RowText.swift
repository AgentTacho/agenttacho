import Foundation

/// The texts of a window row or a budget's amount line besides its bar
/// (spec 025 FR-006, FR-008, FR-019): the reset text with its tooltip and
/// the row's one accessibility label. Both come from the same choice of
/// reset text, so what the row shows and what VoiceOver reads cannot
/// disagree; the view only renders them (constitution II).
public struct RowText: Equatable, Sendable {
    /// "resets in 2h 26m" or "resets 17:20" in the section's time format,
    /// "not started" for a window without a reset time, nil for a window
    /// that reset since the observation (spec 010 FR-016) or is unavailable.
    public let reset: String?
    /// The other time form of `reset` (FR-019); nil without a reset time.
    public let resetTooltip: String?
    /// The window or budget, the percent (for a budget the amount and
    /// budget), the reset text and the pace summary, also when no note
    /// shows (FR-006).
    public let accessibilityLabel: String

    init(reset: String?, resetTooltip: String?, accessibilityLabel: String) {
        self.reset = reset
        self.resetTooltip = resetTooltip
        self.accessibilityLabel = accessibilityLabel
    }

    /// A limit window row. `percent` is the rounded percent, nil for an
    /// unavailable window. `resetsAt` is the reset time at the snapshot time;
    /// `observedWithReset` tells a window that reset since the observation
    /// (no reset text) from one observed without a reset time ("not
    /// started", FR-008). A reached Codex limit adds "Limit reached" (FR-007).
    /// The account's headline row ends with "shown in menu bar" (spec 027
    /// FR-003).
    public static func window(name: String, percent: Int?, resetsAt: Date?, observedWithReset: Bool, limitReached: Bool,
                              bar: RowBar?, times: TimeText, isHeadline: Bool = false) -> RowText {
        let headline = isHeadline ? ", shown in menu bar" : ""
        guard let percent else {
            return RowText(reset: nil, resetTooltip: nil, accessibilityLabel: "\(name), unavailable" + headline)
        }
        let reset = resetsAt.map(times.reset) ?? (observedWithReset ? nil : "not started")
        var parts = [name, PercentFormatter.text(percent)]
        if let reset { parts.append(reset) }
        if let summary = bar?.accessibilitySummary(times: times) { parts.append(summary) }
        if limitReached { parts.append("Limit reached") }
        return RowText(reset: reset, resetTooltip: resetsAt.map(times.resetTooltip),
                       accessibilityLabel: parts.joined(separator: ", ") + headline)
    }

    /// A budget's amount line (FR-006, FR-009): the budget's name, `amount`
    /// ("1,596 of 300 US$/month"), the reset text and the pace summary.
    public static func budget(name: String, amount: String, resetsAt: Date, bar: RowBar, times: TimeText) -> RowText {
        let reset = times.reset(resetsAt)
        let parts = [name, amount, reset] + [bar.accessibilitySummary(times: times)].compactMap { $0 }
        return RowText(reset: reset, resetTooltip: times.resetTooltip(resetsAt), accessibilityLabel: parts.joined(separator: ", "))
    }
}
