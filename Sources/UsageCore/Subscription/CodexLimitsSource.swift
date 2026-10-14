import CryptoKit
import Foundation

/// Plan limits of every Codex subscription account (spec 007 FR-001 to
/// FR-008, FR-020, FR-021, research R4 to R6).
///
/// Per account and refresh: the newest plan snapshot from the session logs
/// of the account's Codex home, and, with live limits on, a request to the
/// plan's usage service when one is due. The shown observation is the live
/// result, or else the newer of the last live result and the snapshot. The
/// last live result lives in memory only (FR-005). A `Retry-After` wait
/// counts up to one hour (FR-007).
///
/// A plain source, not `NetworkBoundSource`: it runs on every refresh,
/// reprices included, and decides about the network itself with a fetch
/// gate per Codex home (research R5). It never writes to a Codex home and
/// never logs credential text (FR-003, FR-018).
public actor CodexLimitsSource: UsageSource {
    /// The refresh coordinator recognizes the source's failure by this name
    /// and carries its entries over (FR-021, plan Design Note 6).
    public static let sourceName = "codexLimits"
    public nonisolated let name = CodexLimitsSource.sourceName

    /// Minimum time between requests for one Codex home on `.manual`,
    /// `.wake`, `.settings`, `.retry` and `.launch` refreshes, as for the
    /// Claude usage endpoint.
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
    }

    private enum Action {
        case off
        case fetch
        /// No request is due (reprice or spacing): without an earlier
        /// failure, nothing is marked stale.
        case notDue
        /// A rate-limit wait for this Codex home (FR-007).
        case blocked(until: Date)
    }

    private enum LiveResult {
        case success(CodexLimitObservation)
        /// No request was made: sign-in missing, expired, unreadable or
        /// already rejected.
        case noRequest(Failure)
        /// The request failed; the digest identifies the token that was sent.
        case failed(Error, tokenDigest: Data)
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

    /// The last successful live result per account, in memory only (FR-005).
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

    /// Rollout files parsed by the last `collect` (for tests).
    public private(set) var lastFilesParsed = 0

    public init(credentialReader: CodexCredentialReader, client: CodexUsageClient, log: DiagnosticLog? = nil,
                paths: Paths = Paths(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.credentialReader = credentialReader
        self.client = client
        self.log = log
        self.paths = paths
        self.clock = clock
    }

    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let now = context.now
        let configuration = context.configuration
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
                action = decide(accountId: account.id, home: home, now: now, trigger: context.trigger)
            } else {
                // Only snapshots; earlier live results are discarded (FR-005).
                lastLive[account.id] = nil
                lastFailure[account.id] = nil
                attemptedHome[account.id] = nil
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
                group.addTask { [credentialReader, client] in
                    (plan.home, await Self.live(reader: credentialReader, client: client, codexHome: codexHome,
                                                rejectedToken: rejected, now: now))
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
            let entry: CodexLimitsEntry
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
                if let failure = lastFailure[id] {
                    entry = Self.fallback(live: lastLive[id], snapshot: snapshot, failure: failure, now: now)
                } else if let live = lastLive[id] {
                    entry = Self.notDue(live: live, snapshot: snapshot, now: now)
                } else {
                    entry = Self.fallback(live: nil, snapshot: snapshot, failure: Failure(reason: Self.noLiveLimitsYetReason), now: now)
                }
                note = "no request due (\(context.trigger.rawValue))"
            case .blocked(let until):
                let snapshot = newestSnapshot(home: plan.home, newerThan: liveObservedAt, parsed: &parsed)
                entry = Self.fallback(live: lastLive[id], snapshot: snapshot,
                                      failure: Failure(reason: Self.rateLimitedReason), now: now)
                note = "rate limited until \(Self.iso(until))"
            case .fetch:
                attemptedHome[id] = plan.home
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
                    entry = CodexLimitsEntry(observation: observation, state: .live)
                    note = "fetched"
                case .noRequest(let failure):
                    lastFailure[id] = failure
                    let snapshot = newestSnapshot(home: plan.home, newerThan: liveObservedAt, parsed: &parsed)
                    entry = Self.fallback(live: lastLive[id], snapshot: snapshot, failure: failure, now: now)
                    note = "no request: " + failure.reason
                case .failed(let error, let tokenDigest):
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
                    entry = Self.fallback(live: lastLive[id], snapshot: snapshot, failure: failure, now: now)
                    note = "request failed: " + Self.detail(of: error)
                }
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
        gates = gates.filter { homes.contains($0.key) }
        rejectedTokens = rejectedTokens.filter { homes.contains($0.key) }
        files = files.filter { homes.contains($0.key) }
        return .codexLimits(entries)
    }

    // MARK: - Fetch gate (research R5)

    private func decide(accountId: String, home: String, now: Date, trigger: RefreshTrigger) -> Action {
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
            return .fetch
        case .local:
            return .notDue
        case .manual, .wake, .settings, .retry, .launch:
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
                             rejectedToken: Data?, now: Date) async -> LiveResult {
        let lookup: CodexCredentialLookup
        do {
            lookup = try reader.read(codexHome: codexHome)
        } catch {
            let reason = (error as? CodexCredentialError)?.message ?? "Codex sign-in could not be read"
            return .noRequest(Failure(reason: reason))
        }
        switch lookup {
        case .missing(let reason):
            return .noRequest(Failure(reason: reason))
        case .found(let credential):
            if credential.isExpired(now: now) {
                return .noRequest(Failure(reason: expiredReason))
            }
            let digest = Data(SHA256.hash(data: Data(credential.accessToken.utf8)))
            if digest == rejectedToken {
                return .noRequest(Failure(reason: rejectedReason, sourceError: rejectedSourceError))
            }
            do {
                return .success(try await client.fetch(credential, observedAt: now))
            } catch {
                return .failed(error, tokenDigest: digest)
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
    static func fallback(live: CodexLimitObservation?, snapshot: CodexLimitObservation?, failure: Failure, now: Date) -> CodexLimitsEntry {
        guard let chosen = newer(live: live, snapshot: snapshot, now: now) else {
            return CodexLimitsEntry(observation: nil, state: .unavailable(reason: failure.reason), sourceError: failure.sourceError)
        }
        return CodexLimitsEntry(observation: chosen, state: .stale(reason: failure.reason), sourceError: failure.sourceError)
    }

    /// The stale reason and source error of a failed request
    /// (contracts/codex-usage-endpoint.md section 1). Only our own error
    /// types are described, so no text from the answer or the sign-in
    /// reaches a message (FR-018).
    static func failure(for error: Error) -> Failure {
        if error as? CodexUsageError == .noLimits {
            return Failure(reason: CodexUsageError.noLimits.description)
        }
        switch error as? UsageEndpointError {
        case .decoding?:
            return Failure(reason: "usage service changed", sourceError: "usage service changed")
        case .httpStatus(401)?:
            return Failure(reason: rejectedReason, sourceError: rejectedSourceError)
        case .httpStatus(403)?:
            return Failure(reason: rejectedSourceError, sourceError: rejectedSourceError)
        case .httpStatus(let code)?:
            return Failure(reason: "usage service returned HTTP \(code)")
        case .rateLimited?:
            return Failure(reason: rateLimitedReason)
        case .network?, nil:
            return Failure(reason: "offline")
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
        }
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
