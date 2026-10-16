import Testing
@testable import UsageCore

/// spec 014 FR-007, FR-010, FR-011: posts that complete out of order with
/// their withdrawal or with a newer post.
@Suite struct CredentialPostLedgerTests {
    static let id = "credential-a"

    @Test func completedPostIsWithdrawnOnce() {
        var ledger = CredentialPostLedger()
        let g = ledger.begin(Self.id)
        let completion = ledger.completed(Self.id, generation: g)
        let first = ledger.withdraw(Self.id)
        let second = ledger.withdraw(Self.id)
        #expect(completion == .current)
        #expect(first)
        #expect(!second)
    }

    @Test func withdrawalBeforeTheCompletionMeansRemoveAgain() {
        var ledger = CredentialPostLedger()
        let g = ledger.begin(Self.id)
        // Nothing had completed, so the withdrawal is not logged.
        let early = ledger.withdraw(Self.id)
        let completion = ledger.completed(Self.id, generation: g)
        // The late completion does not count as posted.
        let later = ledger.withdraw(Self.id)
        #expect(!early)
        #expect(completion == .withdrawn)
        #expect(!later)
    }

    @Test func olderCompletionAfterANewerPostIsSuperseded() {
        var ledger = CredentialPostLedger()
        let old = ledger.begin(Self.id)
        let latest = ledger.begin(Self.id)
        let oldCompletion = ledger.completed(Self.id, generation: old)
        let latestCompletion = ledger.completed(Self.id, generation: latest)
        let withdrawn = ledger.withdraw(Self.id)
        #expect(oldCompletion == .superseded)
        #expect(latestCompletion == .current)
        #expect(withdrawn)
    }

    /// A post, its withdrawal and a new post before the first one completed:
    /// the first completion must not remove the new notification.
    @Test func completionAfterWithdrawAndRepostIsSuperseded() {
        var ledger = CredentialPostLedger()
        let first = ledger.begin(Self.id)
        _ = ledger.withdraw(Self.id)
        let second = ledger.begin(Self.id)
        let firstCompletion = ledger.completed(Self.id, generation: first)
        let secondCompletion = ledger.completed(Self.id, generation: second)
        #expect(firstCompletion == .superseded)
        #expect(secondCompletion == .current)
    }

    @Test func failedPostIsNeverWithdrawnInTheLog() {
        var ledger = CredentialPostLedger()
        _ = ledger.begin(Self.id)
        // A failed post never calls `completed`.
        let withdrawn = ledger.withdraw(Self.id)
        #expect(!withdrawn)
    }

    @Test func identifiersAreIndependent() {
        var ledger = CredentialPostLedger()
        let a = ledger.begin("credential-a")
        let b = ledger.begin("credential-b")
        let withdrawnA = ledger.withdraw("credential-a")
        let completionB = ledger.completed("credential-b", generation: b)
        let completionA = ledger.completed("credential-a", generation: a)
        let withdrawnB = ledger.withdraw("credential-b")
        #expect(!withdrawnA)
        #expect(completionB == .current)
        #expect(completionA == .withdrawn)
        #expect(withdrawnB)
    }
}
