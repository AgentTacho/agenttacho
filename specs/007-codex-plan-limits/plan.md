# Implementation Plan: Codex Plan Limits

**Branch**: `007-codex-plan-limits` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/007-codex-plan-limits/spec.md`

## Summary

Codex subscription accounts gain plan limits: per-window percent and reset time, a bar entry, thresholds, and a live-limits setting. The changes:

- **Live fetch.** A new `CodexUsageClient` calls `GET https://chatgpt.com/backend-api/wham/usage` with the access token from `<codexHome>/auth.json` (read-only, never refreshed). A new `CodexCredentialReader` reads only the fields it needs and checks the JWT expiry.
- **Snapshots.** `CodexSessionParser` gains a pure `latestLimitSnapshot(in:)`. The new source scans the account's rollout files newest first and caches per file, so snapshots of any age count.
- **Source.** A new `CodexLimitsSource` (plain `UsageSource`, own per-home fetch gate) picks live, the newer of last live and snapshot (stale), local only, or unavailable, and returns `SourceOutput.codexLimits`.
- **Display.** `UsageSnapshot.codexLimits` feeds the bar (longest window, critical on a reached limit), the dropdown (all windows, plan, observation time, reason), and `ThresholdTracker` (one key per window, live flag in the key).
- **Settings.** `CodexSubscriptionSettings` gains `shownInBar`, `thresholds`, `liveLimits` with defaults; the editor shows them.
- **Part A follow-ups.** Account Codex homes are scanned for tokens (research R10), and `planAccounts` becomes `codexPlanTokens` (R11).

## Technical Context

**Language/Version**: Swift 5.10 (toolchain 6.4), macOS 14+

**Primary Dependencies**: Foundation, SwiftUI, AppKit. No package dependencies.

**Storage**: Reads `<codexHome>/auth.json`, `<codexHome>/config.toml` (one key), `<codexHome>/sessions/**`. Writes only AgentMeter's `config.json` and diagnostic log.

**Testing**: Swift Testing via `make test`. Synthetic rollout fixtures, `StubURLProtocol` for HTTP, temp Codex homes with synthetic `auth.json` (fake JWTs), injected clocks.

**Target Platform**: macOS 14+ menu bar app

**Project Type**: desktop app (`AgentMeter`) with core library (`UsageCore`)

**Performance Goals**: An incremental refresh with no new Codex files parses no rollout file; the live fetch adds one HTTP request per account per refresh (30 s timeout, concurrent with other sources).

**Constraints**:
- Never write to a Codex home; never call `auth.openai.com`; never decode or hold the refresh token.
- No credential text in logs, errors, notifications, snapshot descriptions, or files (sentinel tests).
- Claude subscription fetch and `EndpointPolicy` unchanged.
- Existing configs load unchanged (FR-017).

**Scale/Scope**: 4 new core files, about 12 changed files, 4 new test suites, 6 extended.

## Global Constraints

- Swift 5.10, macOS 14+, no package dependencies.
- No em-dash or en-dash characters in code, comments, or strings.
- Request only `https://chatgpt.com/backend-api/wham/usage`; no other host for this feature (FR-019).
- With `liveLimits == false`: no read of `auth.json`, no request (FR-019).
- Ephemeral `URLSession` (no cache, no cookies) for the Codex client.
- Doc comments cite FR ids, as in the rest of `UsageCore`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution is the unfilled template. The plan follows the codebase conventions: pure logic in `UsageCore`, Swift Testing per type, thin views, FR ids in doc comments, injectable clocks and readers. Post-design: no violations.

## Project Structure

### Documentation (this feature)

```text
specs/007-codex-plan-limits/
├── plan.md
├── research.md                 # R1 to R11
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── codex-usage-endpoint.md # live service, auth.json, rollout snapshot (read-only)
│   └── config-file.md          # shownInBar, thresholds, liveLimits on codexSubscription
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/Configuration.swift           # CodexSubscriptionSettings fields, decode/encode defaults, checkThresholds, dataRelevant (R9)
├── Subscription/CodexLimits.swift       # NEW: CodexLimitWindow (name), CodexLimitObservation (effectiveWindows), CodexLimitsState, CodexLimitsEntry (R2, R6, R7)
├── Subscription/CodexCredentialReader.swift # NEW: CodexCredential (redacted), CodexCredentialLookup, FileCodexCredentialReader, JWT exp (R3)
├── Subscription/CodexUsageClient.swift  # NEW: request, lenient decode, HTTP outcome mapping, reuses UsageEndpointError (R1, R2)
├── Subscription/CodexLimitsSource.swift # NEW: actor; snapshot scan + cache; CodexFetchGate; selection; logging (R4, R5, R6)
├── Logs/CodexSessionParser.swift        # latestLimitSnapshot(in:) (R4)
├── Logs/CodexSessionSource.swift        # account homes in homes(for:); shared rollout file listing (R4, R10)
├── Snapshot/RefreshCoordinator.swift    # RefreshContext.trigger; SourceOutput.codexLimits merge; carry-over when the source fails
├── Snapshot/UsageSnapshot.swift         # codexLimits; planAccounts -> codexPlanTokens (R11)
├── Snapshot/Aggregator.swift            # rename only
├── Bar/BarLayout.swift                  # codex item (R8)
└── Notifications/ThresholdTracker.swift # WindowKind struct, .codexPlan scope, codex loop (R8)

Sources/AgentMeter/
├── App.swift                 # register CodexLimitsSource
├── DropdownView.swift        # CodexPlanSection with windows, plan, observed-at, reason, limit-reached note
├── AccountSettingsView.swift # CodexSubscriptionEditor: shown in bar, thresholds, live limits; captions
└── NotificationPresenter.swift # unchanged API; uses windowKind.rawValue/displayName

Tests/UsageCoreTests/
├── CodexLimitsTests.swift (new), CodexCredentialReaderTests.swift (new), CodexUsageClientTests.swift (new), CodexLimitsSourceTests.swift (new)
├── Fixtures/codex/limits-*.jsonl (new, synthetic)
└── CodexSessionParserTests, CodexSessionSourceTests, ConfigurationTests, BarLayoutTests, ThresholdTrackerTests, RefreshCoordinatorTests, AggregatorTests (extended or adjusted)
```

**Structure Decision**: Keep the two-target layout. The limits code sits next to the Claude subscription code in `Sources/UsageCore/Subscription/`.

## Design Notes

1. **Model (R2, R6, R7).** Pure value types with `now`-based computed views. `CodexLimitWindow.name` and `CodexLimitObservation.effectiveWindows(now:)` carry FR-009 and FR-010, so bar, dropdown and tracker share one implementation.
2. **Credentials (R3).** `protocol CodexCredentialReader: Sendable { func read(codexHome: String) throws -> CodexCredentialLookup }`. The file reader decodes a minimal `Codable` struct (`auth_mode`, `tokens.access_token`, `tokens.account_id`). JWT payload decoding is a small private helper (split, base64url pad, `JSONSerialization`, `exp` as number). `description` redacts.
3. **Client (R1, R2).** `struct CodexUsageClient { init(session:url:clock:userAgent:); func fetch(_ credential: CodexCredential) async throws -> CodexLimitObservation }`. Maps 401 and 403 to `.httpStatus`, 429 to `.rateLimited(parseRetryAfter)` (reuse the existing parser by making it internal), transport errors to `.network`, decode failure to `.decoding`. An answer without windows throws a dedicated `CodexUsageError.noLimits`.
4. **Snapshots (R4).** `latestLimitSnapshot(in:)` reuses the parser's line splitting and copied-history detection, and runs before the `info` guard. The source's file listing moves into a shared static helper used by both Codex sources.
5. **Source (R5, R6).** `actor CodexLimitsSource: UsageSource`, name `codexLimits`. Per account, concurrently: resolve the newest snapshot; if `liveLimits` and the gate allows, read the credential and fetch; select and build the entry; log one line (source, observation time, reason, never a token). Accounts removed from the config drop their `lastLive`; homes no longer referenced drop their gate and file cache.
6. **Coordinator.** `RefreshContext(configuration:window:now:trigger:)` with `trigger` defaulting to `.scheduled`. The coordinator passes its trigger. A failed result from the source named `CodexLimitsSource.sourceName` is excluded from `subscriptionSourceFailure` (the Claude carry-over) and handled by the codex carry-over instead. `.codexLimits` outputs merge by key into `snapshot.codexLimits`. Entries carrying a source error (`CodexLimitsEntry.sourceError`) become `SourceError`s. If the source throws, previous entries carry over with `.live` turned into `.stale("refresh failed")`.
7. **Thresholds (R8).** Convert `WindowKind` to a struct with the same static members; replace its `switch`-based `displayName` with stored values. Add scope `.codexPlan` and the codex loop. Invert `codexSubscriptionYieldsNoCrossings`.
8. **Bar (R8).** Replace `case .codexSubscription: continue` with a `codexItem`, using `snapshot.generatedAt` as `now`. Invert `codexSubscriptionNeverYieldsABarItem`.
9. **UI.** `CodexPlanSection` shows the header percent (bar percent), one `WindowRow` per effective window with its name, a "limit reached" caption, the capitalized plan type, "as of <time>" when not `.live`, and the stale or unavailable reason, then the existing token breakdown. `CodexSubscriptionEditor` adds the toggle "Show in menu bar", `ThresholdsEditor` ("applies to every plan window"), and the toggle "Live limits from the usage service" with a caption explaining the credential read and the snapshot fallback.

## Risks

- **Undocumented service.** It can change or start rejecting third-party callers. Mitigation: lenient decoding, the snapshot fallback, a source error naming the problem, and the live-limits toggle.
- **Token handling.** A leak would expose the user's ChatGPT session. Mitigation: minimal decode, redacted descriptions, ephemeral session, sentinel tests over logs, entries, errors and notifications.
- **Snapshot scan cost.** A first launch with a large Codex history. Mitigation: newest-first scan that stops at the first file older than the found snapshot, plus a per-file cache.
- **WindowKind refactor.** Touches notifications for all scopes. Mitigation: same raw values and display names for existing members; existing tracker tests must pass unchanged.

## Complexity Tracking

No constitution violations to justify.
