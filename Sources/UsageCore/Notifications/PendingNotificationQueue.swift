import Foundation

/// Notifications held back while the notification permission is pending:
/// the newest threshold crossing per entity, window and threshold, so a
/// prompt left unanswered does not end in a burst of stale notifications
/// (spec 001 FR-028), and one credential alert per account, newest wins
/// (spec 014 FR-011, FR-014).
public struct PendingNotificationQueue: Sendable {
    private var crossings: [ThresholdCrossing] = []
    private var alerts: [CredentialAlert] = []

    public init() {}

    public var isEmpty: Bool { crossings.isEmpty && alerts.isEmpty }

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

    /// Drops the account's queued credential alert, for an episode that
    /// ended, an account removed or moved, or the switch turned off before
    /// permission was granted (spec 014 FR-014). True when one was queued.
    @discardableResult
    public mutating func removeCredential(accountId: String) -> Bool {
        let count = alerts.count
        alerts.removeAll { $0.accountId == accountId }
        return alerts.count != count
    }

    /// Both lists in the order they were queued; the queue is empty after.
    public mutating func drain() -> (crossings: [ThresholdCrossing], alerts: [CredentialAlert]) {
        defer {
            crossings = []
            alerts = []
        }
        return (crossings, alerts)
    }
}
