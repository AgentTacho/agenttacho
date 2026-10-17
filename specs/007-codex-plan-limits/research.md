# Research: Codex Plan Limits

All findings were verified on 2026-10-14 against openai/codex `main` @ `c6327eb` (unchanged at tag `rust-v0.162.1` for the files cited), the locally installed Codex CLI 0.162.1, and the AgentTacho code base on branch `007-codex-plan-limits`. Repo paths below are under `codex-rs/`.

## R1. Usage endpoint

- **Decision**: `GET https://chatgpt.com/backend-api/wham/usage` with headers `Authorization: Bearer <tokens.access_token>`, `ChatGPT-Account-ID: <tokens.account_id>` (omitted when absent), `Accept: application/json`, `User-Agent: AgentTacho/<version>`. No body, 30 s timeout, ephemeral `URLSession` (no cache, no cookies), same as `UsageEndpointClient.defaultSession`.
- **Rationale**: This is the request Codex itself sends for `/status` (`backend-client/src/client.rs:149-157, 269-289`; `app-server/src/request_processors/account_processor.rs:1191-1224`). The base URL contains `/backend-api`, so the path is `/wham/usage`; `/api/codex/usage` is only used for non-ChatGPT base URLs. The `originator` header is not sent on this path in Codex either. The `x-openai-codex-luna-reserve` header is an opt-in that a passive reader must not send.
- **Alternatives considered**: Honouring a custom `chatgpt_base_url` from the Codex `config.toml`. Rejected for now (YAGNI): the default is used by all known setups, and the user's config does not set it.

## R2. Response shape and mapping

- **Decision**: Decode leniently (every field optional):
  - `plan_type: String?`
  - `rate_limit.limit_reached: Bool?`, `rate_limit.primary_window` and `rate_limit.secondary_window`, each with `used_percent` (number), `limit_window_seconds` (int), `reset_at` (epoch seconds)
  - `rate_limit_reached_type: {type: String}?`
  - `additional_rate_limits[]` and `credits` are ignored (FR-008, credits out of scope).
- Window length in minutes is `ceil(limit_window_seconds / 60)`; a window with a length of 0 or less, or without `used_percent`, is dropped. This is the same mapping Codex uses to build its rollout snapshots (`client.rs:615-689`), so live and snapshot windows compare directly (spec Assumption 2).
- **Limit reached per window**: a window counts as reached when its percent is at least 100, or when the source reports a reached limit (`rate_limit.limit_reached == true` live, `rate_limit_reached_type != null` in a snapshot) and the window has the highest percent of the observation. The source does not name the window, and the highest one is the one that blocks.
- **Alternatives considered**: Showing `additional_rate_limits` as extra windows. Rejected: FR-008 limits the feature to the main bucket, and no additional bucket with windows has been observed.

## R3. Credentials

- **Decision**: A `CodexCredentialReader` reads `<codexHome>/auth.json` at refresh time and decodes only `auth_mode`, `tokens.access_token` and `tokens.account_id`. The refresh token and id token are never decoded into memory. Outcomes:
  - `auth_mode == "chatgpt"` with an access token: a `CodexCredential { accessToken, accountId?, expiresAt? }`. `expiresAt` comes from the JWT `exp` claim of the access token (base64url payload, read locally). A token that is not a JWT or has no `exp` has `expiresAt == nil` and is tried.
  - File missing: if `<codexHome>/config.toml` sets `cli_auth_credentials_store` to `keyring` or `auto`, the reason is "Codex keeps its sign-in in the keychain"; otherwise "no Codex plan sign-in found in this Codex home".
  - `auth_mode` other than `chatgpt` (API key): "no Codex plan sign-in found in this Codex home".
  - Unreadable or malformed file: a read error, reported as stale reason only.
- **Expiry**: if `expiresAt <= now`, no request is made (FR-003). Codex refreshes when `exp` is 5 minutes away (`login/src/auth/manager.rs:3030-3048`), so an expired token means Codex has not run for a while.
- **Never refresh**: Codex rotates the refresh token on every refresh (`manager.rs:1600-1626`); reuse of an old one forces a re-login (`refresh_token_reused`). AgentTacho never calls `auth.openai.com` and never writes the Codex home.
- **Redaction**: `CodexCredential.description` and `debugDescription` print `token: <redacted>`, like `OAuthCredential`. Errors are built only from AgentTacho's own error types.
- **Alternatives considered**: Reading the keychain item `Codex Auth` (`login/src/auth/storage.rs:243-257`). Rejected: it adds a keychain prompt and a second credential path for a non-default setup; the spec treats keychain-only sign-ins as missing.

## R4. Snapshot discovery

- **Decision**: A new pure function `CodexSessionParser.latestLimitSnapshot(in: Data) -> CodexLimitObservation?` scans `token_count` events (also those with `info: null`), skips the copied parent history of forked files with the same rule the parser already uses, and returns the newest main-bucket snapshot (`limit_id == "codex"` or absent) that has a plan type and at least one window. Its observation time is the event timestamp.
- The limits source lists `<codexHome>/sessions/**/rollout-*.jsonl` (helper shared with `CodexSessionSource`), sorts by modification date descending, and parses files until it holds a snapshot whose observation time is at or after the next file's modification date. A per-path cache `{size, modificationDate, snapshot?}` avoids re-parsing unchanged files.
- **Rationale**: Rollout files are append-only, so a file's modification date bounds its newest event. In practice the newest file decides, so a refresh parses at most one changed file. Files older than the token window are included (FR-004 any age), which `CodexSessionSource` drops on purpose.
- **Alternatives considered**: Extending `CodexSessionSource` to emit snapshots in its `RecordBatch`. Rejected: that source drops files older than the window, and coupling limits to the token reader's window cache would complicate both.

## R5. Source architecture and network gating

- **Decision**: A new `actor CodexLimitsSource: UsageSource` (deliberately not `NetworkBoundSource`) returns a new `SourceOutput.codexLimits([String: CodexLimitsEntry])`. It owns a per-Codex-home `CodexFetchGate`:
  - no live fetch when the refresh trigger is `.local` (reprice after a price change, Assumption 3) or when live limits are off;
  - no live fetch before `blockedUntil` (Retry-After, capped at one hour, or one refresh interval when the 429 carries none, FR-007);
  - for `.manual`, `.wake` and `.settings` triggers, at most one fetch per 60 s per home, matching `EndpointPolicy`;
  - an account with no fetch attempt yet for its current (Codex home, live limits) combination is fetched once even on `.local`, so settings edits that only touch Codex accounts show live values at once; after a failed attempt, `.local` refreshes make no request (Assumption 3);
  - `.retry` and `.launch` triggers are spaced like `.manual` (60 s per home), so a Claude retry does not cause an extra Codex request.
- Times: `context.now` is used for expiry, the gate, the observation of a live result and `effectiveWindows`; a wait without Retry-After runs one refresh interval from `context.now` of the refresh that got the 429.
- A skip because no request was due (`.local`, spacing) after a successful attempt is not stale: the kept live result stays `.live`, or a newer snapshot is shown as `.newerSnapshot` (spec FR-006 exception); a skip after a failed attempt, or because of a rate-limit wait, is stale.
- `RefreshContext` gains `trigger: RefreshTrigger` (default `.scheduled` in the initializer, so existing tests compile).
- **Rationale**: `EndpointPolicy` is one global gate whose combined outcome would let a Codex rate limit block Claude (and the reverse), while FR-007 asks for a wait per sign-in. A plain source runs in both full and reprice modes, so snapshot changes are picked up even during a Claude backoff, and the source decides about the network itself.
- **Alternatives considered**: Making the source `NetworkBoundSource` and generalizing `EndpointPolicy` to per-key state. Rejected: larger change to a well-tested Claude path for no user-visible gain.

## R6. Choosing the shown observation

- **Decision**: Per account, in memory: `lastLive: CodexLimitObservation?`. Each refresh:
  1. Live limits off: drop `lastLive`; show the newest snapshot; state `.localOnly`.
  2. Live fetch succeeded with at least one window: store and show it; state `.live`.
  3. Request skipped because none was due, the last attempt did not fail, and a live result is kept: the newer of it and the newest snapshot (same clamping as in 4) is shown without stale marking; state `.live` for the live result, `.newerSnapshot` for a newer snapshot (the dropdown shows its observation time; threshold keys still follow the live-limits setting).
  4. Otherwise (including a skip after a failed attempt): candidates are `lastLive` and the newest snapshot; a snapshot time in the future is clamped to `now`; the later one wins; state `.stale(reason)`.
  5. No candidate: state `.unavailable(reason)`. Credential missing, expired or unreadable: no request; the reason names the cause.
- Before display, `effectiveWindows(now:)` applies FR-010: a window whose `resetsAt <= now` shows 0%, no reset time, not reached.
- Source errors (FR-006): only for an undecodable answer (`.decoding`) and a rejected sign-in (HTTP 401 or 403). Offline, expired or missing sign-in, and 429 only set the stale reason.

## R7. Window naming and identity

- **Decision**: `CodexLimitWindow.name`: minutes < 1440 gives `"\(round(minutes/60))-hour"`; a length that rounds to 7 days gives `"weekly"`; otherwise `"\(round(minutes/1440))-day"`. The name is the window's identity for threshold state and display order (shortest first).

## R8. Thresholds and the bar

- **Decision**:
  - `WindowKind` becomes a `struct WindowKind: Hashable, Sendable { rawValue: String; displayName: String }` with static constants `fiveHour`, `sevenDay`, `weekly`, `monthly` (same raw values and names as today) and `static func codex(_ window: CodexLimitWindow, live: Bool)` with raw value `codex-live-<name>` or `codex-local-<name>`. Folding the live flag into the key makes a toggle of the live-limits setting start a fresh baseline (FR-015), and keys that disappear are dropped by the existing `liveKeys` pruning.
  - `ThresholdTracker` gets a third loop. `liveKeys` receives a key for every window of the entry's observation (not only evaluated ones); when the entry is missing or `.unavailable`, the account's existing `.codexPlan` keys are kept. `windowEnd` comparisons for `.codexPlan` keys allow 120 s of difference, so live and snapshot reset times for the same window do not re-baseline.
  - The loop over `codexSubscriptionAccounts` with scope `.codexPlan`, evaluating every effective window that has a `resetsAt` (windows without one are skipped, as for Claude), on any state except `.unavailable` (FR-015: stale values count).
  - `BarLayout`: `.codexSubscription` yields an item when `shownInBar`. Percent: the longest effective window (`CodexLimitsEntry.barPercent`). Level: `.critical` when any effective window is reached, else `level(percent:thresholds:)`. Stale: only for `.stale`. `.unavailable` shows "--"; no entry yet shows "…".
- **Alternatives considered**: An enum case with an associated value. Rejected: `WindowKind.rawValue` is used in notification identifiers and dedup, which a struct keeps simple.

## R9. Configuration

- **Decision**: `CodexSubscriptionSettings` gains `shownInBar = true`, `thresholds: [Int] = []`, `liveLimits = true`. Decoding uses `decodeIfPresent ?? default` (FR-017); encoding writes all four keys (`shownInBar` and `thresholds` reuse the existing account coding keys, `liveLimits` is new). `validate()` applies `checkThresholds` to Codex accounts. `dataRelevant()` blanks `shownInBar` and `thresholds` (display only); `liveLimits` stays data-relevant so toggling it triggers a refresh.
- Alignment already excludes Codex accounts (`effectiveAlignmentAccountId`, `validate()`, settings picker), so FR-016's alignment clause needs only a test.

## R10. Account Codex homes are not scanned for tokens (part A gap)

- **Finding**: `CodexSessionSource.homes(for:)` reads only `~/.codex` and `configuration.codexHomes`, so a Codex subscription account whose `codexHome` is elsewhere has no token data. The limits source reads the account home directly, so limits work regardless.
- **Decision**: Add every Codex subscription account's `codexHome` to `homes(for:)` (deduplicated by canonical path). This is a one-line fix with a test, and makes the account's token breakdown (FR-013) consistent with its limits.

## R11. Naming (part A review finding M-11)

- **Decision**: Rename `UsageSnapshot.planAccounts` to `codexPlanTokens`, since the limits now live in the new `codexLimits` map next to it. Mechanical rename across `Aggregator`, `RefreshCoordinator`, `DropdownView` and tests.
