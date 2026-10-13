# Implementation Plan: LLM Usage Menu Bar

**Branch**: `001-llm-usage-menubar` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-llm-usage-menubar/spec.md`

## Summary

A native macOS menu bar app that shows, per account, how much of a usage limit is consumed. Subscription accounts get Anthropic's real 5-hour and 7-day utilization from the OAuth usage endpoint using the token Claude Code keeps in the macOS Keychain. Token-based accounts (Claude Code via Vertex) get a USD spend computed from Claude Code's session JSONL files, priced with a built-in overridable table, against a self-set weekly budget owned by a budget group. The weekly window aligns with the subscription's 7-day reset. The app is a Swift Package: a UI-free `UsageCore` library holding all logic and tests, and a thin SwiftUI `MenuBarExtra` executable bundled into an `.app` by a Makefile.

## Technical Context

**Language/Version**: Swift 5.10 or newer (Xcode command line tools)

**Primary Dependencies**: Foundation, SwiftUI (`MenuBarExtra`), AppKit (window activation, `NSWorkspace` wake notification), UserNotifications, ServiceManagement (`SMAppService`), Security (Keychain read), CryptoKit (SHA-256 for keychain service suffix). No third-party packages.

**Storage**: JSON config at `~/.config/llm-usage-menubar/config.json`; diagnostic log at `~/Library/Logs/llm-usage-menubar/usage.log`; everything else in memory.

**Testing**: XCTest via `swift test` on `UsageCore` with fixture JSONL files under `Tests/UsageCoreTests/Fixtures`.

**Target Platform**: macOS 14+, Apple Silicon

**Project Type**: desktop app (menu bar utility)

**Performance Goals**: full refresh over 5,000 files under 10 s, incremental refresh under 1 s, idle under 1% CPU and 100 MB (SC-004, SC-008)

**Constraints**: read-only access to Claude Code data (never write keychain or logs), no credentials in config or log, no Dock icon, single in-flight refresh

**Scale/Scope**: 5 to 10 accounts, about 10,000 session files on disk, about 5 screens (bar, dropdown, settings with account, group and price editors)

## Global Constraints

Values every task inherits, copied from spec.md:

- Labels are 1 to 3 characters and unique across all accounts and groups together (FR-032).
- Refresh interval default 5 minutes, minimum 1 minute (60 s); the first refresh starts immediately at launch; never two concurrent refreshes (FR-024).
- Notification thresholds are whole-number percents greater than 0 (FR-027).
- Percents are rounded to the nearest whole number and never capped at 100 (FR-009a).
- Stored credentials are read only at refresh time and never copied into the configuration file, the diagnostic log, notifications, or any other file (FR-011a).
- The diagnostic log is bounded to 5 MB (FR-036).
- One single human-readable configuration file (FR-030) at `~/.config/llm-usage-menubar/config.json`.
- No Dock icon (FR-001); macOS 14 or newer on Apple Silicon; no third-party packages; read-only access to Claude Code's keychain item and session logs.
- Performance: full refresh over 5,000 files under 10 s, incremental refresh under 1 s, idle under 1% CPU and 100 MB resident (SC-004, SC-008).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is the unfilled template, so no project principles constrain this plan. Defaults applied in its place: logic separated from UI into a library with tests, no third-party dependencies, simplest structure that meets the spec. Gate: PASS (pre-research and post-design).

## Project Structure

### Documentation (this feature)

```text
specs/001-llm-usage-menubar/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── config-file.md
│   └── external-sources.md
└── tasks.md              # created by /speckit-tasks
```

### Source Code (repository root)

```text
Package.swift
Makefile                              # build, test, app (bundle), run
Resources/
└── Info.plist                        # LSUIElement=true, bundle id, version

Sources/UsageCore/
├── Config/
│   ├── Configuration.swift           # Codable model + validation (data-model.md)
│   ├── ConfigStore.swift             # load/save/default, mtime-based reload, last-valid fallback
│   └── Paths.swift                   # ~ expansion, config and log locations
├── Pricing/
│   ├── PriceTable.swift              # built-in + overrides, canonical model matching
│   └── Resources/prices.json
├── Logs/
│   ├── SessionRecordParser.swift     # one JSONL line -> UsageRecord?, tolerant
│   ├── LogDirectoryScanner.swift     # enumerate <dir>/projects/**/*.jsonl, canonical paths, dedupe
│   ├── LogIndex.swift                # per-file offsets, incremental re-read, window pruning
│   └── Attribution.swift             # detection rules, custom marker, directory tie-breaker
│   └── SessionLogSource.swift        # UsageSource over scanner + index, per-refresh diagnostics
├── Subscription/
│   ├── CredentialReader.swift        # protocol, service name from dir hash, OAuthCredential decoding
│   ├── UsageEndpointClient.swift     # GET /api/oauth/usage, decode, error mapping
│   └── SubscriptionSource.swift      # UsageSource: per-account state machine (ok/stale/notSignedIn/expired)
├── Windows/
│   └── WindowResolver.swift          # aligned 7-day window or weekday fallback
├── Snapshot/
│   ├── UsageSnapshot.swift           # output types (data-model.md), PercentFormatter
│   ├── Aggregator.swift              # records -> groups, accounts, unassigned, per-model, per-day
│   └── RefreshCoordinator.swift      # actor: UsageSource protocol, single in-flight refresh, window resolution
├── Notifications/
│   └── ThresholdTracker.swift        # crossing detection, baseline, reset on window change
└── Diagnostics/
    └── DiagnosticLog.swift           # append with 5 MB rollover

Sources/LLMUsageMenuBar/
├── App.swift                         # @main, MenuBarExtra, AppModel, timer, wake observer, settings window, start-at-login
├── BarLabel.swift                    # "M 42% V 17%" with threshold styling
├── DropdownView.swift                # entries, stale/error lines, actions
├── BreakdownView.swift               # per-model table and per-day row inside the dropdown
├── SettingsView.swift                # tab container, General and Prices tabs
├── AccountSettingsView.swift         # Accounts and Groups tabs
├── NotificationPresenter.swift       # UNUserNotificationCenter wrapper
└── KeychainCredentialReader.swift    # Security framework implementation of CredentialReader

Tests/UsageCoreTests/
├── Fixtures/                         # small JSONL files: vertex, direct, truncated, subagent, malformed
├── SmokeTests.swift
├── ConfigurationTests.swift
├── ConfigStoreTests.swift
├── DiagnosticLogTests.swift
├── RefreshCoordinatorTests.swift
├── UsageEndpointClientTests.swift
├── CredentialReaderTests.swift
├── SubscriptionSourceTests.swift
├── SessionRecordParserTests.swift
├── AttributionTests.swift
├── PriceTableTests.swift
├── WindowResolverTests.swift
├── LogIndexTests.swift
├── AggregatorTests.swift
└── ThresholdTrackerTests.swift

scripts/sum-vertex.sh                 # jq cross-check for SC-003 (quickstart S2)
README.md
.gitignore
```

**Structure Decision**: Single Swift package with two targets. `UsageCore` has no UI imports so every requirement except rendering and OS integration is unit-testable from the command line. The executable depends on `UsageCore` and injects the Keychain reader and notification presenter through protocols, so tests use in-memory fakes.

## Design notes by requirement area

- **Display (FR-001 to FR-009a)**: `MenuBarExtra` with `.window` style for a custom dropdown. The bar label is built from snapshot entries in configuration order; entries at or above their warning threshold get a distinct style (color if the label supports it, otherwise a glyph prefix). Percent rounding and the uncapped above-100 display live in one formatter in `UsageCore`.
- **Sources (FR-010 to FR-018)**: `UsageSource` protocol with two implementations. The log source owns the `LogIndex` and returns records; the subscription source returns `SubscriptionStatus`. Attribution runs per record. Price matching normalizes snapshot suffixes.
- **Windows and groups (FR-019 to FR-023)**: `WindowResolver` runs every refresh; `Aggregator` filters records by the window, sums per group, flags incomplete totals, builds per-model and per-day breakdowns with zero-filled days.
- **Refresh (FR-024 to FR-026)**: `RefreshCoordinator` actor; the app's timer and the wake observer both call `requestRefresh()`, which is a no-op while a refresh is running except that one pending request is remembered and served when the current refresh ends. The group window is resolved at refresh start from the last known alignment reset (so the log source can skip old files) and re-resolved after the sources finish; if the final window starts earlier, the log source runs once more before aggregation. When the log source fails, the previous group and account entries are carried over marked stale.
- **Notifications (FR-027 to FR-029)**: `ThresholdTracker` is pure logic returning the list of crossings; the presenter sends them. Subscription accounts produce crossings per window kind.
- **Configuration (FR-030 to FR-035)**: `ConfigStore` keeps the last valid configuration and the last error. Settings writes through the same validator. Start at login uses `SMAppService.mainApp`.
- **Diagnostics (FR-036, FR-037)**: `DiagnosticLog` appends one line per source per refresh; "Open log" uses `NSWorkspace.shared.open`.

## Review Focus

Failure modes the spec implies but does not list. Each has a pinning test in the named task.

| Input or failure mode | Expected behavior | Pinned by |
|---|---|---|
| Empty or missing `projects` directory | No records, no error | T030 |
| Configured log directory missing or unreadable | Scanner error logged, other directories still scanned, source succeeds | T030, T036, T038 |
| Session file rewritten or shrunk below the parsed offset | Re-read from offset 0 | T030, T037 |
| Assistant record with missing or unparsable `timestamp`, or no `message.usage` | Line skipped, file still parsed | T025, T026 |
| `cache_creation` without the 5m/1h split, or absent entirely | Fallback to `cache_creation_input_tokens`, else 0 | T026 |
| Model id that is a prefix-extension of a known id (`claude-opus-5-55`) | Unpriced; prefix fallback only at a `-` boundary | T028 |
| Keychain JSON without `claudeAiOauth` | Not signed in | T016 |
| Subscription `null` window | Row shows unavailable; bar uses the other window, `--` when both are null | T015, T021 |
| Provider failure after a good fetch, then recovery | Stale with last values, back to ok on next success (SC-007) | T016a |
| Log source fails on one refresh | Previous groups shown as stale; "Last refreshed" unchanged | T040 |
| Aligned window starts earlier than the fallback window used on the first refresh | Index reset and log source re-run inside the same refresh | T040 |
| Config with wrong field type, budget 0, out-of-range weekday or hour, alignment id pointing at a token-based account | Rejected; last valid configuration stays active | T008, T044 |
| Refresh requested while one is running (timer, wake, settings save) | No concurrent refresh; one follow-up runs afterwards | T013 |
| Refresh interval changed in settings | Timer restarts with the new interval | T014, T046 |
| Week window spanning a DST change | 7 calendar days, one per-day entry each | T029, T054 |
| Same threshold configured twice | One notification | T050 |
| Stale or not-signed-in subscription entry at refresh | No crossing evaluated, baseline unchanged | T050 |

## Complexity Tracking

No constitution violations to justify.
