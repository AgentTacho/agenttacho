import Foundation
import UsageCore

/// What a scenario shows once it has played, computed by the app's own
/// logic (spec 024 FR-016, data-model "Coverage").
public struct CoverageReport: Sendable {
    /// Bar levels after the last frame.
    public let levels: Set<BarLevel>
    /// `↗` and `↑` markers in the bar after the last frame.
    public let markers: Set<String>
    /// Pace states of the dropdown's rows after the last frame, as their
    /// bar ticks and notes show them (spec 025 FR-002): `onPace`, `behind`,
    /// `ahead`.
    public let paceStates: Set<String>
    /// Names of budget owners and ids of token accounts marked incomplete.
    public let incompleteOwners: [String]
    /// Harnesses with usage in any breakdown.
    public let harnesses: Set<Harness>
    /// Rows that call for attention after the last frame, the ones with an
    /// orange note (spec 025 FR-004, FR-035).
    public let attentionRows: [BurnWindowKey]
    /// Names of groups with exactly one member, shown without a member line
    /// (spec 025 FR-010).
    public let singleMemberGroups: [String]
    /// Display names of accounts and names of groups whose times read
    /// absolute (spec 025 FR-021).
    public let absoluteTimeOwners: [String]
    /// Threshold crossings from the launch refresh to the last frame, as
    /// `<display name>@<threshold>`, in order.
    public let crossings: [String]
    /// Each group's member lines and member tables by group name, as the
    /// budget section shows them (spec 026 FR-007).
    public let memberDisplays: [String: MemberDisplay]
    /// The tag of each bar entry that shows one, by entry id (spec 027
    /// FR-008, FR-015).
    public let barTags: [String: String]
    /// The value of each bar entry by entry id ("58%"), so the coverage
    /// test can check the value under a tag (spec 027 FR-015).
    public let barValues: [String: String]
    /// The name of each Claude and Codex subscription's headline row, the
    /// row with the `●`, by account id (spec 027 FR-002, FR-015).
    public let headlineRows: [String: String]
    /// The band of each dropdown section in dropdown order, Unassigned last
    /// when shown, as the dropdown draws them (spec 028 FR-012).
    public let sectionStripes: [BandStyle]
    /// Dropdown rows (windows and budgets) whose level is critical from
    /// their owner's thresholds while their rounded used percent is below
    /// 100, the threshold-driven red (spec 030 FR-020).
    public let thresholdCriticalRows: [BurnWindowKey]
    /// Bar entries at the critical level without a real limit, by entry id
    /// (spec 030 FR-004, FR-020).
    public let thresholdCriticalEntries: [String]
    /// The snapshot after the last frame.
    public let snapshot: UsageSnapshot
}

/// Plays a scenario through a `RefreshCoordinator` with the three demo
/// sources and a clock that jumps from frame to frame, the way the demo app
/// does in real time (spec 024 FR-012, FR-016).
public enum ScenarioCoverage {
    /// One refresh at launch, one at each frame's refresh time
    /// (`DemoSetup.frameRefreshDates`), like the app. The configuration lives in a temporary folder
    /// that is removed afterwards.
    public static func evaluate(scenario: Scenario, launch: Date, calendar: Calendar = .autoupdatingCurrent) async throws -> CoverageReport {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("agenttacho-demo-coverage-" + UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }

        let store = ConfigStore(fileURL: folder.appendingPathComponent("config.json"))
        try store.save(scenario.configuration)
        let clock = CoverageClock(launch)
        let coordinator = RefreshCoordinator(configStore: store, log: DiagnosticLog(fileURL: folder.appendingPathComponent("usage.log")),
                                             resolver: WindowResolver(), aggregator: Aggregator(), calendar: calendar,
                                             clock: { clock.now() })
        let player = ScenarioPlayer(scenario: scenario, launch: launch)
        let prices = scenario.importedPrices ?? .empty
        for source in DemoSetup.sources(player: player, builtInPrices: try PriceTable.builtIn(), importedPrices: { prices },
                                        calendar: calendar) {
            await coordinator.register(source)
        }

        let configuration = scenario.configuration
        var tracker = ThresholdTracker()
        var snapshot = await coordinator.refreshAndWait(trigger: .launch)
        var crossings = tracker.observe(snapshot: snapshot, configuration: configuration)
        for date in DemoSetup.frameRefreshDates(scenario, launch: launch) {
            clock.set(date)
            snapshot = await coordinator.refreshAndWait(trigger: .scheduled)
            crossings += tracker.observe(snapshot: snapshot, configuration: configuration)
        }

        let items = BarLayout.segments(snapshot: snapshot, configuration: configuration)
        // The markers as the bar draws them.
        let markers = Set(BarPresentation.entries(items, settings: configuration.levelDisplay).compactMap(\.runOutMarker))
        return CoverageReport(levels: Set(items.map(\.level)), markers: markers,
                              paceStates: paceStates(snapshot), incompleteOwners: incomplete(snapshot, configuration: configuration),
                              harnesses: harnesses(snapshot),
                              attentionRows: attentionRows(snapshot),
                              singleMemberGroups: configuration.groups.filter { configuration.members(of: $0.id).count == 1 }.map(\.name),
                              absoluteTimeOwners: absoluteTimeOwners(configuration),
                              crossings: crossings.map { "\($0.entityName)@\($0.threshold)" },
                              memberDisplays: memberDisplays(snapshot, configuration: configuration),
                              barTags: Dictionary(uniqueKeysWithValues: items.compactMap { item in item.tag.map { (item.id, $0) } }),
                              barValues: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.value) }),
                              headlineRows: headlineRows(snapshot, configuration: configuration),
                              sectionStripes: SectionBands.stripes(arrangedCount: configuration.arrangedEntries.count,
                                                                   unassignedShown: SectionBands.showsUnassigned(snapshot)),
                              thresholdCriticalRows: thresholdCriticalRows(snapshot, configuration: configuration),
                              thresholdCriticalEntries: items.filter { $0.level == .critical && !$0.overLimit }.map(\.id),
                              snapshot: snapshot)
    }

    /// The rows the dropdown draws red below 100%, decided by the same
    /// `RowBar` level as the dropdown: every Claude and Codex window with
    /// its account's thresholds and every budget with its own (spec 030
    /// FR-005, FR-020). A reached Codex limit is a real limit, not a
    /// threshold-driven red.
    static func thresholdCriticalRows(_ snapshot: UsageSnapshot, configuration: Configuration) -> [BurnWindowKey] {
        let now = snapshot.generatedAt
        var rows: [BurnWindowKey] = []
        func window(_ key: BurnWindowKey, used: Double, limitReached: Bool = false, thresholds: [Int]) {
            guard used.isFinite, !limitReached, PercentFormatter.rounded(used) < 100 else { return }
            let bar = RowBar.make(usedPercent: used, limitReached: false, thresholds: thresholds, direction: .used, reading: nil)
            if bar.level == .critical { rows.append(key) }
        }
        func budget(_ key: BurnWindowKey, entry: GroupEntry?, thresholds: [Int]) {
            guard let entry, entry.percent < 100 else { return }
            if RowBar.budget(entry, thresholds: thresholds, direction: .used, reading: nil).level == .critical { rows.append(key) }
        }
        for account in configuration.accounts {
            switch account.kind {
            case .subscription(let settings):
                guard let status = snapshot.subscriptions[account.id]?.status?.effective(now: now) else { continue }
                if let five = status.fiveHour {
                    window(.claude(account.id, .fiveHour), used: five.utilizationPercent, thresholds: settings.thresholds)
                }
                if let seven = status.sevenDay {
                    window(.claude(account.id, .sevenDay), used: seven.utilizationPercent, thresholds: settings.thresholds)
                }
                for limit in status.modelLimits {
                    window(.claude(account.id, .model(limit.modelName)), used: limit.utilizationPercent, thresholds: settings.thresholds)
                }
            case .codexSubscription(let settings):
                for codex in snapshot.codexLimits[account.id]?.windows(now: now) ?? [] {
                    window(.codex(account.id, codex.name), used: codex.usedPercent, limitReached: codex.limitReached,
                           thresholds: settings.thresholds)
                }
            case .tokenBased(let settings):
                if let own = settings.ownBudget {
                    budget(.accountBudget(account.id), entry: snapshot.accountBudgets[account.id], thresholds: own.thresholds)
                }
            }
        }
        for group in configuration.groups {
            budget(.group(group.id), entry: snapshot.groups[group.id], thresholds: group.thresholds)
        }
        return rows
    }

    /// The headline row of every Claude and Codex subscription, resolved as
    /// the dropdown resolves it (spec 027 FR-006); a Codex plan without
    /// windows has none.
    static func headlineRows(_ snapshot: UsageSnapshot, configuration: Configuration) -> [String: String] {
        var rows: [String: String] = [:]
        for account in configuration.accounts {
            switch account.kind {
            case .subscription(let settings):
                rows[account.id] = HeadlineWindow.claude(accountId: account.id, status: snapshot.subscriptions[account.id]?.status,
                                                         choice: settings.headlineWindow, now: snapshot.generatedAt).rowName
            case .codexSubscription(let settings):
                rows[account.id] = snapshot.codexLimits[account.id].flatMap {
                    HeadlineWindow.codex(accountId: account.id, entry: $0, choice: settings.headlineWindow, now: snapshot.generatedAt)
                }?.rowName
            case .tokenBased:
                continue
            }
        }
        return rows
    }

    /// Every group's member lines and member tables by group name, from the
    /// same rule and the same inputs as the dropdown's budget section: the
    /// arranged members in member order (spec 008 FR-003) with their usage
    /// entries (spec 026 FR-007, idea inbox member-line-rule-in-core).
    static func memberDisplays(_ snapshot: UsageSnapshot, configuration: Configuration) -> [String: MemberDisplay] {
        let groups: [(String, MemberDisplay)] = configuration.arrangedEntries.compactMap { entry in
            guard case .group(let group, let members) = entry else { return nil }
            return (group.name, MemberDisplay.make(memberIds: members.map(\.id), usage: snapshot.tokenAccounts))
        }
        return Dictionary(groups, uniquingKeysWith: { first, _ in first })
    }

    /// The keys whose pace reading calls for attention: the rows that show
    /// an orange bar and note (spec 025 FR-003, FR-004, research R11).
    static func attentionRows(_ snapshot: UsageSnapshot) -> [BurnWindowKey] {
        snapshot.paceKeys.filter { snapshot.paceReading(for: $0)?.callsForAttention == true }
    }

    /// The sections whose times read absolute, by the format that takes
    /// effect: a group member's own value does not count, its group's does
    /// (spec 025 FR-016, FR-021).
    static func absoluteTimeOwners(_ configuration: Configuration) -> [String] {
        configuration.arrangedEntries.compactMap { entry in
            guard configuration.timeFormat(for: entry) == .absolute else { return nil }
            switch entry {
            case .account(let account): return account.displayName
            case .group(let group, _): return group.name
            }
        }
    }

    /// The paces the dropdown shows as bar ticks: the Claude 5-hour, 7-day
    /// and model windows, every Codex window, every budget.
    static func paceStates(_ snapshot: UsageSnapshot) -> Set<String> {
        let now = snapshot.generatedAt
        var paces: [Pace?] = []
        for entry in snapshot.subscriptions.values {
            guard let status = entry.status?.effective(now: now) else { continue }
            paces.append(status.fiveHourPace(now: now))
            paces.append(status.sevenDayPace(now: now))
            paces += status.modelLimits.map { status.pace(of: $0, now: now) }
        }
        for entry in snapshot.codexLimits.values {
            paces += entry.windows(now: now).map { entry.pace(of: $0, now: now) }
        }
        paces += snapshot.groups.values.map { $0.pace(now: now) }
        paces += snapshot.accountBudgets.values.map { $0.pace(now: now) }
        return Set(paces.compactMap { pace in
            switch pace?.status {
            case .onPace?: return "onPace"
            case .ahead?: return "ahead"
            case .behind?: return "behind"
            case nil: return nil
            }
        })
    }

    static func incomplete(_ snapshot: UsageSnapshot, configuration: Configuration) -> [String] {
        let owners = configuration.budgetOwners.filter { owner in
            let entry = owner.kind == .group ? snapshot.groups[owner.id] : snapshot.accountBudgets[owner.id]
            return entry?.incomplete == true
        }.map(\.name)
        let accounts = snapshot.tokenAccounts.filter(\.value.incomplete).keys.sorted()
        return owners + accounts
    }

    static func harnesses(_ snapshot: UsageSnapshot) -> Set<Harness> {
        var breakdowns = snapshot.subscriptions.values.map(\.breakdown)
        breakdowns += snapshot.groups.values.map(\.breakdown)
        breakdowns += snapshot.accountBudgets.values.map(\.breakdown)
        breakdowns += snapshot.tokenAccounts.values.map(\.breakdown)
        breakdowns += snapshot.codexPlanTokens.values.map(\.breakdown)
        return Set(breakdowns.flatMap(\.perHarness).filter { $0.totalTokens > 0 }.map(\.harness))
    }
}

/// The coverage run's clock, moved from frame to frame.
private final class CoverageClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func set(_ date: Date) {
        lock.lock(); current = date; lock.unlock()
    }
}
