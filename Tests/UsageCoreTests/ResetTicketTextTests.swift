import Foundation
import Testing
@testable import UsageCore

/// spec 033 FR-010, FR-010a, FR-011, contracts/texts.md "Dropdown": the
/// tooltips and the VoiceOver label of the gift glyphs.
@Suite struct ResetTicketTextTests {
    typealias T = TimeTextTests
    static let times = T.times(.relative)
    static let soon = T.now.addingTimeInterval(2 * T.day + 3 * T.hour)
    static let later = T.now.addingTimeInterval(9 * T.day)

    @Test func glyphTooltipWithExpiry() {
        #expect(ResetTicketText.glyphTooltip(ResetTicket(expiresAt: Self.soon), times: Self.times)
            == "Free limit reset, expires in 2d 3h (\(T.weekdayTime(Self.soon)))\nClick to open the usage page")
    }

    @Test func glyphTooltipWithoutExpiry() {
        #expect(ResetTicketText.glyphTooltip(ResetTicket(expiresAt: nil), times: Self.times)
            == "Free limit reset, no expiry\nClick to open the usage page")
    }

    @Test func glyphTooltipIsTheSameInBothFormats() {
        let ticket = ResetTicket(expiresAt: Self.soon)
        #expect(ResetTicketText.glyphTooltip(ticket, times: T.times(.absolute)) == ResetTicketText.glyphTooltip(ticket, times: Self.times))
    }

    @Test func overflowTooltipListsTheHiddenTicketsInOrder() {
        let text = ResetTicketText.overflowTooltip([ResetTicket(expiresAt: Self.later), ResetTicket(expiresAt: nil)], times: Self.times)
        #expect(text == """
        Free limit reset, expires in 9d (\(T.long(Self.later)))
        Free limit reset, no expiry
        Click to open the usage page
        """)
    }

    @Test func accessibilityLabels() {
        let one = [ResetTicket(expiresAt: Self.soon)]
        #expect(ResetTicketText.accessibilityLabel(one, times: Self.times) == "1 free limit reset, expires in 2d 3h")
        let several = [ResetTicket(expiresAt: nil), ResetTicket(expiresAt: Self.later), ResetTicket(expiresAt: Self.soon)]
        #expect(ResetTicketText.accessibilityLabel(several, times: Self.times) == "3 free limit resets, the next expires in 2d 3h")
        #expect(ResetTicketText.accessibilityLabel([ResetTicket(expiresAt: nil)], times: Self.times) == "1 free limit reset, no expiry")
        #expect(ResetTicketText.accessibilityLabel([ResetTicket(expiresAt: nil), ResetTicket(expiresAt: nil)], times: Self.times)
            == "2 free limit resets, no expiry")
    }

    @Test func accessibilityLabelLeavesExpiredTicketsOut() {
        let tickets = [ResetTicket(expiresAt: T.now.addingTimeInterval(-60)), ResetTicket(expiresAt: nil)]
        #expect(ResetTicketText.accessibilityLabel(tickets, times: Self.times) == "1 free limit reset, no expiry")
    }

    @Test func accessibilityAction() {
        #expect(ResetTicketText.openActionName == "Open usage page")
    }
}
