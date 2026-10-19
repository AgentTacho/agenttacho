import Foundation
import Testing
@testable import UsageCore

/// spec 025 FR-015, FR-029, research R5: every section note keeps today's
/// text and gets its style (neutral, warning, alert) from core logic.
@Suite struct SectionNoteTests {
    static let locale = Locale(identifier: "en_US")
    static let utc = TimeZone(identifier: "UTC")!
    static let dates = NoteDates(locale: locale, timeZone: utc)
    static let lastGood = isoDate("2026-10-21T09:30:00Z")
    static let observed = isoDate("2026-10-22T13:40:00Z")
    static let retry = isoDate("2026-10-22T15:05:00Z")
    static let directory = "~/.claude-work"

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, calendar: calendar, timeZone: utc))
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: utc))
    }

    static func claude(_ state: SubscriptionState?, isPreliminary: Bool = false, nextRetryAt: Date? = nil,
                       endpointBlockedUntil: Date? = nil) -> [SectionNote] {
        SectionNote.claude(state: state, credentialDirectory: directory, isPreliminary: isPreliminary,
                           nextRetryAt: nextRetryAt, endpointBlockedUntil: endpointBlockedUntil, dates: dates)
    }

    static func codex(_ state: CodexLimitsState, observed: Date? = observed, signInRejected: Bool = false) -> SectionNote? {
        let observation = observed.map { CodexLimitObservation(planType: "plus", observedAt: $0, origin: .live, windows: []) }
        return SectionNote.codex(CodexLimitsEntry(observation: observation, state: state, signInRejected: signInRejected), dates: dates)
    }

    @Test func noteDatesFollowTheLocaleAndTimeZone() {
        #expect(Self.dates.dateTime(Self.lastGood) == Self.dateTime(Self.lastGood))
        #expect(Self.dates.dateTime(Self.lastGood).contains("Oct 21"))
        #expect(Self.dates.time(Self.retry) == Self.time(Self.retry))
        #expect(Self.dates.time(Self.retry).contains("3:05"))
    }

    // MARK: - Claude

    @Test func claudeOkHasNoNote() {
        #expect(Self.claude(.ok).isEmpty)
    }

    @Test func claudeStaleWithLastGoodValueAndRetry() {
        let notes = Self.claude(.stale(lastGoodAt: Self.lastGood, error: "usage endpoint returned HTTP 500"), nextRetryAt: Self.retry,
                                endpointBlockedUntil: Self.observed)
        #expect(notes == [
            SectionNote(text: "Stale, last good value \(Self.dateTime(Self.lastGood))", style: .warning),
            SectionNote(text: "usage endpoint returned HTTP 500", style: .warning),
            SectionNote(text: "Retrying at \(Self.time(Self.retry))", style: .warning),
        ])
    }

    @Test func claudeStaleWithoutLastGoodValueRateLimited() {
        let notes = Self.claude(.stale(lastGoodAt: nil, error: "rate limited"), endpointBlockedUntil: Self.retry)
        #expect(notes == [
            SectionNote(text: "No data yet", style: .warning),
            SectionNote(text: "rate limited", style: .warning),
            SectionNote(text: "Rate limited until \(Self.time(Self.retry))", style: .warning),
        ])
        #expect(Self.claude(.stale(lastGoodAt: nil, error: "x")).count == 2)
    }

    @Test func claudeNotSignedIn() {
        #expect(Self.claude(.notSignedIn) == [
            SectionNote(text: "Not signed in (no Claude Code credentials for ~/.claude-work)", style: .neutral)
        ])
    }

    @Test func claudeCredentialsExpired() {
        #expect(Self.claude(.credentialsExpired) == [
            SectionNote(text: "Credentials expired, run Claude Code to refresh them", style: .warning)
        ])
    }

    @Test func claudeRetryingIsNeutral() {
        #expect(Self.claude(.retrying(lastGoodAt: Self.lastGood, error: "offline", retryAt: Self.retry)) == [
            SectionNote(text: "\(GraceNote.unreachable), retrying at \(Self.time(Self.retry))", style: .neutral)
        ])
        #expect(Self.claude(.retrying(lastGoodAt: nil, error: "usage endpoint returned HTTP 503", retryAt: Self.retry)) == [
            SectionNote(text: "usage endpoint returned HTTP 503, retrying at \(Self.time(Self.retry))", style: .neutral)
        ])
    }

    @Test func claudeSignInRejectedIsAnAlert() {
        let text = SignInRejectedNote.text(credentialDirectory: Self.directory)
        #expect(Self.claude(.signInRejected(lastGoodAt: Self.lastGood)) == [
            SectionNote(text: text, style: .alert),
            SectionNote(text: "Last good value \(Self.dateTime(Self.lastGood))", style: .alert),
        ])
        #expect(Self.claude(.signInRejected(lastGoodAt: nil)) == [SectionNote(text: text, style: .alert)])
    }

    @Test func claudeWithoutState() {
        #expect(Self.claude(nil, isPreliminary: true) == [SectionNote(text: "Refreshing\u{2026}", style: .neutral)])
        #expect(Self.claude(nil, isPreliminary: false) == [SectionNote(text: "No data", style: .neutral)])
        #expect(SectionNote.noData(isPreliminary: true) == SectionNote(text: "Refreshing\u{2026}", style: .neutral))
        #expect(SectionNote.noData(isPreliminary: false) == SectionNote(text: "No data", style: .neutral))
    }

    // MARK: - Codex

    @Test func codexLiveHasNoNote() {
        #expect(Self.codex(.live) == nil)
    }

    @Test func codexNewerSnapshotAndLocalDataAreNeutral() {
        #expect(Self.codex(.newerSnapshot) == SectionNote(text: "As of \(Self.dateTime(Self.observed))", style: .neutral))
        #expect(Self.codex(.localOnly) == SectionNote(text: "Local data, as of \(Self.dateTime(Self.observed))", style: .neutral))
    }

    @Test func codexStaleIsAWarningOrAnAlertWhenRejected() {
        #expect(Self.codex(.stale(reason: "offline")) == SectionNote(text: "Stale, as of \(Self.dateTime(Self.observed)): offline", style: .warning))
        #expect(Self.codex(.stale(reason: "sign-in rejected"), signInRejected: true)
                == SectionNote(text: "Stale, as of \(Self.dateTime(Self.observed)): sign-in rejected", style: .alert))
        #expect(Self.codex(.stale(reason: "offline"), observed: nil) == SectionNote(text: "Stale, as of ?: offline", style: .warning))
    }

    @Test func codexUnavailableIsNeutralOrAnAlertWhenRejected() {
        #expect(Self.codex(.unavailable(reason: "No Codex sign-in"), observed: nil) == SectionNote(text: "No Codex sign-in", style: .neutral))
        #expect(Self.codex(.unavailable(reason: "Sign-in rejected"), observed: nil, signInRejected: true)
                == SectionNote(text: "Sign-in rejected", style: .alert))
    }

    @Test func codexRetryingIsNeutral() {
        #expect(Self.codex(.retrying(reason: "offline", retryAt: Self.retry))
                == SectionNote(text: "\(GraceNote.unreachable), retrying at \(Self.time(Self.retry))", style: .neutral))
        #expect(Self.codex(.retrying(reason: "HTTP 502", retryAt: Self.retry))
                == SectionNote(text: "HTTP 502, retrying at \(Self.time(Self.retry))", style: .neutral))
    }

    // MARK: - Budgets and markers

    @Test func budgetIncompletePricesIsAWarning() {
        #expect(SectionNote.budgetIncomplete(unpricedModels: ["a", "b"]) == SectionNote(text: "incomplete, unpriced: a, b", style: .warning))
    }

    @Test func budgetStaleSince() {
        #expect(SectionNote.budgetStale(since: Self.lastGood, dates: Self.dates)
                == SectionNote(text: "stale since \(Self.dateTime(Self.lastGood))", style: .warning))
        #expect(SectionNote.budgetStale(since: nil, dates: Self.dates) == SectionNote(text: "stale since launch", style: .warning))
    }

    @Test func emptyGroupAndStaleMarker() {
        #expect(SectionNote.emptyGroup == SectionNote(text: "No accounts in this group yet", style: .neutral))
        #expect(SectionNote.staleMarker == SectionNote(text: "stale", style: .warning))
    }
}
