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
    /// The trigger of this refresh. Sources that gate their own requests
    /// (the Codex plan limits source) use it to skip a request that is not
    /// due, such as a reprice (spec 007 research R5).
    public let trigger: RefreshTrigger

    public init(configuration: Configuration, window: DateInterval, now: Date, trigger: RefreshTrigger = .scheduled) {
        self.configuration = configuration
        self.window = window
        self.now = now
        self.trigger = trigger
    }
}

public enum SourceOutput: Sendable {
    /// Keyed by account id, breakdown left empty.
    case subscriptions([String: SubscriptionEntry])
    /// All records with timestamp >= window.start.
    case records([UsageRecord])
    /// Records plus per-location issues and stale harnesses (spec 006 research R7).
    case recordBatch(RecordBatch)
    /// Plan limits of Codex subscription accounts, keyed by account id
    /// (spec 007 FR-001).
    case codexLimits([String: CodexLimitsEntry])
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
public protocol NetworkBoundSource: UsageSource {
    /// A quick retry was not sent because of a rate-limit wait: the
    /// episodes whose retry is due at `now` count their retry as used
    /// (spec 010 FR-007).
    func quickRetrySuppressed(now: Date) async
}

extension NetworkBoundSource {
    public func quickRetrySuppressed(now: Date) async {}
}

/// A source that can show values saved by an earlier launch before the
/// first refresh finishes (spec 010 FR-015, research R6).
public protocol SavedValuesSource: UsageSource {
    /// Entries built from saved values for accounts still configured with
    /// the same canonical directory; nil when there are none.
    func savedOutput(configuration: Configuration, now: Date) async -> SourceOutput?
}

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
    /// A quick retry that arrived while a rate-limit retry was pending (or
    /// the other way round): both run, one after the other (spec 010 FR-007,
    /// FR-008). A scheduled tick replaces it.
    private var pendingQuickRetry = false
    /// Decides per run whether the usage endpoint is called.
    private var policy = EndpointPolicy(refreshInterval: TimeInterval(Configuration.defaultRefreshIntervalSeconds))
    /// The single retry after a rate limit, and its time.
    private var retryTask: Task<Void, Never>?
    private var nextRetryAt: Date?
    /// The trigger of the pending follow-up (`.retry` or `.settings`).
    private var retryTrigger: RefreshTrigger?
    /// The quick retry after a transport failure, and its time (spec 010
    /// FR-004, research R2). Kept apart from the rate-limit retry.
    private var quickRetryTask: Task<Void, Never>?
    private var nextQuickRetryAt: Date?
    private let quickRetrySleep: @Sendable (TimeInterval) async -> Void
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
    /// Accounts with a successful request in this run, with the credential
    /// directory it used. Before an account's first success, its saved
    /// 7-day reset aligns the window only while it is in the future (spec
    /// 010 FR-020). Pruned on every refresh to the configured accounts with
    /// an unchanged directory: another sign-in has not been fetched yet.
    private var accountsFetchedThisRun: [String: String] = [:]

    public private(set) var refreshCount = 0
    public private(set) var latestSnapshot: UsageSnapshot?

    private let continuation: AsyncStream<UsageSnapshot>.Continuation
    public nonisolated let snapshots: AsyncStream<UsageSnapshot>

    public init(configStore: ConfigStore, log: DiagnosticLog, resolver: WindowResolver, aggregator: Aggregator,
                calendar: Calendar = .autoupdatingCurrent, clock: @escaping @Sendable () -> Date = { Date() },
                retrySleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
                quickRetrySleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.configStore = configStore
        self.log = log
        self.resolver = resolver
        self.aggregator = aggregator
        self.calendar = calendar
        self.clock = clock
        self.retrySleep = retrySleep
        self.quickRetrySleep = quickRetrySleep
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
            // A quick retry already waiting behind a rate-limit retry is
            // not queued a second time, so `pendingTrigger` is never
            // `.quickRetry` while `pendingQuickRetry` is set.
            if trigger == .quickRetry && pendingQuickRetry { return }
            // A rate-limit retry and a quick retry do not replace each other.
            if (trigger == .quickRetry && pendingTrigger == .retry) || (trigger == .retry && pendingTrigger == .quickRetry) {
                pendingTrigger = .retry
                pendingQuickRetry = true
                return
            }
            if trigger == .scheduled { pendingQuickRetry = false }
            // A scheduled tick replaces a pending retry or quick retry: a
            // retry that turns out "already fresh" must not swallow the
            // scheduled fetch (spec 010 FR-008).
            if pendingTrigger.map({ trigger.rank > $0.rank || (trigger == .scheduled && ($0 == .retry || $0 == .quickRetry)) }) ?? true {
                pendingTrigger = trigger
            }
            return
        }
        running = true
        loopTask = Task { await self.runLoop(trigger: trigger) }
    }

    /// Publishes an early result built from the values saved by an earlier
    /// launch, before the first refresh finishes (spec 010 FR-015, research
    /// R6): only the saved Claude and Codex entries, every other map empty,
    /// marked `isPreliminary`. It becomes the previous snapshot, so a failed
    /// first refresh shows the saved values stale through the carry-over
    /// paths, but never `latestSnapshot`. Also seeds the alignment reset
    /// from the alignment account's saved 7-day reset while it is in the
    /// future (spec 010 FR-020). Yields nothing, and returns nil, without
    /// saved values or once a refresh produced a result.
    @discardableResult
    public func publishSavedValues() async -> UsageSnapshot? {
        guard latestSnapshot == nil else { return nil }
        let now = clock()
        let (configuration, _) = configStore.load()
        var subscriptions: [String: SubscriptionEntry] = [:]
        var codexLimits: [String: CodexLimitsEntry] = [:]
        for case let source as SavedValuesSource in sources {
            switch await source.savedOutput(configuration: configuration, now: now) {
            case .subscriptions(let entries)?: subscriptions.merge(entries) { _, new in new }
            case .codexLimits(let entries)?: codexLimits.merge(entries) { _, new in new }
            case .records?, .recordBatch?, nil: break
            }
        }
        // A refresh may have finished during the awaits above.
        guard latestSnapshot == nil, !subscriptions.isEmpty || !codexLimits.isEmpty else { return nil }
        let alignmentId = configuration.effectiveAlignmentAccountId
        if lastAlignmentReset == nil, let id = alignmentId,
           let reset = subscriptions[id]?.status?.sevenDay?.resetsAt, reset > now {
            lastAlignmentReset = AlignmentReset(accountId: id, resetsAt: reset)
        }
        let effectiveReset = lastAlignmentReset.flatMap { $0.accountId == alignmentId ? $0 : nil }
        let (window, windowSource) = resolver.resolve(now: now, alignmentReset: effectiveReset,
                                                      fallback: configuration.weekFallback, calendar: calendar)
        let snapshot = UsageSnapshot(generatedAt: now, window: window, windowSource: windowSource,
                                     subscriptions: subscriptions, codexLimits: codexLimits, isPreliminary: true)
        previousSnapshot = snapshot
        continuation.yield(snapshot)
        log.append(source: "refresh", message: "early result from saved values: \(subscriptions.count) Claude, \(codexLimits.count) Codex account(s)")
        return snapshot
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
            updateQuickRetry(after: snapshot, trigger: trigger)
            refreshCount += 1
            latestSnapshot = snapshot
            previousSnapshot = snapshot
            continuation.yield(snapshot)
            if let next = pendingTrigger {
                trigger = next
            } else if pendingQuickRetry {
                pendingQuickRetry = false
                trigger = .quickRetry
            } else {
                break
            }
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
        // Validation rejects duplicate account ids; keeping the first entry
        // avoids a trap should an unvalidated configuration get here.
        let directories = Dictionary(configuration.subscriptionAccounts.map {
            ($0.id, $0.kind.subscription?.credentialDirectory ?? "")
        }, uniquingKeysWith: { first, _ in first })
        accountsFetchedThisRun = accountsFetchedThisRun.filter { directories[$0.key] == $0.value }
        dropPassedSavedAlignmentReset(now: started)
        let effectiveReset = lastAlignmentReset.flatMap { $0.accountId == alignmentId ? $0 : nil }
        let (initialWindow, _) = resolver.resolve(now: started, alignmentReset: effectiveReset,
                                                  fallback: configuration.weekFallback, calendar: calendar)
        let initialCollection = resolver.collectionWindow(weekly: initialWindow, now: started, configuration: configuration, calendar: calendar)
        let context = RefreshContext(configuration: configuration, window: initialCollection, now: started, trigger: trigger)

        policy.refreshInterval = TimeInterval(configuration.refreshIntervalSeconds)
        let networkSources = sources.filter { $0 is NetworkBoundSource }
        let decision = policy.decide(trigger, now: started)
        var mode: Mode = decision == .fetch ? .full : .reprice
        var reuseReason: String?
        if trigger == .quickRetry {
            // The retry the fired timer was set for is attempted now; a
            // timer set since for another time stays.
            if quickRetryTask == nil { nextQuickRetryAt = nil }
            if decision != .fetch {
                // Only Claude accounts are held back here; a due Codex retry
                // is decided by its own source (spec 010 FR-007, FR-008).
                let suppressed = endSuppressedGrace(now: started)
                if !suppressed.isEmpty {
                    log.append(source: "refresh", message: "quick retry suppressed (rate limited) for "
                               + suppressed.joined(separator: ", ") + ", grace ends at the retry time")
                }
                for case let source as NetworkBoundSource in networkSources {
                    await source.quickRetrySuppressed(now: started)
                }
            }
        }
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
        /// False for a quick retry that requested no Claude account (only a
        /// Codex retry was due): the usage endpoint was not called, so the
        /// refresh time and the time of the stored result stay (spec 010
        /// FR-003, FR-009).
        var endpointCalled = mode == .full
        switch mode {
        case .full:
            results = await collect(from: sources, context: context)
            lastNetworkResults = [:]
            lastNetworkDirectories = directories
            var outcomes: [FetchOutcome] = []
            for r in results where r.isNetworkBound {
                lastNetworkResults[r.name] = r
                switch r.result {
                case .success(.subscriptions(let entries)): outcomes += entries.values.compactMap(\.fetchOutcome)
                case .success(.records), .success(.recordBatch), .success(.codexLimits): break
                case .failure: outcomes.append(.otherError)
                }
            }
            if trigger == .quickRetry {
                endpointCalled = !outcomes.isEmpty
                log.append(source: "refresh", message: endpointCalled ? "quick retry sent"
                           : "quick retry: no Claude account due, usage endpoint not called")
            }
            if endpointCalled { lastNetworkRefreshAt = started }
            if let outcome = FetchOutcome.combined(outcomes) {
                if let retryAt = policy.record(outcome, now: started) {
                    scheduleRetry(at: retryAt, trigger: .retry)
                } else if outcome == .success, trigger != .quickRetry || retryTrigger == .retry {
                    // A successful quick retry ends only a rate-limit retry,
                    // never a settings follow-up (spec 010 FR-009).
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
        for id in subscriptions.keys where subscriptions[id]!.state.isOk {
            accountsFetchedThisRun[id] = directories[id]
        }
        // Saved values (shown stale until a success) align only with a
        // future reset (spec 010 FR-020).
        if let id = alignmentId, let reset = subscriptions[id]?.status?.sevenDay?.resetsAt,
           accountsFetchedThisRun[id] != nil || reset > started {
            lastAlignmentReset = AlignmentReset(accountId: id, resetsAt: reset)
        }
        dropPassedSavedAlignmentReset(now: started)
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
                let laterContext = RefreshContext(configuration: configuration, window: collection, now: started, trigger: trigger)
                let rerunResults = await collect(from: rerun, context: laterContext)
                for r in rerunResults {
                    results.removeAll { $0.name == r.name && $0.isWindowSensitive }
                    results.append(r)
                }
            }
        }

        // Gather outputs and errors.
        var records: [UsageRecord] = []
        var staleHarnesses: Set<Harness> = []
        var sourceErrors: [SourceError] = []
        /// Source errors that affect one location or account only and do
        /// not fail the refresh: record batch issues (one location or a busy
        /// database, spec 006 FR-006) and one Codex account's limits (spec
        /// 007 FR-006).
        var isolatedErrorCount = 0
        var recordSourceFailed = false
        var subscriptionSourceFailure: String?
        var codexLimits: [String: CodexLimitsEntry] = [:]
        var codexLimitsSourceFailed = false
        subscriptions = [:]
        for r in results {
            switch r.result {
            case .success(.subscriptions(let fetched)):
                // A reused entry keeps its grace period until its retry ran
                // or its due window passed; a suppressed retry was already
                // ended in the stored result, so it cannot loop (spec 010
                // FR-005, FR-007, FR-008, research R3).
                let entries = fetched.mapValues { r.reused ? $0.reused(now: started) : $0.endingGrace(now: started) }
                subscriptions.merge(entries) { _, new in new }
                // A per-account fetch failure (state .stale) is a failed refresh
                // for that source even though the other accounts succeeded (FR-007).
                // A rejected sign-in counts the same (spec 010 FR-010).
                for id in entries.keys.sorted() {
                    switch entries[id]!.state {
                    case .stale(_, let error):
                        sourceErrors.append(SourceError(sourceName: r.name, message: "\(id): \(error)", at: errorTime(r, started)))
                    case .signInRejected:
                        sourceErrors.append(SourceError(sourceName: r.name, message: "\(id): sign-in rejected", at: errorTime(r, started)))
                    case .ok, .retrying, .notSignedIn, .credentialsExpired:
                        break
                    }
                }
                log.append(source: r.name, message: (r.reused ? "reused for reprice, " : "") + "ok: \(entries.count) account(s) " + describe(entries))
            case .success(.records(let recs)):
                records.append(contentsOf: recs)
                log.append(source: r.name, message: "ok: \(recs.count) record(s) since \(iso(collection.start))")
            case .success(.recordBatch(let batch)):
                // Per-location problems are source errors, but only the
                // affected harness turns stale (spec 006 FR-005, FR-006).
                records.append(contentsOf: batch.records)
                staleHarnesses.formUnion(batch.staleHarnesses)
                for issue in batch.issues {
                    sourceErrors.append(SourceError(sourceName: r.name, message: issue, at: errorTime(r, started)))
                }
                isolatedErrorCount += batch.issues.count
                log.append(source: r.name, message: "ok: \(batch.records.count) record(s) since \(iso(collection.start))"
                           + (batch.issues.isEmpty ? "" : ", \(batch.issues.count) issue(s)")
                           + (batch.staleHarnesses.isEmpty ? "" : ", stale: " + batch.staleHarnesses.map(\.displayName).sorted().joined(separator: ", ")))
            case .success(.codexLimits(let entries)):
                codexLimits.merge(entries) { _, new in new }
                // An unreadable answer or a rejected sign-in is a source
                // error of that account only; its entry is marked stale on
                // its own, like a record batch issue (spec 007 FR-006).
                for id in entries.keys.sorted() {
                    if let error = entries[id]!.sourceError {
                        sourceErrors.append(SourceError(sourceName: r.name, message: "\(id): \(error)", at: errorTime(r, started)))
                        isolatedErrorCount += 1
                    }
                }
                log.append(source: r.name, message: "ok: \(entries.count) account(s)")
            case .failure(let error):
                let message = String(describing: error)
                sourceErrors.append(SourceError(sourceName: r.name, message: message, at: errorTime(r, started)))
                log.append(source: r.name, message: (r.reused ? "reused for reprice, " : "") + "error: \(message)")
                if r.isWindowSensitive {
                    recordSourceFailed = true
                } else if r.name == CodexLimitsSource.sourceName {
                    // Not a Claude subscription failure (spec 007 FR-021).
                    codexLimitsSourceFailed = true
                } else {
                    subscriptionSourceFailure = message
                }
            }
        }

        if let failure = subscriptionSourceFailure, subscriptions.isEmpty, let previous = previousSnapshot {
            // Keep the last known values, marked stale (US1 scenario 3).
            subscriptions = previous.subscriptions.mapValues { entry in
                var copy = entry
                switch entry.state {
                case .ok:
                    copy.state = .stale(lastGoodAt: entry.status?.fetchedAt, error: failure)
                case .stale(let at, _), .retrying(let at, _, _), .signInRejected(let at):
                    // Grace and rejected sign-ins become stale with the
                    // source failure, keeping their last good time (spec 010).
                    copy.state = .stale(lastGoodAt: at, error: failure)
                    copy.quickRetryAt = nil
                case .notSignedIn, .credentialsExpired:
                    break
                }
                return copy
            }
        }

        var snapshot = aggregator.aggregate(records: records, subscriptions: subscriptions,
                                            configuration: configuration, window: window, windowSource: windowSource,
                                            now: started, calendar: calendar, staleHarnesses: staleHarnesses)
        snapshot.generatedAt = started
        snapshot.sourceErrors = sourceErrors
        snapshot.configError = configError?.message
        snapshot.codexLimits = codexLimits
        if codexLimitsSourceFailed, let previous = previousSnapshot {
            // Keep the last shown limits of the accounts that still exist;
            // live values become stale (spec 007 FR-005, FR-021).
            let configured = Set(configuration.codexSubscriptionAccounts.map(\.id))
            for (id, entry) in previous.codexLimits where configured.contains(id) && codexLimits[id] == nil {
                snapshot.codexLimits[id] = entry.markedStale(reason: "refresh failed")
            }
        }
        // A reprice fetches nothing, so it does not count as a successful
        // refresh of the network-bound data. Isolated errors (record batch
        // issues, one Codex account's limits) affect one location, harness
        // or account only, whose entries are marked stale on their own, so
        // they do not hold back the refresh time (spec 006 FR-006, spec 007
        // FR-006).
        // Values in a grace period are not a failure, but the refresh time
        // stays the time of the last good values (spec 010 FR-005).
        let inGrace = snapshot.subscriptions.values.contains { if case .retrying = $0.state { return true }; return false }
        let refreshFailed = sourceErrors.count > isolatedErrorCount || inGrace
        snapshot.lastSuccessfulRefreshAt = !refreshFailed && endpointCalled ? started
            : previousSnapshot?.lastSuccessfulRefreshAt ?? (refreshFailed ? nil : started)
        snapshot.endpointBlockedUntil = policy.blockedUntil.flatMap { $0 > started ? $0 : nil }
        snapshot.nextRetryAt = nextRetryAt

        if recordSourceFailed {
            // Carry the previous values over (or, on the first refresh, the
            // empty ones) and mark them stale (FR-007).
            // Carried-over group entries keep their old `period` and `window`:
            // they are shown as stale and the threshold tracker skips them.
            // The early result from saved values has no budgets, so after
            // it the fresh ones are kept (spec 010 FR-015).
            if let previous = previousSnapshot, !previous.isPreliminary {
                snapshot.groups = previous.groups
                snapshot.accountBudgets = previous.accountBudgets
                snapshot.tokenAccounts = previous.tokenAccounts
                snapshot.codexPlanTokens = previous.codexPlanTokens
                snapshot.unassigned = previous.unassigned
            }
            snapshot.groups = snapshot.groups.mapValues { var g = $0; g.stale = true; return g }
            snapshot.accountBudgets = snapshot.accountBudgets.mapValues { var g = $0; g.stale = true; return g }
            snapshot.tokenAccounts = snapshot.tokenAccounts.mapValues { var t = $0; t.stale = true; return t }
            snapshot.codexPlanTokens = snapshot.codexPlanTokens.mapValues { var t = $0; t.stale = true; return t }
            snapshot.unassigned.stale = true
        }

        for owner in configuration.budgetOwners {
            let entries = owner.kind == .group ? snapshot.groups : snapshot.accountBudgets
            guard let entry = entries[owner.id] else { continue }
            // The owner's own window and the calendar time zone, so a month
            // boundary or a time zone move can be checked (spec 003 FR-016).
            // Named by the owner's name, not its icon (spec 004 FR-004).
            log.append(source: "refresh", message: "\(owner.kind == .group ? "group" : "account budget") \(owner.name) (\(entry.period.adjective), \(iso(entry.window.start)) to \(iso(entry.window.end)), \(calendar.timeZone.identifier)): \(entry.spentUSD) of \(entry.budgetUSD) USD (\(entry.percent)%)"
                       + (entry.incomplete ? ", incomplete (unpriced: \(entry.breakdown.unpricedModels.joined(separator: ", ")))" : "")
                       + (entry.stale ? ", stale" : ""))
        }
        let elapsed = clock().timeIntervalSince(started)
        let windowText = "\(iso(window.start)) to \(iso(window.end)) (\(windowSource == .fallback ? "fallback" : "aligned"))"
        let endpointText: String
        if networkSources.isEmpty {
            endpointText = "no endpoint"
        } else if endpointCalled {
            endpointText = "endpoint fetched"
        } else if mode == .full {
            endpointText = "endpoint not called (no Claude retry due)"
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

    /// Before the alignment account's first successful request, a saved
    /// 7-day reset that has passed no longer aligns the window: alignment
    /// behaves as without a reset time (spec 010 FR-020).
    private func dropPassedSavedAlignmentReset(now: Date) {
        guard let reset = lastAlignmentReset, accountsFetchedThisRun[reset.accountId] == nil,
              reset.resetsAt <= now else { return }
        lastAlignmentReset = nil
    }

    /// Replaces any pending follow-up with one at `date` (plus 1 s, so the
    /// block or spacing has ended when it runs). `trigger` is `.retry` after
    /// a rate limit, `.settings` for a spaced subscription edit.
    private func scheduleRetry(at date: Date, trigger: RefreshTrigger) {
        retryTask?.cancel()
        nextRetryAt = date
        retryTrigger = trigger
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
        retryTrigger = nil
        requestRefresh(trigger: trigger)
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        nextRetryAt = nil
        retryTrigger = nil
    }

    // MARK: Quick retry (spec 010 FR-004, FR-008, research R2)

    /// Sets the quick-retry timer to the earliest `quickRetryAt` of the
    /// snapshot's Claude and Codex entries that is still due, or cancels it
    /// when there is none. A time that passed while the refresh ran but is
    /// inside its due window (`retryAt + delay`) fires at once, so a slow
    /// refresh never loses its retry (spec 010 FR-004). An unchanged
    /// earliest time keeps the timer, or the quick retry it already queued;
    /// only when neither is left (a scheduled tick replaced the queued retry
    /// but sent no request) is it set again. Any other change also drops a
    /// quick retry the timer already queued, and a drop is logged (spec 010
    /// FR-003).
    private func updateQuickRetry(after snapshot: UsageSnapshot, trigger: RefreshTrigger) {
        let now = clock()
        let times = snapshot.subscriptions.values.compactMap(\.quickRetryAt) + snapshot.codexLimits.values.compactMap(\.quickRetryAt)
        let earliest = times.filter { $0.addingTimeInterval(RetryEpisodes.delay) > now }.min()
        let queued = pendingTrigger == .quickRetry || pendingQuickRetry
        let pending = quickRetryTask != nil || queued
        guard earliest != nextQuickRetryAt || (earliest != nil && !pending) else { return }
        if pending, trigger != .quickRetry {
            log.append(source: "refresh", message: earliest == nil
                       ? "quick retry dropped (\(trigger.rawValue) refresh took its place)"
                       : "quick retry moved")
        }
        quickRetryTask?.cancel()
        quickRetryTask = nil
        // A quick retry the fired timer queued is for the old time: with no
        // retry left it would run without a request, and a new time gets
        // its own timer (spec 010 FR-003, FR-008).
        if pendingTrigger == .quickRetry { pendingTrigger = nil }
        pendingQuickRetry = false
        nextQuickRetryAt = earliest
        guard let earliest else { return }
        let delay = max(0, earliest.timeIntervalSince(now)) + 1
        let sleep = quickRetrySleep
        quickRetryTask = Task { [weak self] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            await self?.fireQuickRetry()
        }
        log.append(source: "refresh", message: "quick retry timer set for \(iso(earliest))")
    }

    /// Keeps `nextQuickRetryAt` until the quick retry runs (`performRefresh`
    /// clears it), so a refresh that runs before it neither ends the grace
    /// period nor sets a second timer for the same time (spec 010 FR-008).
    private func fireQuickRetry() {
        quickRetryTask = nil
        requestRefresh(trigger: .quickRetry)
    }

    /// A quick retry held back by a rate-limit wait ends the grace period
    /// of the stored Claude entries whose retry time has come: they turn
    /// stale and lose their retry time, so a later reuse neither shows them
    /// unmarked nor sets the timer again (spec 010 FR-007). Returns their
    /// account ids, sorted.
    private func endSuppressedGrace(now: Date) -> [String] {
        var ended: [String] = []
        for (name, stored) in lastNetworkResults {
            guard case .success(.subscriptions(var entries)) = stored.result else { continue }
            for (id, entry) in entries {
                guard let at = entry.quickRetryAt, at <= now else { continue }
                var copy = entry.endingGrace(now: now)
                copy.quickRetryAt = nil
                entries[id] = copy
                ended.append(id)
            }
            lastNetworkResults[name]?.result = .success(.subscriptions(entries))
        }
        return ended.sorted()
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
            case .retrying(let at, let error, let retryAt):
                return "\(id)=retrying(since \(at.map(iso) ?? "never"), retry at \(iso(retryAt)): \(error))"
            case .signInRejected(let at):
                return "\(id)=signInRejected(since \(at.map(iso) ?? "never"))"
            }
        }.joined(separator: ", ")
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
