import Foundation
import Testing
@testable import UsageCore

/// spec 016 FR-016, contracts/refresh-pace.md rows L1 to L6: the pace line
/// of the dropdown, its reason ranking, time choice and wording.
@Suite struct RefreshPaceStatusTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let locale = Locale(identifier: "en_GB")

    /// 2026-10-16 (a Friday) at `hour:minute` UTC.
    func at(_ hour: Int, _ minute: Int, day: Int = 16) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// Claude and Codex both called at 14:00 (launch). Then scheduled ticks
    /// every 5 minutes to 14:15: Claude sees no activity, Codex sees
    /// activity at every tick. Afterwards Claude is due at 14:35 (interval
    /// 20) and Codex at 14:20 (base).
    private func stretchedClaude() -> AdaptivePace {
        var pace = AdaptivePace(base: 300, inUse: [.claude, .codex])
        pace.recordCall(.claude, at: at(14, 0), scheduled: false, newestActivity: nil)
        pace.recordCall(.codex, at: at(14, 0), scheduled: false, newestActivity: nil)
        pace.refreshCompleted(at: at(14, 0), scheduled: false)
        for minute in [5, 10, 15] {
            let now = at(14, minute)
            if pace.shouldCall(.claude, newestActivity: nil, now: now) {
                pace.recordCall(.claude, at: now, scheduled: true, newestActivity: nil)
            }
            let activity = at(14, minute - 1)
            if pace.shouldCall(.codex, newestActivity: activity, now: now) {
                pace.recordCall(.codex, at: now, scheduled: true, newestActivity: activity)
            }
            pace.refreshCompleted(at: now, scheduled: true)
        }
        return pace
    }

    @Test func l1NoLineWhileEveryPaceIsAtTheBase() {
        var pace = AdaptivePace(base: 300, inUse: [.claude])
        pace.recordCall(.claude, at: at(14, 0), scheduled: false, newestActivity: nil)
        pace.refreshCompleted(at: at(14, 0), scheduled: false)
        #expect(pace.status(now: at(14, 1)) == nil)
        #expect(AdaptivePace(base: 300).status(now: at(14, 1)) == nil)
    }

    /// L2: "no agent activity" names the earliest next call of the stretched
    /// endpoints only (Codex at the base is not stretched).
    @Test func l2NoAgentActivity() {
        let pace = stretchedClaude()
        #expect(pace.interval(.claude) == 1200)
        #expect(pace.interval(.codex) == 300)
        let status = pace.status(now: at(14, 16))
        #expect(status == RefreshPaceStatus(reason: .noAgentActivity, nextAt: at(14, 35), kind: .planLimits))
        #expect(status?.text(now: at(14, 16), calendar: calendar, locale: locale)
                == "Plan limits next checked at 14:35 (no agent activity)")
    }

    /// L3: a timer reason wins and names the earliest next call of any
    /// endpoint in use.
    @Test func l3TimerReasonWinsAndUsesAnyEndpoint() {
        var pace = stretchedClaude()
        _ = pace.update(conditions: SystemConditions(lowPowerMode: true))
        let status = pace.status(now: at(14, 16))
        #expect(status == RefreshPaceStatus(reason: .lowPowerMode, nextAt: at(14, 25), kind: .planLimits))

        var base = AdaptivePace(base: 300, inUse: [.claude])
        base.recordCall(.claude, at: at(14, 10), scheduled: false, newestActivity: nil)
        base.refreshCompleted(at: at(14, 10), scheduled: false)
        _ = base.update(conditions: SystemConditions(lowPowerMode: true))
        #expect(base.status(now: at(14, 11))?.text(now: at(14, 11), calendar: calendar, locale: locale)
                == "Plan limits next checked at 14:20 (Low Power Mode)")
    }

    /// L4: without an endpoint in use the line names the next refresh.
    @Test func l4NoEndpointInUse() {
        var pace = AdaptivePace(base: 300)
        pace.refreshCompleted(at: at(14, 10), scheduled: true)
        _ = pace.update(conditions: SystemConditions(lowPowerMode: true))
        let status = pace.status(now: at(14, 11))
        #expect(status == RefreshPaceStatus(reason: .lowPowerMode, nextAt: at(14, 20), kind: .refresh))
        #expect(status?.text(now: at(14, 11), calendar: calendar, locale: locale) == "Next refresh at 14:20 (Low Power Mode)")
    }

    /// L5: a time on another day carries the abbreviated weekday.
    @Test func l5AnotherDayShowsTheWeekday() {
        let status = RefreshPaceStatus(reason: .idle, nextAt: at(9, 5), kind: .planLimits)
        #expect(status.text(now: at(23, 50, day: 15), calendar: calendar, locale: locale)
                == "Plan limits next checked at Fri 09:05 (away)")
        #expect(status.text(now: at(8, 0), calendar: calendar, locale: locale) == "Plan limits next checked at 09:05 (away)")
    }

    /// L6: a past due time (calls failing by transport) never shows; the
    /// line shows the next scheduled refresh instead.
    @Test func l6NeverAPastTime() {
        var pace = stretchedClaude()
        // Claude was due at 14:35; the scheduled calls at 14:35 and 14:40
        // fail by transport, so its last call stays at 14:15.
        pace.refreshCompleted(at: at(14, 35), scheduled: true)
        pace.refreshCompleted(at: at(14, 40), scheduled: true)
        let now = at(14, 41)
        let status = pace.status(now: now)
        #expect(status?.nextAt == at(14, 45))
        #expect(status.map { $0.nextAt >= now } == true)
    }

    @Test func reasonRanking() {
        #expect(PaceReason.idle < .lowPowerMode)
        #expect(PaceReason.lowPowerMode < .highTemperature)
        #expect(PaceReason.highTemperature < .noAgentActivity)
        var pace = AdaptivePace(base: 300)
        pace.refreshCompleted(at: at(14, 0), scheduled: true)
        _ = pace.update(conditions: SystemConditions(idle: true, lowPowerMode: true, thermalPressure: true))
        #expect(pace.status(now: at(14, 1))?.reason == .idle)
        _ = pace.update(conditions: SystemConditions(lowPowerMode: true, thermalPressure: true))
        #expect(pace.status(now: at(14, 1))?.reason == .lowPowerMode)
        _ = pace.update(conditions: SystemConditions(thermalPressure: true))
        #expect(pace.status(now: at(14, 1))?.reason == .highTemperature)
        let text = pace.status(now: at(14, 1))?.text(now: at(14, 1), calendar: calendar, locale: locale)
        #expect(text == "Next refresh at 14:10 (high temperature)")
    }

    @Test func disabledHasNoLine() {
        var pace = AdaptivePace(enabled: false, base: 300)
        _ = pace.update(conditions: SystemConditions(idle: true))
        #expect(pace.status(now: at(14, 0)) == nil)
    }
}
