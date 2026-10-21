import Foundation
import Testing
@testable import UsageCore

/// spec 033 FR-015, FR-019, contracts/texts.md "Notifications" and
/// "Diagnostic log": the texts of an expiry notification, with a time
/// format pinned to `en_US_POSIX` and UTC.
@Suite struct ResetTicketExpiryTests {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    static let locale = Locale(identifier: "en_US_POSIX")
    /// Wed 21 Oct 2026, 08:00 UTC.
    static let now = isoDate("2026-10-21T08:00:00Z")
    static let times = TimeText(format: .absolute, now: now, calendar: utc, locale: locale)

    static func alert(_ step: ResetTicketExpiryStep, count: Int, expiresAt: Date, name: String = "Claude Max · Work") -> ResetTicketExpiryAlert {
        ResetTicketExpiryAlert(accountId: "acc-max", accountName: name, step: step, expiresAt: expiresAt, count: count)
    }

    static func style() -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: utc, timeZone: utc.timeZone)
    }

    @Test func titlesForOneAndSeveralTickets() {
        let at = Self.now.addingTimeInterval(3600)
        #expect(Self.alert(.threeDays, count: 1, expiresAt: at).title == "Claude Max · Work: free limit reset expires within 3 days")
        #expect(Self.alert(.threeDays, count: 2, expiresAt: at).title == "Claude Max · Work: free limit resets expire within 3 days")
        #expect(Self.alert(.oneDay, count: 1, expiresAt: at).title == "Claude Max · Work: free limit reset expires within 24 hours")
        #expect(Self.alert(.oneDay, count: 3, expiresAt: at).title == "Claude Max · Work: free limit resets expire within 24 hours")
    }

    @Test func bodiesUseTheAbsoluteForm() {
        let today = isoDate("2026-10-21T09:30:00Z")
        #expect(Self.alert(.oneDay, count: 1, expiresAt: today).body(times: Self.times)
            == "1 free limit reset expires \(today.formatted(Self.style().hour().minute())).")
        let withinAWeek = isoDate("2026-10-23T14:00:00Z")
        #expect(Self.alert(.threeDays, count: 2, expiresAt: withinAWeek).body(times: Self.times)
            == "2 free limit resets expire \(withinAWeek.formatted(Self.style().weekday(.abbreviated).hour().minute())).")
        let later = isoDate("2026-11-04T10:00:00Z")
        #expect(Self.alert(.threeDays, count: 1, expiresAt: later).body(times: Self.times)
            == "1 free limit reset expires \(later.formatted(Self.style().weekday(.abbreviated).day().month(.abbreviated).hour().minute())).")
    }

    @Test func identifierNamesAccountExpiryAndStep() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Self.alert(.threeDays, count: 1, expiresAt: at).identifier == "free-reset-acc-max-1800000000-3d")
        #expect(Self.alert(.oneDay, count: 2, expiresAt: at).identifier == "free-reset-acc-max-1800000000-24h")
        #expect(ResetTicketExpiryAlert.identifierPrefix == "free-reset-")
    }

    @Test func logMessages() {
        let at = isoDate("2026-10-23T14:00:00Z")
        let alert = Self.alert(.threeDays, count: 2, expiresAt: at)
        #expect(alert.logMessage(suppressed: false) == "free reset expiry 3d for acc-max, expires 2026-10-23T14:00:00Z")
        #expect(alert.logMessage(suppressed: true) == "free reset expiry 3d for acc-max not sent (switch off), expires 2026-10-23T14:00:00Z")
        #expect(Self.alert(.oneDay, count: 1, expiresAt: at).logMessage(suppressed: false)
            == "free reset expiry 24h for acc-max, expires 2026-10-23T14:00:00Z")
    }

    /// FR-015, FR-019: the texts hold the display name, the count and the
    /// time, and nothing else; the log names the account id only.
    @Test func textsHoldNoOtherData() {
        let at = isoDate("2026-10-23T14:00:00Z")
        let alert = Self.alert(.threeDays, count: 2, expiresAt: at, name: "Work")
        let texts = [alert.title, alert.body(times: Self.times), alert.identifier, alert.logMessage(suppressed: false),
                     alert.logMessage(suppressed: true)]
        for text in texts {
            #expect(!text.contains("Bearer"))
            #expect(!text.contains("token"))
            #expect(!text.contains("grant"))
            #expect(!text.contains("credit"))
        }
        #expect(!alert.logMessage(suppressed: false).contains("Work"))
    }
}
