# Data Model: Credential Notifications

All types live in `UsageCore` unless noted.

## CredentialHealth (new, `Notifications/CredentialHealth.swift`)

```text
enum CredentialHealth: Equatable
  case working
  case rejected
  case notSignedIn
  case notReadable        // Codex sign-in kept in the keychain
  case expired(at: Date)
```

Derivation (returns nil for "unchanged", FR-001):

| Source | Entry | Health |
|---|---|---|
| Claude | `.ok` | working |
| Claude | `.signInRejected` | rejected |
| Claude | `.notSignedIn` | notSignedIn |
| Claude | `.credentialsExpired` with `credentialExpiresAt` | expired(at:) |
| Claude | `.stale`, `.retrying`, `.credentialsExpired` without time | nil |
| Codex (live limits on, entry not computed under live off) | `signInRejected == true` | rejected |
| Codex | `credentialProblem == .notSignedIn` | notSignedIn |
| Codex | `credentialProblem == .keychain` | notReadable |
| Codex | `credentialProblem == .expired(at:)` | expired(at:) |
| Codex | state `.live` or `.newerSnapshot` | working |
| Codex | anything else | nil |

A failing health is any case other than `working`.

## Additions to existing types

- `SubscriptionEntry.credentialExpiresAt: Date?`: set only with `.credentialsExpired`.
- `CodexCredentialProblem` (new enum): `.expired(at: Date)`, `.notSignedIn`, `.keychain`.
- `CodexLimitsEntry.credentialProblem: CodexCredentialProblem?`: set for entries built from a failure before a request (missing or expired sign-in); nil otherwise. Kept by `markedStale`.
- `CodexLimitsSource.Failure.credentialProblem`: carries it from `live()`.
- `Configuration.notifySignInProblems: Bool` (JSON key `notifySignInProblems`, default true when absent; presentation only, excluded from `dataRelevant()`).

## CredentialAlert (new)

| Field | Meaning |
|---|---|
| `accountId` | configured account id |
| `accountName` | account `displayName` |
| `provider` | `.claude` or `.codex` |
| `kind` | `.rejected`, `.notSignedIn`, `.notReadable`, `.expired` |
| `directory` | the credential directory or Codex home as configured, nil when it is the default; the tracker decides (expanded comparison with the default), `CredentialAlert` only formats |

Computed: `identifier` (`credential-<accountId>`), `title`, `body` (contract `contracts/notification-texts.md`). Holds no credential data.

## CredentialAlertEvent (new)

`.deliver(CredentialAlert)`, `.suppressed(CredentialAlert)` (due while the switch is off; only logged) or `.withdraw(accountId: String)`. `logMessage` gives the contract's log text.

## PendingNotificationQueue (new)

Queued notifications while authorization is pending: threshold crossings (newest per entity, window and threshold, as today) and credential alerts (one per account, newest wins). `removeCredential(accountId:)` drops a queued alert (FR-014); `drain()` returns and clears both lists.

## CredentialAlertTracker state (per account id)

| Field | Meaning |
|---|---|
| `identity` | `claude|<canonical dir>` or `codex|<canonical home>|live` |
| `health` | last health other than unchanged; nil until the baseline |
| `episode` | nil while working or before a working health was seen; otherwise the episode |

Episode: `kind` (the latest failing health), `notified: Bool` (a notification fell due, delivered or suppressed by the switch), `delivered: Bool` (a notification is in Notification Center or queued).

### Transitions (per observed health h, `now = snapshot.generatedAt`)

1. Identity differs from the stored one, or no state: store identity, `health = h`, no episode. Emit nothing (baseline, FR-004). If the old state had `delivered`, emit withdraw first (FR-008).
2. `h == nil` (unchanged): nothing changes, except an existing expired episode is re-checked for its delay (step 5).
3. `h == working`: if an episode exists and `delivered`, emit withdraw (FR-007). Clear the episode, `health = working`.
4. `h` failing and the previous health is working (no episode): start an episode with kind `h`.
5. `h` failing with an episode (new or existing): update kind to `h`. If not `notified` and due (kind is rejected, notSignedIn or notReadable; or kind is expired(at) with `now >= at + 24 h`): set `notified = true`; if the switch is on, emit deliver and set `delivered = true`, otherwise emit suppressed (FR-005, FR-006, FR-012).
6. `h` failing and the previous health is failing without an episode (baseline was failing): `health = h`, no episode, nothing emitted.

Configuration pass (each `observe` and `configurationChanged`): accounts no longer present, not eligible (FR-002) or with a changed identity lose their state, with withdraw if `delivered`. When the switch is off, every episode with `delivered` emits withdraw and is set to `delivered = false` (it stays `notified`).
