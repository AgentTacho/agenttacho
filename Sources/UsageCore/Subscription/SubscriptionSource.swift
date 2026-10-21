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
///
/// The usage request also asks for the account's free limit resets with a
/// query flag; the tickets stay in memory and never decide the usage
/// figures, error lines or credential health (spec 033 FR-001, FR-003,
/// FR-004, FR-006).
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
    /// Accounts whose last request got no answer (spec 021 FR-003c,
    /// research R3): added on a no-answer failure, removed on a success or
    /// any HTTP answer, with the account or with a changed credential
    /// directory. A failure before a request leaves it unchanged.
    private var noAnswer: Set<String> = []
    private let store: LastGoodStore?
    private let paths: Paths
    /// True once the saved values were read from the store.
    private var seeded = false
    /// The Claude section last handed to (or loaded from) the store.
    private var lastSaved: [String: SavedClaudeValues] = [:]
    /// The free-reset flag state per account; absent means `.on` (spec 033
    /// FR-004, data-model "TicketFlag").
    private var ticketFlags: [String: TicketFlag] = [:]
    /// The tickets of each account's last successful ticket read in this
    /// run, in memory only (spec 033 FR-003, FR-006).
    private var lastTickets: [String: [ResetTicket]] = [:]
    /// The ticket failure kinds already logged per account in this run
    /// (spec 033 FR-019, research R9).
    private var loggedTicketFailures: [String: Set<String>] = [:]

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

    /// Whether the usage request of an account carries the free-reset flag
    /// (spec 033 FR-004, data-model "TicketFlag").
    enum TicketFlag: Sendable, Equatable {
        /// The flag is sent.
        case on
        /// The flagged request was refused and its plain repeat failed too:
        /// the next request is plain, and the flag returns after a plain
        /// success.
        case suspended
        /// The flagged request was refused and its plain repeat succeeded:
        /// the flag is not sent again until relaunch.
        case offForRun
    }

    /// What one account's request produced, before the episode rules apply.
    private enum Attempt: Sendable {
        case notSignedIn(String)
        /// The credential expired at `expiresAt` (spec 014 FR-005).
        case credentialsExpired(String, expiresAt: Date)
        case credentialReadFailed(String)
        case success(SubscriptionStatus)
        /// The request failed at `at`, the time the quick retry counts
        /// from (spec 010 FR-004).
        case failed(Error, at: Date)
    }

    /// The accounts whose last request got no answer (spec 021 FR-003c).
    public func noAnswerAccounts() async -> Set<String> {
        noAnswer
    }

    /// A quick retry or a no-answer-only run asks only the accounts whose
    /// quick retry is due or, for a manual refresh, whose last request got
    /// no answer, plus new or moved accounts; every other account keeps its
    /// last entry without a request (spec 010 FR-009, spec 021 FR-003,
    /// FR-003a, FR-003c, research R7).
    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let accounts = context.configuration.subscriptionAccounts
        let now = clock()
        let quickRetry = context.trigger == .quickRetry
        let restricted = quickRetry || context.claudeNoAnswerOnly
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
                noAnswer.remove(account.id)
                // Nor are its tickets (spec 033 FR-003). A new sign-in starts
                // with the flag on and logs its ticket read failures afresh
                // (FR-019).
                lastTickets[account.id] = nil
                ticketFlags[account.id] = nil
                loggedTicketFailures[account.id] = nil
            }
            if restricted, let last = lastEntries[account.id], lastDirectories[account.id] == settings.credentialDirectory,
               !episodes.isRetryDue(account.id, now: now),
               !(context.manualRequested && noAnswer.contains(account.id)) {
                // Not part of this quick retry or no-answer run: keep the
                // last entry without a request (spec 010 FR-009, spec 021
                // FR-003c).
                var kept = last.endingGrace(now: now)
                kept.fetchOutcome = nil
                kept.reachedService = false
                kept.quickRetryAt = episodes.retryAt(account.id)
                kept.resetTickets = (lastTickets[account.id] ?? []).usable(at: now)
                entries[account.id] = kept
                continue
            }
            requested.append((account, settings))
        }

        typealias Result = (id: String, attempt: Attempt, tickets: ResetTicketRead?, flag: TicketFlag)
        let results: [Result] = await withTaskGroup(of: Result.self) { group in
            for (account, settings) in requested {
                let flag = ticketFlags[account.id] ?? .on
                group.addTask { [credentialReader, client, clock] in
                    let (attempt, tickets, next) = await Self.attempt(settings: settings, reader: credentialReader, client: client,
                                                                      now: now, clock: clock, flag: flag)
                    return (account.id, attempt, tickets, next)
                }
            }
            var collected: [Result] = []
            for await r in group { collected.append(r) }
            return collected
        }

        for result in results.sorted(by: { $0.id < $1.id }) {
            var (entry, note) = apply(result.attempt, id: result.id, now: now, quickRetry: quickRetry)
            entry.resetTickets = applyTickets(result.tickets, attempt: result.attempt, flag: result.flag, id: result.id, now: now)
            entries[result.id] = entry
            log?.append(source: name, message: "\(result.id): \(note)")
        }

        // Forget accounts that disappeared from the configuration.
        let ids = Set(entries.keys)
        lastGood = lastGood.filter { ids.contains($0.key) }
        liveThisRun = liveThisRun.filter { ids.contains($0) }
        noAnswer = noAnswer.filter { ids.contains($0) }
        ticketFlags = ticketFlags.filter { ids.contains($0.key) }
        lastTickets = lastTickets.filter { ids.contains($0.key) }
        loggedTicketFailures = loggedTicketFailures.filter { ids.contains($0.key) }
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
        case .credentialsExpired(let note, let expiresAt):
            return (SubscriptionEntry(status: previous, state: .credentialsExpired, credentialExpiresAt: expiresAt), prefix + note)
        case .credentialReadFailed(let message):
            return (SubscriptionEntry(status: previous, state: .stale(lastGoodAt: previous?.fetchedAt, error: message)), prefix + message)
        case .success(let status):
            lastGood[id] = status
            liveThisRun.insert(id)
            episodes.succeeded(id)
            noAnswer.remove(id)
            let five = status.fiveHour.map { "\(PercentFormatter.rounded($0.utilizationPercent))%" } ?? "n/a"
            let seven = status.sevenDay.map { "\(PercentFormatter.rounded($0.utilizationPercent))%" } ?? "n/a"
            return (SubscriptionEntry(status: status, state: .ok, fetchOutcome: .success, reachedService: true),
                    prefix + "ok (5h \(five), 7d \(seven))")
        case .failed(let error, let failedAt):
            let message = Self.describe(error)
            let category = FailureCategory.classify(error)
            // Only a failure without an HTTP answer lets "Refresh now" ask
            // again within the spacing (spec 021 FR-003, FR-004).
            if FailureCategory.isNoAnswer(error) {
                noAnswer.insert(id)
            } else {
                noAnswer.remove(id)
            }
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
            // The log names the technical cause; the entry keeps today's
            // text (spec 021 FR-007, FR-008).
            var note = prefix + "fetch failed (\(category.rawValue)): \(Self.logDescribe(error))"
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
            // An answer reached the service unless the failure is a
            // transport failure, HTTP 5xx included (spec 016 FR-005).
            return (SubscriptionEntry(status: previous, state: state, fetchOutcome: outcome, quickRetryAt: retryAt,
                                      reachedService: category != .transport), note)
        }
    }

    /// Commits the flag state and returns the account's tickets after this
    /// attempt (spec 033 FR-003, FR-004): no sign-in found clears them; a
    /// nil read (no request, or a plain request that is not a ticket read)
    /// keeps them minus expired; a read applies per `ResetTicketRead`.
    /// Failures are logged once per kind and account per run (FR-019).
    private func applyTickets(_ read: ResetTicketRead?, attempt: Attempt, flag: TicketFlag, id: String, now: Date) -> [ResetTicket] {
        ticketFlags[id] = flag == .on ? nil : flag
        if case .notSignedIn = attempt {
            lastTickets[id] = nil
            return []
        }
        let previous = lastTickets[id] ?? []
        guard let read else {
            let kept = previous.usable(at: now)
            lastTickets[id] = kept
            return kept
        }
        if let kind = read.failureKind, loggedTicketFailures[id, default: []].insert(kind).inserted {
            log?.append(source: name, message: Self.ticketFailureMessage(kind, id: id))
        }
        let tickets = read.applied(to: previous, now: now)
        lastTickets[id] = tickets
        return tickets
    }

    /// The log label prefixes of a dropped and a suspended flag, followed by
    /// the refusal's status, for example `flag-dropped-http-400` (spec 033
    /// FR-004, FR-019).
    static let flagDropped = "flag-dropped"
    static let flagSuspended = "flag-suspended"

    /// The log line of a failed ticket read; a refused flag names the
    /// refusal's status and what happens to the flag (spec 033 FR-019).
    static func ticketFailureMessage(_ kind: String, id: String) -> String {
        if kind.hasPrefix(flagDropped + "-") {
            let status = kind.dropFirst(flagDropped.count + 1)
            return "\(id): usage service refused the free reset flag (\(status)), not sent again until relaunch"
        }
        if kind.hasPrefix(flagSuspended + "-") {
            let status = kind.dropFirst(flagSuspended.count + 1)
            return "\(id): usage service refused the free reset flag (\(status)) and the plain request failed too, flag sent again after the next successful request"
        }
        return "\(id): free reset tickets not read (\(kind))"
    }

    /// One account's credential read and usage request. With the flag on,
    /// a refusal by an HTTP client error other than 401 and 429 is repeated
    /// once without the flag; the plain result alone becomes the attempt
    /// (spec 033 FR-004, research R2). Returns the ticket read (nil when no
    /// ticket read took place) and the account's next flag state.
    private static func attempt(settings: SubscriptionSettings, reader: CredentialReader, client: UsageEndpointClient,
                                now: Date, clock: @Sendable () -> Date,
                                flag: TicketFlag) async -> (Attempt, ResetTicketRead?, TicketFlag) {
        let credential: OAuthCredential?
        do {
            credential = try reader.read(configDirectory: settings.credentialDirectory)
        } catch {
            return (.credentialReadFailed("credential read failed: \(describe(error))"), nil, flag)
        }
        guard let credential else {
            return (.notSignedIn("not signed in (no credential for \(settings.credentialDirectory))"), nil, flag)
        }
        if credential.isExpired(now: now) {
            return (.credentialsExpired("credentials expired at \(credential.expiresAt)", expiresAt: credential.expiresAt), nil, flag)
        }
        func success(_ fetched: SubscriptionStatus) -> Attempt {
            var status = fetched
            status.subscriptionType = credential.subscriptionType
            status.fetchedAt = now
            return .success(status)
        }
        guard flag == .on else {
            // A plain request is not a ticket read; a success after a
            // failed repeat brings the flag back (data-model "TicketFlag").
            do {
                let status = try await client.fetch(token: credential.accessToken)
                return (success(status), nil, flag == .suspended ? .on : flag)
            } catch {
                return (.failed(error, at: clock()), nil, flag)
            }
        }
        do {
            let result = try await client.fetch(token: credential.accessToken, includeTickets: true)
            return (success(result.status), result.tickets ?? .tickets([]), .on)
        } catch {
            guard case .httpStatus(let code)? = error as? UsageEndpointError, (400..<500).contains(code), code != 401, code != 429 else {
                return (.failed(error, at: clock()), ResetTicketRead.requestFailure(error), .on)
            }
            do {
                let status = try await client.fetch(token: credential.accessToken)
                return (success(status), .clearingFailure("\(flagDropped)-http-\(code)"), .offForRun)
            } catch {
                return (.failed(error, at: clock()), .temporaryFailure("\(flagSuspended)-http-\(code)"), .suspended)
            }
        }
    }

    /// Error text that can never contain a credential: only our own error
    /// types and generic type names are used.
    private static func describe(_ error: Error) -> String {
        if let endpoint = error as? UsageEndpointError { return endpoint.description }
        return String(describing: error)
    }

    /// `describe` plus the technical detail of a no-answer failure, for the
    /// diagnostic log only (spec 021 FR-007, FR-008).
    private static func logDescribe(_ error: Error) -> String {
        if let endpoint = error as? UsageEndpointError { return endpoint.logDescription }
        return describe(error)
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
