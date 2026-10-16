import Foundation
import Testing
@testable import UsageCore

/// spec 017 FR-003, FR-004, research R3, R4, R6: the observations kept in
/// memory, their discard rules and the recent rate.
@Suite struct ObservationLogTests {
    static let t0 = isoDate("2026-10-14T13:10:00Z")
    static let hour: TimeInterval = 3600
    /// The 7-day reset 66 hours after 14:00 (US1).
    static let sevenReset = isoDate("2026-10-17T08:00:00Z")
    static let weekly = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    static let monthly = DateInterval(start: isoDate("2026-11-01T00:00:00Z"), end: isoDate("2026-12-01T00:00:00Z"))
    static let seven = BurnWindowKey.claude("c", .sevenDay)

    static func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    static func claude(_ seven: Double, fetched: Date, reset: Date = sevenReset, five: Double? = nil,
                       models: [ModelLimit] = [], state: SubscriptionState = .ok) -> SubscriptionEntry {
        let fiveWindow = five.map { LimitWindow(utilizationPercent: $0, resetsAt: fetched.addingTimeInterval(2 * hour)) }
        return SubscriptionEntry(status: SubscriptionStatus(fiveHour: fiveWindow,
                                                            sevenDay: LimitWindow(utilizationPercent: seven, resetsAt: reset),
                                                            modelLimits: models, fetchedAt: fetched), state: state)
    }

    static func codex(_ windows: [CodexLimitWindow], observed: Date, origin: CodexLimitObservation.Origin = .live,
                      state: CodexLimitsState = .live) -> CodexLimitsEntry {
        CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: observed, origin: origin, windows: windows),
                         state: state)
    }

    static func budget(_ spent: Decimal, budget: Decimal = 100, window: DateInterval = weekly, period: BudgetPeriod = .weekly,
                       members: [String] = ["a"], stale: Bool = false) -> GroupEntry {
        GroupEntry(spentUSD: spent, budgetUSD: budget, percent: PercentFormatter.rounded(spent: spent, budget: budget),
                   incomplete: false, period: period, window: window, breakdown: .empty, members: members, stale: stale)
    }

    static func snapshot(at: Date, subs: [String: SubscriptionEntry] = [:], groups: [String: GroupEntry] = [:],
                         budgets: [String: GroupEntry] = [:], codex: [String: CodexLimitsEntry] = [:]) -> UsageSnapshot {
        UsageSnapshot(generatedAt: at, window: weekly, windowSource: .fallback, subscriptions: subs, groups: groups,
                      accountBudgets: budgets, codexLimits: codex)
    }

    /// Feeds the snapshots in order, without price changes.
    static func log(_ snapshots: [UsageSnapshot], from start: ObservationLog = ObservationLog()) -> ObservationLog {
        snapshots.reduce(start) { $0.updated(with: $1, budgetPricesChanged: false) }
    }

    static func claudeLog(_ values: [(minutes: Double, percent: Double)], reset: Date = sevenReset) -> ObservationLog {
        log(values.map { snapshot(at: at($0.minutes), subs: ["c": claude($0.percent, fetched: at($0.minutes), reset: reset)]) })
    }

    static func usedPercents(_ log: ObservationLog, _ key: BurnWindowKey) -> [Double] {
        log.entries[key]?.map(\.usedPercent) ?? []
    }

    // MARK: - Appending (FR-003)

    @Test func startsEmpty() {
        #expect(ObservationLog().entries.isEmpty)
        #expect(ObservationLog().recentRate(for: Self.seven, now: Self.t0) == nil)
    }

    /// A refresh that reuses the previous result (same fetch time) adds nothing.
    @Test func appendsOnlyLaterObservations() {
        let first = Self.snapshot(at: Self.at(0), subs: ["c": Self.claude(30, fetched: Self.at(0))])
        let reused = Self.snapshot(at: Self.at(1), subs: ["c": Self.claude(30, fetched: Self.at(0))])
        let later = Self.snapshot(at: Self.at(10), subs: ["c": Self.claude(31, fetched: Self.at(10))])
        let log = Self.log([first, reused, later])
        #expect(log.entries[Self.seven]?.map(\.observedAt) == [Self.at(0), Self.at(10)])
        #expect(log.entries[Self.seven]?.last == RateObservation(observedAt: Self.at(10), usedPercent: 31, resetsAt: Self.sevenReset))
    }

    /// Observations older than 60 minutes before the snapshot are dropped;
    /// one exactly 60 minutes old is kept.
    @Test func lookbackKeepsExactlySixtyMinutes() {
        let kept = Self.claudeLog([(0, 30), (30, 31), (60, 32)])
        #expect(Self.usedPercents(kept, Self.seven) == [30, 31, 32])
        let dropped = Self.log([Self.snapshot(at: Self.at(60) + 1, subs: ["c": Self.claude(33, fetched: Self.at(60) + 1)])], from: kept)
        #expect(Self.usedPercents(dropped, Self.seven) == [31, 32, 33])
    }

    /// FR-004: the recent rate counts an observation exactly 60 minutes
    /// before the snapshot, and not one a second older.
    @Test func recentRateLookbackIsInclusive() throws {
        let log = Self.claudeLog([(0, 30), (60, 32)])
        let atBoundary = try #require(log.recentRate(for: Self.seven, now: Self.at(60)))
        #expect(abs(atBoundary.perHour - 2) < 1e-9)
        #expect(log.recentRate(for: Self.seven, now: Self.at(60) + 1) == nil)
    }

    /// After the clock moved backwards, observations far after the snapshot
    /// time are dropped, so new observations are recorded again and an old
    /// burst stops counting; a fetch up to `futureTolerance` after the
    /// snapshot time stays.
    @Test func clockMovedBackwardsDropsFutureObservations() {
        let burst = Self.claudeLog([(0, 30), (50, 36)])
        let back = Self.at(-180)
        let log = Self.log([Self.snapshot(at: back, subs: ["c": Self.claude(37, fetched: back)])], from: burst)
        #expect(log.entries[Self.seven]?.map(\.observedAt) == [back])
        #expect(log.recentRate(for: Self.seven, now: back) == nil)
        // An observation `ahead` seconds after the next snapshot time.
        func kept(ahead: TimeInterval) -> [Double] {
            let first = Self.log([Self.snapshot(at: Self.at(0), subs: ["c": Self.claude(30, fetched: Self.at(1) + ahead)])])
            let next = Self.snapshot(at: Self.at(1), subs: ["c": Self.claude(31, fetched: Self.at(1) + ahead + 60)])
            return Self.usedPercents(Self.log([next], from: first), Self.seven)
        }
        #expect(kept(ahead: 300) == [30, 31])
        #expect(kept(ahead: ObservationLog.futureTolerance) == [30, 31])
        #expect(kept(ahead: ObservationLog.futureTolerance + 1) == [31])
    }

    // MARK: - Discard rules (FR-003, research R4)

    @Test func lowerPercentDiscardsEarlierObservations() {
        let log = Self.claudeLog([(0, 30), (10, 35), (20, 34)])
        #expect(Self.usedPercents(log, Self.seven) == [34])
    }

    @Test func changedResetDiscardsEarlierObservations() {
        let log = Self.log([
            Self.snapshot(at: Self.at(0), subs: ["c": Self.claude(30, fetched: Self.at(0))]),
            Self.snapshot(at: Self.at(10), subs: ["c": Self.claude(31, fetched: Self.at(10), reset: Self.sevenReset + 3600)]),
        ])
        #expect(Self.usedPercents(log, Self.seven) == [31])
    }

    /// Codex reset times come from raw epochs: less than 60 s apart is the
    /// same reset, also across a half-minute boundary; 2 minutes is not.
    @Test func codexResetToleranceIsUnderSixtySeconds() {
        let reset = isoDate("2026-10-17T08:00:29Z") + 0.6
        func log(secondReset: Date) -> ObservationLog {
            Self.log([
                Self.snapshot(at: Self.at(0), codex: ["x": Self.codex([CodexLimitWindow(lengthMinutes: 10080, usedPercent: 30, resetsAt: reset)],
                                                                      observed: Self.at(0))]),
                Self.snapshot(at: Self.at(10), codex: ["x": Self.codex([CodexLimitWindow(lengthMinutes: 10080, usedPercent: 31, resetsAt: secondReset)],
                                                                       observed: Self.at(10))]),
            ])
        }
        let key = BurnWindowKey.codex("x", "weekly")
        #expect(Self.usedPercents(log(secondReset: reset + 1), key) == [30, 31])
        #expect(Self.usedPercents(log(secondReset: reset + 0.8), key) == [30, 31])
        #expect(Self.usedPercents(log(secondReset: reset + 59), key) == [30, 31])
        #expect(Self.usedPercents(log(secondReset: reset - 59), key) == [30, 31])
        #expect(Self.usedPercents(log(secondReset: reset + 60), key) == [31])
        #expect(Self.usedPercents(log(secondReset: reset + 120), key) == [31])
    }

    /// A Codex window observed alternately from a live result and a session
    /// log keeps one list; a lower reading from either source discards.
    @Test func codexSourcesShareOneList() {
        let reset = Self.sevenReset
        func entry(_ used: Double, _ minutes: Double, _ origin: CodexLimitObservation.Origin) -> UsageSnapshot {
            Self.snapshot(at: Self.at(minutes), codex: ["x": Self.codex([CodexLimitWindow(lengthMinutes: 10080, usedPercent: used, resetsAt: reset)],
                                                                        observed: Self.at(minutes), origin: origin,
                                                                        state: origin == .live ? .live : .newerSnapshot)])
        }
        let key = BurnWindowKey.codex("x", "weekly")
        let mixed = Self.log([entry(30, 0, .live), entry(31, 5, .snapshot), entry(33, 10, .live)])
        #expect(Self.usedPercents(mixed, key) == [30, 31, 33])
        let lower = Self.log([entry(32, 15, .snapshot)], from: mixed)
        #expect(Self.usedPercents(lower, key) == [32])
    }

    @Test func budgetChangesDiscardBudgetObservations() {
        let base = Self.log([
            Self.snapshot(at: Self.at(0), groups: ["g": Self.budget(30)]),
            Self.snapshot(at: Self.at(10), groups: ["g": Self.budget(31)]),
        ])
        let key = BurnWindowKey.group("g")
        #expect(Self.usedPercents(base, key) == [30, 31])
        func next(_ entry: GroupEntry) -> [Double] {
            Self.usedPercents(Self.log([Self.snapshot(at: Self.at(20), groups: ["g": entry])], from: base), key)
        }
        // Unchanged amount, period and members (in any order).
        #expect(next(Self.budget(32)) == [30, 31, 32])
        #expect(next(Self.budget(33, members: ["a"])) == [30, 31, 33])
        // Amount, members and period.
        #expect(next(Self.budget(70, budget: 200)) == [35])
        #expect(next(Self.budget(32, members: ["a", "b"])) == [32])
        #expect(next(Self.budget(32, window: Self.weekly, period: .monthly)) == [32])
        // A moved window (its end).
        let moved = DateInterval(start: Self.weekly.start, end: Self.weekly.end + 86_400)
        #expect(next(Self.budget(32, window: moved)) == [32])
    }

    /// A group and an account with its own budget may share an id (spec
    /// 008): each keeps its own observations and fingerprint.
    @Test func groupAndOwnBudgetWithTheSameIdStaySeparate() {
        let base = Self.log([
            Self.snapshot(at: Self.at(0), groups: ["x": Self.budget(30)], budgets: ["x": Self.budget(10, members: ["x"])]),
            Self.snapshot(at: Self.at(10), groups: ["x": Self.budget(31)], budgets: ["x": Self.budget(12, members: ["x"])]),
        ])
        #expect(Self.usedPercents(base, .group("x")) == [30, 31])
        #expect(Self.usedPercents(base, .accountBudget("x")) == [10, 12])
        // A changed amount of the own budget leaves the group's list alone.
        let next = Self.log([Self.snapshot(at: Self.at(20), groups: ["x": Self.budget(32)],
                                           budgets: ["x": Self.budget(26, budget: 200, members: ["x"])])], from: base)
        #expect(Self.usedPercents(next, .group("x")) == [30, 31, 32])
        #expect(Self.usedPercents(next, .accountBudget("x")) == [13])
    }

    @Test func memberOrderDoesNotCount() {
        let base = Self.log([Self.snapshot(at: Self.at(0), groups: ["g": Self.budget(30, members: ["a", "b"])])])
        let next = Self.log([Self.snapshot(at: Self.at(10), groups: ["g": Self.budget(31, members: ["b", "a"])])], from: base)
        #expect(Self.usedPercents(next, .group("g")) == [30, 31])
    }

    /// A price change discards the observations of budgets only.
    @Test func priceChangeDiscardsBudgetsOnly() {
        func snap(_ minutes: Double, _ value: Double) -> UsageSnapshot {
            Self.snapshot(at: Self.at(minutes), subs: ["c": Self.claude(value, fetched: Self.at(minutes))],
                          groups: ["g": Self.budget(Decimal(value))], budgets: ["o": Self.budget(Decimal(value), members: ["o"])],
                          codex: ["x": Self.codex([CodexLimitWindow(lengthMinutes: 10080, usedPercent: value, resetsAt: Self.sevenReset)],
                                                  observed: Self.at(minutes))])
        }
        let base = Self.log([snap(0, 30)])
        let repriced = base.updated(with: snap(10, 31), budgetPricesChanged: true)
        #expect(Self.usedPercents(repriced, .group("g")) == [31])
        #expect(Self.usedPercents(repriced, .accountBudget("o")) == [31])
        #expect(Self.usedPercents(repriced, Self.seven) == [30, 31])
        #expect(Self.usedPercents(repriced, .codex("x", "weekly")) == [30, 31])
    }

    /// A stale budget entry adds nothing and keeps its observations, which
    /// the lookback prunes.
    @Test func staleBudgetAddsNothing() {
        let base = Self.log([Self.snapshot(at: Self.at(0), groups: ["g": Self.budget(30)])])
        let stale = Self.log([Self.snapshot(at: Self.at(10), groups: ["g": Self.budget(30, stale: true)])], from: base)
        #expect(stale.entries[.group("g")]?.map(\.observedAt) == [Self.at(0)])
        let later = Self.log([Self.snapshot(at: Self.at(61), groups: ["g": Self.budget(30, stale: true)])], from: stale)
        #expect(later.entries[.group("g")] == nil)
        // A stale entry whose window moved still discards (FR-003).
        let moved = DateInterval(start: Self.weekly.start, end: Self.weekly.end + 86_400)
        let staleMoved = Self.log([Self.snapshot(at: Self.at(10), groups: ["g": Self.budget(30, window: moved, stale: true)])], from: base)
        #expect(staleMoved.entries[.group("g")] == nil)
    }

    /// A key without a pace in the new snapshot, or no longer in it, is removed.
    @Test func keysWithoutPaceAreRemoved() {
        let base = Self.log([Self.snapshot(at: Self.at(0), subs: ["c": Self.claude(30, fetched: Self.at(0), five: 10)],
                                           groups: ["g": Self.budget(30), "e": Self.budget(30, members: ["z"])],
                                           codex: ["x": Self.codex([CodexLimitWindow(lengthMinutes: 300, usedPercent: 20, resetsAt: Self.at(120))],
                                                                   observed: Self.at(0))])])
        #expect(base.entries.count == 5)
        let next = Self.log([Self.snapshot(at: Self.at(10),
                                           // 7-day at 100%, 5-hour without a reset time (not started).
                                           subs: ["c": SubscriptionEntry(status: SubscriptionStatus(
                                               fiveHour: LimitWindow(utilizationPercent: 0, resetsAt: nil),
                                               sevenDay: LimitWindow(utilizationPercent: 100, resetsAt: Self.sevenReset),
                                               fetchedAt: Self.at(10)), state: .ok)],
                                           // An empty group; "g" disappeared.
                                           groups: ["e": Self.budget(0, members: [])],
                                           // The limit is reached.
                                           codex: ["x": Self.codex([CodexLimitWindow(lengthMinutes: 300, usedPercent: 25, resetsAt: Self.at(120),
                                                                                     limitReached: true)], observed: Self.at(10))])],
                            from: base)
        #expect(next.entries.isEmpty)
        #expect(next == ObservationLog())
    }

    /// Every kind of window is recorded under its key.
    @Test func everyWindowKindIsRecorded() {
        let limit = ModelLimit(modelName: "Fable", utilizationPercent: 20, resetsAt: Self.sevenReset)
        let log = Self.log([Self.snapshot(at: Self.at(0),
                                          subs: ["c": Self.claude(30, fetched: Self.at(0), five: 10, models: [limit])],
                                          groups: ["g": Self.budget(30)],
                                          budgets: ["o": Self.budget(10, members: ["o"])],
                                          codex: ["x": Self.codex([CodexLimitWindow(lengthMinutes: 300, usedPercent: 20, resetsAt: Self.at(120)),
                                                                   CodexLimitWindow(lengthMinutes: 10080, usedPercent: 30, resetsAt: Self.sevenReset)],
                                                                  observed: Self.at(0))])])
        #expect(Set(log.entries.keys) == [.claude("c", .fiveHour), .claude("c", .sevenDay), .claude("c", .model("Fable")),
                                          .codex("x", "5-hour"), .codex("x", "weekly"), .group("g"), .accountBudget("o")])
        let november = isoDate("2026-11-16T00:00:00Z")
        let monthly = Self.log([Self.snapshot(at: november, groups: ["g": Self.budget(30, window: Self.monthly, period: .monthly)])])
        #expect(monthly.entries[.group("g")]?.map(\.observedAt) == [november])
        #expect(monthly.entries[.group("g")]?.first?.resetsAt == Self.monthly.end)
    }

    // MARK: - Recent rate (FR-004, research R6)

    /// US1 AS1: 30% at 13:10, 36% at 14:00: 7.2 points per hour.
    @Test func storyOneScenarioOne() throws {
        let log = Self.claudeLog([(0, 30), (50, 36)])
        let recent = try #require(log.recentRate(for: Self.seven, now: Self.at(50)))
        #expect(abs(recent.perHour - 7.2) < 1e-9)
        #expect(recent.observedAt == Self.at(50))
        #expect(recent.usedPercent == 36)
    }

    /// US1 AS2: a change of 1 point is below the minimum.
    @Test func storyOneScenarioTwo() {
        let log = Self.claudeLog([(0, 30), (50, 31)])
        #expect(log.recentRate(for: Self.seven, now: Self.at(50)) == nil)
    }

    /// US1 AS3: a monthly budget at 37% 40 minutes before the snapshot and
    /// 40% at the snapshot: 4.5 points per hour.
    @Test func storyOneScenarioThreeBudget() throws {
        let snapshotAt = isoDate("2026-11-16T00:00:00Z")
        let log = Self.log([
            Self.snapshot(at: snapshotAt - 2400, groups: ["g": Self.budget(37, window: Self.monthly, period: .monthly)]),
            Self.snapshot(at: snapshotAt, groups: ["g": Self.budget(40, window: Self.monthly, period: .monthly)]),
        ])
        let recent = try #require(log.recentRate(for: .group("g"), now: snapshotAt))
        #expect(abs(recent.perHour - 4.5) < 1e-9)
    }

    /// US1 AS4: a span under 15 minutes gives no recent rate; exactly 15 does.
    @Test func storyOneScenarioFourMinimumSpan() {
        #expect(Self.claudeLog([(0, 30), (14, 36)]).recentRate(for: Self.seven, now: Self.at(14)) == nil)
        #expect(Self.claudeLog([(0, 30), (15, 36)]).recentRate(for: Self.seven, now: Self.at(15)) != nil)
    }

    /// The oldest and newest observations within the lookback count, not the
    /// neighbors; exactly 2 points qualifies.
    @Test func usesOldestAndNewestWithinTheLookback() throws {
        let log = Self.claudeLog([(0, 30), (20, 30.5), (40, 31), (50, 32)])
        let recent = try #require(log.recentRate(for: Self.seven, now: Self.at(50)))
        #expect(abs(recent.perHour - 2.4) < 1e-9)
        // Anchored at the snapshot: at 13:10 + 70 min only 20, 40 and 50 count.
        #expect(log.recentRate(for: Self.seven, now: Self.at(70)) == nil)
    }

    /// While Codex writes nothing new, its recent rate expires after an hour.
    @Test func quietCodexExpires() {
        func snap(_ used: Double, observed: Double, at minutes: Double) -> UsageSnapshot {
            Self.snapshot(at: Self.at(minutes), codex: ["x": Self.codex([CodexLimitWindow(lengthMinutes: 10080, usedPercent: used,
                                                                                         resetsAt: Self.sevenReset)],
                                                                        observed: Self.at(observed), state: .localOnly)])
        }
        let key = BurnWindowKey.codex("x", "weekly")
        let log = Self.log([snap(30, observed: 0, at: 0), snap(36, observed: 30, at: 30)])
        #expect(log.recentRate(for: key, now: Self.at(30)) != nil)
        let quiet = Self.log([snap(36, observed: 30, at: 61)], from: log)
        #expect(quiet.recentRate(for: key, now: Self.at(61)) == nil)
        #expect(quiet.entries[key]?.count == 1)
    }

    @Test func noRecentRateForUnknownKeys() {
        let log = Self.claudeLog([(0, 30), (50, 36)])
        #expect(log.recentRate(for: .claude("c", .fiveHour), now: Self.at(50)) == nil)
        #expect(log.recentRate(for: .group("c"), now: Self.at(50)) == nil)
    }

    /// The snapshot's burn rate uses the log it carries (spec 017 FR-004,
    /// research R10): US1 AS1 burns fast while behind.
    @Test func snapshotBurnRateUsesTheAttachedLog() throws {
        let log = Self.claudeLog([(0, 30), (50, 36)])
        var snapshot = Self.snapshot(at: Self.at(50), subs: ["c": Self.claude(36, fetched: Self.at(50))])
        #expect(snapshot.burnRate(for: Self.seven)?.burnsFast == false)
        snapshot.observations = log
        let burn = try #require(snapshot.burnRate(for: Self.seven))
        #expect(burn.burnsFast)
        #expect(abs(try #require(burn.recentPerHour) - 7.2) < 1e-9)
    }
}
