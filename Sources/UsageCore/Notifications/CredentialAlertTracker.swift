import Foundation

/// Pure detection of sign-ins that stop working (spec 014 FR-001 to FR-008,
/// FR-011, data-model.md transitions). Fed every snapshot and the current
/// configuration; returns what the presenter should deliver or withdraw.
///
/// State is kept per account id with an identity (`claude|<canonical
/// credential directory>` or `codex|<canonical Codex home>|live`). The
/// first health other than unchanged under an identity is the baseline and
/// never notifies (FR-004); only a change from working to a failing health
/// starts an episode, which notifies at most once (FR-006) and ends with
/// the next working health, withdrawing its notification (FR-007). The
/// clock is `snapshot.generatedAt`. Nothing here sees credential data
/// (FR-010, FR-015).
public struct CredentialAlertTracker: Sendable {
    /// How long a credential must have been expired before its episode
    /// notifies, measured from the credential's own expiry time (spec 014
    /// FR-005, research R7). Agents renew their tokens whenever they run.
    public static let expiryDelay: TimeInterval = 24 * 3600

    /// One failure episode (data-model.md).
    private struct Episode {
        /// The latest failing health.
        var health: CredentialHealth
        /// A notification fell due (delivered, or suppressed by the switch).
        var notified = false
        /// A deliver event was emitted and no withdraw followed yet. Only the
        /// presenter knows whether it reached Notification Center (it may
        /// be queued, or dropped without an app bundle or permission).
        var delivered = false
    }

    private struct State {
        let identity: String
        /// The last health other than unchanged; nil until the baseline.
        var health: CredentialHealth?
        /// Nil while working, or while the baseline was failing.
        var episode: Episode?
        /// Set when the identity changed in the settings: results of
        /// refreshes that started before this time were computed for the
        /// previous directory and do not count (FR-004).
        var notBefore: Date?
    }

    /// An account that can get credential notifications (FR-001, FR-002).
    private struct Eligible {
        let account: Account
        let identity: String
        let provider: CredentialAlert.Provider
        /// The directory or Codex home as configured, nil when default.
        let directory: String?
    }

    private let paths: Paths
    private var states: [String: State] = [:]

    public init(paths: Paths = Paths()) {
        self.paths = paths
    }

    /// The events for one snapshot. Preliminary snapshots (saved values at
    /// launch, spec 010 FR-015) are skipped entirely: their `.ok` entries
    /// come from no request.
    public mutating func observe(snapshot: UsageSnapshot, configuration: Configuration) -> [CredentialAlertEvent] {
        guard !snapshot.isPreliminary else { return [] }
        let eligible = eligibleAccounts(configuration)
        let notify = configuration.notifySignInProblems
        var events = configurationPass(eligible, notify: notify, changedAt: nil)
        for item in eligible {
            let health: CredentialHealth?
            switch item.provider {
            case .claude: health = snapshot.subscriptions[item.account.id].flatMap(CredentialHealth.claude)
            case .codex: health = snapshot.codexLimits[item.account.id].flatMap(CredentialHealth.codex)
            }
            events += apply(health, to: item, now: snapshot.generatedAt, notify: notify)
        }
        return events
    }

    /// The events of a configuration saved from the settings window, so a
    /// switch turned off removes delivered notifications without waiting
    /// for a refresh (spec 014 FR-012, research R5). Removed accounts and
    /// changed directories are handled here too; a refresh that started
    /// before `now` does not set the baseline of a changed account (FR-004).
    public mutating func configurationChanged(_ configuration: Configuration, now: Date = Date()) -> [CredentialAlertEvent] {
        configurationPass(eligibleAccounts(configuration), notify: configuration.notifySignInProblems, changedAt: now)
    }

    // MARK: Transitions (data-model.md)

    private mutating func apply(_ health: CredentialHealth?, to item: Eligible, now: Date, notify: Bool) -> [CredentialAlertEvent] {
        let id = item.account.id
        // Transition 1: no state, a new baseline (FR-004). The configuration
        // pass already dropped a state with another identity.
        var state = states[id] ?? State(identity: item.identity)
        defer { states[id] = state }
        var health = health
        if let notBefore = state.notBefore {
            if now < notBefore {
                health = nil
            } else {
                state.notBefore = nil
            }
        }
        guard let health else {
            // Transition 2: unchanged; an expired episode is re-checked for
            // its delay (FR-005).
            guard var episode = state.episode else { return [] }
            defer { state.episode = episode }
            return notifyIfDue(&episode, item: item, now: now, notify: notify)
        }
        guard let previous = state.health else {
            state.health = health
            return []
        }
        if health == .working {
            // Transition 3: the episode ends (FR-007).
            let withdraw = state.episode?.delivered == true
            state.episode = nil
            state.health = .working
            return withdraw ? [.withdraw(accountId: id)] : []
        }
        state.health = health
        if previous == .working {
            // Transition 4: a new episode.
            state.episode = Episode(health: health)
        }
        guard var episode = state.episode else {
            // Transition 6: the baseline was failing, no episode.
            return []
        }
        // Transition 5.
        episode.health = health
        defer { state.episode = episode }
        return notifyIfDue(&episode, item: item, now: now, notify: notify)
    }

    /// Delivers the episode's notification once it falls due; an episode
    /// notifies at most once, whatever its kind changes to (FR-006). With
    /// the switch off, the due notification is only suppressed, and the
    /// episode still counts as notified (FR-012).
    private func notifyIfDue(_ episode: inout Episode, item: Eligible, now: Date, notify: Bool) -> [CredentialAlertEvent] {
        guard !episode.notified, isDue(episode.health, now: now), let alert = alert(for: item, health: episode.health) else { return [] }
        episode.notified = true
        guard notify else { return [.suppressed(alert)] }
        episode.delivered = true
        return [.deliver(alert)]
    }

    /// Rejected and missing sign-ins notify at once (FR-003, FR-006); an
    /// expiry once `expiryDelay` passed since the credential's expiry time
    /// (FR-005). An expiry time in the future is not due.
    private func isDue(_ health: CredentialHealth, now: Date) -> Bool {
        switch health {
        case .rejected, .notSignedIn, .notReadable: return true
        case .expired(let at): return now >= at.addingTimeInterval(Self.expiryDelay)
        case .working: return false
        }
    }

    /// Accounts no longer configured, no longer eligible, or with another
    /// identity lose their state, withdrawing a delivered notification
    /// (FR-004, FR-008). With the switch off, every delivered notification
    /// is withdrawn; its episode stays notified (FR-012).
    private mutating func configurationPass(_ eligible: [Eligible], notify: Bool, changedAt: Date?) -> [CredentialAlertEvent] {
        let identities = Dictionary(eligible.map { ($0.account.id, $0.identity) }, uniquingKeysWith: { first, _ in first })
        var events: [CredentialAlertEvent] = []
        for id in states.keys.sorted() {
            guard let state = states[id], identities[id] != state.identity else { continue }
            if state.episode?.delivered == true {
                events.append(.withdraw(accountId: id))
            }
            states[id] = nil
        }
        if let changedAt {
            for item in eligible where states[item.account.id] == nil {
                states[item.account.id] = State(identity: item.identity, notBefore: changedAt)
            }
        }
        if !notify {
            for id in states.keys.sorted() where states[id]?.episode?.delivered == true {
                states[id]?.episode?.delivered = false
                events.append(.withdraw(accountId: id))
            }
        }
        return events
    }

    // MARK: Accounts

    /// Claude subscription accounts and Codex subscription accounts with
    /// live limits on, in configuration order (FR-001, FR-002). Bar
    /// visibility plays no part.
    private func eligibleAccounts(_ configuration: Configuration) -> [Eligible] {
        var seen = Set<String>()
        return configuration.accounts.compactMap { account -> Eligible? in
            guard seen.insert(account.id).inserted else { return nil }
            if let settings = account.kind.subscription {
                let directory = settings.credentialDirectory
                let expanded = paths.expand(directory)
                return Eligible(account: account, identity: "claude|\(Attributor.canonical(expanded))", provider: .claude,
                                directory: expanded == paths.defaultClaudeDirectoryPath ? nil : directory)
            }
            if let settings = account.kind.codexSubscription, settings.liveLimits {
                let home = settings.codexHome
                let expanded = paths.expand(home)
                return Eligible(account: account, identity: "codex|\(Attributor.canonical(expanded))|live", provider: .codex,
                                directory: expanded == paths.expand(Paths.defaultCodexHome) ? nil : home)
            }
            return nil
        }
    }

    private func alert(for item: Eligible, health: CredentialHealth) -> CredentialAlert? {
        let kind: CredentialAlert.Kind
        switch health {
        case .rejected: kind = .rejected
        case .notSignedIn: kind = .notSignedIn
        case .notReadable: kind = .notReadable
        case .expired: kind = .expired
        case .working: return nil
        }
        return CredentialAlert(accountId: item.account.id, accountName: item.account.displayName, provider: item.provider,
                               kind: kind, directory: item.directory)
    }
}
