import Foundation
import Testing
@testable import UsageCore

/// spec 014 FR-001: every row of the derivation table in data-model.md.
@Suite struct CredentialHealthTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let observation = CodexLimitObservation(planType: "plus", observedAt: t0, origin: .live,
                                                   windows: [CodexLimitWindow(lengthMinutes: 10080, usedPercent: 10, resetsAt: nil)])

    // MARK: Claude

    @Test func claudeStates() {
        func health(_ state: SubscriptionState, expiresAt: Date? = nil) -> CredentialHealth? {
            CredentialHealth.claude(SubscriptionEntry(status: nil, state: state, credentialExpiresAt: expiresAt))
        }
        #expect(health(.ok) == .working)
        #expect(health(.signInRejected(lastGoodAt: nil)) == .rejected)
        #expect(health(.signInRejected(lastGoodAt: Self.t0)) == .rejected)
        #expect(health(.notSignedIn) == .notSignedIn)
        #expect(health(.credentialsExpired, expiresAt: Self.t0) == .expired(at: Self.t0))
    }

    @Test func claudeUnchangedStates() {
        func health(_ state: SubscriptionState) -> CredentialHealth? {
            CredentialHealth.claude(SubscriptionEntry(status: nil, state: state))
        }
        #expect(health(.stale(lastGoodAt: Self.t0, error: "offline")) == nil)
        #expect(health(.stale(lastGoodAt: nil, error: "credential read failed")) == nil)
        #expect(health(.retrying(lastGoodAt: Self.t0, error: "offline", retryAt: Self.t0)) == nil)
        // An expiry without a known time is never classified as expired.
        #expect(health(.credentialsExpired) == nil)
    }

    // MARK: Codex

    @Test func codexRejected() {
        let stale = CodexLimitsEntry(observation: Self.observation, state: .stale(reason: "rejected"), signInRejected: true)
        let bare = CodexLimitsEntry(observation: nil, state: .unavailable(reason: "rejected"), signInRejected: true)
        #expect(CredentialHealth.codex(stale) == .rejected)
        #expect(CredentialHealth.codex(bare) == .rejected)
    }

    @Test func codexProblems() {
        func health(_ problem: CodexCredentialProblem, observation: CodexLimitObservation? = nil) -> CredentialHealth? {
            let state: CodexLimitsState = observation == nil ? .unavailable(reason: "x") : .stale(reason: "x")
            return CredentialHealth.codex(CodexLimitsEntry(observation: observation, state: state, credentialProblem: problem))
        }
        #expect(health(.notSignedIn) == .notSignedIn)
        #expect(health(.keychain) == .notReadable)
        #expect(health(.expired(at: Self.t0)) == .expired(at: Self.t0))
        #expect(health(.notSignedIn, observation: Self.observation) == .notSignedIn)
        #expect(health(.expired(at: Self.t0), observation: Self.observation) == .expired(at: Self.t0))
    }

    @Test func codexWorking() {
        #expect(CredentialHealth.codex(CodexLimitsEntry(observation: Self.observation, state: .live)) == .working)
        #expect(CredentialHealth.codex(CodexLimitsEntry(observation: Self.observation, state: .newerSnapshot)) == .working)
    }

    @Test func codexUnchanged() {
        let entries = [
            CodexLimitsEntry(observation: Self.observation, state: .stale(reason: "offline")),
            CodexLimitsEntry(observation: Self.observation, state: .retrying(reason: "offline", retryAt: Self.t0)),
            CodexLimitsEntry(observation: nil, state: .unavailable(reason: "Codex sign-in file could not be read")),
        ]
        for entry in entries {
            #expect(CredentialHealth.codex(entry) == nil, "\(entry.state)")
        }
    }

    /// Live limits off: a local-only entry never counts, whatever it holds.
    @Test func codexWithLiveLimitsOffIsUnchanged() {
        #expect(CredentialHealth.codex(CodexLimitsEntry(observation: Self.observation, state: .localOnly)) == nil)
        let flagged = CodexLimitsEntry(observation: Self.observation, state: .localOnly, signInRejected: true,
                                       credentialProblem: .notSignedIn)
        #expect(CredentialHealth.codex(flagged) == nil)
    }
}
