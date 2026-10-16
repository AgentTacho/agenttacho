import CryptoKit
import Foundation

/// Plan limits of every Codex subscription account (spec 007 FR-001 to
/// FR-008, FR-020, FR-021, research R4 to R6).
///
/// Per account and refresh: the newest plan snapshot from the session logs
/// of the account's Codex home, and, with live limits on, a request to the
/// plan's usage service when one is due. The shown observation is the live
/// result, or else the newer of the last live result and the snapshot. The
/// last live result is kept in memory and, with a store, saved across
/// launches (FR-005, spec 010 FR-017). A `Retry-After` wait
/// counts up to one hour (FR-007).
///
/// A plain source, not `NetworkBoundSource`: it runs on every refresh,
/// reprices included, and decides about the network itself with a fetch
/// gate per Codex home (research R5). It never writes to a Codex home and
/// never logs credential text (FR-003, FR-018).
///
/// Failed requests are classified (spec 010 FR-001); the first transport
/// failure of an episode after a live success keeps the shown observation
/// unmarked (`.retrying`) until one quick retry 30 s later, which bypasses
/// the per-home spacing (spec 010 FR-004, FR-005, FR-008).
///
/// With a `LastGoodStore`, the last live result survives a relaunch: it is
/// seeded once into the last live result, competes with snapshots by
/// observation time and is written back when it changed (spec 010 FR-013,
/// FR-015, FR-017). A saved result never gets a grace period (FR-005).
public actor CodexLimitsSource: EndpointGatedSource, SavedValuesSource {
    /// The refresh coordinator recognizes the source's failure by this name
    /// and carries its entries over (FR-021, plan Design Note 6).
    public static let sourceName = "codexLimits"
    public nonisolated let name = CodexLimitsSource.sourceName

    /// Minimum time between requests for one Codex home on `.manual`,
    /// `.wake`, `.settings`, `.retry`, `.launch`, `.dropdownOpen` and
    /// `.idleReturn` refreshes, as for the Claude usage endpoint.
    static let minimumSpacing: TimeInterval = EndpointPolicy.minimumSpacing

    /// Longest `Retry-After` wait honoured for one Codex home; a longer
    /// stated wait counts as this one (FR-007).
    static let maximumRetryAfter: TimeInterval = 3600

    static let expiredReason = "Codex sign-in expired, run Codex to renew it"
    static let rateLimitedReason = "rate limited by the usage service"
    static let noLocalLimitsReason = "no Codex plan limits recorded in this Codex home"
    static let rejectedSourceError = "Codex sign-in rejected"
    static let rejectedReason = "Codex sign-in rejected, run Codex to renew it"
    static let noLiveLimitsYetReason = "no live limits yet"

    /// Request state of one Codex home (one Codex sign-in, FR-007).
    struct FetchGate {
        var lastFetchAt: Date?
        var blockedUntil: Date?
    }

    /// The newest snapshot of one rollout file and what decided to parse it.
    struct FileSnapshot {
        var size: Int
        var modificationDate: Date
        var snapshot: CodexLimitObservation?
    }

    /// What a failed or skipped live fetch shows: the stale reason and, for
    /// an unreadable answer or a rejected sign-in, a source error (FR-006).
    struct Failure: Equatable {
        var reason: String
        var sourceError: String?
        /// A rejected sign-in, from a 401 or 403 answer or a token already
        /// rejected (spec 010 FR-012).
        var signInRejected = false
        /// A missing or expired sign-in found before a request (spec 014
        /// FR-001).
        var credentialProblem: CodexCredentialProblem?
    }

    private enum Action {
        case off
        case fetch
        /// No request is due (reprice or spacing): without an earlier
        /// failure, nothing is marked stale.
        case notDue
        /// A rate-limit wait for this Codex home (FR-007).
        case blocked(until: Date)

        /// True when live limits are on for the account.
        var isLive: Bool {
            if case .off = self { return false }
            return true
        }
    }

    private enum LiveResult {
        case success(CodexLimitObservation)
        /// No request was made: sign-in missing, expired, unreadable or
        /// already rejected.
        case noRequest(Failure)
        /// The request failed at `at`; the digest identifies the token that
        /// was sent. The quick retry counts from `at` (spec 010 FR-004).
        case failed(Error, tokenDigest: Data, at: Date)
    }

    private struct Plan {
        let account: Account
        let settings: CodexSubscriptionSettings
        let home: String
        let action: Action
    }

    private let credentialReader: CodexCredentialReader
    private let client: CodexUsageClient
    private let log: DiagnosticLog?
    private let paths: Paths
    private let clock: @Sendable () -> Date

    /// The last successful live result per account (FR-005); seeded from
    /// the saved values at launch (spec 010 FR-017).
    private var lastLive: [String: CodexLimitObservation] = [:]
    /// The outcome of the last failed live attempt per account, shown again
    /// while no new request is due.
    private var lastFailure: [String: Failure] = [:]
    /// Canonical Codex home per account at the last refresh.
    private var accountHomes: [String: String] = [:]
    /// The canonical Codex home each account had a fetch attempt for while
    /// live limits were on (research R5).
    private var attemptedHome: [String: String] = [:]
    /// Keyed by canonical Codex home.
    private var gates: [String: FetchGate] = [:]
    /// SHA-256 of the access token the usage service rejected with HTTP 401,
    /// per canonical Codex home, in memory only. The same token is not sent
    /// again on scheduled refreshes; Codex replaces it when it renews the
    /// sign-in (FR-003). A manual refresh or turning live limits off clears it.
    private var rejectedTokens: [String: Data] = [:]
    /// Keyed by canonical Codex home, then by canonical file path.
    private var files: [String: [String: FileSnapshot]] = [:]

    /// Failure episodes per account (spec 010 FR-004 to FR-009).
    private var episodes = RetryEpisodes()
    /// Accounts with a live success in this run; only their values get a
    /// grace period (spec 010 FR-005, plan Design Note 10).
    private var liveThisRun: Set<String> = []

    private let store: LastGoodStore?
    /// True once the saved values were read from the store.
    private var seeded = false
    /// The Codex section last handed to (or loaded from) the store.
    private var lastSaved: [String: SavedCodexValues] = [:]

    /// Rollout files parsed by the last `collect` (for tests).
    public private(set) var lastFilesParsed = 0

    public init(credentialReader: CodexCredentialReader, client: CodexUsageClient, log: DiagnosticLog? = nil,
                paths: Paths = Paths(), clock: @escaping @Sendable () -> Date = { Date() }, store: LastGoodStore? = nil) {
        self.credentialReader = credentialReader
        self.client = client
        self.log = log
        self.paths = paths
        self.clock = clock
        self.store = store
    }

    /// Seeds the last live result once from the store, for accounts with
    /// live limits on and the same canonical Codex home; the home is
    /// recorded too, so the first collect keeps it. A future observation
    /// time counts as `now` (spec 010 FR-015, FR-017).
    private func seedIfNeeded(configuration: Configuration, now: Date) async {
        guard !seeded, let store else { return }
        seeded = true
        let saved = await store.values().codex
        lastSaved = saved
        var count = 0
        for account in configuration.codexSubscriptionAccounts {
            guard let settings = account.kind.codexSubscription, settings.liveLimits, lastLive[account.id] == nil,
                  let values = saved[account.id] else { continue }
            let home = Attributor.canonical(paths.expand(settings.codexHome))
            guard values.codexHome == home else { continue }
            lastLive[account.id] = values.observation(now: now)
            accountHomes[account.id] = home
            count += 1
        }
        if count > 0 {
            log?.append(source: name, message: "seeded saved live limits for \(count) account(s)", at: clock())
        }
    }

    /// The newer of the saved live result and the newest snapshot per
    /// account, shown while the first refresh runs (spec 010 FR-015,
    /// FR-017); nil when no account has a saved live result.
    public func savedOutput(configuration: Configuration, now: Date) async -> SourceOutput? {
        await seedIfNeeded(configuration: configuration, now: now)
        var parsed = 0
        var entries: [String: CodexLimitsEntry] = [:]
        for account in configuration.codexSubscriptionAccounts {
            guard let settings = account.kind.codexSubscription, settings.liveLimits, let live = lastLive[account.id] else { continue }
            let home = Attributor.canonical(paths.expand(settings.codexHome))
            let snapshot = newestSnapshot(home: home, newerThan: live.observedAt, parsed: &parsed)
            entries[account.id] = Self.notDue(live: live, snapshot: snapshot, now: now)
        }
        return entries.isEmpty ? nil : .codexLimits(entries)
    }

    /// Hands the last live results of accounts with live limits on to the
    /// store when they changed (spec 010 FR-013, FR-017).
    private func save(plans: [Plan]) async {
        guard let store else { return }
        var saved: [String: SavedCodexValues] = [:]
        for plan in plans where plan.action.isLive {
            guard let live = lastLive[plan.account.id] else { continue }
            saved[plan.account.id] = SavedCodexValues(codexHome: plan.home, observation: live)
        }
        guard saved != lastSaved else { return }
        lastSaved = saved
        await store.replace(codex: saved)
    }

    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let now = context.now
        let configuration = context.configuration
        await seedIfNeeded(configuration: configuration, now: now)
        var parsed = 0
        var plans: [Plan] = []
        let liveHomes = Set(configuration.codexSubscriptionAccounts.compactMap { account -> String? in
            guard let settings = account.kind.codexSubscription, settings.liveLimits else { return nil }
            return Attributor.canonical(paths.expand(settings.codexHome))
        })
        for account in configuration.codexSubscriptionAccounts {
            guard let settings = account.kind.codexSubscription else { continue }
            let home = Attributor.canonical(paths.expand(settings.codexHome))
            if accountHomes[account.id] != home {
                // A live result of another Codex home is not this account's.
                lastLive[account.id] = nil
                lastFailure[account.id] = nil
                liveThisRun.remove(account.id)
                episodes.succeeded(account.id)
            }
            if episodes.isRetryOverdue(account.id, now: now) {
                // The grace period passed its due window without a request
                // (plan Design Note 10): its quick retry counts as used.
                episodes.expire(account.id)
                log?.append(source: name, message: "\(account.id): quick retry not sent in time, episode exhausted", at: clock())
            }
            accountHomes[account.id] = home
            if context.trigger == .manual || !liveHomes.contains(home) {
                // A manual refresh or a live-limits toggle is the user asking
                // for a retry: a rejected token may be tried once more. An
                // account with live limits on for the same home keeps it.
                rejectedTokens[home] = nil
            }
            let action: Action
            if settings.liveLimits {
                action = decide(accountId: account.id, home: home, now: now, trigger: context.trigger,
                                paceDue: context.codexPaceDue)
            } else {
                // Only snapshots; earlier live results are discarded (FR-005).
                lastLive[account.id] = nil
                lastFailure[account.id] = nil
                attemptedHome[account.id] = nil
                liveThisRun.remove(account.id)
                episodes.succeeded(account.id)
                action = .off
            }
            plans.append(Plan(account: account, settings: settings, home: home, action: action))
        }

        // Credential reads and requests run concurrently; one account's
        // failure never affects another (FR-021). One request per Codex home
        // (one sign-in, FR-007), keyed by the canonical home.
        let results: [String: LiveResult] = await withTaskGroup(of: (String, LiveResult).self) { group in
            var requested = Set<String>()
            for plan in plans {
                guard case .fetch = plan.action, requested.insert(plan.home).inserted else { continue }
                let codexHome = plan.settings.codexHome
                let rejected = rejectedTokens[plan.home]
                group.addTask { [credentialReader, client, clock] in
                    (plan.home, await Self.live(reader: credentialReader, client: client, codexHome: codexHome,
                                                rejectedToken: rejected, now: now, clock: clock))
                }
            }
            var collected: [String: LiveResult] = [:]
            for await (id, result) in group { collected[id] = result }
            return collected
        }

        var entries: [String: CodexLimitsEntry] = [:]
        for plan in plans {
            let id = plan.account.id
            // Only a snapshot newer than the kept live result can be shown,
            // so the scan stops at older files (FR-004, FR-005).
            let liveObservedAt = lastLive[id]?.observedAt
            var entry: CodexLimitsEntry
            var note: String
            switch plan.action {
            case .off:
                if let snapshot = newestSnapshot(home: plan.home, newerThan: nil, parsed: &parsed) {
                    entry = CodexLimitsEntry(observation: snapshot, state: .localOnly)
                } else {
                    entry = CodexLimitsEntry(observation: nil, state: .unavailable(reason: Self.noLocalLimitsReason))
                }
                note = "live limits off"
            case .notDue:
                // The last attempt's outcome stands: a failure keeps the
                // values stale (and the newer of live and snapshot shown).
                // Without one, the newer of the kept live result and the
                // snapshot is shown without stale marking (FR-005, FR-006).
                let snapshot = newestSnapshot(home: plan.home, newerThan: liveObservedAt, parsed: &parsed)
                if let failure = lastFailure[id], let retrying = graceEntry(id: id, live: lastLive[id], snapshot: snapshot,
                                                                           failure: failure, now: now) {
                    // Until the quick retry ran the values stay unmarked (spec 010 FR-005).
                    entry = retrying
                } else if let failure = lastFailure[id] {
                    entry = Self.fallback(live: lastLive[id], snapshot: snapshot, failure: failure, now: now)
                } else if let live = lastLive[id] {
                    entry = Self.notDue(live: live, snapshot: snapshot, now: now)
                } else {
                    entry = Self.fallback(live: nil, snapshot: snapshot, failure: Failure(reason: Self.noLiveLimitsYetReason), now: now)
                }
                note = context.trigger == .scheduled && !context.codexPaceDue
                    ? "no request due (adaptive pace)" : "no request due (\(context.trigger.rawValue))"
            case .blocked(let until):
                let snapshot = newestSnapshot(home: plan.home, newerThan: liveObservedAt, parsed: &parsed)
                note = "rate limited until \(Self.iso(until))"
                if let failure = lastFailure[id], let retryAt = episodes.retryAt(id) {
                    if context.trigger != .quickRetry || now < retryAt {
                        // Until the quick retry runs the grace period goes
                        // on: a refresh without a request leaves it pending
                        // (spec 010 FR-008).
                        entry = graceEntry(id: id, live: lastLive[id], snapshot: snapshot, failure: failure, now: now)
                            ?? Self.fallback(live: lastLive[id], snapshot: snapshot, failure: failure, now: now)
                    } else {
                        // The quick retry is due but blocked: stale with the
                        // transport reason, the retry counts as used (spec 010
                        // FR-007).
                        episodes.expire(id)
                        entry = Self.fallback(live: lastLive[id], snapshot: snapshot, failure: failure, now: now)
                        note += ", quick retry suppressed (rate limited), marked stale (was due at \(Self.iso(retryAt)))"
                    }
                } else {
                    entry = Self.fallback(live: lastLive[id], snapshot: snapshot,
                                          failure: Failure(reason: Self.rateLimitedReason), now: now)
                }
            case .fetch:
                attemptedHome[id] = plan.home
                let sentPrefix = context.trigger == .quickRetry ? "quick retry sent, " : ""
                guard let result = results[plan.home] else {
                    // Every home with a due fetch has a result.
                    assertionFailure("no live result for \(id)")
                    entry = CodexLimitsEntry(observation: nil, state: .unavailable(reason: Self.noLiveLimitsYetReason))
                    note = "no result"
                    break
                }
                switch result {
                case .success(let observation):
                    // The live result is shown; no snapshot can be newer.
                    lastLive[id] = observation
                    lastFailure[id] = nil
                    rejectedTokens[plan.home] = nil
                    gates[plan.home, default: FetchGate()].lastFetchAt = now
                    liveThisRun.insert(id)
                    episodes.succeeded(id)
                    entry = CodexLimitsEntry(observation: observation, state: .live, reachedService: true)
                    note = sentPrefix + "fetched"
                case .noRequest(let failure):
                    // Shown stale: a later transport failure must not unmark
                    // the values again, and a pending quick retry is dropped
                    // (spec 010 FR-002, FR-005).
                    liveThisRun.remove(id)
                    episodes.expire(id)
                    lastFailure[id] = failure
                    let snapshot = newestSnapshot(home: plan.home, newerThan: liveObservedAt, parsed: &parsed)
                    entry = Self.fallback(live: lastLive[id], snapshot: snapshot, failure: failure, now: now)
                    note = sentPrefix + "no request: " + failure.reason
                case .failed(let error, let tokenDigest, let failedAt):
                    gates[plan.home, default: FetchGate()].lastFetchAt = now
                    if case .rateLimited(let wait)? = error as? UsageEndpointError {
                        // Without a stated wait, skip one refresh interval;
                        // a stated wait counts up to one hour (FR-007).
                        let stated = wait.map { min($0, Self.maximumRetryAfter) }
                        let until = now.addingTimeInterval(stated ?? TimeInterval(configuration.refreshIntervalSeconds))
                        gates[plan.home, default: FetchGate()].blockedUntil = until
                    }
                    if case .httpStatus(401)? = error as? UsageEndpointError {
                        rejectedTokens[plan.home] = tokenDigest
                    }
                    let failure = Self.failure(for: error)
                    lastFailure[id] = failure
                    let snapshot = newestSnapshot(home: plan.home, newerThan: liveObservedAt, parsed: &parsed)
                    let category = FailureCategory.classify(error)
                    let phase = episodes.failed(id, category: category, now: max(failedAt, now),
                                                hasLiveValuesThisRun: liveThisRun.contains(id))
                    note = sentPrefix + "request failed: " + Self.detail(of: error) + " (\(category.rawValue))"
                    if case .grace(let retryAt, _) = phase {
                        note += ", quick retry scheduled at \(Self.iso(retryAt))"
                    }
                    entry = graceEntry(id: id, live: lastLive[id], snapshot: snapshot, failure: failure, now: now)
                        ?? Self.fallback(live: lastLive[id], snapshot: snapshot, failure: failure, now: now)
                    // An answer reached the service unless the failure is a
                    // transport failure, HTTP 5xx included (spec 016 FR-005).
                    entry.reachedService = category != .transport
                }
                // A due fetch tried the home, with or without a request
                // (spec 016 FR-012, FR-014).
                entry.attempted = true
            }
            if plan.action.isLive {
                entry.quickRetryAt = episodes.retryAt(id)
            }
            entries[id] = entry
            log?.append(source: name, message: "\(id): " + Self.describe(entry) + ", \(note)", at: clock())
        }
        lastFilesParsed = parsed

        // Forget accounts and Codex homes the configuration no longer has.
        let ids = Set(plans.map(\.account.id))
        let homes = Set(plans.map(\.home))
        lastLive = lastLive.filter { ids.contains($0.key) }
        lastFailure = lastFailure.filter { ids.contains($0.key) }
        accountHomes = accountHomes.filter { ids.contains($0.key) }
        attemptedHome = attemptedHome.filter { ids.contains($0.key) }
        liveThisRun = liveThisRun.filter { ids.contains($0) }
        episodes.forget(except: ids)
        gates = gates.filter { homes.contains($0.key) }
        rejectedTokens = rejectedTokens.filter { homes.contains($0.key) }
        files = files.filter { homes.contains($0.key) }
        await save(plans: plans)
        return .codexLimits(entries)
    }

    /// The `.retrying` entry of an account in an unmarked grace period
    /// whose quick retry has not been attempted yet; nil otherwise (spec
    /// 010 FR-005). The phase stays `.grace` until the retry is sent, is
    /// suppressed or its due window passes (all of which end it), so a
    /// refresh without a request between the retry time and the
    /// coordinator's timer (`retryAt + 1 s`) keeps the values unmarked.
    private func graceEntry(id: String, live: CodexLimitObservation?, snapshot: CodexLimitObservation?,
                            failure: Failure, now: Date) -> CodexLimitsEntry? {
        guard case .grace(let retryAt, true)? = episodes.phases[id], !episodes.isRetryOverdue(id, now: now),
              let shown = Self.newer(live: live, snapshot: snapshot, now: now) else { return nil }
        return CodexLimitsEntry(observation: shown, state: .retrying(reason: failure.reason, retryAt: retryAt),
                                credentialProblem: failure.credentialProblem)
    }

    /// Test hook, not used by the app: blocks requests for `home` until
    /// `until`, as a rate limit would, for tests of a quick retry that falls
    /// into a rate-limit wait (spec 010 FR-007).
    func block(home: String, until: Date) {
        gates[Attributor.canonical(paths.expand(home)), default: FetchGate()].blockedUntil = until
    }

    // MARK: - Fetch gate (research R5)

    /// `paceDue` is the adaptive pace's answer for a scheduled refresh; it
    /// holds back only that trigger (spec 016 FR-006, research R4).
    private func decide(accountId: String, home: String, now: Date, trigger: RefreshTrigger, paceDue: Bool) -> Action {
        let gate = gates[home] ?? FetchGate()
        if let until = gate.blockedUntil, until > now {
            return .blocked(until: until)
        }
        // A new account, a changed Codex home or live limits turned back on:
        // fetch once, whatever the trigger.
        if attemptedHome[accountId] != home {
            return .fetch
        }
        switch trigger {
        case .scheduled:
            return paceDue ? .fetch : .notDue
        case .quickRetry:
            // Only accounts in a grace period whose retry is due, without the
            // spacing (spec 010 FR-008, FR-009).
            return episodes.isRetryDue(accountId, now: now) ? .fetch : .notDue
        case .local:
            return .notDue
        case .manual, .wake, .settings, .retry, .launch, .dropdownOpen, .idleReturn:
            // The dropdown-open and return-from-idle refreshes are spaced
            // per home like wake (spec 016 FR-011, FR-012, research R6).
            if let last = gate.lastFetchAt, now.timeIntervalSince(last) < Self.minimumSpacing {
                return .notDue
            }
            return .fetch
        }
    }

    /// Reads the sign-in and fetches the limits. No request is made for a
    /// missing, expired or unreadable sign-in (FR-003), nor for a token the
    /// service already rejected.
    private static func live(reader: CodexCredentialReader, client: CodexUsageClient, codexHome: String,
                             rejectedToken: Data?, now: Date, clock: @Sendable () -> Date) async -> LiveResult {
        let lookup: CodexCredentialLookup
        do {
            lookup = try reader.read(codexHome: codexHome)
        } catch {
            let reason = (error as? CodexCredentialError)?.message ?? "Codex sign-in could not be read"
            return .noRequest(Failure(reason: reason))
        }
        switch lookup {
        case .missing(let reason):
            let problem: CodexCredentialProblem = reason == CodexCredentialLookup.keychain ? .keychain : .notSignedIn
            return .noRequest(Failure(reason: reason, credentialProblem: problem))
        case .found(let credential):
            if credential.isExpired(now: now), let expiresAt = credential.expiresAt {
                return .noRequest(Failure(reason: expiredReason, credentialProblem: .expired(at: expiresAt)))
            }
            let digest = Data(SHA256.hash(data: Data(credential.accessToken.utf8)))
            if digest == rejectedToken {
                return .noRequest(Failure(reason: rejectedReason, sourceError: rejectedSourceError, signInRejected: true))
            }
            do {
                return .success(try await client.fetch(credential, observedAt: now))
            } catch {
                return .failed(error, tokenDigest: digest, at: clock())
            }
        }
    }

    // MARK: - Selection (research R6)

    /// The newer of the last live result and the snapshot; a snapshot time
    /// in the future counts as `now`, and the live result wins a tie
    /// (FR-005).
    static func newer(live: CodexLimitObservation?, snapshot: CodexLimitObservation?, now: Date) -> CodexLimitObservation? {
        switch (live, snapshot) {
        case (let live?, let snapshot?):
            return live.observedAt >= min(snapshot.observedAt, now) ? live : snapshot
        case (let live?, nil):
            return live
        case (nil, let snapshot?):
            return snapshot
        case (nil, nil):
            return nil
        }
    }

    /// A refresh without a due request after a successful one: the kept
    /// live result stays `.live` unless a newer snapshot exists, which is
    /// shown as `.newerSnapshot`; nothing failed, so neither is stale
    /// (FR-005, FR-006 exception).
    static func notDue(live: CodexLimitObservation, snapshot: CodexLimitObservation?, now: Date) -> CodexLimitsEntry {
        let chosen = newer(live: live, snapshot: snapshot, now: now) ?? live
        return CodexLimitsEntry(observation: chosen, state: chosen == live ? .live : .newerSnapshot)
    }

    /// The newer of the last live result and the snapshot, marked stale with
    /// the failure's reason (FR-005, FR-006). Unavailable without either.
    /// A rejected sign-in sets `signInRejected` for the attention style
    /// (spec 010 FR-012).
    static func fallback(live: CodexLimitObservation?, snapshot: CodexLimitObservation?, failure: Failure, now: Date) -> CodexLimitsEntry {
        guard let chosen = newer(live: live, snapshot: snapshot, now: now) else {
            return CodexLimitsEntry(observation: nil, state: .unavailable(reason: failure.reason), sourceError: failure.sourceError,
                                    signInRejected: failure.signInRejected, credentialProblem: failure.credentialProblem)
        }
        return CodexLimitsEntry(observation: chosen, state: .stale(reason: failure.reason), sourceError: failure.sourceError,
                                signInRejected: failure.signInRejected, credentialProblem: failure.credentialProblem)
    }

    /// The stale reason and source error of a failed request
    /// (contracts/codex-usage-endpoint.md section 1). Only our own error
    /// types are described, so no text from the answer or the sign-in
    /// reaches a message (FR-018).
    static func failure(for error: Error) -> Failure {
        let category = FailureCategory.classify(error)
        let endpoint = error as? UsageEndpointError
        switch category {
        case .transport:
            if case .httpStatus(let code)? = endpoint {
                return Failure(reason: "usage service unavailable (HTTP \(code))")
            }
            return Failure(reason: "offline")
        case .signInRejected:
            let reason = endpoint == .httpStatus(401) ? rejectedReason : rejectedSourceError
            return Failure(reason: reason, sourceError: rejectedSourceError, signInRejected: true)
        case .rateLimited:
            return Failure(reason: rateLimitedReason)
        case .serviceChanged:
            switch endpoint {
            case .decoding?:
                return Failure(reason: "usage service changed", sourceError: "usage service changed")
            case .httpStatus(let code)?:
                return Failure(reason: "usage service returned HTTP \(code)")
            default:
                return Failure(reason: CodexUsageError.noLimits.description)
            }
        }
    }

    /// The failure's cause for the diagnostic log (FR-020). Only our own
    /// error types are described; none of them holds the token (FR-018).
    static func detail(of error: Error) -> String {
        if let error = error as? UsageEndpointError { return error.description }
        if let error = error as? CodexUsageError { return error.description }
        return String(describing: type(of: error))
    }

    // MARK: - Snapshots (research R4)

    /// The newest plan snapshot under `<home>/sessions`, at any age
    /// (FR-004). Files are visited newest first; the scan stops once the
    /// best snapshot is at least as new as the next file's modification
    /// date (rollout files are append-only), or once the next file is no
    /// newer than `newerThan`: the kept live result wins a tie, so no
    /// snapshot in that file could be shown (FR-005). Unchanged files are
    /// not parsed again; an unreadable file is logged and retried on the
    /// next refresh.
    private func newestSnapshot(home: String, newerThan bound: Date?, parsed: inout Int) -> CodexLimitObservation? {
        var errors: [String] = []
        let listed = CodexSessionSource.rolloutFiles(under: URL(fileURLWithPath: home).appendingPathComponent("sessions"), errors: &errors)
        for error in errors {
            log?.append(source: name, message: "\(home): \(error)", at: clock())
        }
        let present = Set(listed.map(\.path))
        var cache = (files[home] ?? [:]).filter { present.contains($0.key) }
        var best: CodexLimitObservation?
        for file in listed.sorted(by: { $0.modificationDate > $1.modificationDate }) {
            if let best, best.observedAt >= file.modificationDate { break }
            if let bound, file.modificationDate <= bound { break }
            let snapshot: CodexLimitObservation?
            if let cached = cache[file.path], cached.size == file.size, cached.modificationDate == file.modificationDate {
                snapshot = cached.snapshot
            } else {
                guard let data = FileManager.default.contents(atPath: file.path) else {
                    log?.append(source: name, message: "\(home): error: cannot read \(file.path)", at: clock())
                    continue
                }
                snapshot = CodexSessionParser.latestLimitSnapshot(in: data)
                cache[file.path] = FileSnapshot(size: file.size, modificationDate: file.modificationDate, snapshot: snapshot)
                parsed += 1
            }
            if let snapshot, best.map({ snapshot.observedAt > $0.observedAt }) ?? true {
                best = snapshot
            }
        }
        files[home] = cache
        return best
    }

    // MARK: - Logging (FR-020)

    /// Which source supplied the shown values, the observation time and
    /// the reason; never a token.
    static func describe(_ entry: CodexLimitsEntry) -> String {
        let origin: String
        switch entry.observation?.origin {
        case .live?: origin = "live"
        case .snapshot?: origin = "snapshot"
        case nil: origin = "none"
        }
        let observed = entry.observation.map { ", observed \(iso($0.observedAt))" } ?? ""
        switch entry.state {
        case .live:
            return "live\(observed)"
        case .newerSnapshot:
            return "newer snapshot, \(origin)\(observed)"
        case .localOnly:
            return "local only, \(origin)\(observed)"
        case .stale(let reason):
            return "stale, \(origin)\(observed), reason: \(reason)"
        case .unavailable(let reason):
            return "unavailable, reason: \(reason)"
        case .retrying(let reason, let retryAt):
            return "retrying at \(iso(retryAt)), \(origin)\(observed), reason: \(reason)"
        }
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
