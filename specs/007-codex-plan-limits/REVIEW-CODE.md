# Code Review: Codex Plan Limits

**Spec:** specs/007-codex-plan-limits/spec.md
**Date:** 2026-10-14
**Reviewer:** Claude (speckit.spex-gates.review-code)
**Diff:** `git diff main...HEAD` (branch 007-codex-plan-limits)

## Compliance Summary

**Overall Score: 96.3% (52/54) before the deep review fix loop; 98.1% (53/54) after it**

- Functional Requirements: 19/21 before fixes (FR-005, FR-019 minor deviations); 20/21 after (FR-019 fixed, FR-005 partly fixed, one ambiguity left)
- Edge Cases: 10/10 (100%)
- Acceptance Scenarios: 16/16 (100%)
- Success Criteria: 7/7 (100%, SC-001 and SC-002 depend on the live service and are covered by design, not measured here)

Baseline `make test`: 551 tests in 63 suites passed.

## Detailed Review

### Functional Requirements

| FR | Implementation | Status | Notes |
|----|----------------|--------|-------|
| FR-001 | `CodexLimits.swift` (`CodexLimitWindow`, `CodexLimitObservation`, `CodexLimitsEntry`); `CodexLimitsSource.collect` builds one entry per Codex subscription account | Compliant | Window: length, percent, reset, reached; observation: plan type, time, origin |
| FR-002 | `CodexLimitsSource.live` reads via `FileCodexCredentialReader` inside `collect`; `CodexUsageClient.fetch` sends the bearer token | Compliant | Credential read only at refresh time, never cached |
| FR-003 | `CodexCredentialReader.swift` only reads `auth.json` / `config.toml`; expired JWT `exp` returns `.noRequest` before any request (`CodexLimitsSource.swift:264`) | Compliant | No refresh-token decode, no write path. Test `codexHomeIsNeverChanged` |
| FR-004 | `CodexSessionParser.latestLimitSnapshot` + `CodexLimitsSource.newestSnapshot` (any age, newest-first scan, cached per file) | Compliant | Skips missing plan type, empty windows, copied fork history |
| FR-005 | `CodexLimitsSource.fallback` (newer of last live and snapshot, future snapshot clamped to now); `.off` clears `lastLive`; `lastLive` in memory only | Minor deviation | On a not-due refresh (`.notDue`, reprice or manual within spacing) the kept live result is shown even when a newer local snapshot exists (`CodexLimitsSource.swift:168-171`). FR-005 says the newest observation wins whenever the service is not used; FR-006 says the live result keeps its live state in that case. The two clauses together are ambiguous for this narrow window |
| FR-006 | `CodexLimitsState.stale(reason:)`, `.localOnly`; `failure(for:)` maps decoding and 401/403 to `sourceError`; coordinator turns `sourceError` into `SourceError` | Compliant | Reasons match the spec examples |
| FR-007 | `FetchGate.blockedUntil` per canonical Codex home; `Retry-After` or one refresh interval; `decide` checks the gate for every trigger including manual | Compliant | One home per account (FR-016), so per home equals per sign-in |
| FR-008 | Parser drops `limit_id != "codex"`; client ignores `additional_rate_limits` | Compliant | |
| FR-009 | `CodexLimitWindow.name`; `CodexLimitObservation.init` dedupes by name; tracker keys by name | Compliant | |
| FR-010 | `CodexLimitObservation.effectiveWindows(now:)` | Compliant | 0%, no reset, no reached note |
| FR-011 | `DropdownView.swift` `CodexPlanSection`, `CodexWindowRow`, `planDisplayName` | Compliant | |
| FR-012 | `BarLayout.codexItem`: longest window, `--` when none, `.critical` on any reached window, stale only for `.stale` | Compliant | |
| FR-013 | `Aggregator` `codexPlanTokens` (renamed from `planAccounts`, assumption M-11) | Compliant | Totals unchanged |
| FR-014 | `CodexSubscriptionSettings.thresholds`, `checkThresholds` in validation, per-window evaluation | Compliant | |
| FR-015 | `ThresholdTracker` `.codexPlan` scope, `WindowKind.codex(_:live:)` keyed on live-limits setting, dropped keys on plan change, 120 s reset tolerance | Compliant | |
| FR-016 | `CodexSubscriptionEditor` toggles + thresholds; alignment uses `isSubscription` (Claude only) | Compliant | |
| FR-017 | `Account.init(from:)` defaults for missing keys | Compliant | Tests in `ConfigurationTests` |
| FR-018 | `CodexCredential.description` redacts; fixed-text errors; `describe` never prints the token; ephemeral, cache-free session | Compliant | Test `credentialsNeverLeak` |
| FR-019 | Only `CodexUsageClient.defaultURL`; `.off` skips reader and client | Minor deviation (risk), fixed in the deep review (redirects refused) | The shared `UsageEndpointClient.defaultSession` follows HTTP redirects by default. A redirect from `chatgpt.com` would make the app contact another host with the `Authorization` header. Not observed, but the guarantee "contact no service other than the plan's usage service" is not enforced |
| FR-020 | `CodexLimitsSource.describe` + per-account log line with origin, time and reason/note | Compliant | |
| FR-021 | Task group per account; coordinator carries previous entries over on a source failure without touching Claude subscriptions | Compliant | |

### Edge Cases

| Edge case | Status | Notes |
|-----------|--------|-------|
| Several Codex subscription accounts | Compliant | Per-account home, `lastLive` reset on home change |
| API-key sign-in | Compliant | `auth_mode != "chatgpt"` gives `noPlanSignIn` |
| Rate limit | Compliant | FR-007 gate |
| Changed or unreadable answer | Compliant | Lenient decoder, type mismatch gives source error |
| Other buckets | Compliant | |
| Empty snapshots | Compliant | Nil snapshots never replace `best` |
| Plan change | Compliant | Windows follow newest observation, tracker drops keys |
| Limit reached | Compliant | `applyingReachedRule`, `.critical` bar level |
| Session file mid-write | Compliant | Parser skips undecodable lines |
| Clock skew | Compliant | `min(snapshot.observedAt, now)` in `fallback` |

### Acceptance Scenarios

All 16 scenarios of US1 to US4 trace to the code paths above and to tests in `CodexLimitsSourceTests`, `BarLayoutTests`, `ThresholdTrackerTests`, `RefreshCoordinatorTests` and `ConfigurationTests`.

### Extra Features (Not in Spec)

- **Keychain detection** (`FileCodexCredentialReader.keychainStorage`): reads `cli_auth_credentials_store` from `config.toml` to give a precise stale reason. Matches the Key Entities note that a keychain sign-in counts as missing. Helpful, in the contract.
- **`CodexSessionSource` scans every account's Codex home** (research R10). Supports FR-004 for homes not listed as extra Codex homes. Helpful.

### Spec-Declared Constants

The spec has no `## Constants` section. Check skipped.

## Recommendations

### Critical (Must Fix)

- None from the compliance pass.

### Spec Evolution Candidates

- FR-005/FR-006 interplay on not-due refreshes (see FR-005 row).

### Fix Candidates

- FR-019: refuse HTTP redirects for the Codex usage request so the bearer token can only reach `chatgpt.com/backend-api/wham/usage`.

## Conclusion

Compliance is 96.3%, above the 95% threshold for the deep review. The two deviations are narrow: one is a spec ambiguity, the other a missing hardening against redirects.

## Deep Review Report

**Gate: PASS** (after fix round 1, plus a Minor follow-up). Full details: `specs/007-codex-plan-limits/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 3 | 2 | 1 (Notable) | completed |
| Architecture & Idioms | 8 | 2 | 6 (Minor) | completed |
| Security | 5 | 2 | 3 (2 Minor, 1 Notable) | completed |
| Production Readiness | 6 | 2 | 4 (2 Minor, 2 Notable) | completed |
| Test Quality | 15 | 4 | 11 (Minor) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external) | 1 | 0 | 1 (Minor) | completed (round 2 on the fixes: 0) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed |
| Re-review round 1 | 2 | 2 | 0 | completed |
| Test Suite (regression) | 1 | 1 | 0 | passed (556 tests) |

Raw counts per agent include duplicates. After deduplication there were 5 Important findings (all fixed), 26 Minor (6 fixed) and 4 Notable.

MVP: Test Quality (15 findings)

Key fixes applied:
1. Redirects refused for the Codex usage request; own ephemeral session with a 45 s resource timeout; response origin check (security, architecture, test quality). FR-018, FR-019.
2. A not-due refresh after a failed fetch stays stale instead of showing an older live result as live, which removes a duplicate-notification path (correctness, architecture). FR-005, FR-006, FR-015.
3. `PercentFormatter.rounded` no longer traps on huge untrusted percents (security). FR-021.
4. A token rejected with HTTP 401 is not sent again on scheduled refreshes; only an in-memory SHA-256 digest is kept; manual refresh, live-limits toggle, success or a new token clear it (production readiness).
5. Threshold evaluation skips entries computed under the other live-limits setting (correctness). FR-015.
6. FR-020 log lines now name the failure cause; tests strengthened (live-off discard, end-to-end log leak check, reset-passed state retention, redirect, 401/403).

Post-fix spec coverage: 21/21 requirements verified (no code removed).

Findings that needed a human decision (all resolved 2026-10-14, see review-findings.md, Resolved Ambiguities):
- FR-005 vs FR-006 on a not-due refresh without a prior failure: resolved; a newer local snapshot is shown without stale marking (`.newerSnapshot`).
- Suppressing a 401-rejected token and retrying on 403: resolved; kept as implemented and written into FR-003.
- `Retry-After` cap: resolved; honoured up to one hour (FR-007).
- The Claude usage client still follows redirects: out of scope, tracked in brainstorm/idea-inbox.md (`claude-client-redirect-guard`).
