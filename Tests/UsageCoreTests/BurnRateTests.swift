import Foundation
import Testing
@testable import UsageCore

/// spec 017 FR-001, FR-002, FR-005 to FR-007, research R7: the sustainable
/// and average rates, the qualification rules and the fast run-out.
@Suite struct BurnRateTests {
    static let start = isoDate("2026-10-11T09:00:00Z")
    static let week = WindowResolver.weekSeconds
    static let reset = start.addingTimeInterval(week)
    static let hour: TimeInterval = 3600

    /// The burn rate of a 7-day window starting at `start`, observed after
    /// `elapsedShare` of the window, evaluated at the observation time.
    static func weekly(_ used: Double, elapsedShare: Double, recent: RecentRate? = nil, now: Date? = nil) throws -> BurnRate? {
        let observed = start.addingTimeInterval(week * elapsedShare)
        let now = now ?? observed
        let pace = try #require(Pace.compute(usedPercent: used, windowStart: start, resetsAt: reset, observedAt: observed, now: now))
        return BurnRate.compute(pace: pace, usedPercent: used, windowStart: start, resetsAt: reset,
                                observedAt: observed, now: now, recent: recent)
    }

    // MARK: - Rates (FR-001, FR-002)

    @Test func sustainableAndAverageRates() throws {
        let burn = try #require(try Self.weekly(40, elapsedShare: 0.5))
        // 60 points left over 84 hours; 40 points used in 84 hours.
        #expect(abs(burn.sustainablePerHour - 60.0 / 84) < 1e-9)
        #expect(abs(try #require(burn.averagePerHour) - 40.0 / 84) < 1e-9)
        #expect(burn.recentPerHour == nil)
        #expect(burn.fastRunOut == nil)
        #expect(!burn.burnsFast)
    }

    @Test func averageIsNilWithoutElapsedTime() throws {
        let burn = try #require(try Self.weekly(10, elapsedShare: 0))
        #expect(burn.averagePerHour == nil)
        #expect(!burn.burnsFast)
    }

    /// A future-dated observation (at or after the reset) leaves the
    /// sustainable rate undefined.
    @Test func nilWhenTheObservationIsAtOrAfterTheReset() throws {
        let pace = try #require(Pace.compute(usedPercent: 40, windowStart: Self.start, resetsAt: Self.reset,
                                             observedAt: Self.start, now: Self.start))
        #expect(BurnRate.compute(pace: pace, usedPercent: 40, windowStart: Self.start, resetsAt: Self.reset,
                                 observedAt: Self.reset, now: Self.start, recent: nil) == nil)
        #expect(BurnRate.compute(pace: pace, usedPercent: 40, windowStart: Self.start, resetsAt: Self.reset,
                                 observedAt: Self.reset.addingTimeInterval(60), now: Self.start, recent: nil) == nil)
    }

    @Test func constants() {
        #expect(BurnRate.factor == 2)
        #expect(BurnRate.lookback == 3600)
        #expect(BurnRate.minimumSpan == 900)
        #expect(BurnRate.minimumChange == 2)
    }

    // MARK: - Average rate (FR-005 to FR-007)

    /// Exactly twice the sustainable rate qualifies: a 75-hour window, 50%
    /// after 25 hours (2 points per hour) with 50 points over 50 hours left.
    @Test func averageAtExactlyTwiceQualifies() throws {
        let start = Self.start
        let reset = start.addingTimeInterval(75 * Self.hour)
        let observed = start.addingTimeInterval(25 * Self.hour)
        let pace = try #require(Pace.compute(usedPercent: 50, windowStart: start, resetsAt: reset, observedAt: observed, now: observed))
        let burn = try #require(BurnRate.compute(pace: pace, usedPercent: 50, windowStart: start, resetsAt: reset,
                                                 observedAt: observed, now: observed, recent: nil))
        #expect(burn.sustainablePerHour == 1)
        #expect(burn.averagePerHour == 2)
        #expect(burn.burnsFast)
        let fast = try #require(burn.fastRunOut)
        let runOut = try #require(pace.runOut)
        #expect(abs(fast.timeIntervalSince(runOut)) < 1)
        #expect(abs(fast.timeIntervalSince(observed.addingTimeInterval(25 * Self.hour))) < 1)
    }

    /// The average does not qualify without a counted spec 011 run-out, even
    /// at a high ratio: inside the 10% hold back.
    @Test func averageNeedsTheSpec011RunOut() throws {
        let burn = try #require(try Self.weekly(30, elapsedShare: 0.05))
        #expect(try #require(burn.averagePerHour) >= 2 * burn.sustainablePerHour)
        #expect(!burn.burnsFast)
    }

    /// US2 AS1: 62% with 43% elapsed, ratio about 2.2, burns fast; the fast
    /// run-out is spec 011's run-out to the second.
    @Test func storyTwoScenarioOne() throws {
        let observed = Self.start.addingTimeInterval(Self.week * 0.43)
        let pace = try #require(Pace.compute(usedPercent: 62, windowStart: Self.start, resetsAt: Self.reset,
                                             observedAt: observed, now: observed))
        let burn = try #require(try Self.weekly(62, elapsedShare: 0.43))
        let ratio = try #require(burn.averagePerHour) / burn.sustainablePerHour
        #expect(abs(ratio - 2.16) < 0.01)
        #expect(burn.burnsFast)
        let fast = try #require(burn.fastRunOut)
        #expect(abs(fast.timeIntervalSince(try #require(pace.runOut))) < 1)
    }

    /// US2 AS2: 55% with 45% elapsed is 10% ahead with a spec 011 run-out,
    /// but its average stays below twice the sustainable rate.
    @Test func storyTwoScenarioTwo() throws {
        let observed = Self.start.addingTimeInterval(Self.week * 0.45)
        let pace = try #require(Pace.compute(usedPercent: 55, windowStart: Self.start, resetsAt: Self.reset,
                                             observedAt: observed, now: observed))
        #expect(pace.runOut != nil)
        let burn = try #require(try Self.weekly(55, elapsedShare: 0.45))
        #expect(!burn.burnsFast)
        #expect(burn.fastRunOut == nil)
    }

    /// A pace whose run-out the caller computed earlier, with a snapshot time
    /// after the average run-out: the average does not qualify (FR-007).
    @Test func averageRunOutAtOrBeforeTheSnapshotDoesNotQualify() throws {
        let start = Self.start
        let reset = start.addingTimeInterval(75 * Self.hour)
        let observed = start.addingTimeInterval(25 * Self.hour)
        let runOut = observed.addingTimeInterval(25 * Self.hour)
        let pace = Pace(expectedPercent: 33, delta: 17, status: .ahead(17), runOut: runOut)
        let atRunOut = try #require(BurnRate.compute(pace: pace, usedPercent: 50, windowStart: start, resetsAt: reset,
                                                     observedAt: observed, now: runOut, recent: nil))
        #expect(!atRunOut.burnsFast)
        let before = try #require(BurnRate.compute(pace: pace, usedPercent: 50, windowStart: start, resetsAt: reset,
                                                   observedAt: observed, now: runOut.addingTimeInterval(-60), recent: nil))
        #expect(before.burnsFast)
    }

    // MARK: - Recent rate (FR-004 to FR-007)

    /// US1 AS1: 30% at 13:10 and 36% at 14:00 is 7.2 points per hour, with
    /// 66 hours to the reset (sustainable 64 / 66): burns fast while behind.
    @Test func storyOneScenarioOne() throws {
        let observed = isoDate("2026-10-14T14:00:00Z")
        let reset = observed.addingTimeInterval(66 * Self.hour)
        let start = reset.addingTimeInterval(-Self.week)
        let pace = try #require(Pace.compute(usedPercent: 36, windowStart: start, resetsAt: reset, observedAt: observed, now: observed))
        guard case .behind = pace.status else { Issue.record("expected behind, got \(pace.status)"); return }
        let recent = RecentRate(perHour: 7.2, observedAt: observed, usedPercent: 36)
        let burn = try #require(BurnRate.compute(pace: pace, usedPercent: 36, windowStart: start, resetsAt: reset,
                                                 observedAt: observed, now: observed, recent: recent))
        #expect(burn.recentPerHour == 7.2)
        #expect(burn.burnsFast)
        // 64 points at 7.2 per hour: 8 h 53 min 20 s.
        #expect(burn.fastRunOut == observed.addingTimeInterval(64 / 7.2 * Self.hour))
    }

    /// US1 AS2: 1.2 points per hour at 31% with 66 hours left is below
    /// twice the sustainable rate (69 / 66 = 1.05, doubled 2.09).
    @Test func storyOneScenarioTwo() throws {
        let observed = isoDate("2026-10-14T14:00:00Z")
        let reset = observed.addingTimeInterval(66 * Self.hour)
        let start = reset.addingTimeInterval(-Self.week)
        let pace = try #require(Pace.compute(usedPercent: 31, windowStart: start, resetsAt: reset, observedAt: observed, now: observed))
        let recent = RecentRate(perHour: 1.2, observedAt: observed, usedPercent: 31)
        let burn = try #require(BurnRate.compute(pace: pace, usedPercent: 31, windowStart: start, resetsAt: reset,
                                                 observedAt: observed, now: observed, recent: recent))
        #expect(burn.recentPerHour == 1.2)
        #expect(!burn.burnsFast)
    }

    /// US1 AS3: a monthly budget with half of a 30-day month elapsed, 40% at
    /// the snapshot, recent 4.5 points per hour with 360 hours left.
    @Test func storyOneScenarioThreeBudget() throws {
        let start = isoDate("2026-11-01T00:00:00Z")
        let reset = start.addingTimeInterval(720 * Self.hour)
        let observed = start.addingTimeInterval(360 * Self.hour)
        let pace = try #require(Pace.compute(usedPercent: 40, windowStart: start, resetsAt: reset, observedAt: observed, now: observed))
        #expect(pace.runOut == nil)
        let recent = RecentRate(perHour: 4.5, observedAt: observed, usedPercent: 40)
        let burn = try #require(BurnRate.compute(pace: pace, usedPercent: 40, windowStart: start, resetsAt: reset,
                                                 observedAt: observed, now: observed, recent: recent))
        #expect(burn.burnsFast)
        #expect(burn.fastRunOut == observed.addingTimeInterval(60 / 4.5 * Self.hour))
    }

    /// The recent rate qualifies on pace and inside the hold back too.
    @Test func recentQualifiesOnPaceAndInsideTheHoldBack() throws {
        let onPaceAt = Self.start.addingTimeInterval(Self.week * 0.5)
        let onPace = try #require(try Self.weekly(50, elapsedShare: 0.5,
                                                  recent: RecentRate(perHour: 5, observedAt: onPaceAt, usedPercent: 50)))
        #expect(onPace.burnsFast)
        let earlyAt = Self.start.addingTimeInterval(Self.week * 0.05)
        let early = try #require(try Self.weekly(9, elapsedShare: 0.05,
                                                 recent: RecentRate(perHour: 6, observedAt: earlyAt, usedPercent: 9)))
        #expect(early.burnsFast)
    }

    /// Exactly twice qualifies: 50 points over 50 hours, 2 points per hour.
    @Test func recentAtExactlyTwiceQualifies() throws {
        let observed = isoDate("2026-10-14T12:00:00Z")
        let reset = observed.addingTimeInterval(50 * Self.hour)
        let start = reset.addingTimeInterval(-Self.week)
        let pace = try #require(Pace.compute(usedPercent: 50, windowStart: start, resetsAt: reset, observedAt: observed, now: observed))
        func burn(_ perHour: Double) throws -> BurnRate {
            try #require(BurnRate.compute(pace: pace, usedPercent: 50, windowStart: start, resetsAt: reset, observedAt: observed,
                                          now: observed, recent: RecentRate(perHour: perHour, observedAt: observed, usedPercent: 50)))
        }
        #expect(try burn(2).burnsFast)
        #expect(try !burn(1.99).burnsFast)
    }

    /// A recent run-out at or before the snapshot time does not qualify: 50%
    /// at 10 points per hour runs out 5 hours after the observation.
    @Test func recentRunOutAtOrBeforeTheSnapshotDoesNotQualify() throws {
        let observed = isoDate("2026-10-14T12:00:00Z")
        let reset = observed.addingTimeInterval(50 * Self.hour)
        let start = reset.addingTimeInterval(-Self.week)
        let recent = RecentRate(perHour: 10, observedAt: observed, usedPercent: 50)
        func burn(now: Date) throws -> BurnRate {
            let pace = try #require(Pace.compute(usedPercent: 50, windowStart: start, resetsAt: reset, observedAt: observed, now: now))
            return try #require(BurnRate.compute(pace: pace, usedPercent: 50, windowStart: start, resetsAt: reset,
                                                 observedAt: observed, now: now, recent: recent))
        }
        let runOut = observed.addingTimeInterval(5 * Self.hour)
        #expect(try !burn(now: runOut).burnsFast)
        #expect(try burn(now: runOut).fastRunOut == nil)
        #expect(try burn(now: runOut.addingTimeInterval(-60)).fastRunOut == runOut)
    }

    // MARK: - Both rates (FR-007)

    /// When both qualify, the earlier run-out wins.
    @Test func earlierRunOutWins() throws {
        let observed = Self.start.addingTimeInterval(Self.week * 0.43)
        let average = try #require(try Self.weekly(62, elapsedShare: 0.43))
        let averageRunOut = try #require(average.fastRunOut)
        // 38 points at 10 per hour: 3.8 hours, earlier than the average run-out.
        let faster = try #require(try Self.weekly(62, elapsedShare: 0.43,
                                                  recent: RecentRate(perHour: 10, observedAt: observed, usedPercent: 62)))
        #expect(faster.fastRunOut == observed.addingTimeInterval(3.8 * Self.hour))
        #expect(try #require(faster.fastRunOut) < averageRunOut)
        // A recent rate that qualifies but runs out later than the average.
        let slower = try #require(try Self.weekly(62, elapsedShare: 0.43,
                                                  recent: RecentRate(perHour: 0.85, observedAt: observed, usedPercent: 62)))
        #expect(slower.fastRunOut == averageRunOut)
    }

    /// FR-007: the recent rate is measured against the newest observation
    /// within the lookback, not the entry's own value: 65 points left at
    /// 7.2 per hour from 10 minutes before the entry's observation.
    @Test func recentRunOutIsAnchoredAtTheNewestObservation() throws {
        let observed = isoDate("2026-10-14T14:00:00Z")
        let reset = observed.addingTimeInterval(66 * Self.hour)
        let start = reset.addingTimeInterval(-Self.week)
        let pace = try #require(Pace.compute(usedPercent: 36, windowStart: start, resetsAt: reset, observedAt: observed, now: observed))
        let newest = observed.addingTimeInterval(-600)
        let burn = try #require(BurnRate.compute(pace: pace, usedPercent: 36, windowStart: start, resetsAt: reset, observedAt: observed,
                                                 now: observed, recent: RecentRate(perHour: 7.2, observedAt: newest, usedPercent: 35)))
        #expect(burn.fastRunOut == newest.addingTimeInterval(65 / 7.2 * Self.hour))
    }

    @Test func burnsFastFollowsTheFastRunOut() throws {
        let fast = try #require(try Self.weekly(62, elapsedShare: 0.43))
        #expect(fast.burnsFast == (fast.fastRunOut != nil))
        let slow = try #require(try Self.weekly(40, elapsedShare: 0.5))
        #expect(slow.burnsFast == (slow.fastRunOut != nil))
        #expect(!slow.burnsFast)
    }
}

/// spec 017 research R10: `UsageSnapshot.burnRate(for:)` resolves a key to
/// the same inputs the pace accessors use.
@Suite struct SnapshotBurnRateTests {
    static let now = isoDate("2026-10-14T12:00:00Z")
    static let fetched = now.addingTimeInterval(-120)
    static let hour: TimeInterval = 3600
    static let week = WindowResolver.weekSeconds
    static let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))

    static func snapshot(subscriptions: [String: SubscriptionEntry] = [:], groups: [String: GroupEntry] = [:],
                         accountBudgets: [String: GroupEntry] = [:], codexLimits: [String: CodexLimitsEntry] = [:]) -> UsageSnapshot {
        UsageSnapshot(generatedAt: now, window: window, windowSource: .fallback, subscriptions: subscriptions,
                      groups: groups, accountBudgets: accountBudgets, codexLimits: codexLimits)
    }

    static func claude(_ status: SubscriptionStatus) -> UsageSnapshot {
        snapshot(subscriptions: ["c": SubscriptionEntry(status: status, state: .ok)])
    }

    /// The burn rate computed by hand from the pace inputs.
    static func expected(pace: Pace?, used: Double, start: Date, reset: Date, observed: Date) -> BurnRate? {
        pace.flatMap { BurnRate.compute(pace: $0, usedPercent: used, windowStart: start, resetsAt: reset,
                                        observedAt: observed, now: now, recent: nil) }
    }

    @Test func claudeSevenDayUsesTheFetchTime() throws {
        // 62% with 3/7 of the week elapsed at the fetch time: burns fast (US2).
        let reset = Self.fetched.addingTimeInterval(4 * 24 * Self.hour)
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 62, resetsAt: reset), fetchedAt: Self.fetched)
        let burn = try #require(Self.claude(status).burnRate(for: .claude("c", .sevenDay)))
        let expected = Self.expected(pace: status.sevenDayPace(now: Self.now), used: 62,
                                     start: reset.addingTimeInterval(-Self.week), reset: reset, observed: Self.fetched)
        #expect(burn == expected)
        #expect(burn.burnsFast)
        #expect(burn.recentPerHour == nil)
    }

    @Test func claudeFiveHourAndModelLimit() throws {
        let fiveReset = Self.fetched.addingTimeInterval(2.5 * Self.hour)
        let modelReset = Self.fetched.addingTimeInterval(3.5 * 24 * Self.hour)
        let limit = ModelLimit(modelName: "Fable", utilizationPercent: 30, resetsAt: modelReset)
        let status = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 70, resetsAt: fiveReset),
                                        sevenDay: LimitWindow(utilizationPercent: 20, resetsAt: modelReset),
                                        modelLimits: [limit], fetchedAt: Self.fetched)
        let snapshot = Self.claude(status)
        let five = try #require(snapshot.burnRate(for: .claude("c", .fiveHour)))
        #expect(five == Self.expected(pace: status.fiveHourPace(now: Self.now), used: 70,
                                      start: fiveReset.addingTimeInterval(-Pace.fiveHourSeconds), reset: fiveReset, observed: Self.fetched))
        let model = try #require(snapshot.burnRate(for: .claude("c", .model("Fable"))))
        #expect(model == Self.expected(pace: status.pace(of: limit, now: Self.now), used: 30,
                                       start: modelReset.addingTimeInterval(-Self.week), reset: modelReset, observed: Self.fetched))
        #expect(snapshot.burnRate(for: .claude("c", .model("Other"))) == nil)
        #expect(snapshot.burnRate(for: .claude("x", .sevenDay)) == nil)
    }

    /// No pace, no burn rate: a window that has not started, at or above
    /// 100%, or reset at the snapshot time.
    @Test func claudeWithoutPaceHasNoBurnRate() {
        let notStarted = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 0, resetsAt: nil),
                                            sevenDay: LimitWindow(utilizationPercent: 100, resetsAt: Self.now.addingTimeInterval(Self.hour)),
                                            modelLimits: [ModelLimit(modelName: "Fable", utilizationPercent: 40, resetsAt: Self.now)],
                                            fetchedAt: Self.fetched)
        let snapshot = Self.claude(notStarted)
        #expect(snapshot.burnRate(for: .claude("c", .fiveHour)) == nil)
        #expect(snapshot.burnRate(for: .claude("c", .sevenDay)) == nil)
        #expect(snapshot.burnRate(for: .claude("c", .model("Fable"))) == nil)
        let noStatus = Self.snapshot(subscriptions: ["c": SubscriptionEntry(status: nil, state: .notSignedIn)])
        #expect(noStatus.burnRate(for: .claude("c", .sevenDay)) == nil)
    }

    @Test func codexResolvesTheWindowByName() throws {
        let observed = Self.now.addingTimeInterval(-600)
        let fiveReset = Self.now.addingTimeInterval(4 * Self.hour)
        let weekReset = Self.now.addingTimeInterval(3 * 24 * Self.hour)
        let observation = CodexLimitObservation(planType: "plus", observedAt: observed, origin: .live, windows: [
            CodexLimitWindow(lengthMinutes: 300, usedPercent: 50, resetsAt: fiveReset),
            CodexLimitWindow(lengthMinutes: 10080, usedPercent: 40, resetsAt: weekReset),
            CodexLimitWindow(lengthMinutes: 600, usedPercent: 10, resetsAt: Self.now.addingTimeInterval(Self.hour), limitReached: true),
        ])
        let entry = CodexLimitsEntry(observation: observation, state: .live)
        let snapshot = Self.snapshot(codexLimits: ["x": entry])
        let windows = entry.windows(now: Self.now)
        let five = try #require(windows.first { $0.name == "5-hour" })
        let weekly = try #require(windows.first { $0.name == "weekly" })
        #expect(try #require(snapshot.burnRate(for: .codex("x", "5-hour")))
                == Self.expected(pace: entry.pace(of: five, now: Self.now), used: 50,
                                 start: fiveReset.addingTimeInterval(-300 * 60), reset: fiveReset, observed: observed))
        #expect(try #require(snapshot.burnRate(for: .codex("x", "weekly")))
                == Self.expected(pace: entry.pace(of: weekly, now: Self.now), used: 40,
                                 start: weekReset.addingTimeInterval(-Self.week), reset: weekReset, observed: observed))
        // Limit reached, unknown window, unknown account.
        #expect(snapshot.burnRate(for: .codex("x", "10-hour")) == nil)
        #expect(snapshot.burnRate(for: .codex("x", "2-day")) == nil)
        #expect(snapshot.burnRate(for: .codex("y", "weekly")) == nil)
        let unavailable = Self.snapshot(codexLimits: ["x": CodexLimitsEntry(observation: nil, state: .unavailable(reason: "none"))])
        #expect(unavailable.burnRate(for: .codex("x", "weekly")) == nil)
    }

    /// A group and an account with its own budget may share an id (spec
    /// 008); each key reads its own entry.
    @Test func groupAndOwnBudgetWithTheSameIdStaySeparate() throws {
        let group = GroupEntry(spentUSD: 40, budgetUSD: 100, percent: 40, incomplete: false, window: Self.window,
                               breakdown: .empty, members: ["a"])
        let own = GroupEntry(spentUSD: 62, budgetUSD: 100, percent: 62, incomplete: false, window: Self.window,
                             breakdown: .empty, members: ["x"])
        let snapshot = Self.snapshot(groups: ["x": group], accountBudgets: ["x": own])
        #expect(Set(snapshot.paceKeys) == [.group("x"), .accountBudget("x")])
        #expect(try #require(snapshot.burnRate(for: .group("x"))).burnsFast == false)
        #expect(try #require(snapshot.burnRate(for: .accountBudget("x"))).burnsFast)
    }

    @Test func budgetKeysReadGroupsAndAccountBudgets() throws {
        // 40 of 100 dollars with 2.5 of 7 days elapsed: 4% ahead, no run-out.
        let group = GroupEntry(spentUSD: 40, budgetUSD: 100, percent: 40, incomplete: false, window: Self.window,
                               breakdown: .empty, members: ["a"])
        // 62 of 100 dollars: far ahead, burns fast by the average.
        let own = GroupEntry(spentUSD: 62, budgetUSD: 100, percent: 62, incomplete: false, window: Self.window,
                             breakdown: .empty, members: ["b"])
        let snapshot = Self.snapshot(groups: ["g": group], accountBudgets: ["b": own])
        let g = try #require(snapshot.burnRate(for: .group("g")))
        #expect(g == Self.expected(pace: group.pace(now: Self.now), used: 40, start: Self.window.start, reset: Self.window.end, observed: Self.now))
        #expect(!g.burnsFast)
        let b = try #require(snapshot.burnRate(for: .accountBudget("b")))
        #expect(b == Self.expected(pace: own.pace(now: Self.now), used: 62, start: Self.window.start, reset: Self.window.end, observed: Self.now))
        #expect(b.burnsFast)
        #expect(snapshot.burnRate(for: .group("z")) == nil)
    }

    @Test func budgetWithoutPaceHasNoBurnRate() {
        let empty = GroupEntry(spentUSD: 0, budgetUSD: 100, percent: 0, incomplete: false, window: Self.window,
                               breakdown: .empty, members: [])
        let over = GroupEntry(spentUSD: 120, budgetUSD: 100, percent: 120, incomplete: false, window: Self.window,
                              breakdown: .empty, members: ["a"])
        let snapshot = Self.snapshot(groups: ["e": empty, "o": over])
        #expect(snapshot.burnRate(for: .group("e")) == nil)
        #expect(snapshot.burnRate(for: .group("o")) == nil)
    }

    /// SC-002: for every entry kind the decision and the fast run-out match
    /// a hand calculation from the observed values to within one minute.
    @Test func handCalculatedFastRunOutPerKind() throws {
        func expectRunOut(_ burn: BurnRate?, _ expected: Date, _ kind: String) throws {
            let runOut = try #require(burn?.fastRunOut, "\(kind)")
            #expect(abs(runOut.timeIntervalSince(expected)) < 60, "\(kind)")
        }
        // Claude 5-hour: 70% after 2.5 of 5 hours is 28 points per hour
        // against 30 / 2.5 = 12 sustainable; 30 points left last 64.3 min.
        // Model limit: 80% after 3.5 of 7 days, 20 points left at 80 / 84 h
        // last 21 hours (sustainable 20 / 84 h, ratio 4).
        let fiveReset = Self.fetched.addingTimeInterval(2.5 * Self.hour)
        let modelReset = Self.fetched.addingTimeInterval(84 * Self.hour)
        let status = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 70, resetsAt: fiveReset),
                                        sevenDay: LimitWindow(utilizationPercent: 20, resetsAt: modelReset),
                                        modelLimits: [ModelLimit(modelName: "Fable", utilizationPercent: 80, resetsAt: modelReset)],
                                        fetchedAt: Self.fetched)
        let claude = Self.claude(status)
        try expectRunOut(claude.burnRate(for: .claude("c", .fiveHour)), Self.fetched.addingTimeInterval(64.2857 * 60), "5-hour")
        try expectRunOut(claude.burnRate(for: .claude("c", .model("Fable"))), Self.fetched.addingTimeInterval(21 * Self.hour), "model")
        // 7-day: 20% after 3.5 days is behind, no fast burn.
        #expect(claude.burnRate(for: .claude("c", .sevenDay))?.burnsFast == false)

        // Codex 5-hour: 50% after 50 minutes is 60 points per hour against
        // 50 / 4 h 10 min = 12; 50 points left last 50 minutes. Weekly: 40%
        // after 95.8 h (0.42 per hour) against 60 / 72.2 h (0.83): not fast.
        let observed = Self.now.addingTimeInterval(-600)
        let codex = Self.snapshot(codexLimits: ["x": CodexLimitsEntry(observation: CodexLimitObservation(
            planType: "plus", observedAt: observed, origin: .live, windows: [
                CodexLimitWindow(lengthMinutes: 300, usedPercent: 50, resetsAt: Self.now.addingTimeInterval(4 * Self.hour)),
                CodexLimitWindow(lengthMinutes: 10080, usedPercent: 40, resetsAt: Self.now.addingTimeInterval(72 * Self.hour)),
            ]), state: .live)])
        try expectRunOut(codex.burnRate(for: .codex("x", "5-hour")), observed.addingTimeInterval(50 * 60), "Codex 5-hour")
        #expect(codex.burnRate(for: .codex("x", "weekly"))?.burnsFast == false)

        // Weekly budget: 62 of 100 dollars after 60 of 168 hours, 1.03 per
        // hour against 38 / 108 h; 38 points left last 36.77 hours.
        let weekly = GroupEntry(spentUSD: 62, budgetUSD: 100, percent: 62, incomplete: false, window: Self.window,
                                breakdown: .empty, members: ["a"])
        // Monthly budget: 70 of 100 dollars after 324 of 744 hours, 0.216
        // per hour against 30 / 420 h; 30 points left last 138.86 hours.
        let october = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))
        let monthly = GroupEntry(spentUSD: 70, budgetUSD: 100, percent: 70, incomplete: false, period: .monthly, window: october,
                                 breakdown: .empty, members: ["a"])
        let budgets = Self.snapshot(groups: ["w": weekly], accountBudgets: ["m": monthly])
        try expectRunOut(budgets.burnRate(for: .group("w")), Self.now.addingTimeInterval(36.7742 * Self.hour), "weekly budget")
        try expectRunOut(budgets.burnRate(for: .accountBudget("m")), Self.now.addingTimeInterval(138.857 * Self.hour), "monthly budget")
    }

    /// With an empty observation log only the average can make it burn fast:
    /// a 7-day window behind even use does not.
    @Test func emptyLogHasNoRecentRate() throws {
        let reset = Self.fetched.addingTimeInterval(66 * Self.hour)
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 36, resetsAt: reset), fetchedAt: Self.fetched)
        let snapshot = Self.claude(status)
        #expect(snapshot.observations == ObservationLog())
        let burn = try #require(snapshot.burnRate(for: .claude("c", .sevenDay)))
        #expect(burn.recentPerHour == nil)
        #expect(!burn.burnsFast)
    }
}
