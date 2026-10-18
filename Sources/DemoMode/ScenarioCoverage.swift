import Foundation
import UsageCore

/// What a scenario shows once it has played, computed by the app's own
/// logic (spec 024 FR-016, data-model "Coverage").
public struct CoverageReport: Sendable {
    /// Bar levels after the last frame.
    public let levels: Set<BarLevel>
    /// `↗` and `↑` markers in the bar after the last frame.
    public let markers: Set<String>
    /// States of the dropdown's pace meters after the last frame: `onPace`,
    /// `behind`, `ahead`.
    public let paceStates: Set<String>
    /// Names of budget owners and ids of token accounts marked incomplete.
    public let incompleteOwners: [String]
    /// Harnesses with usage in any breakdown.
    public let harnesses: Set<Harness>
    /// Threshold crossings from the launch refresh to the last frame, as
    /// `<display name>@<threshold>`, in order.
    public let crossings: [String]
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
                              crossings: crossings.map { "\($0.entityName)@\($0.threshold)" }, snapshot: snapshot)
    }

    /// The paces the dropdown shows a meter for: the Claude 5-hour, 7-day
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
