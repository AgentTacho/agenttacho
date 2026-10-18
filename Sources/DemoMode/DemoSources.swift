import Foundation
import UsageCore

// The three demo sources (spec 024 FR-006, research R3). One per kind of
// value, because a source returns one `SourceOutput` case per refresh. All
// three read the same `ScenarioPlayer`, so they see the same frames. None is
// network bound, endpoint gated, window sensitive or restores saved values,
// so the coordinator collects them on every refresh like a log scan.

/// The Claude plan windows of the scenario's subscription accounts, as
/// fetched at the refresh time (spec 024 FR-006, FR-011).
public struct DemoSubscriptionSource: UsageSource {
    public static let sourceName = "demoSubscriptions"
    public let name = DemoSubscriptionSource.sourceName
    private let player: ScenarioPlayer

    public init(player: ScenarioPlayer) {
        self.player = player
    }

    /// One `.ok` entry per configured subscription account the scenario has
    /// windows for, fetched at `context.now`, with the reset times fixed to
    /// launch.
    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let state = await player.state(at: context.now)
        let configured = Set(context.configuration.subscriptionAccounts.map(\.id))
        var entries: [String: SubscriptionEntry] = [:]
        for (id, windows) in state.claude where configured.contains(id) {
            let models = (windows.models ?? [:]).keys.sorted().map { name in
                let value = windows.models![name]!
                return ModelLimit(modelName: name, utilizationPercent: value.used, resetsAt: player.launch.addingTimeInterval(value.resetsIn.seconds))
            }
            let status = SubscriptionStatus(
                fiveHour: LimitWindow(utilizationPercent: windows.fiveHour.used, resetsAt: await player.resetDate(windows.fiveHour)),
                sevenDay: LimitWindow(utilizationPercent: windows.sevenDay.used, resetsAt: await player.resetDate(windows.sevenDay)),
                modelLimits: models, subscriptionType: windows.plan, fetchedAt: context.now)
            entries[id] = SubscriptionEntry(status: status, state: .ok, fetchOutcome: .success)
        }
        return .subscriptions(entries)
    }
}

/// The Codex plan limits of the scenario's Codex subscription accounts, as a
/// live result observed at the refresh time (spec 024 FR-006). The
/// scenario's configuration sets `liveLimits`, so the threshold tracker
/// takes them like real live limits.
public struct DemoCodexLimitsSource: UsageSource {
    public static let sourceName = "demoCodexLimits"
    public let name = DemoCodexLimitsSource.sourceName
    private let player: ScenarioPlayer

    public init(player: ScenarioPlayer) {
        self.player = player
    }

    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let state = await player.state(at: context.now)
        let configured = Set(context.configuration.codexSubscriptionAccounts.map(\.id))
        var entries: [String: CodexLimitsEntry] = [:]
        for (id, limits) in state.codex where configured.contains(id) {
            var windows: [CodexLimitWindow] = []
            for value in limits.windows {
                windows.append(CodexLimitWindow(lengthMinutes: value.lengthMinutes, usedPercent: value.used,
                                                resetsAt: await player.resetDate(value)))
            }
            let observation = CodexLimitObservation(planType: limits.plan, observedAt: context.now, origin: .live,
                                                    windows: CodexLimitWindow.applyingReachedRule(windows, sourceReportsReached: false))
            entries[id] = CodexLimitsEntry(observation: observation, state: .live)
        }
        return .codexLimits(entries)
    }
}

/// The scenario's token usage records, priced like the session log source
/// prices real records (spec 024 FR-006, FR-010, research R6, R7).
public struct DemoRecordSource: UsageSource {
    public static let sourceName = "demoRecords"
    public let name = DemoRecordSource.sourceName
    private let player: ScenarioPlayer
    private let builtInPrices: PriceTable
    /// The imported layer of the price table, read on every refresh, so an
    /// import in the demo's Settings reprices like in the real app.
    private let importedPrices: @Sendable () -> ImportedPrices
    /// The calendar of the refresh coordinator, for the start of the month.
    private let calendar: Calendar

    public init(player: ScenarioPlayer, builtInPrices: PriceTable, importedPrices: @escaping @Sendable () -> ImportedPrices,
                calendar: Calendar = .autoupdatingCurrent) {
        self.player = player
        self.builtInPrices = builtInPrices
        self.importedPrices = importedPrices
        self.calendar = calendar
    }

    /// Every record of the scenario at `context.now`, at `launch + at`. The
    /// window is not applied: the aggregator measures every budget over its
    /// own window. The message id `<scenario>-<index>` stays the same across
    /// refreshes.
    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let state = await player.state(at: context.now)
        let launch = player.launch
        let name = player.scenario.name
        let pricer = PriceTable.effective(builtIn: builtInPrices, imported: importedPrices(),
                                          overrides: context.configuration.priceOverrides)
        let monthStart = calendar.dateInterval(of: .month, for: launch)?.start ?? launch
        let records = state.usage.enumerated().map { index, entry in
            var timestamp = launch.addingTimeInterval(entry.at.seconds)
            if context.configuration.budgetOwner(forAccount: entry.account)?.budget.period == .monthly, timestamp < monthStart {
                timestamp = movedIntoMonth(timestamp, monthStart: monthStart, launch: launch)
            }
            let id = "\(name)-\(index)"
            let cost = pricer.cost(model: entry.model, input: entry.input, output: entry.output, cacheWrite5m: entry.cacheWrite,
                                   cacheWrite1h: 0, cacheRead: entry.cacheRead)
            return UsageRecord(messageId: id, timestamp: timestamp, model: entry.model,
                               canonicalModel: PriceTable.canonicalModel(entry.model), requestId: id, accountId: entry.account,
                               inputTokens: entry.input, outputTokens: entry.output, cacheWrite5mTokens: entry.cacheWrite,
                               cacheWrite1hTokens: 0, cacheReadTokens: entry.cacheRead, costUSD: cost,
                               project: Project(rootPath: entry.project), harness: entry.harness)
        }
        return .records(records)
    }

    /// A monthly budget sums the current calendar month only, so a capture
    /// on the 1st would show an almost empty budget. A record from before
    /// the month moves to the 1st at the same time of day; the total stays,
    /// only the per-day trend changes (research R6). A time of day after
    /// the launch time would put it in the future, so it goes to the start
    /// of the month then.
    private func movedIntoMonth(_ timestamp: Date, monthStart: Date, launch: Date) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: timestamp)
        guard let moved = calendar.date(byAdding: time, to: monthStart), moved <= launch else { return monthStart }
        return moved
    }
}
