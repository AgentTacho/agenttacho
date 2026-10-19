import Foundation
import Testing
@testable import UsageCore

/// spec 025 FR-024, FR-025, research R6, spec 026 FR-011, FR-013: the
/// "Last refreshed" text, its pace and status tooltips, and the footer's
/// error lines.
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

    // MARK: Status tooltip (spec 026 FR-013)

    static let status = "Last refreshed Oct 18, 4:54 PM"
    static let pace = "Refreshing every 15 min: no agent activity"

    @Test func statusTooltipIsAbsentWithoutTruncationOrPace() {
        #expect(FooterText.statusTooltip(statusText: Self.status, isTruncated: false, paceText: nil) == nil)
    }

    @Test func truncatedStatusShowsItsFullText() {
        #expect(FooterText.statusTooltip(statusText: Self.status, isTruncated: true, paceText: nil) == Self.status)
    }

    @Test func slowedPaceShowsThePaceText() {
        #expect(FooterText.statusTooltip(statusText: Self.status, isTruncated: false, paceText: Self.pace) == Self.pace)
    }

    @Test func truncatedStatusAndPaceAreJoinedByALineBreak() {
        #expect(FooterText.statusTooltip(statusText: Self.status, isTruncated: true, paceText: Self.pace)
                == "\(Self.status)\n\(Self.pace)")
    }

    // MARK: Footer errors (spec 026 FR-011)

    static func errors(_ count: Int) -> [SourceError] {
        (0..<count).map { SourceError(sourceName: "Source \($0 + 1)", message: "failed \($0 + 1)", at: now) }
    }

    @Test func noErrorsShowNoLine() {
        #expect(FooterErrors.visible([]).isEmpty)
    }

    @Test func upToThreeErrorsShowOneLineEach() {
        let lines = FooterErrors.visible(Self.errors(3))
        #expect(lines == [
            FooterErrorLine(text: "Source 1: failed 1", tooltip: "Source 1: failed 1"),
            FooterErrorLine(text: "Source 2: failed 2", tooltip: "Source 2: failed 2"),
            FooterErrorLine(text: "Source 3: failed 3", tooltip: "Source 3: failed 3"),
        ])
    }

    @Test func fourErrorsShowTwoLinesAndTheRest() {
        let lines = FooterErrors.visible(Self.errors(4))
        #expect(lines.count == 3)
        #expect(lines.prefix(2).map(\.text) == ["Source 1: failed 1", "Source 2: failed 2"])
        #expect(lines[2].text == "+2 more")
        #expect(lines[2].tooltip == "Source 1: failed 1\nSource 2: failed 2\nSource 3: failed 3\nSource 4: failed 4")
    }

    @Test func fiveErrorsListAllInTheLastTooltip() {
        let lines = FooterErrors.visible(Self.errors(5))
        #expect(lines.count == 3)
        #expect(lines.prefix(2).map(\.text) == ["Source 1: failed 1", "Source 2: failed 2"])
        #expect(lines[2].text == "+3 more")
        #expect(lines[2].tooltip == (1...5).map { "Source \($0): failed \($0)" }.joined(separator: "\n"))
    }
}

/// spec 026 FR-010, FR-011: the sections' height above the pinned footer.
@Suite struct FooterLayoutTests {
    @Test func sectionsThatFitKeepTheirHeight() {
        #expect(FooterLayout.sectionsHeight(content: 300, footer: 60, cap: 640) == 300)
    }

    @Test func tallSectionsGetWhatTheCapLeavesAboveTheFooter() {
        #expect(FooterLayout.sectionsHeight(content: 900, footer: 60, cap: 640) == 580)
    }

    @Test func aTallFooterLeavesTheSectionsTheirMinimum() {
        #expect(FooterLayout.sectionsHeight(content: 900, footer: 600, cap: 640) == 160)
        #expect(FooterLayout.sectionsHeight(content: 100, footer: 600, cap: 640) == 100)
    }
}

/// spec 026 FR-010a: the height cap follows the room left on the panel's
/// screen, so the pinned footer never sits below the visible frame.
@Suite struct ScreenAwareCapTests {
    @Test func plentyOfRoomKeepsTheFixedCap() {
        #expect(FooterLayout.room(available: 1200, margin: 8) == 1192)
        #expect(FooterLayout.cap(available: 1200, maxCap: 640, margin: 8) == 640)
        #expect(FooterLayout.cap(available: 648, maxCap: 640, margin: 8) == 640)
    }

    @Test func aShortScreenCapsAtTheRoomMinusTheMargin() {
        #expect(FooterLayout.cap(available: 500, maxCap: 640, margin: 8) == 492)
        #expect(FooterLayout.sectionsHeight(content: 900, footer: 60,
                                            cap: FooterLayout.cap(available: 500),
                                            room: FooterLayout.room(available: 500)) == 432)
    }

    @Test func anUnknownScreenUsesTheFixedCap() {
        #expect(FooterLayout.room(available: nil) == .infinity)
        #expect(FooterLayout.cap(available: nil) == 640)
    }

    @Test func roomNeverGoesNegative() {
        #expect(FooterLayout.room(available: 4, margin: 8) == 0)
        #expect(FooterLayout.cap(available: 4) == 0)
    }

    @Test func lessRoomThanFooterPlusFloorGivesTheSectionsWhatRemains() {
        let available = 208.0  // room 200, footer 60: the 160 pt floor yields
        let cap = FooterLayout.cap(available: available)
        let room = FooterLayout.room(available: available)
        #expect(FooterLayout.sectionsHeight(content: 900, footer: 60, cap: cap, room: room) == 140)
        #expect(FooterLayout.sectionsHeight(content: 100, footer: 60, cap: cap, room: room) == 100)
    }

    @Test func sectionsNeverGoNegativeWhenTheFooterFillsTheRoom() {
        let cap = FooterLayout.cap(available: 50)
        let room = FooterLayout.room(available: 50)
        #expect(FooterLayout.sectionsHeight(content: 900, footer: 60, cap: cap, room: room) == 0)
    }

    @Test func plentyOfRoomKeepsTheFloorForATallFooter() {
        let cap = FooterLayout.cap(available: 1200)
        let room = FooterLayout.room(available: 1200)
        #expect(FooterLayout.sectionsHeight(content: 900, footer: 600, cap: cap, room: room) == 160)
    }

    @Test func thePanelNeverExceedsTheCapOrTheRoom() {
        for available in stride(from: 0.0, through: 1400, by: 37) {
            let cap = FooterLayout.cap(available: available)
            let room = FooterLayout.room(available: available)
            for footer in stride(from: 20.0, through: 200, by: 30) {
                for content in stride(from: 0.0, through: 1500, by: 75) {
                    let sections = FooterLayout.sectionsHeight(content: content, footer: footer, cap: cap, room: room)
                    #expect(sections >= 0)
                    #expect(sections <= content)
                    if footer <= room {
                        #expect(sections + footer <= room)
                    }
                    if footer + 160 <= cap {
                        #expect(sections + footer <= cap)
                    }
                }
            }
        }
    }
}
