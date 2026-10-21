import Foundation

/// Pure detection of free limit resets about to expire (spec 033 FR-014,
/// FR-016, FR-017, data-model "ResetTicketExpiryTracker"). Fed every
/// snapshot, the configuration and the current time; returns the
/// notifications that fall due.
///
/// Per account, the usable tickets are grouped by expiry time; tickets
/// without expiry never notify. A group inside the 3-day range gets the
/// 3-day step, one inside the 24-hour range the 24-hour step; a group first
/// seen inside the 24-hour range gets only that one. Each step is delivered
/// at most once per account and expiry time, also across relaunches: the
/// delivered steps are kept in a `ResetTicketNoticeStore` until their
/// expiry time passes or their account is removed. With the switch off a
/// step that falls due is suppressed and counts as delivered.
public struct ResetTicketExpiryTracker {
    private let store: ResetTicketNoticeStore
    private var delivered: Set<ResetTicketNoticeKey>
    /// The login each account read its tickets from: the Claude Code
    /// directory, or the Codex home with live limits on.
    private var identities: [String: String] = [:]
    /// Set when an account's login changed in the settings: tickets of
    /// snapshots from refreshes that started before this time belong to the
    /// previous login and do not notify (spec 033 FR-014, as spec 014
    /// FR-004 does for credential notifications).
    private var notBefore: [String: Date] = [:]

    /// Loads the record once (spec 033 FR-016).
    public init(store: ResetTicketNoticeStore) {
        self.store = store
        self.delivered = store.load()
    }

    /// Records a configuration saved from the settings window at `now`: an
    /// account whose login is new or changed ignores the tickets of
    /// refreshes that started before `now`.
    public mutating func configurationChanged(_ configuration: Configuration, now: Date = Date()) {
        let current = Self.identities(configuration)
        for (id, identity) in current where identities[id] != identity {
            notBefore[id] = now
        }
        identities = current
        notBefore = notBefore.filter { current[$0.key] != nil }
    }

    /// The events for one snapshot at `now`. Preliminary snapshots (saved
    /// values at launch) are skipped.
    public mutating func observe(snapshot: UsageSnapshot, configuration: Configuration, now: Date) -> [ResetTicketExpiryEvent] {
        guard !snapshot.isPreliminary else { return [] }
        let before = delivered
        var events: [ResetTicketExpiryEvent] = []
        let current = Self.identities(configuration)
        identities = current
        notBefore = notBefore.filter { current[$0.key] != nil }
        // Codex accounts with live limits off read no tickets (spec 033
        // FR-001); their record stays until the account is removed.
        let live = Set(current.keys)
        let accounts = configuration.subscriptionAccounts.map { ($0, snapshot.subscriptions[$0.id]?.resetTickets ?? []) }
            + configuration.codexSubscriptionAccounts.map { ($0, live.contains($0.id) ? snapshot.codexLimits[$0.id]?.resetTickets ?? [] : []) }
        for (account, allTickets) in accounts {
            var tickets = allTickets
            if let fence = notBefore[account.id] {
                if snapshot.generatedAt < fence {
                    tickets = []
                } else {
                    notBefore[account.id] = nil
                }
            }
            for (expiresAt, count) in tickets.groupedByExpiry(at: now).sorted(by: { $0.key < $1.key }) {
                guard let step = Self.step(remaining: expiresAt.timeIntervalSince(now)) else { continue }
                let key = ResetTicketNoticeKey(accountId: account.id, expiresAt: expiresAt, step: step)
                guard !delivered.contains(key) else { continue }
                // The 24-hour step also settles the 3-day one (data-model).
                for passed in ResetTicketExpiryStep.allCases where passed.leadTime >= step.leadTime {
                    delivered.insert(ResetTicketNoticeKey(accountId: account.id, expiresAt: expiresAt, step: passed))
                }
                let alert = ResetTicketExpiryAlert(accountId: account.id, accountName: account.displayName, step: step,
                                                   expiresAt: key.expiresAt, count: count)
                events.append(configuration.notifyFreeResetExpiry ? .deliver(alert) : .suppressed(alert))
            }
        }
        // Forget passed expiry times and removed accounts (spec 033 FR-016).
        let ids = Set(accounts.map(\.0.id))
        delivered = delivered.filter { $0.expiresAt > now && ids.contains($0.accountId) }
        if delivered != before {
            store.save(delivered)
        }
        return events
    }

    /// The login per account that reads tickets: Claude subscription
    /// accounts by their Claude Code directory, Codex subscription accounts
    /// with live limits on by their Codex home.
    private static func identities(_ configuration: Configuration) -> [String: String] {
        var result: [String: String] = [:]
        for account in configuration.accounts where result[account.id] == nil {
            if let settings = account.kind.subscription {
                result[account.id] = "claude|\(settings.credentialDirectory)"
            } else if let settings = account.kind.codexSubscription, settings.liveLimits {
                result[account.id] = "codex|\(settings.codexHome)"
            }
        }
        return result
    }

    /// The step whose range `remaining` lies in, the shortest one first: a
    /// range holds the times less than its lead time before the expiry
    /// (spec 033 FR-014); nil from 3 days on.
    static func step(remaining: TimeInterval) -> ResetTicketExpiryStep? {
        if remaining < ResetTicketExpiryStep.oneDay.leadTime { return .oneDay }
        if remaining < ResetTicketExpiryStep.threeDays.leadTime { return .threeDays }
        return nil
    }
}
