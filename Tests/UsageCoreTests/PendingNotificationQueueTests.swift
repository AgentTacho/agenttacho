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
