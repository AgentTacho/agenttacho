# Tasks: LLM Usage Menu Bar

**Input**: Design documents from `/specs/001-llm-usage-menubar/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included. quickstart.md requires `swift test` coverage for parsing, attribution, pricing, windows, aggregation, thresholds, and config validation. Tests for `UsageCore` are written before the implementation they cover and must fail first.

**Organization**: Tasks are grouped by user story. `UsageCore` holds all logic; `LLMUsageMenuBar` is the SwiftUI shell.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1 to US5)
- Include exact file paths in descriptions

## Path Conventions

Swift Package at repository root: `Package.swift`, `Sources/UsageCore/`, `Sources/LLMUsageMenuBar/`, `Tests/UsageCoreTests/`, `Resources/`, `Makefile` (see plan.md).

## Shared Interfaces

Types that more than one task produces or consumes. A task that uses one of these names uses it exactly as written here; field lists live in data-model.md.

```swift
// Sources/UsageCore/Snapshot/RefreshCoordinator.swift (T013)
public struct RefreshContext {
    public let configuration: Configuration
    public let window: DateInterval        // group window resolved at the start of this refresh
    public let now: Date
}
public enum SourceOutput {
    case subscriptions([String: SubscriptionEntry])   // keyed by account id, breakdown left empty
    case records([UsageRecord])                       // all records with timestamp >= window.start
}
public protocol UsageSource: Sendable {
    var name: String { get }                          // used in SourceError and DiagnosticLog
    func collect(context: RefreshContext) async throws -> SourceOutput
}
public actor RefreshCoordinator {
    public init(configStore: ConfigStore, log: DiagnosticLog, resolver: WindowResolver, aggregator: Aggregator)
    public func register(_ source: UsageSource)
    public func requestRefresh()                      // no-op while running, but sets a pending flag
    public nonisolated var snapshots: AsyncStream<UsageSnapshot> { get }
}

// Sources/UsageCore/Logs/LogDirectoryScanner.swift (T036)
public struct ScannedFile { let canonicalPath: String; let configDirectory: String; let size: Int; let modificationDate: Date }

// Sources/UsageCore/Snapshot/Aggregator.swift (T039, T055)
public struct Aggregator {
    public func aggregate(records: [UsageRecord], subscriptions: [String: SubscriptionEntry],
                          configuration: Configuration, window: DateInterval, windowSource: WindowSource,
                          now: Date, calendar: Calendar) -> UsageSnapshot
}

// Sources/UsageCore/Notifications/ThresholdTracker.swift (T051)
public struct ThresholdCrossing: Equatable {
    public let entityId: String; public let entityName: String
    public let windowKind: WindowKind; public let threshold: Int; public let percent: Int
}
public enum WindowKind: String { case fiveHour, sevenDay, weekly }
```

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Buildable package skeleton with both targets, tests, and the app bundle pipeline

- [x] T001 Create `Package.swift` with targets `UsageCore` (library, resources `Resources/prices.json`), `LLMUsageMenuBar` (executable depending on UsageCore), `UsageCoreTests` (XCTest, resources `Fixtures` so tests load them via `Bundle.module`), platform macOS 14, swift-tools-version 5.10
- [x] T002 [P] Create placeholder sources so the package builds: `Sources/UsageCore/UsageCore.swift` (empty namespace enum) and `Sources/LLMUsageMenuBar/App.swift` (minimal `@main` App with an empty `MenuBarExtra`)
- [x] T003 [P] Create `Resources/Info.plist` with `CFBundleIdentifier` `dev.rhuss.llm-usage-menubar`, `CFBundleName` `LLM Usage`, `LSUIElement` true, `CFBundleShortVersionString` 0.1.0, `LSMinimumSystemVersion` 14.0
- [x] T004 [P] Create `Makefile` with targets `build` (swift build -c release), `test` (swift test), `app` (copy the release binary into `build/LLM Usage.app/Contents/MacOS/`, copy Info.plist into `Contents/`, copy the SwiftPM resource bundle `.build/release/UsageCore_UsageCore.bundle` into `Contents/Resources/` so `Bundle.module` finds `prices.json` outside the build tree, `codesign --force --sign - --identifier dev.rhuss.llm-usage-menubar`), `run` (`open "build/LLM Usage.app"`), `clean`
- [x] T005 [P] Create `.gitignore` with `.build/`, `build/`, `*.xcodeproj`, `.swiftpm/`, `.DS_Store`
- [x] T006 Verify `swift build` and `swift test` succeed on the skeleton (one trivial test in `Tests/UsageCoreTests/SmokeTests.swift`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Configuration model, paths, diagnostics, snapshot types, and the refresh skeleton that every story builds on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T007 [P] Implement `Sources/UsageCore/Config/Paths.swift`: tilde expansion, `configFileURL` (`~/.config/llm-usage-menubar/config.json`), `logFileURL` (`~/Library/Logs/llm-usage-menubar/usage.log`), `defaultClaudeDirectory` (`~/.claude`), with an injectable home directory for tests
- [x] T008 [P] Write `Tests/UsageCoreTests/ConfigurationTests.swift`: decode the example from `contracts/config-file.md`, round-trip encode, and validation failures for label length, duplicate labels across accounts and groups (comparison is exact, case-sensitive), token account without group or with an unknown `groupId`, empty group, two subscription accounts sharing a credential directory, interval below 60, threshold of 0, `weeklyBudgetUSD` of 0 or negative, `weekFallback.weekday` outside 1 to 7 or `hour` outside 0 to 23, `alignmentAccountId` naming a token-based or unknown account, unknown account `type` rejected, a field of the wrong JSON type (`"refreshIntervalSeconds": "300"`) rejected as a decode error, unknown top-level keys ignored
- [x] T009 Implement `Sources/UsageCore/Config/Configuration.swift` per data-model.md: `Configuration`, `Account` with `type` discriminator (`subscription` / `tokenBased`), `SubscriptionSettings`, `TokenBasedSettings`, `BudgetGroup`, `WeekFallback`, `PriceEntry`, `Harness`, `Provider`, plus `Configuration.validate() throws ConfigurationError` covering all rules in T008; `ConfigurationError` carries a human-readable `message` for the settings window and the dropdown
- [x] T044 [P] [US3] Write `Tests/UsageCoreTests/ConfigStoreTests.swift` in a temp directory: save then load round-trip, hand-edited invalid JSON keeps the last valid configuration and reports the error, a file that decodes but fails `validate()` is treated the same way, reload happens only when mtime changes, default creation on missing file (moved here from Phase 5 so the test precedes T010)
- [x] T010 Implement `Sources/UsageCore/Config/ConfigStore.swift`: `load() -> (Configuration, ConfigurationError?)` returns the last valid configuration and an optional error, reloads only when file mtime changed, `save(_:)` validates then writes atomically (known keys only; unknown keys from a hand-edited file are not preserved, see contracts/config-file.md), `makeDefault(hasDefaultCredentials:)` builds the FR-034 default (one subscription account labeled `M` when credentials exist)
- [x] T011 [P] Implement `Sources/UsageCore/Diagnostics/DiagnosticLog.swift`: `append(source:message:)` with timestamp, rollover to `usage.log.1` when the file exceeds 5 MB, injectable file URL; add `Tests/UsageCoreTests/DiagnosticLogTests.swift` covering rollover
- [x] T012 [P] Implement `Sources/UsageCore/Snapshot/UsageSnapshot.swift` with all snapshot types from data-model.md (`UsageSnapshot`, `SubscriptionEntry`, `SubscriptionState`, `GroupEntry`, `TokenAccountEntry`, `UsageBreakdown`, `ModelUsage`, `DayUsage`, `SourceError`, `WindowSource`) and `PercentFormatter.rounded(_:)` (nearest whole number, uncapped)
- [x] T013 Implement `Sources/UsageCore/Snapshot/RefreshCoordinator.swift` as the actor in Shared Interfaces: `requestRefresh()` ignores calls while a refresh runs but records one pending request that starts a single follow-up refresh when the current one ends; each refresh reloads the configuration through `ConfigStore.load()` (setting `UsageSnapshot.configError`), runs registered `UsageSource` instances in a task group, captures per-source errors into `sourceErrors` (`SourceError(sourceName:message:at:)`), logs each outcome through `DiagnosticLog`, sets `lastSuccessfulRefreshAt` to `generatedAt` when no source failed (otherwise carries the previous value), and publishes the resulting `UsageSnapshot` through `snapshots`; add `Tests/UsageCoreTests/RefreshCoordinatorTests.swift` for single-in-flight behavior, the pending follow-up, and error isolation (FR-024, FR-026)
- [x] T014 Implement `Sources/LLMUsageMenuBar/App.swift` for real: `MenuBarExtra` with `.window` style, an `AppModel` (`@Observable`) that owns `ConfigStore`, `RefreshCoordinator`, a repeating `Task` timer using `refreshIntervalSeconds` (restarted whenever a loaded configuration changes the interval), an immediate refresh at launch, and a `NSWorkspace.didWakeNotification` observer that calls `requestRefresh()`

**Checkpoint**: Package builds, config loads and validates, a refresh with zero sources produces an empty snapshot

---

## Phase 3: User Story 1 - Glance at subscription limits from the menu bar (Priority: P1) 🎯 MVP

**Goal**: Bar shows `M <n>%` from Anthropic's real limits; dropdown shows both windows with reset times, stale and not-signed-in states

**Independent Test**: Launch the bundle on a machine with Claude Code signed in; within 60 s the bar shows the percent, the dropdown shows 5-hour and 7-day rows matching Claude Code's `/usage` within 1 point (quickstart S1)

### Tests for User Story 1

- [x] T015 [P] [US1] Write `Tests/UsageCoreTests/UsageEndpointClientTests.swift` using a stubbed `URLProtocol`: decodes the response shape in `contracts/external-sources.md`, treats `null` windows as unavailable, maps non-200 to `UsageEndpointError.httpStatus(Int)` (401 included; the expired-credential decision is made by `SubscriptionSource`, T016a), maps an undecodable body to `UsageEndpointError.decoding`, asserts the request carries the Bearer and `anthropic-beta` headers
- [x] T016 [P] [US1] Write `Tests/UsageCoreTests/CredentialReaderTests.swift` for the pure parts of T017: keychain service name is `Claude Code-credentials` for `~/.claude` and `Claude Code-credentials-<sha256 prefix>` otherwise (verify `bf7c1594` for `/Users/rhuss/.local/share/cc-deck/profiles/private/claude`, tilde expanded, no trailing slash), `OAuthCredential` decoding from keychain JSON reads `claudeAiOauth.accessToken` and `expiresAt` (epoch ms), JSON without a `claudeAiOauth` object (only `mcpOAuth`) decodes to nil, `isExpired` compares `expiresAt` to an injected `now`
- [x] T016a [P] [US1] Write `Tests/UsageCoreTests/SubscriptionSourceTests.swift` with a fake `CredentialReader` and a stubbed `URLProtocol`: reader returning nil yields `SubscriptionState.notSignedIn`; an expired credential yields `credentialsExpired` and no HTTP request is made; HTTP 200 yields `.ok` with the decoded status; a failure after a prior `.ok` yields `.stale(lastGoodAt, error)` keeping the last status; a success after `.stale` returns to `.ok` (SC-007); two accounts where one fails and one succeeds both appear in the output (FR-026); the diagnostic log text and `String(describing:)` of the output never contain the fake token value `SECRET-TOKEN-123` (FR-011a)

### Implementation for User Story 1

- [x] T017 [US1] Implement `Sources/UsageCore/Subscription/CredentialReader.swift`: `CredentialReader` protocol (`func read(configDirectory: String) throws -> OAuthCredential?`), `KeychainServiceName.for(configDirectory:)` using CryptoKit SHA-256 over the tilde-expanded absolute path without trailing slash, `OAuthCredential` (`accessToken`, `expiresAt`) decoding from the keychain JSON, `isExpired(now:)`
- [x] T018 [US1] Implement `Sources/UsageCore/Subscription/UsageEndpointClient.swift`: `fetch(token:) async throws -> SubscriptionStatus` against `https://api.anthropic.com/api/oauth/usage` with injectable `URLSession`, decode `five_hour` and `seven_day` (`utilization`, `resets_at` ISO 8601 with fractional seconds and offset), errors per T015
- [x] T019 [US1] Implement `Sources/UsageCore/Subscription/SubscriptionSource.swift` conforming to `UsageSource` (`name` = `"subscription"`): for each subscription account in `context.configuration` read credentials, produce `notSignedIn` or `credentialsExpired` without a request when applicable, otherwise fetch status, keep the last good status per account in the source and return `.stale` on failure (`.ok` again on the next success), return `.subscriptions(...)`, never include the token in any error message or log line
- [x] T020 [US1] Implement `Sources/LLMUsageMenuBar/KeychainCredentialReader.swift` using `SecItemCopyMatching` (generic password, service from T017, `kSecReturnData`), returning nil for `errSecItemNotFound`
- [x] T021 [US1] Implement `Sources/LLMUsageMenuBar/BarLabel.swift`: builds the bar text from snapshot entries marked `shownInBar`, subscription accounts in `accounts` order followed by groups in `groups` order, as `<label> <percent>%`; subscription percent is the higher of the two windows (the available one when a window is `null`, `--` when both are); entries at or above warning threshold (lowest configured threshold or 80) and at or above 100 get distinct styling (color via `Text` attributed string if rendered, else a `⚠` prefix fallback); "not signed in" and "credentials expired" render as `<label> --`; token-based accounts and Unassigned never appear (FR-002)
- [x] T022 [US1] Implement `Sources/LLMUsageMenuBar/DropdownView.swift` (first pass): one section per subscription account with 5-hour and 7-day rows (percent, local reset time via `Date.FormatStyle`, "unavailable" for a `null` window), state line for stale (last good time plus error text), not signed in, credentials expired ("run Claude Code to refresh"); footer with "Last refreshed" from `lastSuccessfulRefreshAt`, "Refresh now", "Open log", "Settings...", "Quit"
- [x] T023 [US1] Wire `AppModel` in `Sources/LLMUsageMenuBar/App.swift`: register `SubscriptionSource` with `KeychainCredentialReader`, call `ConfigStore.makeDefault` on first launch when the keychain item exists (FR-034), feed snapshots to `BarLabel` and `DropdownView`, implement "Refresh now", "Open log" (`NSWorkspace.shared.open(logFileURL)`), and "Quit"
- [x] T024 [US1] Run quickstart S1 via `make app && make run`; record keychain consent behavior and any `MenuBarExtra` label styling limitation in `specs/001-llm-usage-menubar/research.md` under "Open items"

**Checkpoint**: MVP delivers the subscription percent in the bar with details in the dropdown

---

## Phase 4: User Story 2 - Track token-based spend against a self-set weekly budget (Priority: P2)

**Goal**: Vertex sessions are found in local logs, priced, summed per budget group inside the aligned weekly window, and shown as spend, budget, percent, and reset time

**Independent Test**: With a configured group and Vertex session logs present, the dropdown shows `$x of $60 (n%)` matching a manual `jq` sum within 1 cent; unpriced models are flagged; unattributable sessions appear under Unassigned (quickstart S2)

### Tests for User Story 2

- [x] T025 [P] [US2] Create fixtures in `Tests/UsageCoreTests/Fixtures/`: `vertex-session.jsonl` (3 assistant records sharing one `message.id` with `req_vrtx_` ids, plus user and system records), `direct-session.jsonl` (`req_011` ids), `truncated.jsonl` (valid lines then a cut-off last line), `subagents/agent-x.jsonl` (sidechain record), `unknown-model.jsonl`, `custom-marker.jsonl` (record containing the string `"inference_geo":"eu"`), `malformed-fields.jsonl` (assistant records with a missing `timestamp`, an unparsable `timestamp`, a missing `message.usage`, and a `cache_creation` object without the 5m/1h split)
- [x] T026 [P] [US2] Write `Tests/UsageCoreTests/SessionRecordParserTests.swift`: parses the usage fields in `contracts/external-sources.md`, reads `cache_creation.ephemeral_5m/1h` split with fallback to `cache_creation_input_tokens` (and 0 when both are absent), skips non-assistant lines, skips undecodable and truncated lines, skips assistant records with a missing or unparsable `timestamp` or no `message.usage` (fixture `malformed-fields.jsonl`), dedupes by `message.id` keeping the last record
- [x] T027 [P] [US2] Write `Tests/UsageCoreTests/AttributionTests.swift`: `req_vrtx_` maps to the Vertex account, `req_011` maps to the subscription account, custom marker substring match, no match and multi-match yield Unassigned, directory tie-breaker between two subscription accounts with distinct config directories, no subscription account configured means a `req_011` record is Unassigned
- [x] T028 [P] [US2] Write `Tests/UsageCoreTests/PriceTableTests.swift`: built-in table loads from the bundle resource and contains every model in research.md R5, normalization strips `-20251001` and `@20251101`, prefix fallback matches only at a `-` boundary (`claude-opus-5-5-eu` matches `claude-opus-5-5`; `claude-opus-5-55` is unpriced) and prefers the longest key (`claude-opus-5-5-eu` is not priced as `claude-opus-5`), unknown model is unpriced, override replaces built-in, cost computation for one record matches a hand-calculated value to the cent including 5m and 1h cache writes
- [x] T029 [P] [US2] Write `Tests/UsageCoreTests/WindowResolverTests.swift`: aligned window is `[resets_at - 7d, resets_at)`, fallback uses most recent Monday 00:00 local and ends 7 days later, fallback rolls over at the boundary, aligned window moves when a new reset timestamp arrives, last fetched reset is kept while the provider is unreachable, a fallback window spanning a DST change still has a 7-day calendar span (`calendar` with `Europe/Berlin`)
- [x] T030 [P] [US2] Write `Tests/UsageCoreTests/LogIndexTests.swift` against a temp directory: discovers `projects/**/*.jsonl` including `subagents/`, an empty or missing `projects` directory yields no records and no error, an unreadable configured directory is reported in the result's `errors` while other directories are still scanned, skips files with mtime before window start, re-reads only appended bytes on a changed file, a file whose size shrank below `parsedOffset` is re-read from offset 0, prunes records before the window start, counts a symlinked tree only once
- [x] T031 [P] [US2] Write `Tests/UsageCoreTests/AggregatorTests.swift`: group total across two member accounts, percent rounding and uncapped above 100, `incomplete` flag with an unpriced model, Unassigned entry not counted in any group, records outside the window (before start or at or after end) excluded, `resetAt` equals `window.end`

### Implementation for User Story 2

- [x] T032 [P] [US2] Add `Sources/UsageCore/Resources/prices.json` with the twelve entries from research.md R5 (input, output, cacheWrite5m = 1.25x input, cacheWrite1h = 2x input, cacheRead as listed) and implement `Sources/UsageCore/Pricing/PriceTable.swift`: load built-in from `Bundle.module`, merge overrides, `canonicalModel(_:)` (strip `-YYYYMMDD` or `@YYYYMMDD`), `price(for:) -> PriceEntry?` (exact match, then longest key that is a prefix ending at a `-` boundary), `cost(of: UsageRecord) -> Decimal?`
- [x] T033 [P] [US2] Implement `Sources/UsageCore/Logs/SessionRecordParser.swift`: `parse(line:) -> RawUsageRecord?` with the field mapping in `contracts/external-sources.md` (nil for anything listed as skipped in T026), and `dedupe(_:)` by `message.id` (fallback `requestId`) keeping the last
- [x] T034 [P] [US2] Implement `Sources/UsageCore/Logs/Attribution.swift`: `DetectionRule` (`requestIdPrefix`, `rawContains`), built-in rules per `Provider` (`vertex` → `req_vrtx_`) and for subscription (`req_` not matching any token-based rule), `Attributor(configuration:)` with `accountId(for record: RawUsageRecord, rawLine: String, fileConfigDirectory: String) -> String?` implementing single match, directory tie-breaker (canonical path comparison), and Unassigned (nil)
- [x] T035 [US2] Implement `Sources/UsageCore/Windows/WindowResolver.swift`: `resolve(now:alignmentReset:fallback:calendar:) -> (DateInterval, WindowSource)`
- [x] T036 [US2] Implement `Sources/UsageCore/Logs/LogDirectoryScanner.swift`: enumerate `<dir>/projects` recursively for `.jsonl`, resolve symlinks to canonical paths, dedupe across configured directories (first configured directory wins), return `(files: [ScannedFile], errors: [String])` where a missing or unreadable directory adds an error and does not stop the scan
- [x] T037 [US2] Implement `Sources/UsageCore/Logs/LogIndex.swift`: in-memory `[String: FileIndexEntry]`, `update(files:window:parser:attributor:pricer:)` that skips unchanged files, reads appended bytes from `parsedOffset` up to the last newline, re-reads from 0 when the file size is below `parsedOffset`, parses and dedupes per file, attributes and prices records, prunes records with `timestamp < window.start` and drops entries with mtime before `window.start`; `reset()` clears the index (used by T040 when the window start moves earlier)
- [x] T038 [US2] Implement `Sources/UsageCore/Logs/SessionLogSource.swift` conforming to `UsageSource` (`name` = `"sessionLogs"`): builds the directory list (`~/.claude` plus `logDirectories`), runs the scanner and index with `context.window`, logs one diagnostic line per refresh with files seen, files re-read, records in window, and scanner errors (FR-036), returns `.records(...)`; throws only when no configured directory could be scanned at all
- [x] T039 [US2] Implement `Sources/UsageCore/Snapshot/Aggregator.swift` per Shared Interfaces: filter records to `window` (start inclusive, end exclusive), build `GroupEntry` per group (spend, budget, percent via `PercentFormatter`, incomplete, `resetAt = window.end`, members), `TokenAccountEntry` per token-based account, the Unassigned entry, with per-model totals (per-day trend added in US5)
- [x] T040 [US2] Extend `RefreshCoordinator` in `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`: at refresh start resolve the window from the alignment account's last known `seven_day.resets_at` (the designated `alignmentAccountId`, else the first subscription account; kept in the actor from the previous refresh) and put it in `RefreshContext`; after sources finish re-resolve with any newer reset, and if the final window starts earlier than the context window call `LogIndex.reset()` and run `SessionLogSource` once more with the final window before aggregating; then run `Aggregator` and fill `UsageSnapshot.groups`, `tokenAccounts`, `unassigned`, `window`, `windowSource`; when the session log source failed this refresh, reuse the previous snapshot's `groups`, `tokenAccounts`, and `unassigned` with `stale = true` (FR-007); add a case to `RefreshCoordinatorTests.swift` for the earlier-start re-run and the stale carry-over
- [x] T041 [US2] Extend `Sources/LLMUsageMenuBar/DropdownView.swift`: group sections showing `$spent of $budget (n%)`, "incomplete, unpriced: <models>" line when flagged, "stale since <lastSuccessfulRefreshAt>" line when `stale`, window end as reset time, and the Unassigned section with token totals
- [x] T042 [US2] Extend `Sources/LLMUsageMenuBar/BarLabel.swift` to include groups marked `shownInBar` with their percent and threshold styling; register `SessionLogSource` in `App.swift`
- [x] T043 [US2] Add `scripts/sum-vertex.sh` (jq over `req_vrtx_` records in a window with prices from `Sources/UsageCore/Resources/prices.json`) used by quickstart S2 to cross-check SC-003, and run S2

**Checkpoint**: Subscription and group percents both appear in the bar; spend matches the script within 1 cent

---

## Phase 5: User Story 3 - Configure accounts, groups, budgets, and display (Priority: P3)

**Goal**: A settings window edits everything in the config file with validation, and the app reloads hand-edited files safely

**Independent Test**: Add a second token-based account into the existing group, hide an entry from the bar, set the interval to 2 minutes, save; the bar updates and `config.json` contains the values. Invalid values are rejected with a message (quickstart S3)

### Tests for User Story 3

- `Tests/UsageCoreTests/ConfigStoreTests.swift` (T044) was moved to Phase 2 so it precedes `ConfigStore`.
- [x] T044a [P] [US3] Extend `Tests/UsageCoreTests/ConfigurationTests.swift` for T048: `removingAccount(id:)` on a group's last member removes the group too, on a non-last member keeps the group, and on a subscription account that is the `alignmentAccountId` clears `alignmentAccountId`

### Implementation for User Story 3

- [x] T048 [US3] Implement group lifecycle in `Sources/UsageCore/Config/Configuration.swift`: `removingAccount(id:) -> Configuration` deletes a group when its last member is removed and clears `alignmentAccountId` when it named the removed account; `ThresholdTracker` (US4) drops state for ids no longer present on the next refresh
- [x] T045 [US3] Implement `Sources/LLMUsageMenuBar/SettingsView.swift`: `TabView` container plus the General tab (refresh interval with 60 s minimum message, week fallback weekday and hour, alignment account picker over subscription accounts, start at login toggle, log directories list with add and remove) and the Prices tab (built-in rows read-only with override editor, add model); every edit is applied to a draft `Configuration` and saved through the closure provided by T046
- [x] T045a [US3] Implement `Sources/LLMUsageMenuBar/AccountSettingsView.swift`: the Accounts tab (list, add subscription or token-based, label with 1 to 3 character validation, display name, credential directory, provider, group picker that requires a choice or creates a new group with label and budget, custom marker, shown-in-bar and thresholds for subscription accounts, remove via `Configuration.removingAccount(id:)`) and the Groups tab (name, label, weekly budget, shown-in-bar, thresholds, members read-only); embed both tabs in `SettingsView.swift`
- [x] T046 [US3] Implement settings presentation in `Sources/LLMUsageMenuBar/App.swift`: "Settings..." opens a `Window` scene, activates the app (`NSApp.activate`), saves through `ConfigStore.save` showing `ConfigurationError.message` inline, restarts the refresh timer with the saved interval, and triggers a refresh after a successful save
- [x] T047 [US3] Implement start-at-login in `Sources/LLMUsageMenuBar/App.swift` via `SMAppService.mainApp.register()` / `unregister()` driven by `startAtLogin`, with the status read back on launch
- [x] T049 [US3] Surface `ConfigStore` errors in `Sources/LLMUsageMenuBar/DropdownView.swift` as a "Configuration error: ..." line from `UsageSnapshot.configError` while the last valid configuration stays active

**Checkpoint**: All configuration in the contract is editable from the UI and by hand

---

## Phase 6: User Story 4 - Get notified before hitting a limit (Priority: P4)

**Goal**: One macOS notification per crossed threshold per window, with launch baseline and window reset semantics

**Independent Test**: Set a threshold just above current usage, append a synthetic Vertex record, refresh: one notification; refresh again: none (quickstart S4)

### Tests for User Story 4

- [x] T050 [P] [US4] Write `Tests/UsageCoreTests/ThresholdTrackerTests.swift`: crossing from below to at-or-above fires once, staying above does not refire, first observation after launch is baseline only, a window end change resets state, a single jump over two thresholds yields two crossings (one per threshold, duplicate threshold values configured twice yield one), subscription five-hour and seven-day windows are tracked independently, a stale or not-signed-in subscription entry produces no crossing, removed entities are dropped

### Implementation for User Story 4

- [x] T051 [US4] Implement `Sources/UsageCore/Notifications/ThresholdTracker.swift`: `observe(snapshot:config:) -> [ThresholdCrossing]` with state keyed by `(entityId, windowKind)` per data-model.md; `entityName` is the account `displayName` or group `name`
- [x] T052 [US4] Implement `Sources/LLMUsageMenuBar/NotificationPresenter.swift`: request authorization once, send `UNNotificationRequest` per crossing with title `<entityName> reached <threshold>%` and body naming the window (`5-hour`, `7-day`, `weekly`) and current percent
- [x] T053 [US4] Hook `ThresholdTracker` into the snapshot stream in `Sources/LLMUsageMenuBar/App.swift` and log each sent notification through `DiagnosticLog`

**Checkpoint**: Notifications fire exactly once per threshold per window (SC-006)

---

## Phase 7: User Story 5 - Understand where the usage went (Priority: P5)

**Goal**: Expandable per-model and per-day breakdowns for groups, token-based accounts, Unassigned, and subscription accounts (tokens only)

**Independent Test**: With logs spanning three days and two models, the group details show two model rows summing to the total and one entry per day with zeros for idle days (quickstart S5)

### Tests for User Story 5

- [x] T054 [P] [US5] Extend `Tests/UsageCoreTests/AggregatorTests.swift`: per-model rows sum to the group total, per-day trend has one entry per local calendar day touched by the window (8 entries when the window starts mid-day) with zero-filled days, a window spanning a DST change still yields one entry per calendar day, subscription breakdown carries tokens and no cost

### Implementation for User Story 5

- [x] T055 [US5] Extend `Sources/UsageCore/Snapshot/Aggregator.swift` to produce `UsageBreakdown.perDay` (local calendar days from `calendar.startOfDay(for: window.start)` to the day containing `window.end - 1s`, zero-filled) and subscription account breakdowns from records attributed to them (cost nil)
- [x] T056 [US5] Implement `Sources/LLMUsageMenuBar/BreakdownView.swift`: disclosure group per entry with a model table (input, output, cache write, cache read, cost or "unpriced") and a compact per-day row of values; embed it in `DropdownView.swift` for groups, token accounts, Unassigned, and subscription accounts

**Checkpoint**: All five user stories independently functional

---

## Phase 8: Polish & Cross-Cutting Concerns

- [x] T057 [P] Write `README.md`: what the app shows, build and run via `make`, keychain consent note, config file location, price overrides, log location
- [x] T058 [P] Performance check for SC-004 and SC-008: time a full refresh over the real `~/.claude/projects` tree and an incremental refresh with `DiagnosticLog` timestamps (targets 10 s and 1 s), sample CPU and memory with `top -l` every 60 s for one hour with the app idle between refreshes (targets 1% average CPU, 100 MB RSS), record results in `specs/001-llm-usage-menubar/quickstart.md`
- [x] T059 Review `Sources/UsageCore/Subscription/`, `Sources/UsageCore/Diagnostics/`, and `Sources/LLMUsageMenuBar/NotificationPresenter.swift` to confirm no token or credential value can reach the log, snapshot, notification, or config (FR-011a); the automated check is the leak assertion in `SubscriptionSourceTests.swift` (T016a), extend it if the review finds a new path
- [x] T060 Run all quickstart scenarios S1 to S5 end to end from the bundle and fix anything found; while running S2 time the add-account-to-bar flow against SC-005 (under 2 minutes) and note the result in quickstart.md
- [x] T061 Code cleanup: remove placeholder code from T002, ensure `swift build` has no warnings, `swift test` green

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Depends on Phase 1; blocks all user stories
- **User Stories (Phases 3 to 7)**: All depend on Phase 2. US1 and US2 are independent of each other. US3 edits the config that US1 and US2 read but is testable with either. US4 depends on at least one of US1 or US2 producing percents. US5 extends US2's aggregator.
- **Polish (Phase 8)**: After the desired stories

### Within Each User Story

- Test tasks first; they must fail before the implementation task they cover
- `UsageCore` types before sources, sources before the coordinator wiring, coordinator before UI

### Parallel Opportunities

- Phase 1: T002 to T005 in parallel after T001
- Phase 2: T007, T008, T011, T012 in parallel; T009 after T008; T044 after T009; T010 after T044; T013 after T010 and T012; T014 after T013
- US1: T015, T016, T016a in parallel, then T017 to T019 sequentially, T020 to T022 in parallel after T019, T023 after T022
- US2: T025 to T031 in parallel; T032 to T034 in parallel after the tests; T035 to T040 sequential; T041 and T042 in parallel
- US3: T044a first; T048 before T045 and T045a; T045 and T045a in parallel; T046 after both

---

## Parallel Example: User Story 2

```bash
# Tests and fixtures together:
Task: "Create fixtures in Tests/UsageCoreTests/Fixtures/"
Task: "Write Tests/UsageCoreTests/SessionRecordParserTests.swift"
Task: "Write Tests/UsageCoreTests/AttributionTests.swift"
Task: "Write Tests/UsageCoreTests/PriceTableTests.swift"
Task: "Write Tests/UsageCoreTests/WindowResolverTests.swift"

# Independent core pieces together:
Task: "Implement Sources/UsageCore/Pricing/PriceTable.swift"
Task: "Implement Sources/UsageCore/Logs/SessionRecordParser.swift"
Task: "Implement Sources/UsageCore/Logs/Attribution.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 and Phase 2
2. Phase 3 (US1): subscription percent in the bar
3. Validate with quickstart S1, then continue

### Incremental Delivery

1. US1: subscription limits (MVP)
2. US2: Vertex spend against a budget
3. US3: settings window
4. US4: notifications
5. US5: breakdowns
6. Polish

---

## Notes

- Commit after each task or logical group
- Never log, persist, or display OAuth tokens (FR-011a)
- All logic goes in `UsageCore`; the executable only renders and integrates with macOS
