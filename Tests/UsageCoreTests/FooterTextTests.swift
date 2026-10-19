import Foundation
import Testing
@testable import UsageCore

/// spec 025 FR-014, FR-024, FR-025, research R6: the "Last refreshed" line,
/// its pace tooltip and the week's token total in Details.
@Suite struct FooterTextTests {
    static let locale = Locale(identifier: "en_US")
    static let utc = calendar("UTC")
    /// Thu 22 Oct 2026, 17:10 UTC.
    static let now = isoDate("2026-10-22T17:10:00Z")

    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static func style(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    static func lastRefreshed(_ at: Date?, hasSnapshot: Bool = true, isPreliminary: Bool = false, calendar: Calendar = utc) -> String {
        FooterText.lastRefreshed(at: at, hasSnapshot: hasSnapshot, isPreliminary: isPreliminary, now: now, calendar: calendar, locale: locale)
    }

    @Test func todayShowsTheTime() {
        let at = isoDate("2026-10-22T16:54:00Z")
        #expect(Self.lastRefreshed(at) == "Last refreshed \(at.formatted(Self.style(Self.utc).hour().minute()))")
        #expect(Self.lastRefreshed(at).contains("4:54"))
        #expect(!Self.lastRefreshed(at).contains("Oct"))
    }

    @Test func earlierDayAddsTheDate() {
        let at = isoDate("2026-10-21T16:54:00Z")
        #expect(Self.lastRefreshed(at) == "Last refreshed \(at.formatted(Self.style(Self.utc).month(.abbreviated).day().hour().minute()))")
        #expect(Self.lastRefreshed(at).contains("Oct 21"))
    }

    /// "Today" is decided in the calendar's time zone: 23:30 UTC on the 21st
    /// is already the 22nd in Berlin.
    @Test func todayFollowsTheCalendarsTimeZone() {
        let at = isoDate("2026-10-21T23:30:00Z")
        let berlin = Self.calendar("Europe/Berlin")
        #expect(Self.lastRefreshed(at, calendar: berlin) == "Last refreshed \(at.formatted(Self.style(berlin).hour().minute()))")
        #expect(Self.lastRefreshed(at).contains("Oct 21"))
    }

    @Test func withoutARefreshTime() {
        #expect(Self.lastRefreshed(nil, hasSnapshot: false) == "Refreshing\u{2026}")
        #expect(Self.lastRefreshed(nil, hasSnapshot: true, isPreliminary: true) == "Refreshing\u{2026}")
        #expect(Self.lastRefreshed(nil, hasSnapshot: true, isPreliminary: false) == "No successful refresh yet")
    }

    /// A known last refresh time wins over "Refreshing…", also while the
    /// result is preliminary.
    @Test func aKnownRefreshTimeWins() {
        let at = isoDate("2026-10-22T16:54:00Z")
        #expect(Self.lastRefreshed(at, hasSnapshot: true, isPreliminary: true).hasPrefix("Last refreshed "))
    }

    @Test func paceTooltipIsThePaceLineText() {
        let status = RefreshPaceStatus(reason: .noAgentActivity, nextAt: isoDate("2026-10-22T17:30:00Z"), kind: .planLimits,
                                       plans: [.claude])
        #expect(FooterText.paceTooltip(status, now: Self.now, calendar: Self.utc) == status.text(now: Self.now, calendar: Self.utc))
        #expect(FooterText.paceTooltip(nil, now: Self.now, calendar: Self.utc) == nil)
    }

    @Test func weeklyTokenTotal() {
        #expect(DetailsTotal.weekly(tokens: 45_100_000, locale: Self.locale) == "This week: 45.1M tokens")
        #expect(DetailsTotal.weekly(tokens: 0, locale: Self.locale) == "This week: 0 tokens")
        #expect(DetailsTotal.weekly(tokens: 1_234, locale: Self.locale) == "This week: 1.2K tokens")
    }
}
