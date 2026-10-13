import Foundation

/// Turns records and subscription entries into a snapshot (FR-006, FR-008, FR-009).
public struct Aggregator: Sendable {
    public init() {}

    public func aggregate(records: [UsageRecord], subscriptions: [String: SubscriptionEntry],
                          configuration: Configuration, window: DateInterval, windowSource: WindowSource,
                          now: Date, calendar: Calendar) -> UsageSnapshot {
        // Start inclusive, end exclusive (FR-023).
        let inWindow = records.filter { $0.timestamp >= window.start && $0.timestamp < window.end }

        let knownIds = Set(configuration.accounts.map(\.id))
        var byAccount: [String: [UsageRecord]] = [:]
        var unassignedRecords: [UsageRecord] = []
        for record in inWindow {
            if let id = record.accountId, knownIds.contains(id) {
                byAccount[id, default: []].append(record)
            } else {
                unassignedRecords.append(record)
            }
        }

        var tokenAccounts: [String: TokenAccountEntry] = [:]
        for account in configuration.tokenBasedAccounts {
            let recs = byAccount[account.id] ?? []
            tokenAccounts[account.id] = TokenAccountEntry(breakdown: breakdown(of: recs, priced: true, window: window, calendar: calendar),
                                                          incomplete: recs.contains { !$0.isPriced })
        }

        var groups: [String: GroupEntry] = [:]
        for group in configuration.groups {
            let members = configuration.members(of: group.id).map(\.id)
            let recs = members.flatMap { byAccount[$0] ?? [] }
            let spent = recs.reduce(Decimal(0)) { $0 + ($1.costUSD ?? 0) }
            groups[group.id] = GroupEntry(spentUSD: spent,
                                          budgetUSD: group.weeklyBudgetUSD,
                                          percent: PercentFormatter.rounded(spent: spent, budget: group.weeklyBudgetUSD),
                                          incomplete: recs.contains { !$0.isPriced },
                                          resetAt: window.end,
                                          breakdown: breakdown(of: recs, priced: true, window: window, calendar: calendar),
                                          members: members)
        }

        var subscriptionEntries = subscriptions
        for (id, entry) in subscriptions {
            var copy = entry
            copy.breakdown = breakdown(of: byAccount[id] ?? [], priced: false, window: window, calendar: calendar)
            subscriptionEntries[id] = copy
        }

        return UsageSnapshot(generatedAt: now,
                             window: window,
                             windowSource: windowSource,
                             subscriptions: subscriptionEntries,
                             groups: groups,
                             tokenAccounts: tokenAccounts,
                             unassigned: TokenAccountEntry(breakdown: breakdown(of: unassignedRecords, priced: false, window: window, calendar: calendar),
                                                           incomplete: false))
    }

    /// Per-model totals (and, from T055, the per-day trend). `priced: false`
    /// yields token counts only (subscription accounts, Unassigned).
    func breakdown(of records: [UsageRecord], priced: Bool, window: DateInterval, calendar: Calendar) -> UsageBreakdown {
        var perModel: [String: ModelUsage] = [:]
        for r in records {
            var m = perModel[r.canonicalModel] ?? ModelUsage(model: r.canonicalModel, costUSD: priced ? 0 : nil, priced: true)
            m.inputTokens += r.inputTokens
            m.outputTokens += r.outputTokens
            m.cacheWrite5mTokens += r.cacheWrite5mTokens
            m.cacheWrite1hTokens += r.cacheWrite1hTokens
            m.cacheReadTokens += r.cacheReadTokens
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
                              perDay: perDay(of: records, priced: priced, window: window, calendar: calendar),
                              unpricedModels: priced ? models.filter { !$0.priced }.map(\.model) : [])
    }

    /// One entry per local calendar day from the day containing `window.start`
    /// to the day containing `window.end - 1 s`, zero-filled (FR-008, T055).
    func perDay(of records: [UsageRecord], priced: Bool, window: DateInterval, calendar: Calendar) -> [DayUsage] {
        let firstDay = calendar.startOfDay(for: window.start)
        let lastDay = calendar.startOfDay(for: window.end.addingTimeInterval(-1))
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
