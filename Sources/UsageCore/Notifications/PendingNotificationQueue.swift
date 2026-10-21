import Foundation

/// Notifications held back while the notification permission is pending:
/// the newest threshold crossing per entity, window and threshold, so a
/// prompt left unanswered does not end in a burst of stale notifications
/// (spec 001 FR-028), one credential alert per account, newest wins
/// (spec 014 FR-011, FR-014), and the free reset expiry alerts, each once
/// (spec 033 FR-018).
public struct PendingNotificationQueue: Sendable {
    private var crossings: [ThresholdCrossing] = []
    private var alerts: [CredentialAlert] = []
    private var expiries: [ResetTicketExpiryAlert] = []

    public init() {}

    public var isEmpty: Bool { crossings.isEmpty && alerts.isEmpty && expiries.isEmpty }

    public mutating func add(_ crossing: ThresholdCrossing) {
        crossings.removeAll {
            $0.entityId == crossing.entityId && $0.windowKind == crossing.windowKind && $0.threshold == crossing.threshold
        }
        crossings.append(crossing)
    }

    public mutating func add(_ alert: CredentialAlert) {
        alerts.removeAll { $0.accountId == alert.accountId }
        alerts.append(alert)
    }

    /// Queues an expiry alert. A queued alert of the same account and
    /// expiry time is replaced, so a group that reached the 24-hour step
    /// while permission was pending posts once, not a 3-day and a 24-hour
    /// notification together (spec 033 FR-014, FR-018).
    public mutating func add(_ alert: ResetTicketExpiryAlert) {
        expiries.removeAll { $0.accountId == alert.accountId && $0.expiresAt == alert.expiresAt }
        expiries.append(alert)
    }

    /// Splits drained expiry alerts into those to post and those to drop
    /// with the reason for the log: an alert whose expiry passed while it
    /// was queued, or every alert while the switch is off at drain time
    /// (spec 033 FR-012, FR-017, FR-018).
    public static func dueExpiries(_ alerts: [ResetTicketExpiryAlert], notify: Bool,
                                   now: Date) -> (post: [ResetTicketExpiryAlert], drop: [(ResetTicketExpiryAlert, String)]) {
        var post: [ResetTicketExpiryAlert] = []
        var drop: [(ResetTicketExpiryAlert, String)] = []
        for alert in alerts {
            if !notify {
                drop.append((alert, "switch off"))
            } else if alert.expiresAt <= now {
                drop.append((alert, "expired while queued"))
            } else {
                post.append(alert)
            }
        }
        return (post, drop)
    }

    /// Drops the account's queued credential alert, for an episode that
    /// ended, an account removed or moved, or the switch turned off before
    /// permission was granted (spec 014 FR-014). True when one was queued.
    @discardableResult
    public mutating func removeCredential(accountId: String) -> Bool {
        let count = alerts.count
        alerts.removeAll { $0.accountId == accountId }
        return alerts.count != count
    }

    /// The three lists in the order they were queued; the queue is empty
    /// after.
    public mutating func drain() -> (crossings: [ThresholdCrossing], alerts: [CredentialAlert], expiries: [ResetTicketExpiryAlert]) {
        defer {
            crossings = []
            alerts = []
            expiries = []
        }
        return (crossings, alerts, expiries)
    }
}
