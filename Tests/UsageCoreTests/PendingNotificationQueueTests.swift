import Foundation
import Testing
@testable import UsageCore

/// spec 014 FR-014: threshold crossings and credential alerts queued while
/// notification permission is pending.
@Suite struct PendingNotificationQueueTests {
    private func crossing(_ id: String, _ kind: WindowKind = .sevenDay, threshold: Int = 80, percent: Int = 81) -> ThresholdCrossing {
        ThresholdCrossing(entityId: id, entityName: id, windowKind: kind, threshold: threshold, percent: percent)
    }

    private func alert(_ id: String, _ kind: CredentialAlert.Kind = .rejected) -> CredentialAlert {
        CredentialAlert(accountId: id, accountName: id, provider: .claude, kind: kind, directory: nil)
    }

    @Test func newerCrossingForTheSameKeyReplacesTheOlder() {
        var queue = PendingNotificationQueue()
        queue.add(crossing("a", percent: 81))
        queue.add(crossing("a", .fiveHour, percent: 82))
        queue.add(crossing("a", threshold: 90, percent: 91))
        queue.add(crossing("a", percent: 85))
        let drained = queue.drain()
        #expect(drained.crossings == [crossing("a", .fiveHour, percent: 82), crossing("a", threshold: 90, percent: 91),
                                      crossing("a", percent: 85)])
    }

    @Test func newerAlertForTheSameAccountReplacesTheOlder() {
        var queue = PendingNotificationQueue()
        queue.add(alert("a", .expired))
        queue.add(alert("b"))
        queue.add(alert("a", .rejected))
        #expect(queue.drain().alerts == [alert("b"), alert("a", .rejected)])
    }

    @Test func removeCredentialDropsOnlyThatAccountsAlert() {
        var queue = PendingNotificationQueue()
        queue.add(crossing("a"))
        queue.add(alert("a"))
        queue.add(alert("b"))
        let removed = queue.removeCredential(accountId: "a")
        let removedMissing = queue.removeCredential(accountId: "missing")
        #expect(removed)
        #expect(!removedMissing)
        let drained = queue.drain()
        #expect(drained.crossings == [crossing("a")])
        #expect(drained.alerts == [alert("b")])
    }

    @Test func drainReturnsBothListsInOrderAndEmptiesTheQueue() {
        var queue = PendingNotificationQueue()
        queue.add(crossing("a"))
        queue.add(alert("x"))
        queue.add(crossing("b"))
        queue.add(alert("y"))
        let drained = queue.drain()
        #expect(drained.crossings == [crossing("a"), crossing("b")])
        #expect(drained.alerts == [alert("x"), alert("y")])
        #expect(queue.isEmpty)
        let again = queue.drain()
        #expect(again.crossings.isEmpty && again.alerts.isEmpty)
    }
}

/// spec 033 FR-018: expiry alerts queue like threshold notifications while
/// permission is pending, beside crossings and credential alerts.
@Suite struct PendingExpiryAlertTests {
    private func expiry(_ id: String, _ step: ResetTicketExpiryStep = .threeDays, at seconds: TimeInterval = 1_800_000_000) -> ResetTicketExpiryAlert {
        ResetTicketExpiryAlert(accountId: id, accountName: id, step: step, expiresAt: Date(timeIntervalSince1970: seconds), count: 1)
    }

    @Test func expiryAlertsQueueAndDrainInOrder() {
        var queue = PendingNotificationQueue()
        queue.add(expiry("a"))
        queue.add(ThresholdCrossing(entityId: "c", entityName: "c", windowKind: .sevenDay, threshold: 80, percent: 81))
        queue.add(expiry("b", .oneDay))
        queue.add(CredentialAlert(accountId: "x", accountName: "x", provider: .claude, kind: .rejected, directory: nil))
        #expect(!queue.isEmpty)
        let drained = queue.drain()
        #expect(drained.expiries == [expiry("a"), expiry("b", .oneDay)])
        #expect(drained.crossings.map(\.entityId) == ["c"])
        #expect(drained.alerts.map(\.accountId) == ["x"])
        #expect(queue.isEmpty)
        let again = queue.drain()
        #expect(again.expiries.isEmpty)
    }

    @Test func theSameAlertQueuesOnce() {
        var queue = PendingNotificationQueue()
        queue.add(expiry("a"))
        queue.add(expiry("a", at: 1_800_000_600))
        queue.add(expiry("a"))
        #expect(queue.drain().expiries == [expiry("a", at: 1_800_000_600), expiry("a")])
    }

    @Test func removeCredentialLeavesExpiryAlerts() {
        var queue = PendingNotificationQueue()
        queue.add(expiry("a"))
        let removed = queue.removeCredential(accountId: "a")
        #expect(!removed)
        #expect(queue.drain().expiries == [expiry("a")])
    }
}

/// spec 033 FR-012, FR-014, FR-017, FR-018: a group that reached the next
/// step while permission was pending posts once; at drain time the switch
/// and the expiry are checked again.
@Suite struct PendingExpiryDrainTests {
    private func expiry(_ id: String, _ step: ResetTicketExpiryStep = .threeDays, at seconds: TimeInterval = 1_800_000_000) -> ResetTicketExpiryAlert {
        ResetTicketExpiryAlert(accountId: id, accountName: id, step: step, expiresAt: Date(timeIntervalSince1970: seconds), count: 1)
    }

    @Test func theShorterStepReplacesTheQueuedOne() {
        var queue = PendingNotificationQueue()
        queue.add(expiry("a"))
        queue.add(expiry("b"))
        queue.add(expiry("a", .oneDay))
        #expect(queue.drain().expiries == [expiry("b"), expiry("a", .oneDay)])
    }

    @Test func drainChecksTheSwitchAndTheExpiry() {
        let alerts = [expiry("a", at: 1_800_000_000), expiry("b", at: 1_800_001_000)]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let on = PendingNotificationQueue.dueExpiries(alerts, notify: true, now: now)
        #expect(on.post == [expiry("b", at: 1_800_001_000)])
        #expect(on.drop.map(\.0) == [expiry("a", at: 1_800_000_000)])
        #expect(on.drop.map(\.1) == ["expired while queued"])
        let off = PendingNotificationQueue.dueExpiries(alerts, notify: false, now: now)
        #expect(off.post.isEmpty)
        #expect(off.drop.map(\.1) == ["switch off", "switch off"])
    }
}
