import Foundation
import Testing
@testable import UsageCore

/// A local record of `harness` written at `at`, for the activity signal.
func paceRecord(_ harness: Harness, at: Date, accountId: String? = nil) -> UsageRecord {
    UsageRecord(messageId: UUID().uuidString, timestamp: at, model: "m", canonicalModel: "m", requestId: "r",
                accountId: accountId, inputTokens: 1, outputTokens: 1, cacheWrite5mTokens: 0, cacheWrite1hTokens: 0,
                cacheReadTokens: 0, costUSD: nil, harness: harness)
}

/// spec 016 contracts/refresh-pace.md, rows P, T and D, as pure values
/// (FR-003 to FR-013, FR-019). Times are minutes after t0.
@Suite struct AdaptivePaceTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func t(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private func pace(base: TimeInterval = 300, inUse: Set<PacedEndpoint> = [.claude]) -> AdaptivePace {
        AdaptivePace(base: base, inUse: inUse)
    }

    /// Launch call at t=0, then scheduled ticks every `step` minutes up to
    /// `until`, calling only when the pace says so and recording each call
    /// with `activity(minute)` as the newest activity. Returns the minutes
    /// at which the endpoint was called.
    private func run(_ pace: inout AdaptivePace, _ endpoint: PacedEndpoint = .claude, step: Double = 5, until: Double,
                     from start: Double = 0, activity: (Double) -> Date? = { _ in nil }) -> [Double] {
        if start == 0 {
            pace.recordCall(endpoint, at: t(0), scheduled: false, newestActivity: nil)
            pace.refreshCompleted(at: t(0), scheduled: false)
        }
        var calls: [Double] = []
        for minute in stride(from: start + step, through: until, by: step) {
            let newest = activity(minute)
            if pace.shouldCall(endpoint, newestActivity: newest, now: t(minute)) {
                calls.append(minute)
                pace.recordCall(endpoint, at: t(minute), scheduled: true, newestActivity: newest)
            }
            pace.refreshCompleted(at: t(minute), scheduled: true)
        }
        return calls
    }

    // MARK: Endpoint pace

    /// P1, SC-001: calls at 0, 5, 15, 35, 65, 95 while scans run every 5.
    @Test func p1QuietEndpointDoublesUpToTheCap() {
        var pace = pace()
        let calls = run(&pace, until: 120)
        #expect(calls == [5, 15, 35, 65, 95])
        #expect(pace.interval(.claude) == 1800)
        #expect(calls.count + 1 <= 7)
    }

    /// P2, SC-002: a new Claude Code record brings the call and the base back.
    @Test func p2ActivityCallsAndReturnsToTheBase() {
        var pace = pace()
        _ = run(&pace, until: 65)
        #expect(pace.interval(.claude) == 1800)
        let newest = pace.newestActivity(.claude, in: [paceRecord(.claudeCode, at: t(69))])
        #expect(pace.shouldCall(.claude, newestActivity: newest, now: t(70)))
        let change = pace.recordCall(.claude, at: t(70), scheduled: true, newestActivity: newest)
        #expect(change == IntervalChange(endpoint: .claude, from: 1800, to: 300, reason: nil))
        #expect(pace.lastCallAt(.claude) == t(70))
    }

    /// Activity counts only after at least the timer interval since the last call.
    @Test func activityWaitsForTheTimerInterval() {
        var pace = pace()
        _ = run(&pace, until: 15)
        #expect(!pace.shouldCall(.claude, newestActivity: t(16), now: t(17)))
        #expect(pace.shouldCall(.claude, newestActivity: t(16), now: t(20)))
    }

    /// P3: Codex records keep the Codex pace at the base; Claude grows.
    @Test func p3CodexRecordsDoNotCountForClaude() {
        let records = [paceRecord(.codex, at: t(1))]
        let probe = pace()
        #expect(probe.newestActivity(.claude, in: records) == nil)
        #expect(probe.newestActivity(.codex, in: records) == t(1))

        var claude = pace()
        var codex = pace(inUse: [.codex])
        let claudeCalls = run(&claude, until: 60) { _ in nil }
        let codexCalls = run(&codex, .codex, until: 60) { self.t($0 - 1) }
        #expect(claudeCalls == [5, 15, 35])
        #expect(codexCalls == Array(stride(from: 5.0, through: 60, by: 5)))
        #expect(codex.interval(.codex) == 300)
    }

    /// P4: an OpenCode record counts for both endpoints, of any account,
    /// Unassigned included (FR-004).
    @Test func p4OpenCodeCountsForBoth() {
        let records = [paceRecord(.openCode, at: t(12)), paceRecord(.claudeCode, at: t(3), accountId: "acc")]
        let pace = pace()
        #expect(pace.newestActivity(.claude, in: records) == t(12))
        #expect(pace.newestActivity(.codex, in: records) == t(12))
        #expect(pace.newestActivity(.codex, in: [paceRecord(.claudeCode, at: t(3))]) == nil)
    }

    /// P5: re-read records older than the last call are no activity.
    @Test func p5OlderRecordsAreNoActivity() {
        var pace = pace()
        _ = run(&pace, until: 15)
        #expect(pace.interval(.claude) == 1200)
        #expect(!pace.shouldCall(.claude, newestActivity: t(14), now: t(25)))
        let change = pace.recordCall(.claude, at: t(35), scheduled: true, newestActivity: t(14))
        #expect(change?.to == 1800)
    }

    /// P6, P7: a call that did not reach the service is not recorded, so
    /// interval and last call stay and older activity counts at the next call.
    @Test func p6p7UnrecordedCallsCarryActivityOver() {
        var pace = pace()
        _ = run(&pace, until: 5)
        #expect(pace.interval(.claude) == 600)
        // Activity at 7; the scheduled call at 15 fails by transport.
        #expect(pace.shouldCall(.claude, newestActivity: t(7), now: t(15)))
        pace.refreshCompleted(at: t(15), scheduled: true)
        #expect(pace.lastCallAt(.claude) == t(5))
        #expect(pace.interval(.claude) == 600)
        // The next call reaches the service and sees the activity from 7.
        #expect(pace.shouldCall(.claude, newestActivity: t(7), now: t(20)))
        let change = pace.recordCall(.claude, at: t(20), scheduled: true, newestActivity: t(7))
        #expect(change == IntervalChange(endpoint: .claude, from: 600, to: 300, reason: nil))
    }

    /// P8: a quiet unscheduled call counts as last call without doubling.
    @Test func p8UnscheduledQuietCallKeepsTheInterval() {
        var pace = pace()
        _ = run(&pace, until: 15)
        #expect(pace.interval(.claude) == 1200)
        let intervalChange1 = pace.recordCall(.claude, at: t(20), scheduled: false, newestActivity: nil)
        #expect(intervalChange1 == nil)
        #expect(pace.lastCallAt(.claude) == t(20))
        #expect(pace.interval(.claude) == 1200)
    }

    /// P9: an unscheduled call that saw activity returns to the base.
    @Test func p9UnscheduledCallWithActivityReturnsToTheBase() {
        var pace = pace()
        _ = run(&pace, until: 15)
        let change = pace.recordCall(.claude, at: t(20), scheduled: false, newestActivity: t(18))
        #expect(change == IntervalChange(endpoint: .claude, from: 1200, to: 300, reason: nil))
    }

    /// P10: a tick up to 5 s early counts as due.
    @Test func p10TickToleranceOfFiveSeconds() {
        var pace = pace()
        _ = run(&pace, until: 5)
        let due = t(15)
        #expect(pace.dueAt(.claude) == due)
        #expect(pace.shouldCall(.claude, newestActivity: nil, now: due.addingTimeInterval(-3)))
        #expect(pace.shouldCall(.claude, newestActivity: nil, now: due.addingTimeInterval(-5)))
        #expect(!pace.shouldCall(.claude, newestActivity: nil, now: due.addingTimeInterval(-6)))
    }

    /// P11: a base of 40 minutes is never stretched.
    @Test func p11LongBaseNeverStretches() {
        var pace = pace(base: 2400)
        let calls = run(&pace, step: 40, until: 400)
        #expect(calls == Array(stride(from: 40.0, through: 400, by: 40)))
        #expect(pace.interval(.claude) == 2400)
        #expect(pace.status(now: t(401)) == nil)
    }

    /// P12: a base of 1 minute grows 1, 2, 4, 8, 16, 30.
    @Test func p12OneMinuteBase() {
        var pace = pace(base: 60)
        var intervals: [TimeInterval] = [pace.interval(.claude)]
        pace.recordCall(.claude, at: t(0), scheduled: false, newestActivity: nil)
        for minute in 1...6 {
            pace.recordCall(.claude, at: t(Double(minute)), scheduled: true, newestActivity: nil)
            intervals.append(pace.interval(.claude))
        }
        #expect(intervals == [60, 120, 240, 480, 960, 1800, 1800])
    }

    /// P13, FR-002: disabled means today's behavior.
    @Test func p13DisabledIsTheFixedTimer() {
        var pace = AdaptivePace(enabled: false, base: 300, inUse: [.claude])
        let timerChanged2 = pace.update(conditions: SystemConditions(idle: true, lowPowerMode: true))
        #expect(timerChanged2 == false)
        #expect(pace.timerInterval == 300)
        #expect(pace.timerReason == nil)
        let calls = run(&pace, until: 60)
        #expect(calls == Array(stride(from: 5.0, through: 60, by: 5)))
        let intervalChange3 = pace.recordCall(.claude, at: t(61), scheduled: true, newestActivity: nil)
        #expect(intervalChange3 == nil)
        #expect(pace.interval(.claude) == 300)
        #expect(pace.status(now: t(62)) == nil)
        #expect(!pace.shouldRefreshOnOpen(now: t(70)))
        #expect(pace.nextScheduledRefresh(now: t(61)) == t(65))
    }

    // MARK: Timer pace

    /// T1: idle stretches the timer to 30 minutes; endpoint due times use it.
    @Test func t1IdleTimer() {
        var pace = pace()
        pace.recordCall(.claude, at: t(0), scheduled: false, newestActivity: nil)
        pace.refreshCompleted(at: t(10), scheduled: true)
        let timerChanged4 = pace.update(conditions: SystemConditions(idle: true))
        #expect(timerChanged4)
        #expect(pace.timerInterval == 1800)
        #expect(pace.timerReason == .idle)
        #expect(pace.dueAt(.claude) == t(30))
        #expect(pace.nextScheduledRefresh(now: t(11)) == t(30))
        var noEndpoint = self.pace(inUse: [])
        noEndpoint.refreshCompleted(at: t(10), scheduled: true)
        _ = noEndpoint.update(conditions: SystemConditions(idle: true))
        #expect(noEndpoint.nextScheduledRefresh(now: t(11)) == t(40))
    }

    /// T2: Low Power Mode doubles the timer; due times use max(interval, timer).
    @Test func t2LowPowerMode() {
        var pace = pace()
        pace.recordCall(.claude, at: t(0), scheduled: false, newestActivity: nil)
        pace.refreshCompleted(at: t(0), scheduled: false)
        let timerChanged5 = pace.update(conditions: SystemConditions(lowPowerMode: true))
        #expect(timerChanged5)
        #expect(pace.timerInterval == 600)
        #expect(pace.timerReason == .lowPowerMode)
        #expect(pace.dueAt(.claude) == t(10))
        #expect(pace.nextScheduledRefresh(now: t(1)) == t(10))
        #expect(!pace.shouldCall(.claude, newestActivity: t(1), now: t(5)))
    }

    /// T3, T4: several conditions, the longest interval and the highest reason.
    @Test func t3t4SeveralConditions() {
        var pace = pace()
        _ = pace.update(conditions: SystemConditions(thermalPressure: true))
        #expect(pace.timerInterval == 600)
        #expect(pace.timerReason == .highTemperature)
        _ = pace.update(conditions: SystemConditions(lowPowerMode: true, thermalPressure: true))
        #expect(pace.timerInterval == 600)
        #expect(pace.timerReason == .lowPowerMode)
        _ = pace.update(conditions: SystemConditions(idle: true, lowPowerMode: true))
        #expect(pace.timerInterval == 1800)
        #expect(pace.timerReason == .idle)
    }

    /// Low Power Mode with a base of 20 minutes is capped at 30.
    @Test func lowPowerModeIsCapped() {
        var pace = pace(base: 1200)
        _ = pace.update(conditions: SystemConditions(lowPowerMode: true))
        #expect(pace.timerInterval == 1800)
    }

    /// T5: when the condition ends, the base counts from the last refresh.
    @Test func t5ConditionEnds() {
        var pace = pace(inUse: [])
        _ = pace.update(conditions: SystemConditions(lowPowerMode: true))
        pace.refreshCompleted(at: t(35), scheduled: true)
        #expect(pace.nextScheduledRefresh(now: t(36)) == t(45))
        let timerChanged6 = pace.update(conditions: SystemConditions())
        #expect(timerChanged6)
        #expect(pace.timerReason == nil)
        #expect(pace.nextScheduledRefresh(now: t(38)) == t(40))
        #expect(pace.nextScheduledRefresh(now: t(50)) == t(50))
    }

    /// T6: a base above the cap is used unchanged while idle.
    @Test func t6LongBaseWhileIdle() {
        var pace = pace(base: 2400)
        let timerChanged7 = pace.update(conditions: SystemConditions(idle: true, lowPowerMode: true))
        #expect(timerChanged7 == false)
        #expect(pace.timerInterval == 2400)
        #expect(pace.timerReason == nil)
    }

    /// T8, SC-005: base 7, Low Power Mode, Claude interval 30: ticks at 14,
    /// 28, then at the due time 30.
    @Test func t8DueTimePullsTheTick() {
        var pace = pace(base: 420)
        for minute in [-100.0, -90, -80, -70, 0] {
            pace.recordCall(.claude, at: t(minute), scheduled: minute != -100, newestActivity: nil)
        }
        #expect(pace.interval(.claude) == 1800)
        pace.refreshCompleted(at: t(0), scheduled: true)
        _ = pace.update(conditions: SystemConditions(lowPowerMode: true))
        var ticks: [Date] = []
        var now = t(0)
        while ticks.count < 3 {
            now = pace.nextScheduledRefresh(now: now)
            ticks.append(now)
            if pace.shouldCall(.claude, newestActivity: nil, now: now) {
                pace.recordCall(.claude, at: now, scheduled: true, newestActivity: nil)
            }
            pace.refreshCompleted(at: now, scheduled: true)
        }
        #expect(ticks == [t(14), t(28), t(30)])
        #expect(pace.lastCallAt(.claude) == t(30))
    }

    /// T9: a call that keeps failing never makes the timer fire at once again.
    @Test func t9UnmovedLastCallDoesNotSpin() {
        var pace = pace()
        pace.recordCall(.claude, at: t(0), scheduled: false, newestActivity: nil)
        pace.refreshCompleted(at: t(0), scheduled: false)
        #expect(pace.shouldCall(.claude, newestActivity: nil, now: t(5)))
        pace.refreshCompleted(at: t(5), scheduled: true)
        #expect(pace.nextScheduledRefresh(now: t(5)) == t(10))
        pace.refreshCompleted(at: t(10), scheduled: true)
        #expect(pace.nextScheduledRefresh(now: t(10)) == t(15))
        #expect(pace.nextScheduledRefresh(now: t(10)) > t(10))
    }

    /// T10: an endpoint in use without any call follows the last refresh.
    @Test func t10NeverCalledEndpoint() {
        var pace = pace()
        pace.refreshCompleted(at: t(0), scheduled: false)
        #expect(pace.dueAt(.claude) == nil)
        #expect(pace.nextScheduledRefresh(now: t(1)) == t(5))
    }

    /// T11: the clock moved back an hour after a call.
    @Test func t11ClockMovedBackwards() {
        var pace = pace()
        _ = run(&pace, until: 60)
        pace.normalize(now: t(0))
        #expect(pace.lastCallAt(.claude) == t(0))
        #expect(pace.lastRefreshAt == t(0))
        #expect(pace.lastScheduledAt == t(0))
        let bound = max(pace.interval(.claude), pace.timerInterval) / 60
        #expect(pace.shouldCall(.claude, newestActivity: nil, now: t(bound)))
        // The normalized last refresh plus the base timer.
        #expect(pace.nextScheduledRefresh(now: t(0)) == t(5))
    }

    /// FR-014, spec 010 FR-008: a wake call that failed by transport is a
    /// try; the overdue endpoint does not pull the next scheduled refresh
    /// to now, where it would use up the quick retry.
    @Test func failedTryHandlesTheDueTime() {
        var pace = pace()
        pace.recordCall(.claude, at: t(0), scheduled: true, newestActivity: nil)
        pace.refreshCompleted(at: t(0), scheduled: true)
        pace.recordTry(.claude, at: t(20))
        pace.refreshCompleted(at: t(20), scheduled: false)
        #expect(pace.lastCallAt(.claude) == t(0))
        #expect(pace.lastTriedAt(.claude) == t(20))
        #expect(pace.interval(.claude) == 300)
        #expect(pace.nextScheduledRefresh(now: t(20)) == t(25))
    }

    /// FR-012, FR-020: within 60 s of a try without an answer (an expired
    /// sign-in) opening the dropdown starts no refresh.
    @Test func openWaitsAMinuteAfterATry() {
        var pace = pace()
        pace.recordTry(.claude, at: t(0))
        pace.refreshCompleted(at: t(0), scheduled: false)
        #expect(pace.lastCallAt(.claude) == nil)
        #expect(pace.shouldRefreshOnOpen(now: t(0.5)) == false)
        #expect(pace.shouldRefreshOnOpen(now: t(1)))
    }

    /// FR-011, FR-002: a return from idle refreshes, except within 60 s
    /// after a wake refresh, and never while disabled.
    @Test func idleReturnDecision() {
        let idle = SystemConditions(idle: true)
        var pace = pace()
        _ = pace.update(conditions: idle)
        #expect(pace.idleReturn(from: SystemConditions(), now: t(0)) == .none)
        _ = pace.update(conditions: SystemConditions())
        #expect(pace.idleReturn(from: idle, now: t(0)) == .refresh)
        #expect(pace.idleReturn(from: SystemConditions(lowPowerMode: true), now: t(0)) == .none)
        pace.wakeRequested(at: t(10))
        #expect(pace.idleReturn(from: idle, now: t(10).addingTimeInterval(59)) == .afterWake)
        #expect(pace.idleReturn(from: idle, now: t(10).addingTimeInterval(60)) == .refresh)
        var off = AdaptivePace(enabled: false, base: 300, inUse: [.claude])
        _ = off.update(conditions: SystemConditions())
        #expect(off.idleReturn(from: idle, now: t(0)) == .none)
    }

    /// Edge case "Base interval of 30 minutes or more" at exactly 30.
    @Test func baseOfExactlyThirtyMinutesNeverStretches() {
        var pace = pace(base: 1800)
        #expect(run(&pace, step: 30, until: 120) == [30, 60, 90, 120])
        #expect(pace.interval(.claude) == 1800)
        #expect(pace.status(now: t(120)) == nil)
        _ = pace.update(conditions: SystemConditions(idle: true, lowPowerMode: true))
        #expect(pace.timerInterval == 1800)
        #expect(pace.timerReason == nil)
    }

    /// T12: before the first completed refresh, one timer interval from now;
    /// with no scheduled refresh yet a past due time fires once.
    @Test func t12NoRefreshYet() {
        var pace = pace()
        #expect(pace.nextScheduledRefresh(now: t(0)) == t(5))
        _ = pace.update(conditions: SystemConditions(idle: true))
        #expect(pace.nextScheduledRefresh(now: t(0)) == t(30))
        _ = pace.update(conditions: SystemConditions())
        pace.recordCall(.claude, at: t(0), scheduled: false, newestActivity: nil)
        pace.refreshCompleted(at: t(0), scheduled: false)
        #expect(pace.lastScheduledAt == nil)
        #expect(pace.nextScheduledRefresh(now: t(7)) == t(7))
        pace.refreshCompleted(at: t(7), scheduled: true)
        #expect(pace.nextScheduledRefresh(now: t(7)) == t(12))
    }

    /// T13: only a scheduled refresh hides a due time, a reprice does not.
    @Test func t13RepriceDoesNotHideADueTime() {
        var pace = pace()
        _ = run(&pace, until: 5)
        #expect(pace.dueAt(.claude) == t(15))
        let justBefore = t(15).addingTimeInterval(-3)
        var reprice = pace
        reprice.refreshCompleted(at: justBefore, scheduled: false)
        #expect(reprice.nextScheduledRefresh(now: justBefore) == t(15))
        var scheduled = pace
        scheduled.refreshCompleted(at: justBefore, scheduled: true)
        #expect(scheduled.nextScheduledRefresh(now: justBefore) == justBefore.addingTimeInterval(300))
    }

    // MARK: Dropdown open (FR-012)

    @Test func d1d2d3OpenDependsOnTheOldestEndpoint() {
        var pace = pace(inUse: [.claude, .codex])
        pace.recordCall(.claude, at: t(0), scheduled: false, newestActivity: nil)
        #expect(pace.shouldRefreshOnOpen(now: t(0.5)), "Codex was never called")
        pace.recordCall(.codex, at: t(0), scheduled: false, newestActivity: nil)
        #expect(!pace.shouldRefreshOnOpen(now: t(0.5)))
        #expect(pace.shouldRefreshOnOpen(now: t(4)))
        var claudeOnly = self.pace()
        claudeOnly.recordCall(.claude, at: t(0), scheduled: false, newestActivity: nil)
        #expect(claudeOnly.shouldRefreshOnOpen(now: t(4)))
        #expect(!claudeOnly.shouldRefreshOnOpen(now: t(0.5)))
        #expect(claudeOnly.shouldRefreshOnOpen(now: t(1)), "60 s is old enough")
        var mixed = self.pace(inUse: [.claude, .codex])
        mixed.recordCall(.codex, at: t(0), scheduled: false, newestActivity: nil)
        mixed.recordCall(.claude, at: t(4.5), scheduled: false, newestActivity: nil)
        #expect(mixed.shouldRefreshOnOpen(now: t(5)))
    }

    @Test func d5WithoutEndpointsTheLastRefreshCounts() {
        var pace = pace(inUse: [])
        #expect(pace.shouldRefreshOnOpen(now: t(0)))
        pace.refreshCompleted(at: t(0), scheduled: false)
        #expect(!pace.shouldRefreshOnOpen(now: t(0.5)))
        #expect(pace.shouldRefreshOnOpen(now: t(2)))
    }

    @Test func d6DisabledNeverRefreshesOnOpen() {
        let pace = AdaptivePace(enabled: false, base: 300, inUse: [.claude])
        #expect(!pace.shouldRefreshOnOpen(now: t(100)))
    }

    // MARK: Configuration

    @Test func updateConfigurationResetsIntervalsOnAChangedBaseOrToggle() {
        var config = Configuration()
        config.accounts = [Account(displayName: "Max", kind: .subscription(SubscriptionSettings()))]
        var pace = AdaptivePace(base: 300)
        pace.update(configuration: config)
        #expect(pace.inUse == [.claude])
        _ = run(&pace, until: 15)
        #expect(pace.interval(.claude) == 1200)
        pace.update(configuration: config)
        #expect(pace.interval(.claude) == 1200, "unchanged configuration keeps the pace")
        config.refreshIntervalSeconds = 120
        pace.update(configuration: config)
        #expect(pace.base == 120)
        #expect(pace.interval(.claude) == 120)
        _ = run(&pace, step: 2, until: 30, from: 15)
        #expect(pace.interval(.claude) > 120)
        config.adaptiveRefresh = false
        pace.update(configuration: config)
        #expect(!pace.enabled)
        #expect(pace.interval(.claude) == 120)
        #expect(pace.lastCallAt(.claude) != nil, "the last call stays known")
        config.adaptiveRefresh = true
        pace.update(configuration: config)
        #expect(pace.enabled)
        #expect(pace.interval(.claude) == 120)
    }

    @Test func updateConditionsReportsChanges() {
        var pace = pace()
        let timerChanged8 = pace.update(conditions: SystemConditions(lowPowerMode: true))
        #expect(timerChanged8)
        let timerChanged9 = pace.update(conditions: SystemConditions(lowPowerMode: true))
        #expect(!timerChanged9)
        let timerChanged10 = pace.update(conditions: SystemConditions(lowPowerMode: true, thermalPressure: true))
        #expect(timerChanged10 == false,
                "same interval and reason")
        let timerChanged11 = pace.update(conditions: SystemConditions(thermalPressure: true))
        #expect(timerChanged11, "the reason changed")
        let timerChanged12 = pace.update(conditions: SystemConditions())
        #expect(timerChanged12)
        #expect(pace.conditions == SystemConditions())
    }

    @Test func endpointsInUse() {
        var config = Configuration()
        #expect(!PacedEndpoint.claude.isInUse(config))
        #expect(!PacedEndpoint.codex.isInUse(config))
        config.accounts = [Account(displayName: "Codex", harness: .codex,
                                   kind: .codexSubscription(CodexSubscriptionSettings(liveLimits: false)))]
        #expect(!PacedEndpoint.codex.isInUse(config), "live limits off")
        config.accounts.append(Account(displayName: "Codex 2", harness: .codex,
                                       kind: .codexSubscription(CodexSubscriptionSettings(codexHome: "~/.codex2", liveLimits: true))))
        #expect(PacedEndpoint.codex.isInUse(config))
        #expect(!PacedEndpoint.claude.isInUse(config))
        config.accounts.append(Account(displayName: "Max", kind: .subscription(SubscriptionSettings())))
        #expect(PacedEndpoint.claude.isInUse(config))
        #expect(PacedEndpoint.claude.harnesses == [.claudeCode, .openCode])
        #expect(PacedEndpoint.codex.harnesses == [.codex, .openCode])
    }
}
