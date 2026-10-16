import Foundation
import Testing
@testable import UsageCore

/// spec 016 FR-016, contracts/refresh-pace.md rows L1 to L6: the pace line
/// of the dropdown, its reason ranking, time choice and wording. spec 019
/// FR-001 to FR-006: the line names the slowed plan or plans and the agent.
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

    /// `stretchedClaude()` for either endpoint: both called at 14:00
    /// (launch), then scheduled ticks every 5 minutes to 14:15 in which
    /// `quiet` sees no activity and the other endpoint sees activity at
    /// every tick. Afterwards `quiet` is due at 14:35 (interval 20) and the
    /// other at 14:20 (base).
    private func stretched(_ quiet: PacedEndpoint) -> AdaptivePace {
        var pace = AdaptivePace(base: 300, inUse: [.claude, .codex])
        pace.recordCall(.claude, at: at(14, 0), scheduled: false, newestActivity: nil)
        pace.recordCall(.codex, at: at(14, 0), scheduled: false, newestActivity: nil)
        pace.refreshCompleted(at: at(14, 0), scheduled: false)
        for minute in [5, 10, 15] {
            let now = at(14, minute)
            for endpoint in PacedEndpoint.allCases {
                let activity = endpoint == quiet ? nil : at(14, minute - 1)
                if pace.shouldCall(endpoint, newestActivity: activity, now: now) {
                    pace.recordCall(endpoint, at: now, scheduled: true, newestActivity: activity)
                }
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
    /// endpoints only (Codex at the base is not stretched), and only the
    /// Claude plan with its agent (spec 019 FR-001).
    @Test func l2NoAgentActivity() {
        let pace = stretchedClaude()
        #expect(pace.interval(.claude) == 1200)
        #expect(pace.interval(.codex) == 300)
        let status = pace.status(now: at(14, 16))
        #expect(status == RefreshPaceStatus(reason: .noAgentActivity, nextAt: at(14, 35), kind: .planLimits, plans: [.claude]))
        #expect(status?.text(now: at(14, 16), calendar: calendar, locale: locale)
                == "Claude limits next checked at 14:35 (no Claude Code activity)")
    }

    /// spec 019 FR-001: only Codex slowed names Codex and its agent.
    @Test func onlyCodexSlowedNamesCodex() {
        let pace = stretched(.codex)
        #expect(pace.interval(.codex) == 1200)
        #expect(pace.interval(.claude) == 300)
        let status = pace.status(now: at(14, 16))
        #expect(status?.plans == [.codex])
        #expect(status?.nextAt == at(14, 35))
        #expect(status?.text(now: at(14, 16), calendar: calendar, locale: locale)
                == "Codex limits next checked at 14:35 (no Codex activity)")
    }

    /// Both endpoints slowed: scheduled ticks every 5 minutes from 14:00 to
    /// 14:20. `later` sees activity at 14:04 and is quiet afterwards, the
    /// other endpoint is quiet throughout. Afterwards `later` is due at
    /// 14:40 and the other at 14:35, both at interval 20.
    private func bothSlowed(later: PacedEndpoint) -> AdaptivePace {
        var pace = AdaptivePace(base: 300, inUse: [.claude, .codex])
        for minute in [0, 5, 10, 15, 20] {
            let now = at(14, minute)
            for endpoint in PacedEndpoint.allCases {
                let activity = endpoint == later && minute >= 5 ? at(14, 4) : nil
                if pace.shouldCall(endpoint, newestActivity: activity, now: now) {
                    pace.recordCall(endpoint, at: now, scheduled: true, newestActivity: activity)
                }
            }
            pace.refreshCompleted(at: now, scheduled: true)
        }
        return pace
    }

    /// spec 019 FR-002, FR-004: both slowed name Claude, then Codex, even
    /// when Codex is due first; the time is the earlier next check.
    @Test func bothSlowedNameClaudeThenCodex() {
        let pace = bothSlowed(later: .claude)
        #expect(pace.lastCallAt(.claude) == at(14, 20))
        #expect(pace.dueAt(.claude) == at(14, 40))
        #expect(pace.dueAt(.codex) == at(14, 35))
        let status = pace.status(now: at(14, 21))
        #expect(status?.plans == [.claude, .codex])
        #expect(status?.nextAt == at(14, 35))
        #expect(status?.text(now: at(14, 21), calendar: calendar, locale: locale)
                == "Claude and Codex limits next checked at 14:35 (no agent activity)")
    }

    /// spec 019 scenario 3, FR-002: Claude due first, the same order and
    /// Claude's time.
    @Test func bothSlowedClaudeDueFirst() {
        let pace = bothSlowed(later: .codex)
        #expect(pace.dueAt(.claude) == at(14, 35))
        #expect(pace.dueAt(.codex) == at(14, 40))
        let status = pace.status(now: at(14, 21))
        #expect(status?.plans == [.claude, .codex])
        #expect(status?.nextAt == at(14, 35))
        #expect(status?.text(now: at(14, 21), calendar: calendar, locale: locale)
                == "Claude and Codex limits next checked at 14:35 (no agent activity)")
    }

    /// spec 019 SC-002 and the edge case on new activity: both plans
    /// slowed, then Claude Code writes usage. The line keeps both names
    /// until the next refresh that sees the activity, then names only Codex.
    @Test func claudeActivityLeavesOnlyCodexNamed() {
        var pace = bothSlowed(later: .codex)
        let activity = at(14, 22)
        #expect(pace.status(now: at(14, 23))?.plans == [.claude, .codex])
        let now = at(14, 25)
        #expect(pace.shouldCall(.claude, newestActivity: activity, now: now))
        pace.recordCall(.claude, at: now, scheduled: true, newestActivity: activity)
        #expect(!pace.shouldCall(.codex, newestActivity: nil, now: now))
        pace.refreshCompleted(at: now, scheduled: true)
        let status = pace.status(now: at(14, 26))
        #expect(status?.plans == [.codex])
        #expect(status?.text(now: at(14, 26), calendar: calendar, locale: locale)
                == "Codex limits next checked at 14:40 (no Codex activity)")
    }

    /// spec 019 edge cases: a plan not in use is never named, and a plan in
    /// use at the base is not named either.
    @Test func planNotInUseIsNotNamed() {
        var pace = AdaptivePace(base: 300, inUse: [.claude])
        pace.recordCall(.claude, at: at(14, 0), scheduled: false, newestActivity: nil)
        pace.recordCall(.codex, at: at(14, 0), scheduled: false, newestActivity: nil)
        pace.refreshCompleted(at: at(14, 0), scheduled: false)
        // Codex stretched by quiet scheduled calls, Claude active at the base.
        for minute in [5, 10] {
            let now = at(14, minute)
            pace.recordCall(.codex, at: now, scheduled: true, newestActivity: nil)
            pace.recordCall(.claude, at: now, scheduled: true, newestActivity: at(14, minute - 1))
            pace.refreshCompleted(at: now, scheduled: true)
        }
        #expect(pace.interval(.codex) > 300)
        #expect(pace.interval(.claude) == 300)
        #expect(pace.status(now: at(14, 11)) == nil)

        // Claude stretched too: only Claude, the plan in use, is named.
        pace.recordCall(.claude, at: at(14, 15), scheduled: true, newestActivity: nil)
        pace.refreshCompleted(at: at(14, 15), scheduled: true)
        #expect(pace.interval(.claude) > 300)
        #expect(pace.status(now: at(14, 16))?.plans == [.claude])
        #expect(pace.status(now: at(14, 16))?.text(now: at(14, 16), calendar: calendar, locale: locale)
                == "Claude limits next checked at 14:25 (no Claude Code activity)")
    }

    /// spec 019 FR-003, scenarios 4 and 5, SC-001: every timer reason keeps
    /// today's wording, with a slowed plan in use and without any plan in
    /// use. Idle stretches the timer to 30 minutes, Low Power Mode and high
    /// temperature to twice the base.
    @Test(arguments: [
        (SystemConditions(idle: true), "away", "14:45", "14:40"),
        (SystemConditions(lowPowerMode: true), "Low Power Mode", "14:25", "14:20"),
        (SystemConditions(thermalPressure: true), "high temperature", "14:25", "14:20"),
    ])
    func timerReasonKeepsTodaysWording(_ conditions: SystemConditions, _ name: String,
                                       _ planTime: String, _ refreshTime: String) {
        var pace = stretched(.codex)
        _ = pace.update(conditions: conditions)
        let status = pace.status(now: at(14, 16))
        #expect(status?.plans == [])
        #expect(status?.text(now: at(14, 16), calendar: calendar, locale: locale)
                == "Plan limits next checked at \(planTime) (\(name))")

        var none = AdaptivePace(base: 300)
        none.refreshCompleted(at: at(14, 10), scheduled: true)
        _ = none.update(conditions: conditions)
        #expect(none.status(now: at(14, 11))?.text(now: at(14, 11), calendar: calendar, locale: locale)
                == "Next refresh at \(refreshTime) (\(name))")
    }

    /// spec 019 FR-003: a timer reason keeps "Plan limits" even when the
    /// status carries plans.
    @Test func timerReasonIgnoresPlans() {
        let status = RefreshPaceStatus(reason: .idle, nextAt: at(14, 35), kind: .planLimits, plans: [.claude])
        #expect(status.text(now: at(14, 16), calendar: calendar, locale: locale)
                == "Plan limits next checked at 14:35 (away)")
    }

    /// spec 019 FR-003: a timer reason names no plan and keeps the wording.
    @Test func timerReasonNamesNoPlan() {
        var pace = stretchedClaude()
        _ = pace.update(conditions: SystemConditions(lowPowerMode: true))
        let status = pace.status(now: at(14, 16))
        #expect(status?.plans == [])
        #expect(status?.text(now: at(14, 16), calendar: calendar, locale: locale)
                == "Plan limits next checked at 14:25 (Low Power Mode)")

        var none = AdaptivePace(base: 300)
        none.refreshCompleted(at: at(14, 10), scheduled: true)
        _ = none.update(conditions: SystemConditions(lowPowerMode: true))
        #expect(none.status(now: at(14, 11))?.plans == [])
    }

    /// spec 019 FR-006: the time on another day carries the weekday.
    @Test func bothPlansOnAnotherDay() {
        let status = RefreshPaceStatus(reason: .noAgentActivity, nextAt: at(9, 5), kind: .planLimits, plans: [.claude, .codex])
        #expect(status.text(now: at(23, 50, day: 15), calendar: calendar, locale: locale)
                == "Claude and Codex limits next checked at Fri 09:05 (no agent activity)")
    }

    /// spec 019 FR-006: a 12 hour locale (macOS puts a narrow no-break space
    /// before AM).
    @Test func bothPlansTwelveHour() {
        let status = RefreshPaceStatus(reason: .noAgentActivity, nextAt: at(9, 5), kind: .planLimits, plans: [.claude, .codex])
        #expect(status.text(now: at(23, 50, day: 15), calendar: calendar, locale: Locale(identifier: "en_US"))
                == "Claude and Codex limits next checked at Fri 9:05\u{202F}AM (no agent activity)")
    }

    /// spec 019 FR-001: the plan and agent names.
    @Test func planAndAgentNames() {
        #expect(PacedEndpoint.claude.planName == "Claude")
        #expect(PacedEndpoint.claude.agentName == "Claude Code")
        #expect(PacedEndpoint.codex.planName == "Codex")
        #expect(PacedEndpoint.codex.agentName == "Codex")
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
