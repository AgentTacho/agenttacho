# Data Model: Codex Plan Limits

All types live in `UsageCore` and are `Sendable` and `Equatable`.

## Configuration

### CodexSubscriptionSettings (extended)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `codexHome` | `String` | `Paths.defaultCodexHome` | unchanged (spec 006) |
| `shownInBar` | `Bool` | `true` | FR-016; display-only for `dataRelevant()` |
| `thresholds` | `[Int]` | `[]` | FR-014; each > 0 (`checkThresholds`) |
| `liveLimits` | `Bool` | `true` | FR-016; data-relevant (toggling refreshes) |

Missing keys decode to the defaults (FR-017). Validation keeps `.duplicateCodexHome`.

## Limits

### CodexLimitWindow

| Field | Type | Notes |
|-------|------|-------|
| `lengthMinutes` | `Int` | > 0 |
| `usedPercent` | `Double` | raw source value |
| `resetsAt` | `Date?` | from epoch seconds |
| `limitReached` | `Bool` | research R2 rule |

Computed: `name` (research R7), the window's identity. Display order: ascending `lengthMinutes`.

### CodexLimitObservation

| Field | Type | Notes |
|-------|------|-------|
| `planType` | `String?` | raw (`"plus"`); displayed capitalized |
| `observedAt` | `Date` | fetch time (live) or event timestamp (snapshot) |
| `origin` | `.live` or `.snapshot` | |
| `windows` | `[CodexLimitWindow]` | at least one; unique by `name` (later duplicate dropped) |

`effectiveWindows(now:)`: windows with `resetsAt <= now` become `usedPercent 0, resetsAt nil, limitReached false` (FR-010).

### CodexLimitsState

- `.live`: fetched successfully in this refresh, or the kept live result when no request was due (`.local` trigger or spacing), the last attempt did not fail and no snapshot is newer (spec FR-006 exception).
- `.newerSnapshot`: same situation, but a snapshot newer than the kept live result exists; the snapshot is shown with its observation time, not stale (spec FR-005, FR-006 exception). Threshold keys use the live flag like `.live`.
- `.localOnly`: live limits off; snapshot shown, not a failure.
- `.stale(reason: String)`: live limits on, values from an earlier live result or a snapshot.
- `.unavailable(reason: String)`: no observation at all.

### CodexLimitsEntry

| Field | Type | Notes |
|-------|------|-------|
| `observation` | `CodexLimitObservation?` | nil only for `.unavailable` |
| `state` | `CodexLimitsState` | |
| `sourceError` | `String?` | set only for an undecodable answer or a rejected sign-in (FR-006); the coordinator turns it into a `SourceError` |

Computed with `now`:
- `windows(now:)`: effective windows, shortest first.
- `barPercent(now:)`: rounded percent of the longest effective window (spec 001 FR-009a), nil when no observation.
- `anyLimitReached(now:)`.

### UsageSnapshot (changed)

- New: `codexLimits: [String: CodexLimitsEntry]` keyed by account id.
- Renamed: `planAccounts` to `codexPlanTokens` (research R11).

## Credentials

### CodexCredential

| Field | Type | Notes |
|-------|------|-------|
| `accessToken` | `String` | never logged; `description` redacts |
| `accountId` | `String?` | sent as `ChatGPT-Account-ID` |
| `expiresAt` | `Date?` | JWT `exp`; nil means unknown |

### CodexCredentialLookup

- `.found(CodexCredential)`
- `.missing(reason: String)`: no file, API-key mode, or keychain storage (research R3).

## Source state (in memory only)

- `CodexLimitsSource.lastLive: [accountId: CodexLimitObservation]`: cleared for an account when live limits are off, its Codex home changes, or the account is removed. Not persisted (spec FR-005).
- `CodexLimitsSource.gates: [canonical codexHome: CodexFetchGate]` where `CodexFetchGate { lastFetchAt: Date?, blockedUntil: Date? }`.
- `CodexLimitsSource.attempted: [accountId: (home, liveLimits)]`: the account had a fetch attempt for this combination; until then a `.local` refresh may fetch once.
- `CodexLimitsSource.files: [path: {size, modificationDate, snapshot: CodexLimitObservation?}]`.

## State transitions (per account, per refresh)

```text
liveLimits off ───────────────────────────────▶ .localOnly(newest snapshot) or .unavailable
liveLimits on:
  credential missing/expired/unreadable ─┐
  rate-limit wait (Retry-After ≤ 1 h) ───┼──▶ newest of (lastLive, snapshot) ─▶ .stale(reason) or .unavailable(reason)
  fetch error / no windows ──────────────┘
  no request due (.local, spacing) ──────────▶ last attempt failed: stale as above;
                                               else newer of (lastLive, snapshot): .live (lastLive) or .newerSnapshot (snapshot)
  fetch ok with windows ─────────────────────▶ .live(store lastLive)
```

## Threshold keys

`Key(scope: .codexPlan, entityId: accountId, windowKind: .codex(window, live: liveLimits))`, raw value `codex-live-<name>` or `codex-local-<name>`. `State.windowEnd` is the window's `resetsAt`.
