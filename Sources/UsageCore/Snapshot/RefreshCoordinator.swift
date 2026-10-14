import Foundation

// MARK: - Shared interfaces (tasks.md)

public struct RefreshContext: Sendable {
    public let configuration: Configuration
    /// Collection window of this refresh: the weekly window, widened to span
    /// the monthly window when at least one group is monthly (spec 003
    /// research R2). Record sources return every record with
    /// `timestamp >= window.start`; groups filter to their own window later.
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

/// A source that calls a network endpoint (the rate-limited usage endpoint).
/// A reprice reuses its last result instead of calling it (FR-023a).
public protocol NetworkBoundSource: UsageSource {}

// MARK: - Coordinator

/// Owns the single in-flight refresh (FR-024), runs every source in isolation
/// (FR-026), and publishes `UsageSnapshot` values.
public actor RefreshCoordinator {
    private let configStore: ConfigStore
    private let log: DiagnosticLog
    private let resolver: WindowResolver
    private let aggregator: Aggregator
    /// Read on every refresh. The production default is
    /// `Calendar.autoupdatingCurrent`, so a time zone change moves the monthly
    /// window at the next refresh (spec 003 FR-016, research R1).
    private let calendar: Calendar
    private let clock: @Sendable () -> Date

    private var sources: [UsageSource] = []
    private var running = false
    /// One trigger remembered while a refresh runs; the highest rank wins.
    private var pendingTrigger: RefreshTrigger?
    /// Decides per run whether the usage endpoint is called.
    private var policy = EndpointPolicy(refreshInterval: TimeInterval(Configuration.defaultRefreshIntervalSeconds))
    /// The single retry after a rate limit, and its time.
    private var retryTask: Task<Void, Never>?
    private var nextRetryAt: Date?
    /// Credential directory per subscription account at the last full
    /// refresh; a reused entry whose directory changed since is dropped.
    private var lastNetworkDirectories: [String: String] = [:]
    private let retrySleep: @Sendable (TimeInterval) async -> Void
    /// Last result of every network-bound source, by source name, stored
    /// after each full refresh and reused by a reprice.
    private var lastNetworkResults: [String: SourceResult] = [:]
    /// Start of the full refresh that produced `lastNetworkResults`.
    private var lastNetworkRefreshAt: Date?
    private var loopTask: Task<Void, Never>?
    private var previousSnapshot: UsageSnapshot?
    private var lastAlignmentReset: AlignmentReset?

    public private(set) var refreshCount = 0
    public private(set) var latestSnapshot: UsageSnapshot?

    private let continuation: AsyncStream<UsageSnapshot>.Continuation
    public nonisolated let snapshots: AsyncStream<UsageSnapshot>

    public init(configStore: ConfigStore, log: DiagnosticLog, resolver: WindowResolver, aggregator: Aggregator,
                calendar: Calendar = .autoupdatingCurrent, clock: @escaping @Sendable () -> Date = { Date() },
                retrySleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.configStore = configStore
        self.log = log
        self.resolver = resolver
        self.aggregator = aggregator
        self.calendar = calendar
        self.clock = clock
        self.retrySleep = retrySleep
        let (stream, continuation) = AsyncStream.makeStream(of: UsageSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        self.snapshots = stream
        self.continuation = continuation
    }

    public func register(_ source: UsageSource) {
        sources.append(source)
    }

    public var isRunning: Bool { running }

    /// Starts a refresh for `trigger`, or remembers it while one runs (one
    /// pending trigger, the highest `rank` wins). Whether the usage endpoint
    /// is called is decided by `EndpointPolicy` when the run starts.
    public func requestRefresh(trigger: RefreshTrigger = .scheduled) {
        if running {
            // A scheduled tick replaces a pending retry: a retry that turns
            // out "already fresh" must not swallow the scheduled fetch.
            if pendingTrigger.map({ trigger.rank > $0.rank || (trigger == .scheduled && $0 == .retry) }) ?? true {
                pendingTrigger = trigger
            }
            return
        }
        running = true
        loopTask = Task { await self.runLoop(trigger: trigger) }
    }

    /// A refresh that never calls the usage endpoint and reuses the last
    /// network result (FR-023a). Used after price imports and local edits.
    public func requestReprice() {
        requestRefresh(trigger: .local)
    }

    /// Requests a refresh and waits until the coordinator is idle again.
    public func refreshAndWait(trigger: RefreshTrigger = .scheduled) async -> UsageSnapshot {
        requestRefresh(trigger: trigger)
        return await waitUntilIdle()
    }

    /// Requests a reprice and waits until the coordinator is idle again.
    public func repriceAndWait() async -> UsageSnapshot {
        requestReprice()
        return await waitUntilIdle()
    }

    private func waitUntilIdle() async -> UsageSnapshot {
        while let task = loopTask {
            await task.value
            if loopTask == task { loopTask = nil }
        }
        return latestSnapshot!
    }

    private enum Mode {
        case full
        case reprice
    }

    private func runLoop(trigger initial: RefreshTrigger) async {
        var trigger = initial
        while true {
            pendingTrigger = nil
            let snapshot = await performRefresh(trigger: trigger)
            refreshCount += 1
            latestSnapshot = snapshot
            previousSnapshot = snapshot
            continuation.yield(snapshot)
            guard let next = pendingTrigger else { break }
            trigger = next
        }
        running = false
    }

    // MARK: Refresh

    private struct SourceResult {
        let name: String
        var result: Result<SourceOutput, Error>
        let isWindowSensitive: Bool
        var isNetworkBound = false
        /// True when a reprice reused the stored result instead of calling the source.
        var reused = false
    }

    private func performRefresh(trigger: RefreshTrigger) async -> UsageSnapshot {
        let started = clock()
        let (configuration, configError) = configStore.load()
        let alignmentId = configuration.effectiveAlignmentAccountId
        let effectiveReset = lastAlignmentReset.flatMap { $0.accountId == alignmentId ? $0 : nil }
        let (initialWindow, _) = resolver.resolve(now: started, alignmentReset: effectiveReset,
                                                  fallback: configuration.weekFallback, calendar: calendar)
        let initialCollection = resolver.collectionWindow(weekly: initialWindow, now: started, configuration: configuration, calendar: calendar)
        let context = RefreshContext(configuration: configuration, window: initialCollection, now: started)

        policy.refreshInterval = TimeInterval(configuration.refreshIntervalSeconds)
        let networkSources = sources.filter { $0 is NetworkBoundSource }
        let decision = policy.decide(trigger, now: started)
        var mode: Mode = decision == .fetch ? .full : .reprice
        var reuseReason: String?
        if case .reuse(let reason, let retryAt) = decision {
            reuseReason = reason
            if let retryAt { scheduleRetry(at: retryAt, trigger: trigger == .settings ? .settings : .retry) }
        }
        // A reprice needs a stored result for every network-bound source;
        // otherwise it runs as a full refresh.
        if mode == .reprice && !networkSources.allSatisfy({ lastNetworkResults[$0.name] != nil }) {
            log.append(source: "refresh", message: "no stored network result, running a full refresh")
            mode = .full
            reuseReason = nil
        }
        var results: [SourceResult]
        switch mode {
        case .full:
            results = await collect(from: sources, context: context)
            lastNetworkResults = [:]
            lastNetworkRefreshAt = started
            lastNetworkDirectories = Dictionary(uniqueKeysWithValues: configuration.subscriptionAccounts.map {
                ($0.id, $0.kind.subscription?.credentialDirectory ?? "")
            })
            var outcomes: [FetchOutcome] = []
            for r in results where r.isNetworkBound {
                lastNetworkResults[r.name] = r
                switch r.result {
                case .success(.subscriptions(let entries)): outcomes += entries.values.compactMap(\.fetchOutcome)
                case .success(.records): break
                case .failure: outcomes.append(.otherError)
                }
            }
            if let outcome = FetchOutcome.combined(outcomes) {
                if let retryAt = policy.record(outcome, now: started) {
                    scheduleRetry(at: retryAt, trigger: .retry)
                } else if outcome == .success {
                    cancelRetry()
                }
            }
        case .reprice:
            results = await collect(from: sources.filter { !($0 is NetworkBoundSource) }, context: context)
            // Keep only accounts that still exist with the credential
            // directory their reused result was fetched with.
            let configured = Set(configuration.subscriptionAccounts.filter {
                lastNetworkDirectories[$0.id] == ($0.kind.subscription?.credentialDirectory ?? "")
            }.map(\.id))
            for source in networkSources {
                var reused = lastNetworkResults[source.name]!
                reused.reused = true
                if case .success(.subscriptions(let entries)) = reused.result {
                    reused.result = .success(.subscriptions(entries.filter { configured.contains($0.key) }))
                }
                results.append(reused)
            }
        }

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
        // Monthly windows do not move with the reset; only a weekly window
        // that now starts before the collection start forces a re-run.
        let collection = resolver.collectionWindow(weekly: window, now: started, configuration: configuration, calendar: calendar)
        if collection.start < initialCollection.start {
            let rerun = sources.filter { $0 is WindowSensitiveSource }
            if !rerun.isEmpty {
                for case let source as WindowSensitiveSource in rerun {
                    await source.resetForEarlierWindow()
                }
                let laterContext = RefreshContext(configuration: configuration, window: collection, now: started)
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
                        sourceErrors.append(SourceError(sourceName: r.name, message: "\(id): \(error)", at: errorTime(r, started)))
                    }
                }
                log.append(source: r.name, message: (r.reused ? "reused for reprice, " : "") + "ok: \(entries.count) account(s) " + describe(entries))
            case .success(.records(let recs)):
                records.append(contentsOf: recs)
                log.append(source: r.name, message: "ok: \(recs.count) record(s) since \(iso(collection.start))")
            case .failure(let error):
                let message = String(describing: error)
                sourceErrors.append(SourceError(sourceName: r.name, message: message, at: errorTime(r, started)))
                log.append(source: r.name, message: (r.reused ? "reused for reprice, " : "") + "error: \(message)")
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
        // A reprice fetches nothing, so it does not count as a successful
        // refresh of the network-bound data.
        snapshot.lastSuccessfulRefreshAt = sourceErrors.isEmpty && mode == .full ? started
            : previousSnapshot?.lastSuccessfulRefreshAt ?? (sourceErrors.isEmpty ? started : nil)
        snapshot.endpointBlockedUntil = policy.blockedUntil.flatMap { $0 > started ? $0 : nil }
        snapshot.nextRetryAt = nextRetryAt

        if recordSourceFailed {
            // Carry the previous values over (or, on the first refresh, the
            // empty ones) and mark them stale (FR-007).
            // Carried-over group entries keep their old `period` and `window`:
            // they are shown as stale and the threshold tracker skips them.
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
            // The group's own window and the calendar time zone, so a month
            // boundary or a time zone move can be checked (spec 003 FR-016).
            log.append(source: "refresh", message: "group \(group.shownLabel.plain) (\(entry.period.adjective), \(iso(entry.window.start)) to \(iso(entry.window.end)), \(calendar.timeZone.identifier)): \(entry.spentUSD) of \(entry.budgetUSD) USD (\(entry.percent)%)"
                       + (entry.incomplete ? ", incomplete (unpriced: \(entry.breakdown.unpricedModels.joined(separator: ", ")))" : "")
                       + (entry.stale ? ", stale" : ""))
        }
        let elapsed = clock().timeIntervalSince(started)
        let windowText = "\(iso(window.start)) to \(iso(window.end)) (\(windowSource == .fallback ? "fallback" : "aligned"))"
        let endpointText: String
        if networkSources.isEmpty {
            endpointText = "no endpoint"
        } else if mode == .full {
            endpointText = "endpoint fetched"
        } else {
            endpointText = "endpoint reused (\(reuseReason ?? "reprice"))"
        }
        log.append(source: "refresh", message: String(format: "done in %.3f s, %d source error(s), window %@%@%@, trigger %@, %@",
                                                      elapsed, sourceErrors.count, windowText,
                                                      configError.map { ", config error: \($0.message)" } ?? "",
                                                      mode == .reprice ? ", reprice (network sources reused)" : "",
                                                      trigger.rawValue, endpointText))
        return snapshot
    }

    /// Replaces any pending follow-up with one at `date` (plus 1 s, so the
    /// block or spacing has ended when it runs). `trigger` is `.retry` after
    /// a rate limit, `.settings` for a spaced subscription edit.
    private func scheduleRetry(at date: Date, trigger: RefreshTrigger) {
        retryTask?.cancel()
        nextRetryAt = date
        let delay = max(0, date.timeIntervalSince(clock())) + 1
        let sleep = retrySleep
        retryTask = Task { [weak self] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            await self?.fireRetry(trigger: trigger)
        }
        log.append(source: "refresh", message: "endpoint \(trigger.rawValue) follow-up scheduled at \(iso(date))")
    }

    private func fireRetry(trigger: RefreshTrigger) {
        retryTask = nil
        nextRetryAt = nil
        requestRefresh(trigger: trigger)
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        nextRetryAt = nil
    }

    /// A reused result keeps the time of the refresh that produced it.
    private func errorTime(_ result: SourceResult, _ started: Date) -> Date {
        result.reused ? (lastNetworkRefreshAt ?? started) : started
    }

    private func collect(from sources: [UsageSource], context: RefreshContext) async -> [SourceResult] {
        await withTaskGroup(of: SourceResult.self) { group in
            for source in sources {
                group.addTask {
                    do {
                        let output = try await source.collect(context: context)
                        return SourceResult(name: source.name, result: .success(output), isWindowSensitive: source is WindowSensitiveSource,
                                            isNetworkBound: source is NetworkBoundSource)
                    } catch {
                        return SourceResult(name: source.name, result: .failure(error), isWindowSensitive: source is WindowSensitiveSource,
                                            isNetworkBound: source is NetworkBoundSource)
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
