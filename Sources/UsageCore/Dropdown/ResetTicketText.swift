import Foundation

/// The texts of an account's gift glyphs in the dropdown: each glyph's
/// tooltip, the "+N" marker's tooltip and the VoiceOver label of the group
/// (spec 033 FR-010, FR-010a, FR-011, contracts/texts.md). Times use the
/// relative and absolute forms of the window reset texts (spec 025).
public enum ResetTicketText {
    /// The last line of every tooltip (spec 033 FR-010a).
    public static let clickLine = "Click to open the usage page"
    /// The VoiceOver action that opens the usage page (spec 033 FR-011).
    public static let openActionName = "Open usage page"

    /// "Free limit reset, expires in 2d 3h (Thu 14:00)" or "Free limit
    /// reset, no expiry", then the click line.
    public static func glyphTooltip(_ ticket: ResetTicket, times: TimeText) -> String {
        line(ticket, times: times) + "\n" + clickLine
    }

    /// One glyph line per ticket behind the "+N" marker, in the given
    /// order, then the click line.
    public static func overflowTooltip(_ tickets: [ResetTicket], times: TimeText) -> String {
        (tickets.map { line($0, times: times) } + [clickLine]).joined(separator: "\n")
    }

    /// The glyphs and the marker read as one element: "2 free limit
    /// resets, the next expires in 2d", "1 free limit reset, no expiry".
    /// Expired tickets are left out (spec 033 FR-011, FR-012).
    public static func accessibilityLabel(_ tickets: [ResetTicket], times: TimeText) -> String {
        let usable = tickets.usable(at: times.now).sortedForDisplay
        let count = usable.count == 1 ? "1 free limit reset" : "\(usable.count) free limit resets"
        guard let next = usable.first?.expiresAt else { return "\(count), no expiry" }
        let relative = TimeText.relative(from: times.now, to: next)
        return usable.count == 1 ? "\(count), expires \(relative)" : "\(count), the next expires \(relative)"
    }

    private static func line(_ ticket: ResetTicket, times: TimeText) -> String {
        guard let expiresAt = ticket.expiresAt else { return "Free limit reset, no expiry" }
        return "Free limit reset, expires \(times.expiry(expiresAt))"
    }
}
