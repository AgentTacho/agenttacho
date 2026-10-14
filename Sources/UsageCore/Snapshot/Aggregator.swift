import Foundation

/// Turns records and subscription entries into a snapshot (FR-006, FR-008, FR-009).
public struct Aggregator: Sendable {
    private let resolver = WindowResolver()

    public init() {}

    /// `window` is the weekly window. `records` may reach further back (the
    /// collection window of spec 003 research R2); every budget owner (a
    /// group or an account with its own budget, spec 004 research R4), and
    /// its member accounts, is measured over its own window, while Unassigned
    /// and subscription breakdowns stay on the weekly window (spec 003
    /// FR-008, FR-009, research R3).
    ///
    /// `staleHarnesses` names harnesses whose records were carried over from
    /// an earlier read; every entry containing one of their records is marked
    /// stale (spec 006 FR-005, research R7).
    public func aggregate(records: [UsageRecord], subscriptions: [String: SubscriptionEntry],
                          configuration: Configuration, window: DateInterval, windowSource: WindowSource,
                          now: Date, calendar: Calendar, staleHarnesses: Set<Harness> = []) -> UsageSnapshot {
        func isStale(_ recs: [UsageRecord]) -> Bool {
            !staleHarnesses.isEmpty && recs.contains { staleHarnesses.contains($0.harness) }
        }
        let knownIds = Set(configuration.accounts.map(\.id))
        var byAccount: [String: [UsageRecord]] = [:]
        var unassignedRecords: [UsageRecord] = []
        for record in records {
            if let id = record.accountId, knownIds.contains(id) {
                byAccount[id, default: []].append(record)
            } else {
                unassignedRecords.append(record)
            }
        }

        let today = calendar.startOfDay(for: now)
        let month = resolver.monthWindow(now: now, calendar: calendar)
        /// The window of a group and the last day of its per-day trend: every
        /// day of the weekly window, or the 1st up to today for a monthly
        /// window (spec 003 FR-005, FR-013, research R6).
        func groupWindow(_ period: BudgetPeriod) -> (window: DateInterval, lastDay: Date) {
            switch period {
            case .weekly: return (window, lastDay(of: window, calendar: calendar))
            case .monthly: return (month, min(today, lastDay(of: month, calendar: calendar)))
            }
        }

        var tokenAccounts: [String: TokenAccountEntry] = [:]
        for account in configuration.tokenBasedAccounts {
            let period = configuration.budgetOwner(forAccount: account.id)?.budget.period ?? .weekly
            let (accountWindow, last) = groupWindow(period)
            let recs = Self.inWindow(byAccount[account.id] ?? [], accountWindow)
            tokenAccounts[account.id] = TokenAccountEntry(breakdown: breakdown(of: recs, priced: true, window: accountWindow, lastDay: last, calendar: calendar),
                                                          incomplete: recs.contains { !$0.isPriced },
                                                          stale: isStale(recs))
        }

        var groups: [String: GroupEntry] = [:]
        var accountBudgets: [String: GroupEntry] = [:]
        for owner in configuration.budgetOwners {
            let budget = owner.budget
            let (ownWindow, last) = groupWindow(budget.period)
            var memberSpend: [String: Decimal] = [:]
            var recs: [UsageRecord] = []
            for member in owner.memberIds {
                let memberRecs = Self.inWindow(byAccount[member] ?? [], ownWindow)
                memberSpend[member] = memberRecs.reduce(Decimal(0)) { $0 + ($1.costUSD ?? 0) }
                recs += memberRecs
            }
            let spent = recs.reduce(Decimal(0)) { $0 + ($1.costUSD ?? 0) }
            let entry = GroupEntry(spentUSD: spent,
                                   budgetUSD: budget.budgetUSD,
                                   percent: PercentFormatter.rounded(spent: spent, budget: budget.budgetUSD),
                                   incomplete: recs.contains { !$0.isPriced },
                                   period: budget.period,
                                   window: ownWindow,
                                   breakdown: breakdown(of: recs, priced: true, window: ownWindow, lastDay: last, calendar: calendar),
                                   members: owner.memberIds,
                                   memberSpendUSD: memberSpend,
                                   stale: isStale(recs))
            switch owner.kind {
            case .group: groups[owner.id] = entry
            case .account: accountBudgets[owner.id] = entry
            }
        }

        let weeklyLastDay = lastDay(of: window, calendar: calendar)
        var subscriptionEntries = subscriptions
        for (id, entry) in subscriptions {
            var copy = entry
            copy.breakdown = breakdown(of: Self.inWindow(byAccount[id] ?? [], window), priced: false, window: window,
                                       lastDay: weeklyLastDay, calendar: calendar)
            subscriptionEntries[id] = copy
        }

        // Codex subscription accounts: token counts over the weekly window,
        // no cost, no budget (spec 006 FR-017).
        var planAccounts: [String: TokenAccountEntry] = [:]
        for account in configuration.codexSubscriptionAccounts {
            let recs = Self.inWindow(byAccount[account.id] ?? [], window)
            planAccounts[account.id] = TokenAccountEntry(breakdown: breakdown(of: recs, priced: false, window: window,
                                                                              lastDay: weeklyLastDay, calendar: calendar),
                                                         incomplete: false, stale: isStale(recs))
        }

        let unassignedInWindow = Self.inWindow(unassignedRecords, window)
        return UsageSnapshot(generatedAt: now,
                             window: window,
                             windowSource: windowSource,
                             subscriptions: subscriptionEntries,
                             groups: groups,
                             accountBudgets: accountBudgets,
                             tokenAccounts: tokenAccounts,
                             planAccounts: planAccounts,
                             unassigned: TokenAccountEntry(breakdown: breakdown(of: unassignedInWindow, priced: false, window: window,
                                                                                lastDay: weeklyLastDay, calendar: calendar),
                                                           incomplete: false,
                                                           stale: isStale(unassignedInWindow)))
    }

    /// Start inclusive, end exclusive (FR-023).
    static func inWindow(_ records: [UsageRecord], _ window: DateInterval) -> [UsageRecord] {
        records.filter { $0.timestamp >= window.start && $0.timestamp < window.end }
    }

    /// Start of the local day containing `window.end - 1 s`.
    func lastDay(of window: DateInterval, calendar: Calendar) -> Date {
        calendar.startOfDay(for: window.end.addingTimeInterval(-1))
    }

    /// Per-model totals and the per-day trend. `priced: false` yields token
    /// counts only (subscription accounts, Unassigned).
    func breakdown(of records: [UsageRecord], priced: Bool, window: DateInterval, lastDay: Date, calendar: Calendar) -> UsageBreakdown {
        var perModel: [String: ModelUsage] = [:]
        for r in records {
            var m = perModel[r.canonicalModel] ?? ModelUsage(model: r.canonicalModel, costUSD: priced ? 0 : nil, priced: true)
            m.inputTokens += r.inputTokens
            m.outputTokens += r.outputTokens
            m.cacheWrite5mTokens += r.cacheWrite5mTokens
            m.cacheWrite1hTokens += r.cacheWrite1hTokens
            m.cacheReadTokens += r.cacheReadTokens
            m.reasoningTokens += r.reasoningTokens
            if priced {
                if let cost = r.costUSD, m.priced {
                    m.costUSD = (m.costUSD ?? 0) + cost
                } else {
                    m.priced = false
                    m.costUSD = nil
                }
            }
            perModel[r.canonicalModel] = m
        }
        let models = perModel.values.sorted { $0.model < $1.model }
        return UsageBreakdown(perModel: models,
                              perDay: perDay(of: records, priced: priced, window: window, lastDay: lastDay, calendar: calendar),
                              perProject: perProject(of: records, priced: priced),
                              unpricedModels: priced ? models.filter { !$0.priced }.map(\.model) : [],
                              perHarness: perHarness(of: records, priced: priced))
    }

    /// Per-harness totals (spec 006 FR-021): priced breakdowns ranked by
    /// priced cost, then tokens; token-only breakdowns by tokens; ties in
    /// harness declaration order.
    func perHarness(of records: [UsageRecord], priced: Bool) -> [HarnessUsage] {
        var byHarness: [Harness: (usage: HarnessUsage, pricedCost: Decimal)] = [:]
        for r in records {
            var entry = byHarness[r.harness] ?? (HarnessUsage(harness: r.harness, costUSD: priced ? 0 : nil), 0)
            entry.usage.totalTokens += r.totalTokens
            if priced {
                if let cost = r.costUSD {
                    entry.pricedCost += cost
                    if entry.usage.priced { entry.usage.costUSD = (entry.usage.costUSD ?? 0) + cost }
                } else {
                    entry.usage.priced = false
                    entry.usage.costUSD = nil
                }
            }
            byHarness[r.harness] = entry
        }
        let order = Dictionary(uniqueKeysWithValues: Harness.allCases.enumerated().map { ($1, $0) })
        return byHarness.values.sorted { a, b in
            if priced, a.pricedCost != b.pricedCost { return a.pricedCost > b.pricedCost }
            if a.usage.totalTokens != b.usage.totalTokens { return a.usage.totalTokens > b.usage.totalTokens }
            return order[a.usage.harness]! < order[b.usage.harness]!
        }.map(\.usage)
    }

    /// Per-project totals, ranked: priced breakdowns by priced cost, then
    /// tokens; token-only breakdowns by tokens; then name and path.
    func perProject(of records: [UsageRecord], priced: Bool) -> [ProjectUsage] {
        var byId: [String: ProjectUsage] = [:]
        for r in records {
            let id = r.project?.rootPath ?? ""
            var p = byId[id] ?? ProjectUsage(project: r.project, displayName: r.project?.name ?? "Unknown",
                                             costUSD: priced ? 0 : nil)
            p.totalTokens += r.totalTokens
            if priced {
                if let cost = r.costUSD {
                    p.pricedCostUSD += cost
                    if p.priced { p.costUSD = (p.costUSD ?? 0) + cost }
                } else {
                    p.priced = false
                    p.costUSD = nil
                }
            }
            byId[id] = p
        }

        var nameCounts: [String: Int] = [:]
        for p in byId.values {
            if let name = p.project?.name { nameCounts[name, default: 0] += 1 }
        }
        for (id, p) in byId {
            guard let project = p.project, (nameCounts[project.name] ?? 0) > 1 else { continue }
            let parent = ((project.rootPath as NSString).deletingLastPathComponent as NSString).lastPathComponent
            byId[id]?.displayName = "\(project.name) (\(parent))"
        }

        return byId.values.sorted { a, b in
            if priced, a.pricedCostUSD != b.pricedCostUSD { return a.pricedCostUSD > b.pricedCostUSD }
            if a.totalTokens != b.totalTokens { return a.totalTokens > b.totalTokens }
            if a.displayName != b.displayName { return a.displayName < b.displayName }
            return a.id < b.id
        }
    }

    /// One entry per local calendar day from the day containing `window.start`
    /// to `lastDay`, zero-filled (FR-008, T055). `lastDay` is the window's last
    /// day for weekly windows and today for monthly windows (spec 003 FR-013).
    func perDay(of records: [UsageRecord], priced: Bool, window: DateInterval, lastDay: Date, calendar: Calendar) -> [DayUsage] {
        let firstDay = calendar.startOfDay(for: window.start)
        var days: [DayUsage] = []
        var day = firstDay
        while day <= lastDay {
            days.append(DayUsage(day: day, costUSD: priced ? 0 : nil))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        guard !days.isEmpty else { return [] }
        var indexByDay: [Date: Int] = [:]
        for (i, d) in days.enumerated() { indexByDay[d.day] = i }
        for r in records {
            guard let i = indexByDay[calendar.startOfDay(for: r.timestamp)] else { continue }
            days[i].inputTokens += r.inputTokens
            days[i].outputTokens += r.outputTokens
            days[i].cacheWriteTokens += r.cacheWriteTokens
            days[i].cacheReadTokens += r.cacheReadTokens
            if priced, let cost = r.costUSD {
                days[i].costUSD = (days[i].costUSD ?? 0) + cost
            }
        }
        return days
    }
}
