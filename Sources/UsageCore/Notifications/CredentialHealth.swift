import Foundation

/// The state of an account's sign-in as one refresh saw it (spec 014
/// FR-001, data-model.md). Derived from the snapshot entries only: no
/// credential is read again (FR-015). A nil result of the derivations means
/// "unchanged": the account keeps its previous health.
public enum CredentialHealth: Equatable, Sendable {
    /// A request for the account succeeded.
    case working
    /// The usage service rejected the sign-in (spec 010 FR-001), or a Codex
    /// token already rejected was kept from being sent (spec 007 FR-003).
    case rejected
    /// No credential was found for the account.
    case notSignedIn
    /// Codex keeps its sign-in in the keychain, which AgentTacho cannot read.
    case notReadable
    /// The credential's expiry time `at` passed, so no request was sent.
    case expired(at: Date)

    /// The health of a Claude subscription account, or nil for unchanged:
    /// transport, rate limit, service changed, unreadable credentials, a
    /// grace period, and an expiry without a known time (spec 014 FR-001,
    /// edge case "Expiry time unknown").
    public static func claude(_ entry: SubscriptionEntry) -> CredentialHealth? {
        switch entry.state {
        case .ok: return .working
        case .signInRejected: return .rejected
        case .notSignedIn: return .notSignedIn
        case .credentialsExpired: return entry.credentialExpiresAt.map { .expired(at: $0) }
        case .stale, .retrying: return nil
        }
    }

    /// The health of a Codex subscription account with live limits on, or
    /// nil for unchanged. An entry computed with live limits off never has a
    /// health (spec 014 FR-001, FR-002).
    public static func codex(_ entry: CodexLimitsEntry) -> CredentialHealth? {
        if entry.state.impliedLiveLimits == false { return nil }
        if entry.signInRejected { return .rejected }
        switch entry.credentialProblem {
        case .notSignedIn?: return .notSignedIn
        case .keychain?: return .notReadable
        case .expired(let at)?: return .expired(at: at)
        case nil: break
        }
        switch entry.state {
        case .live, .newerSnapshot: return .working
        case .localOnly, .stale, .unavailable, .retrying: return nil
        }
    }
}
