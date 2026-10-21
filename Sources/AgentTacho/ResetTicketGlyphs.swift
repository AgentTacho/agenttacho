import AppKit
import SwiftUI
import UsageCore

/// The free limit resets of an account in its dropdown header: one dimmed
/// gift glyph per usable ticket, at most three, soonest expiry first, then
/// a "+N" marker for the rest, all in the secondary text color (spec 033
/// FR-008, FR-009). Each element has its own tooltip; a click on any of
/// them opens the provider's usage page and closes the dropdown (FR-010,
/// FR-010a). VoiceOver reads the group as one element with an action that
/// opens the page (FR-011). Tickets expire at `times.now`, the reference
/// time the dropdown updates while it is open (FR-012). Nothing is drawn
/// without a usable ticket. The texts come from `ResetTicketText`.
struct ResetTicketGlyphs: View {
    /// The current panel's text colors (spec 032 FR-007).
    @Environment(\.dropdownColors) private var colors
    let tickets: [ResetTicket]
    /// The section's times; tooltips use the relative and absolute forms of
    /// the reset texts (spec 025).
    let times: TimeText
    let usagePage: URL
    /// Closes the dropdown after the page was opened.
    let onOpen: () -> Void

    /// The glyphs and the marker sit a little smaller than the account icon,
    /// so they read as a hint next to the name (spec 033 FR-009).
    private static let size = NSFont.smallSystemFontSize

    var body: some View {
        let glyphs = tickets.glyphs(at: times.now)
        if !glyphs.shown.isEmpty {
            HStack(spacing: 3) {
                // Each glyph is its own button, so each keeps its own tooltip.
                ForEach(Array(glyphs.shown.enumerated()), id: \.offset) { _, ticket in
                    Button(action: open) {
                        labelText("solid:gift", size: Self.size)
                    }
                    .help(ResetTicketText.glyphTooltip(ticket, times: times))
                }
                if !glyphs.overflow.isEmpty {
                    Button(action: open) {
                        Text("+\(glyphs.overflow.count)").font(.system(size: Self.size)).monospacedDigit()
                    }
                    .help(ResetTicketText.overflowTooltip(glyphs.overflow, times: times))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.secondary)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ResetTicketText.accessibilityLabel(tickets, times: times))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            .accessibilityAction(named: ResetTicketText.openActionName) { open() }
        }
    }

    /// Opens the usage page in the default browser, then closes the
    /// dropdown; the browser uses the user's own session (spec 033 FR-010a).
    private func open() {
        NSWorkspace.shared.open(usagePage)
        onOpen()
    }
}
