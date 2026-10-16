import Foundation

/// Fetches the provider-reported limits for every subscription account
/// (FR-011). Keeps the last good status per account so a failure yields
/// `.stale` with the previous values (SC-007). Never logs or returns a token.
/// Network-bound: a reprice reuses its last result (FR-023a).
///
/// Failed requests are classified (spec 010 FR-001). The first transport
/// failure of an episode keeps values of this run unmarked (`.retrying`)
/// until one quick retry 30 s later (spec 010 FR-004, FR-005); a rejected
/// sign-in is its own state (spec 010 FR-010).
///
/// With a `LastGoodStore`, the last good values survive a relaunch: they are
/// seeded once from the store, shown early by `savedOutput`, and written
/// back after every collect that changed them (spec 010 FR-013 to FR-015).
/// Saved values never get a grace period (spec 010 FR-005).
public actor SubscriptionSource: NetworkBoundSource, SavedValuesSource {
    public static let sourceName = "subscription"
    public nonisolated let name = SubscriptionSource.sourceName

    private let credentialReader: CredentialReader
    private let client: UsageEndpointClient
    private let log: DiagnosticLog?
    private let clock: @Sendable () -> Date
    private var lastGood: [String: SubscriptionStatus] = [:]
    /// Failure episodes per account (spec 010 FR-004 to FR-009).
    private var episodes = RetryEpisodes()
    /// Accounts with a successful request in this run; only their values
    /// get a grace period (spec 010 FR-005).
    private var liveThisRun: Set<String> = []
    /// The entry of each account at the last collect, returned for accounts
    /// a quick retry does not request (spec 010 FR-009).
    private var lastEntries: [String: SubscriptionEntry] = [:]
    /// The credential directory of each account at the last collect.
    private var lastDirectories: [String: String] = [:]
    private let store: LastGoodStore?
    private let paths: Paths
    /// True once the saved values were read from the store.
    private var seeded = false
    /// The Claude section last handed to (or loaded from) the store.
    private var lastSaved: [String: SavedClaudeValues] = [:]

    public init(credentialReader: CredentialReader, client: UsageEndpointClient, log: DiagnosticLog? = nil,
                clock: @escaping @Sendable () -> Date = { Date() }, store: LastGoodStore? = nil, paths: Paths = Paths()) {
        self.credentialReader = credentialReader
        self.client = client
        self.log = log
        self.clock = clock
        self.store = store
        self.paths = paths
    }

    /// The canonical form of a configured credential directory, as stored
    /// in the saved file (spec 010 FR-015).
    private func canonical(_ directory: String) -> String {
        Attributor.canonical(paths.expand(directory))
    }

    /// Seeds the last good values once from the store: only entries whose
    /// canonical directory matches the account's, with a future fetch time
    /// clamped to `now` (spec 010 FR-015, edge case "Clock moved backwards").
    private func seedIfNeeded(configuration: Configuration, now: Date) async {
        guard !seeded, let store else { return }
        seeded = true
        let saved = await store.values().claude
        lastSaved = saved
        var count = 0
        for account in configuration.subscriptionAccounts {
            guard let settings = account.kind.subscription, lastGood[account.id] == nil,
                  let values = saved[account.id], values.credentialDirectory == canonical(settings.credentialDirectory) else { continue }
            lastGood[account.id] = values.status(now: now)
            count += 1
        }
        if count > 0 {
            log?.append(source: name, message: "seeded saved last good values for \(count) account(s)")
        }
    }

    /// The saved values as `.ok` entries, shown while the first refresh runs
    /// (spec 010 FR-015); nil when no configured account has any.
    public func savedOutput(configuration: Configuration, now: Date) async -> SourceOutput? {
        await seedIfNeeded(configuration: configuration, now: now)
        var entries: [String: SubscriptionEntry] = [:]
        for account in configuration.subscriptionAccounts {
            guard let status = lastGood[account.id] else { continue }
            entries[account.id] = SubscriptionEntry(status: status, state: .ok)
        }
        return entries.isEmpty ? nil : .subscriptions(entries)
    }

    /// Hands the last good values of the shown accounts to the store when
    /// they changed; accounts without values (a not-signed-in account has
    /// none, `apply` clears them) are dropped (spec 010 FR-013, FR-015).
    private func save(entries: [String: SubscriptionEntry], accounts: [Account]) async {
        guard let store else { return }
        var saved: [String: SavedClaudeValues] = [:]
        for account in accounts {
            guard let settings = account.kind.subscription, let status = lastGood[account.id],
                  entries[account.id] != nil else { continue }
            saved[account.id] = SavedClaudeValues(credentialDirectory: canonical(settings.credentialDirectory), status: status)
        }
        guard saved != lastSaved else { return }
        lastSaved = saved
        await store.replace(claude: saved)
    }

    /// What one account's request produced, before the episode rules apply.
    private enum Attempt: Sendable {
        case notSignedIn(String)
        case credentialsExpired(String)
        case credentialReadFailed(String)
        case success(SubscriptionStatus)
        /// The request failed at `at`, the time the quick retry counts
        /// from (spec 010 FR-004).
        case failed(Error, at: Date)
    }

    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let accounts = context.configuration.subscriptionAccounts
        let now = clock()
        let quickRetry = context.trigger == .quickRetry
        await seedIfNeeded(configuration: context.configuration, now: now)
        var entries: [String: SubscriptionEntry] = [:]

        // A grace period whose due window passed without a request (the
        // retry was suppressed by a rate limit) has used its retry
        // (spec 010 FR-007, plan Design Note 10).
        for account in accounts where episodes.isRetryOverdue(account.id, now: now) {
            episodes.expire(account.id)
            log?.append(source: name, message: "\(account.id): quick retry not sent in time, episode exhausted")
        }

        var requested: [(Account, SubscriptionSettings)] = []
        for account in accounts {
            guard let settings = account.kind.subscription else { continue }
            if lastDirectories[account.id].map({ $0 != settings.credentialDirectory }) ?? false {
                // Values of another sign-in are not this account's.
                lastGood[account.id] = nil
                liveThisRun.remove(account.id)
                episodes.succeeded(account.id)
            }
            if quickRetry, let last = lastEntries[account.id], lastDirectories[account.id] == settings.credentialDirectory,
               !episodes.isRetryDue(account.id, now: now) {
                // Not part of this quick retry: keep the last entry without
                // a request (spec 010 FR-009).
                var kept = last.endingGrace(now: now)
                kept.fetchOutcome = nil
                kept.quickRetryAt = episodes.retryAt(account.id)
                entries[account.id] = kept
                continue
            }
            requested.append((account, settings))
        }

        let results: [(String, Attempt)] = await withTaskGroup(of: (String, Attempt).self) { group in
            for (account, settings) in requested {
                group.addTask { [credentialReader, client, clock] in
                    (account.id, await Self.attempt(settings: settings, reader: credentialReader, client: client, now: now,
                                                    clock: clock))
                }
            }
            var collected: [(String, Attempt)] = []
            for await r in group { collected.append(r) }
            return collected
        }

        for (id, attempt) in results.sorted(by: { $0.0 < $1.0 }) {
            let (entry, note) = apply(attempt, id: id, now: now, quickRetry: quickRetry)
            entries[id] = entry
            log?.append(source: name, message: "\(id): \(note)")
        }

        // Forget accounts that disappeared from the configuration.
        let ids = Set(entries.keys)
        lastGood = lastGood.filter { ids.contains($0.key) }
        liveThisRun = liveThisRun.filter { ids.contains($0) }
        episodes.forget(except: ids)
        lastEntries = entries
        lastDirectories = Dictionary(accounts.compactMap { account in
            account.kind.subscription.map { (account.id, $0.credentialDirectory) }
        }, uniquingKeysWith: { first, _ in first })
        await save(entries: entries, accounts: accounts)
        return .subscriptions(entries)
    }

    /// A rate-limit wait kept the quick retry from being sent: the accounts
    /// whose retry is due have used it (spec 010 FR-007).
    public func quickRetrySuppressed(now: Date) async {
        for id in episodes.phases.keys.sorted() where episodes.isRetryDue(id, now: now) {
            episodes.expire(id)
            log?.append(source: name, message: "\(id): quick retry suppressed (rate limited), episode exhausted")
            lastEntries[id] = lastEntries[id]?.endingGrace(now: now)
            lastEntries[id]?.quickRetryAt = nil
        }
    }

    /// Turns an attempt into the account's entry and log note, applying the
    /// failure episode rules (spec 010 FR-002 to FR-010).
    private func apply(_ attempt: Attempt, id: String, now: Date, quickRetry: Bool) -> (SubscriptionEntry, String) {
        let previous = lastGood[id]
        let prefix = quickRetry ? "quick retry: " : ""
        switch attempt {
        case .success, .failed:
            break
        case .notSignedIn, .credentialsExpired, .credentialReadFailed:
            // A failure before a request shows the values stale (or none):
            // a later transport failure must not unmark them again, and a
            // pending quick retry is dropped (spec 010 FR-002, FR-005).
            liveThisRun.remove(id)
            episodes.expire(id)
        }
        switch attempt {
        case .notSignedIn(let note):
            // Values without a sign-in are not shown and not saved, so they
            // are forgotten: a later failed request must not show them again
            // nor the next save write them back (spec 010 FR-015).
            lastGood[id] = nil
            episodes.succeeded(id)
            return (SubscriptionEntry(status: nil, state: .notSignedIn), prefix + note)
        case .credentialsExpired(let note):
            return (SubscriptionEntry(status: previous, state: .credentialsExpired), prefix + note)
        case .credentialReadFailed(let message):
            return (SubscriptionEntry(status: previous, state: .stale(lastGoodAt: previous?.fetchedAt, error: message)), prefix + message)
        case .success(let status):
            lastGood[id] = status
            liveThisRun.insert(id)
            episodes.succeeded(id)
            let five = status.fiveHour.map { "\(PercentFormatter.rounded($0.utilizationPercent))%" } ?? "n/a"
            let seven = status.sevenDay.map { "\(PercentFormatter.rounded($0.utilizationPercent))%" } ?? "n/a"
            return (SubscriptionEntry(status: status, state: .ok, fetchOutcome: .success), prefix + "ok (5h \(five), 7d \(seven))")
        case .failed(let error, let failedAt):
            let message = Self.describe(error)
            let category = FailureCategory.classify(error)
            let outcome: FetchOutcome
            if case .rateLimited(let wait)? = error as? UsageEndpointError {
                outcome = .rateLimited(retryAfter: wait)
            } else {
                outcome = .otherError
            }
            // The retry counts from the failure, not the refresh start: a
            // timeout arrives 30 s after the request (spec 010 FR-004).
            let phase = episodes.failed(id, category: category, now: max(failedAt, now),
                                        hasLiveValuesThisRun: liveThisRun.contains(id))
            var note = prefix + "fetch failed (\(category.rawValue)): \(message)"
                + (previous.map { ", keeping values from \($0.fetchedAt)" } ?? "")
            let state: SubscriptionState
            var retryAt: Date?
            switch phase {
            case .grace(let at, let unmarked):
                retryAt = at
                state = unmarked && previous != nil
                    ? .retrying(lastGoodAt: previous?.fetchedAt, error: message, retryAt: at)
                    : .stale(lastGoodAt: previous?.fetchedAt, error: message)
                note += ", quick retry scheduled at \(Self.iso(at))"
            case .exhausted:
                state = category == .signInRejected
                    ? .signInRejected(lastGoodAt: previous?.fetchedAt)
                    : .stale(lastGoodAt: previous?.fetchedAt, error: message)
            }
            return (SubscriptionEntry(status: previous, state: state, fetchOutcome: outcome, quickRetryAt: retryAt), note)
        }
    }

    private static func attempt(settings: SubscriptionSettings, reader: CredentialReader, client: UsageEndpointClient,
                                now: Date, clock: @Sendable () -> Date) async -> Attempt {
        let credential: OAuthCredential?
        do {
            credential = try reader.read(configDirectory: settings.credentialDirectory)
        } catch {
            return .credentialReadFailed("credential read failed: \(describe(error))")
        }
        guard let credential else {
            return .notSignedIn("not signed in (no credential for \(settings.credentialDirectory))")
        }
        if credential.isExpired(now: now) {
            return .credentialsExpired("credentials expired at \(credential.expiresAt)")
        }
        do {
            var status = try await client.fetch(token: credential.accessToken)
            status.subscriptionType = credential.subscriptionType
            status.fetchedAt = now
            return .success(status)
        } catch {
            return .failed(error, at: clock())
        }
    }

    /// Error text that can never contain a credential: only our own error
    /// types and generic type names are used.
    private static func describe(_ error: Error) -> String {
        if let endpoint = error as? UsageEndpointError { return endpoint.description }
        return String(describing: error)
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
