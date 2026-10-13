import Foundation

// MARK: - Shared interfaces (tasks.md)

public struct RefreshContext: Sendable {
    public let configuration: Configuration
    /// Group window resolved at the start of this refresh.
    public let window: DateInterval
    public let now: Date

    public init(configuration: Configuration, window: DateInterval, now: Date) {
        self.configuration = configuration
        self.window = window
        self.now = now
    }
}

public enum SourceOutput: Sendable {
    /// Keyed by account id, breakdown left empty.
    case subscriptions([String: SubscriptionEntry])
    /// All records with timestamp >= window.start.
    case records([UsageRecord])
}

public protocol UsageSource: Sendable {
    /// Used in `SourceError` and the diagnostic log.
    var name: String { get }
    func collect(context: RefreshContext) async throws -> SourceOutput
}

/// A source that keeps state tied to the window start and can be re-run with
/// an earlier window inside the same refresh (tasks T040).
public protocol WindowSensitiveSource: UsageSource {
    func resetForEarlierWindow() async
}

// MARK: - Coordinator

/// Owns the single in-flight refresh (FR-024), runs every source in isolation
/// (FR-026), and publishes `UsageSnapshot` values.
public actor RefreshCoordinator {
    private let configStore: ConfigStore
    private let log: DiagnosticLog
    private let resolver: WindowResolver
    private let aggregator: Aggregator
    private let calendar: Calendar
    private let clock: @Sendable () -> Date

    private var sources: [UsageSource] = []
    private var running = false
    private var pending = false
    private var loopTask: Task<Void, Never>?
    private var previousSnapshot: UsageSnapshot?
    private var lastAlignmentReset: AlignmentReset?

    public private(set) var refreshCount = 0
    public private(set) var latestSnapshot: UsageSnapshot?

    private let continuation: AsyncStream<UsageSnapshot>.Continuation
    public nonisolated let snapshots: AsyncStream<UsageSnapshot>

    public init(configStore: ConfigStore, log: DiagnosticLog, resolver: WindowResolver, aggregator: Aggregator,
                calendar: Calendar = .current, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.configStore = configStore
        self.log = log
        self.resolver = resolver
        self.aggregator = aggregator
        self.calendar = calendar
        self.clock = clock
        let (stream, continuation) = AsyncStream.makeStream(of: UsageSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        self.snapshots = stream
        self.continuation = continuation
    }

    public func register(_ source: UsageSource) {
        sources.append(source)
    }

    public var isRunning: Bool { running }

    /// No-op while a refresh runs, except that one pending request is
    /// remembered and served when the current refresh ends.
    public func requestRefresh() {
        if running {
            pending = true
            return
        }
        running = true
        loopTask = Task { await self.runLoop() }
    }

    /// Requests a refresh and waits until the coordinator is idle again.
    public func refreshAndWait() async -> UsageSnapshot {
        requestRefresh()
        while let task = loopTask {
            await task.value
            if loopTask == task { loopTask = nil }
        }
        return latestSnapshot!
    }

    private func runLoop() async {
        repeat {
            pending = false
            let snapshot = await performRefresh()
            refreshCount += 1
            latestSnapshot = snapshot
            previousSnapshot = snapshot
            continuation.yield(snapshot)
        } while pending
        running = false
    }

    // MARK: Refresh

    private struct SourceResult {
        let name: String
        let result: Result<SourceOutput, Error>
        let isWindowSensitive: Bool
    }

    private func performRefresh() async -> UsageSnapshot {
        let started = clock()
        let (configuration, configError) = configStore.load()
        let alignmentId = configuration.effectiveAlignmentAccountId
        let effectiveReset = lastAlignmentReset.flatMap { $0.accountId == alignmentId ? $0 : nil }
        let (initialWindow, _) = resolver.resolve(now: started, alignmentReset: effectiveReset,
                                                  fallback: configuration.weekFallback, calendar: calendar)
        let context = RefreshContext(configuration: configuration, window: initialWindow, now: started)

        var results = await collect(from: sources, context: context)

        // Re-resolve the window with a reset fetched during this refresh (T040).
        var subscriptions: [String: SubscriptionEntry] = [:]
        for case .success(.subscriptions(let entries)) in results.map(\.result) {
            subscriptions.merge(entries) { _, new in new }
        }
        if let id = alignmentId, let reset = subscriptions[id]?.status?.sevenDay?.resetsAt {
            lastAlignmentReset = AlignmentReset(accountId: id, resetsAt: reset)
        }
        let finalReset = lastAlignmentReset.flatMap { $0.accountId == alignmentId ? $0 : nil }
        let (window, windowSource) = resolver.resolve(now: started, alignmentReset: finalReset,
                                                      fallback: configuration.weekFallback, calendar: calendar)
        if window.start < initialWindow.start {
            let rerun = sources.filter { $0 is WindowSensitiveSource }
            if !rerun.isEmpty {
                for case let source as WindowSensitiveSource in rerun {
                    await source.resetForEarlierWindow()
                }
                let laterContext = RefreshContext(configuration: configuration, window: window, now: started)
                let rerunResults = await collect(from: rerun, context: laterContext)
                for r in rerunResults {
                    results.removeAll { $0.name == r.name && $0.isWindowSensitive }
                    results.append(r)
                }
            }
        }

        // Gather outputs and errors.
        var records: [UsageRecord] = []
        var sourceErrors: [SourceError] = []
        var recordSourceFailed = false
        var subscriptionSourceFailure: String?
        subscriptions = [:]
        for r in results {
            switch r.result {
            case .success(.subscriptions(let entries)):
                subscriptions.merge(entries) { _, new in new }
                // A per-account fetch failure (state .stale) is a failed refresh
                // for that source even though the other accounts succeeded (FR-007).
                for id in entries.keys.sorted() {
                    if case .stale(_, let error) = entries[id]!.state {
                        sourceErrors.append(SourceError(sourceName: r.name, message: "\(id): \(error)", at: started))
                    }
                }
                log.append(source: r.name, message: "ok: \(entries.count) account(s) " + describe(entries))
            case .success(.records(let recs)):
                records.append(contentsOf: recs)
                log.append(source: r.name, message: "ok: \(recs.count) record(s) since \(iso(window.start))")
            case .failure(let error):
                let message = String(describing: error)
                sourceErrors.append(SourceError(sourceName: r.name, message: message, at: started))
                log.append(source: r.name, message: "error: \(message)")
                if r.isWindowSensitive { recordSourceFailed = true } else { subscriptionSourceFailure = message }
            }
        }

        if let failure = subscriptionSourceFailure, subscriptions.isEmpty, let previous = previousSnapshot {
            // Keep the last known values, marked stale (US1 scenario 3).
            subscriptions = previous.subscriptions.mapValues { entry in
                var copy = entry
                switch entry.state {
                case .ok:
                    copy.state = .stale(lastGoodAt: entry.status?.fetchedAt, error: failure)
                case .stale(let at, _):
                    copy.state = .stale(lastGoodAt: at, error: failure)
                case .notSignedIn, .credentialsExpired:
                    break
                }
                return copy
            }
        }

        var snapshot = aggregator.aggregate(records: records, subscriptions: subscriptions,
                                            configuration: configuration, window: window, windowSource: windowSource,
                                            now: started, calendar: calendar)
        snapshot.generatedAt = started
        snapshot.sourceErrors = sourceErrors
        snapshot.configError = configError?.message
        snapshot.lastSuccessfulRefreshAt = sourceErrors.isEmpty ? started : previousSnapshot?.lastSuccessfulRefreshAt

        if recordSourceFailed {
            // Carry the previous values over (or, on the first refresh, the
            // empty ones) and mark them stale (FR-007).
            if let previous = previousSnapshot {
                snapshot.groups = previous.groups
                snapshot.tokenAccounts = previous.tokenAccounts
                snapshot.unassigned = previous.unassigned
            }
            snapshot.groups = snapshot.groups.mapValues { var g = $0; g.stale = true; return g }
            snapshot.tokenAccounts = snapshot.tokenAccounts.mapValues { var t = $0; t.stale = true; return t }
            snapshot.unassigned.stale = true
        }

        for group in configuration.groups {
            guard let entry = snapshot.groups[group.id] else { continue }
            log.append(source: "refresh", message: "group \(group.shownLabel.plain): \(entry.spentUSD) of \(entry.budgetUSD) USD (\(entry.percent)%)"
                       + (entry.incomplete ? ", incomplete (unpriced: \(entry.breakdown.unpricedModels.joined(separator: ", ")))" : "")
                       + (entry.stale ? ", stale" : ""))
        }
        let elapsed = clock().timeIntervalSince(started)
        let windowText = "\(iso(window.start)) to \(iso(window.end)) (\(windowSource == .fallback ? "fallback" : "aligned"))"
        log.append(source: "refresh", message: String(format: "done in %.3f s, %d source error(s), window %@%@", elapsed, sourceErrors.count,
                                                      windowText, configError.map { ", config error: \($0.message)" } ?? ""))
        return snapshot
    }

    private func collect(from sources: [UsageSource], context: RefreshContext) async -> [SourceResult] {
        await withTaskGroup(of: SourceResult.self) { group in
            for source in sources {
                group.addTask {
                    do {
                        let output = try await source.collect(context: context)
                        return SourceResult(name: source.name, result: .success(output), isWindowSensitive: source is WindowSensitiveSource)
                    } catch {
                        return SourceResult(name: source.name, result: .failure(error), isWindowSensitive: source is WindowSensitiveSource)
                    }
                }
            }
            var results: [SourceResult] = []
            for await r in group { results.append(r) }
            return results
        }
    }

    private func describe(_ entries: [String: SubscriptionEntry]) -> String {
        entries.keys.sorted().map { id in
            let entry = entries[id]!
            switch entry.state {
            case .ok:
                let five = entry.status?.fiveHour.map { "\(PercentFormatter.rounded($0.utilizationPercent))%" } ?? "n/a"
                let seven = entry.status?.sevenDay.map { "\(PercentFormatter.rounded($0.utilizationPercent))%" } ?? "n/a"
                return "\(id)=ok(5h \(five), 7d \(seven))"
            case .stale(let at, let error):
                return "\(id)=stale(since \(at.map(iso) ?? "never"): \(error))"
            case .notSignedIn:
                return "\(id)=notSignedIn"
            case .credentialsExpired:
                return "\(id)=credentialsExpired"
            }
        }.joined(separator: ", ")
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
