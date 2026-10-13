# Research: LLM Usage Menu Bar

**Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

All findings below were verified against the machine this app will run on first. Credential values were never printed; only structure and locations were inspected.

## R1: Where Claude Code stores session logs

**Decision**: Scan `<configDir>/projects/**/*.jsonl` for every configured config directory. Default config directory is `~/.claude`. Subagent transcripts live in `<configDir>/projects/<project>/<sessionId>/subagents/agent-*.jsonl` and must be included.

**Findings**:
- `~/.claude/projects` holds about 9,700 JSONL files on this machine: about 1,500 top-level session files and about 8,100 subagent transcripts in nested directories.
- cc-deck profile directories (`~/.local/share/cc-deck/profiles/<name>/claude`) symlink `projects` and `todos` to `~/.claude/projects` and `~/.claude/todos`. So on this machine all profiles share one log tree. The spec's directory tie-breaker for multiple subscription accounts (FR-013) only separates accounts when profile directories have their own `projects` tree. Scanning must resolve symlinks and dedupe by canonical path so a shared tree is never counted twice (spec edge case).
- Files are append-only. A file's modification time is an upper bound on the timestamps of the records it contains, so files not modified since before the current window start can be skipped entirely.

**Alternatives considered**: Watching directories with FSEvents (rejected for v1: polling on the refresh interval with mtime checks already meets SC-004 and is simpler).

## R2: Session JSONL record structure

**Decision**: Parse only records with `"type":"assistant"` that have `message.usage`. Dedupe by `message.id` (fallback `requestId`), keeping the last record seen. Timestamp from top-level `timestamp` (ISO 8601 UTC).

**Findings** (fields verified on real records):
- Top-level: `type`, `timestamp`, `sessionId`, `requestId`, `uuid`, `parentUuid`, `cwd`, `version`, `isSidechain`, `requestedModel`.
- `message.model`: bare model id, e.g. `claude-opus-4-8`, `claude-opus-5-5`, `claude-fable-5-1`, `claude-haiku-4-5-20251001`. Vertex sessions on this machine do not use the `@date` form; model ids look identical to direct ones.
- `message.id`: `msg_...` or `msg_vrtx_...`.
- `message.usage`: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, and `cache_creation.ephemeral_5m_input_tokens` / `cache_creation.ephemeral_1h_input_tokens` (split of cache writes by TTL).
- One API response produces several assistant records (one per content block) with the same `message.id` and the same cumulative usage. Counting every record would triple-count; dedupe by `message.id` is mandatory.
- Partially written last line occurs while a session is live; the parser skips any line that fails to decode.

## R3: Provider marker (Vertex vs direct Anthropic)

**Decision**: Built-in detection rule is the `requestId` prefix. `req_vrtx_` means Vertex; `req_011` (generally `req_` without a provider infix) means direct Anthropic. The `message.id` prefix (`msg_vrtx_`) corroborates. Bedrock would be `req_bdrk_` by the same convention but is not verified and not in scope.

**Findings**: Across about 300 recent files, 36,374 records carried `req_011...` and 15,380 carried `req_vrtx_...`. No other prefixes appeared. This is a reliable per-record marker, so attribution is per record, not per file.

**Custom marker (FR-013)**: a user-supplied substring matched against the raw JSON line of the assistant record. Covers future providers without a code change.

## R4: Subscription credentials and the usage endpoint

**Decision**: Read the OAuth access token from the macOS Keychain, call the OAuth usage endpoint, never refresh or write tokens.

**Findings**:
- Keychain generic password items: service `Claude Code-credentials` for the default config dir, and `Claude Code-credentials-<suffix>` for others, where suffix is the first 8 hex characters of SHA-256 of the config directory path (verified: `private` profile maps to `bf7c1594`, `work` to `4381c536`). Account name is the macOS username.
- Item value is JSON with `claudeAiOauth.accessToken`, `refreshToken`, `expiresAt` (epoch ms), `subscriptionType` (`max`), `scopes`, `rateLimitTier`, plus unrelated `mcpOAuth` entries.
- Read through `/usr/bin/security find-generic-password -s <service> -w` (2026-10-13). Claude Code writes its items with that tool, so each item trusts it and no keychain dialog appears; reading with the keychain API from the ad-hoc signed app prompted again after every rebuild.
- Endpoint: `GET https://api.anthropic.com/api/oauth/usage` with headers `Authorization: Bearer <accessToken>` and `anthropic-beta: oauth-2025-04-20`. Verified HTTP 200. Response fields used: `five_hour.utilization` (percent, float), `five_hour.resets_at` (ISO 8601 with offset), `seven_day.utilization`, `seven_day.resets_at`. Extra fields (`limits[]`, `seven_day_opus`, `extra_usage`) are ignored. Null windows are shown as unavailable (spec assumption).
- Reading another app's keychain item triggers a one-time macOS consent dialog. The dialog recurs if the app's code signature changes, so the bundle script must sign with a stable identifier (ad-hoc signing with a fixed bundle id is acceptable for personal use; a developer certificate is better).
- An expired access token cannot be refreshed without writing back to Claude Code's keychain item, which the spec forbids. Decision: when `expiresAt` is in the past, the account shows "credentials expired, run Claude Code to refresh" and the refresh is skipped for that source.

**Alternatives considered**: reading `~/.claude/.credentials.json` (not present on this machine; Keychain is the macOS storage), implementing the refresh flow (rejected: modifies harness state, duplicates Claude Code's client id handling).

## R5: Price table

**Decision**: Ship a built-in JSON price table (USD per million tokens) keyed by canonical model id, with input, output, cache-write 5-minute, cache-write 1-hour, and cache-read prices. Vertex and direct are priced identically by default (spec assumption); the user can override per model.

**Canonical ids and prices** (from the Claude API reference cached 2026-10-06; cache write defaults are 1.25x input for 5m and 2x input for 1h; cache read 0.1x input unless listed):

| Model id | Input | Output | Cache read |
|---|---|---|---|
| claude-fable-5-1 | 10.00 | 50.00 | 0.25 |
| claude-fable-5 | 10.00 | 50.00 | 1.00 |
| claude-opus-5-5 | 4.00 | 20.00 | 0.20 |
| claude-opus-5 | 5.00 | 25.00 | 0.50 |
| claude-opus-4-8 | 5.00 | 25.00 | 0.50 |
| claude-opus-4-7 | 5.00 | 25.00 | 0.50 |
| claude-opus-4-6 | 5.00 | 25.00 | 0.50 |
| claude-sonnet-5-5 | 2.00 | 10.00 | 0.20 |
| claude-sonnet-5 | 2.00 | 10.00 | 0.20 |
| claude-sonnet-4-6 | 3.00 | 15.00 | 0.30 |
| claude-haiku-5-5 | 0.10 | 0.50 | 0.01 |
| claude-haiku-4-5 | 1.00 | 5.00 | 0.10 |

**Matching rule**: normalize the log's model id by stripping a trailing `-YYYYMMDD` or `@YYYYMMDD` snapshot suffix, then exact match; if no exact match, longest key that is a prefix of the normalized id where the prefix ends at a `-` boundary (so `claude-opus-5-5-eu` matches `claude-opus-5-5` but `claude-opus-5-55` matches nothing). Unmatched models are reported as unpriced (FR-016). Fable 5.1 and Opus 5.5 are the only verified exceptions to the 0.1x cache-read rule; the table carries explicit values for every row so overrides are uniform.

## R6: Platform and stack

**Decision**: Swift 5.10+, SwiftUI `MenuBarExtra` for the bar item and dropdown, AppKit where SwiftUI falls short (window activation for settings), `UserNotifications` for threshold alerts, `ServiceManagement.SMAppService` for start at login, `Security` framework for Keychain reads. Target macOS 14 or newer (current is macOS 26; the spec allows dropping anything older than the previous major release, and 14 gives headroom for the user's other Macs).

**Build**: Swift Package Manager only, no Xcode project. Targets: `UsageCore` (library, all logic, no UI imports), `LLMUsageMenuBar` (executable, SwiftUI app), `UsageCoreTests` (XCTest). A `Makefile` target `app` assembles `build/LLM Usage.app` with an `Info.plist` that sets `LSUIElement` (no Dock icon) and a bundle identifier, then ad-hoc codesigns it. Notifications and keychain consent require running from a bundle, so `make app && make run` is the way to launch; `swift test` covers the core.

**Alternatives considered**: Xcode project (rejected: harder to drive from CLI and from the implement stage), Rust with a menu bar crate (rejected: notifications, keychain and SwiftUI integration are far smoother in Swift), Electron or Tauri (rejected: footprint conflicts with SC-008).

## R7: Configuration and state files

**Decision**:
- Config: `~/.config/llm-usage-menubar/config.json`, Codable, written by the settings window and readable by hand. Reloaded at the start of every refresh when its modification time changed; on decode failure the last valid config stays active and the error is surfaced (FR-033).
- Diagnostic log: `~/Library/Logs/llm-usage-menubar/usage.log`, capped at 5 MB by renaming to `usage.log.1` when the cap is reached (one generation kept).
- Notification baseline and the last known reset timestamps: in memory only. A relaunch re-establishes the baseline per FR-028; persisting it would add a state file for no spec requirement.

## R8: Refresh and incremental scanning

**Decision**: A `RefreshCoordinator` actor owns a single in-flight refresh (FR-024). It runs all sources concurrently in a task group, collects per-source results or errors (FR-026), builds a `UsageSnapshot`, and publishes it to the UI. The log source keeps an in-memory index per canonical file path (size, mtime, byte offset already parsed, records in the current window). On refresh it lists files, skips files whose mtime is before the window start, re-reads changed files from the stored offset (append-only), and drops index entries for files outside the window. A `NSWorkspace.didWakeNotification` observer triggers an immediate refresh after sleep.

**Performance check**: listing 10,000 files and stat-ing them takes well under one second on APFS; parsing only changed files keeps the incremental refresh under the 1-second target (SC-004). The first scan after launch reads only files modified inside the window, typically a few hundred.

## R9: Week window alignment

**Decision**: `WindowResolver` computes the group window from the designated subscription account's last fetched `seven_day.resets_at`: `[resets_at - 7 days, resets_at)`. If none has been fetched since launch, use the fallback weekday and hour: start is the most recent occurrence in local time, end is 7 days later. Both the aligned timestamp and the fallback are recomputed every refresh so the window rolls over without a restart.

## Open items carried into implementation

- Whether `MenuBarExtra` with `.menuBarExtraStyle(.window)` renders the bar label with per-entry coloring. If attributed strings are not supported in the label, the fallback is a symbol prefix (for example a warning glyph) per entry above threshold, which still satisfies FR-003.
  - Implementation (T021): the label is built both ways. `BarLabelBuilder.attributed` colors warning entries orange and entries at or above 100% red, and `BarSegment.text` always carries a glyph prefix (`⚠` at or above the warning threshold, `‼` at or above 100%) plus a `~` prefix for stale values. macOS is known to render menu bar label text as a template, so the glyph is the behavior to rely on; the color is a bonus where it survives. Not confirmed visually during the implement stage (no human at the screen).
- Keychain consent prompts with ad-hoc signing: acceptable for the user's own machine; document in quickstart.
  - Observed (T024, first launch from the bundle, 2026-10-13): the first keychain read happened during default-configuration creation and took about 9 seconds before the "credentials found: true" line was logged; the refresh then completed with HTTP 200 (5h 24%, 7d 55%) and no authorization error, so the consent dialog was either answered or not required. The full first refresh took 13.6 s because of that wait; later refreshes are expected in well under a second. Re-signing the bundle with a changed identity would trigger the dialog again.

## Toolchain findings during implementation

- The machine has only the Command Line Tools (no Xcode). XCTest is not shipped there, so the tests use Apple's Swift Testing framework (`import Testing`), which is part of the toolchain. `swift test` needs `-Xswiftc -plugin-path <toolchain>/usr/lib/swift/host/plugins/testing` to find the testing macros; the `Makefile` `test` target passes it.
- The default macOS 27 SDK turns SwiftUI property wrappers such as `@State` into macros whose plugin (`SwiftUIMacros`) the Command Line Tools do not ship. The `Makefile` exports `SDKROOT` pointing at the installed macOS 26 SDK when present; the deployment target stays macOS 14.
- SwiftPM's new build system names the resource bundle `llm-usage-menubar_UsageCore.bundle` (package name prefix), and `Bundle.module` looks for it in `Contents/Resources` of the app. The `Makefile` copies that name.
