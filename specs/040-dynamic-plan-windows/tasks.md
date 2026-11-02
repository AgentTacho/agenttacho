# Tasks: Dynamic Claude Plan Windows

**Input**: Design documents from `specs/040-dynamic-plan-windows/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Required. Constitution II demands tests written before the implementation for all UsageCore and DemoMode logic: each test task lands before the task that makes it pass, and a test task's tests fail before its implementation task. `make test` compiles every target (UsageCore, DemoMode, AgentTacho, both test targets), so a test that calls a missing API stops the whole test target from compiling. Therefore a test task and its implementation task land as one pair (one commit), and **every implementation task leaves `make test` green**; never `swift build` or `xcodebuild` directly.

**Migration strategy**: Phase 1 adds the list model (`windows`) while the legacy accessors `fiveHour: LimitWindow?`, `sevenDay: LimitWindow?`, `modelLimits: [ModelLimit]` and the legacy initializer stay with their old types, now computed from `windows`; `ModelLimit` and `LimitWindow` stay their own structs. New code uses `window(_:)`, `planWindows`, `modelLimitWindows` and `defaultWindow` (distinct names, so old and new coexist). Later tasks move each call site to the new accessors. T031 removes the legacy accessors, the legacy initializer and `ModelLimit`. Shims are marked `// spec 040 migration shim, removed in T031`.

**Conventions**: Doc comments cite the requirement they implement (`spec 040 FR-004`). No em dash or en dash characters anywhere. Conventional Commits with an `Assisted-By: 🤖 Claude Code` trailer.

## Phase 1: Foundational (blocks every user story)

**Purpose**: the list model, identities and builder (research R2 to R5, data-model.md).

**Interfaces** (decided here; later tasks use these names):

```swift
// Sources/UsageCore/Pace/ObservationLog.swift
public struct ClaudeWindow: Hashable, Sendable {           // identity, spec 040 FR-004
    public let rawValue: String
    public init(rawValue: String)
    public static let fiveHour: ClaudeWindow                 // "fiveHour"
    public static let sevenDay: ClaudeWindow                 // "sevenDay"
    public static func model(_ name: String) -> ClaudeWindow // "model:<name>"
    public var modelName: String?   // the text after "model:" when it contains no ":"; nil otherwise (model:<name>:<kind>, limit:..., fiveHour, sevenDay)
}

// Sources/UsageCore/Subscription/ClaudeLimits.swift (new file; ClaudeLimit lives here)
public struct ClaudeLimit: Equatable, Sendable {
    public var identity: ClaudeWindow
    public var kind: String
    public var group: String?
    public var length: TimeInterval?          // nil: unknown group, no pace
    public var name: String                   // display name
    public var modelName: String?             // set for a model limit
    public var allowancePercentOfWeekly: Int?
    public var utilizationPercent: Double
    public var resetsAt: Date?
    public var isModelLimit: Bool { modelName != nil }
    public init(identity: ClaudeWindow, kind: String, group: String?, length: TimeInterval?, name: String, modelName: String?,
                allowancePercentOfWeekly: Int?, utilizationPercent: Double, resetsAt: Date?)
    // Public fixtures, usable from both test targets and DemoMode. Pinned values:
    // fiveHour: kind five_hour, group five_hour, name "5-hour", length 5 h
    // sevenDay: kind seven_day, group weekly, name "7-day", length 7 d
    // model:    kind weekly_scoped, group weekly, name = model name, length 7 d
    // Tests comparing a parsed `limits` window with a fixture compare identity, percent and reset only (kinds differ, e.g. weekly_all).
    public static func fiveHour(_ percent: Double, resetsAt: Date?) -> ClaudeLimit
    public static func sevenDay(_ percent: Double, resetsAt: Date?) -> ClaudeLimit
    public static func model(_ name: String, _ percent: Double, resetsAt: Date?, allowance: Int? = nil) -> ClaudeLimit
}
public struct ClaudeLimitEntry: Equatable, Sendable {      // one decoded `limits` entry
    public var kind: String?; public var group: String?
    public var percent: Double?; public var resetsAt: Date?; public var resetUnreadable: Bool
    public var modelName: String?; public var hasModelScope: Bool; public var isSurfaceOnly: Bool
    public var rawIndex: Int
    public init(kind: String?, group: String?, percent: Double?, resetsAt: Date?, resetUnreadable: Bool = false,
                modelName: String? = nil, hasModelScope: Bool = false, isSurfaceOnly: Bool = false, rawIndex: Int)
}
public struct ClaudeWindowReport: Equatable, Sendable {    // for the FR-012 log line
    public var usedFallback: Bool
    public var read: [String]      // "<kind>/<group>/<scope>" in response order; a missing kind or group is an empty field ("daily_all//none")
    public var skipped: [String]   // same format
    public var signature: Set<String> { Set(read + skipped.map { $0 + " skipped" }) }
    public init(usedFallback: Bool, read: [String], skipped: [String])
}
public enum ClaudeLimits {
    public static func build(entries: [ClaudeLimitEntry]?, allowances: [Int: Int],
                             fallbackFiveHour: (percent: Double, resetsAt: Date?)?,
                             fallbackSevenDay: (percent: Double, resetsAt: Date?)?) -> (windows: [ClaudeLimit], report: ClaudeWindowReport)
    public static func groupLength(_ group: String?) -> TimeInterval?      // FR-003
}

// Sources/UsageCore/Snapshot/UsageSnapshot.swift
public struct SubscriptionStatus {
    public var windows: [ClaudeLimit]           // FR-006 order
    public var windowReport: ClaudeWindowReport? // set by the endpoint client, nil for saved values
    public init(windows: [ClaudeLimit], windowReport: ClaudeWindowReport? = nil, subscriptionType: String? = nil, fetchedAt: Date)
    public func window(_ id: ClaudeWindow) -> ClaudeLimit?
    public var planWindows: [ClaudeLimit]; public var modelLimitWindows: [ClaudeLimit]
    public var defaultWindow: ClaudeLimit?      // FR-009
    // Legacy until T031, old types, computed from `windows`:
    // var fiveHour: LimitWindow?; var sevenDay: LimitWindow?; var modelLimits: [ModelLimit]
    // init(fiveHour:sevenDay:modelLimits:subscriptionType:fetchedAt:)
}

// Sources/UsageCore/Pace/Pace.swift
extension ClaudeLimit { func paceInputs(observedAt: Date) -> PaceInputs? }  // nil without length or reset
extension SubscriptionStatus { public func pace(of window: ClaudeLimit, now: Date) -> Pace? }

// Sources/UsageCore/Config/HeadlineChoice.swift
public enum HeadlineChoice { case claude(ClaudeWindow); case codexWindow(String) }

// Sources/UsageCore/Bar/HeadlineWindow.swift
public static func tag(claude window: ClaudeLimit) -> String
public static func choice(forClaude identity: ClaudeWindow, status: SubscriptionStatus?) -> HeadlineChoice? // nil for the default window
```

- [X] T001 Write failing tests for `ClaudeWindow` (raw values, `model(_:)`, `modelName` including nil for `model:Fable:daily_scoped` and `limit:x`, equality by raw value) in Tests/UsageCoreTests/ClaudeWindowTests.swift (own file, so it compiles before `ClaudeLimit` exists); lands together with T003
- [X] T002 Write failing tests in Tests/UsageCoreTests/ClaudeLimitsTests.swift for the `ClaudeLimit` fixtures (pinned values above) and the builder; lands together with T004: (a) the 2026-11-02 shape (`weekly_all`/`weekly` and `weekly_scoped`/`weekly`/Fable) gives `[sevenDay "7-day", model:Fable "Fable"]`, both 7-day length, allowance from `allowances[rawIndex]`; (b) groups `five_hour`, `session`, `5h` give `fiveHour` "5-hour" 5 h, ordered before 7-day; (c) unknown group `daily` (kind `daily_all`) gives `limit:daily_all` "daily", no length, after known plan windows and before model limits; (d) group `Rolling_Day` named "rolling day"; (e) two unscoped weekly kinds with `weekly_all` second: `weekly_all` is `sevenDay` "7-day", the other `limit:<kind>` named from its kind; (f) two unscoped 5-hour-group entries: the first is `fiveHour`, the second `limit:<kind>`; (g) two Fable limits (weekly group and `daily` group): `model:Fable` "Fable" and `model:Fable:<kind>` "Fable daily"; a second weekly Fable limit is named from its kind; (h) model limit and plan window with the same display name keep different identities; (i) surface-only scope skipped and reported; model scope with an empty or missing `display_name` skipped; (j) entry without kind and group skipped; without kind uses the group in `limit:<group>`; (k) duplicate identity keeps the first, the second reported as skipped; (l) equal lengths keep response order; (m) no readable unscoped entry: fallback windows (kinds `five_hour`, `seven_day`, groups `five_hour`, `weekly`) supply plan windows, model limits still from entries, `usedFallback` true; `entries` nil behaves the same; (n) a readable unscoped entry present: fallback ignored; (o) null reset kept as nil, also for model limits; unreadable reset skipped; (p) report `read` strings `weekly_all/weekly/none`, `weekly_scoped/weekly/model:Fable` in response order (spec FR-001 to FR-006, FR-012)
- [X] T003 Implement `ClaudeWindow` as the struct above in Sources/UsageCore/Pace/ObservationLog.swift (replacing the enum) and rewrite the enum switches in Sources/UsageCore/Bar/HeadlineWindow.swift (`tag(claude:)`, `choice(forClaude:)`) and Sources/UsageCore/Pace/BurnRate.swift (`burnInputs`) with `==` comparisons and `modelName`, behavior unchanged; T001 passes, `make test` green
- [X] T004 Create Sources/UsageCore/Subscription/ClaudeLimits.swift with `ClaudeLimit`, `ClaudeLimitEntry`, `ClaudeWindowReport` and `ClaudeLimits` per the interfaces (all with public initializers); T002 passes
- [X] T005 Write failing tests in Tests/UsageCoreTests/ClaudeLimitsTests.swift (lands with T006) for `SubscriptionStatus(windows:)`, `window(_:)`, `planWindows`, `modelLimitWindows`, `defaultWindow` (sevenDay; else longest with a length, first in FR-006 order among equal lengths; else first plan window; nil without plan windows) and `effective(now:)` (every window past its reset shows 0% with nil reset, model limits included)
- [X] T006 Change `SubscriptionStatus` in Sources/UsageCore/Snapshot/UsageSnapshot.swift to the stored `windows` and `windowReport` with the new accessors; keep the legacy initializer `init(fiveHour:sevenDay:modelLimits:subscriptionType:fetchedAt:)` (builds `windows` through the fixtures) and the legacy computed `fiveHour: LimitWindow?`, `sevenDay: LimitWindow?`, `modelLimits: [ModelLimit]` with their old types, so no other file changes; `ModelLimit` and `LimitWindow` stay as they are; `effective(now:)` zeroes every window past its reset (the legacy accessors follow); T005 passes, `make test` green with all existing tests unchanged

**Checkpoint**: `make test` green; the list model exists and every old call site still compiles through the shims.

## Phase 2: User Story 1, no dead 5-hour row (P1) 🎯 MVP

**Goal**: today's answer gives a "7-day" and a "Fable" row and nothing that reads "unavailable".

**Independent Test**: parse the 2026-11-02 answer shape and check the list; in the demo build the Claude section has no 5-hour row.

- [X] T007 [US1] Write failing tests in Tests/UsageCoreTests/UsageEndpointClientTests.swift: the contracts/usage-endpoint-limits.md example decodes to `[sevenDay 11%, model:Fable 15% allowance 50]` with `windowReport.usedFallback == false`; `severity` and `is_active` of any JSON type are tolerated (FR-013); a `seven_day` object with an unreadable `resets_at` or a missing `utilization` does not fail the answer when `limits` has an unscoped entry; the 2026-11-02 answer with the null codenamed top-level keys and `spend`/`extra_usage`/`seven_day_breakdown` objects decodes; resets 06:59:59.7 and 07:00:00.2 give equal `resetsAt` for `limits` entries and fallback windows (`normalizedReset`, spec 001 FR-029); fallback cases: no `limits` key with `five_hour` and `seven_day` gives `[fiveHour, sevenDay]` and `usedFallback`; `limits: []` the same; only a Fable entry gives `[sevenDay from top level, model:Fable]`; an unreadable `five_hour` with a good `seven_day` in fallback mode keeps the 7-day window and the answer; non-empty `limits` with an unscoped entry ignores a non-null `five_hour` (FR-001, FR-002, US4)
- [X] T008 [US1] Rewrite the body decoding in Sources/UsageCore/Subscription/UsageEndpointClient.swift: lenient `limits` entries into `ClaudeLimitEntry` (kind, group, percent, resets_at through `normalizedReset`, scope.model.display_name, scope.surface, rawIndex), lenient `five_hour`/`seven_day`, shares by raw index, then `ClaudeLimits.build`; set `windowReport`; the ticket read is unchanged; T007 passes
- [X] T009 [US1] Write failing tests in Tests/UsageCoreTests/ThresholdTrackerTests.swift: live keys come from the plan windows of the latest successful status (`WindowKind(rawValue: identity.rawValue, displayName: name)`), so an answer without a 5-hour window tracks only `sevenDay`; model limits get no keys; a window without a reset is skipped; with no successful status (stale, preliminary) the previous keys of the account stay; a `daily` window crossing a threshold notifies with "daily"; a window missing from a later successful status drops its key without a crossing; when it returns it starts from a new baseline (FR-008, US2 scenarios 3 and 5); migrate this file's status constructors to `SubscriptionStatus(windows:)`
- [X] T010 [US1] Implement T009 in Sources/UsageCore/Notifications/ThresholdTracker.swift (no fixed `[.fiveHour, .sevenDay]`; `WindowKind.fiveHour`/`.sevenDay` keep their raw values so saved state carries over)
- [X] T011 [US1] Move pace and burn rate to the list: write failing tests first in Tests/UsageCoreTests/PaceTests.swift, Tests/UsageCoreTests/PaceReadingTests.swift and Tests/UsageCoreTests/BurnRateTests.swift (a window without length has no pace and no pace key; a model limit in the weekly group keeps its weekly pace; a `fiveHour` window paces over 5 h); then replace `fiveHourPace`, `sevenDayPace`, `pace(of: ModelLimit)` with `pace(of:now:)` / `ClaudeLimit.paceInputs(observedAt:)` in Sources/UsageCore/Pace/Pace.swift, iterate `status.windows` in `paceKeys` (Sources/UsageCore/Pace/PaceReading.swift) and look windows up by identity in `burnInputs(for:)` (Sources/UsageCore/Pace/BurnRate.swift); update every caller in the same task: Sources/UsageCore/Bar/HeadlineWindow.swift, Sources/DemoMode/ScenarioCoverage.swift, Sources/AgentTacho/DropdownView.swift, Tests/UsageCoreTests/HeadlineWindowTests.swift (lines around 35 and 59) and Tests/DemoModeTests/DefaultScenarioTests.swift (around line 176); `rg -n "fiveHourPace|sevenDayPace|pace\(of: .*ModelLimit" Sources Tests` is empty afterwards (FR-007)
- [X] T012 [US1] Write failing tests for the log lines: in Tests/UsageCoreTests/SubscriptionSourceTests.swift the first successful fetch writes `[subscription] <id>: windows weekly_all/weekly/none, weekly_scoped/weekly/model:Fable (limits)`, an identical second fetch writes none (signatures compared as sets), a changed set writes again, fallback says `(fallback)`, skipped entries carry ` skipped`, no percent or reset in the line, and the source's summary reads `ok (7-day 11%, Fable 15%)` (today `ok (5h x, 7d y)`, SubscriptionSource.swift around line 293); in Tests/UsageCoreTests/RefreshCoordinatorTests.swift the coordinator summary reads `<id>=ok(7-day 11%, Fable 15%)` (today `ok(5h x, 7d y)`, RefreshCoordinator.swift around line 1119) (FR-012)
- [X] T013 [US1] Implement T012 in Sources/UsageCore/Subscription/SubscriptionSource.swift (per-account last signature in memory, read from `status.windowReport`) and Sources/UsageCore/Snapshot/RefreshCoordinator.swift
- [X] T014 [US1] Write failing tests in Tests/UsageCoreTests/SectionNoteTests.swift for the Claude section note with an ok state and no windows: "No limits reported" (edge case "no window at all"); implement in Sources/UsageCore/Dropdown/SectionNote.swift
- [X] T015 [US1] Change the Claude section in Sources/AgentTacho/DropdownView.swift to one `ForEach` over the effective `status.windows` (id: identity): plan windows use the window row, model limits the model limit row, pace from `status.pace(of:now:)` (none for nil length), headline marker and click by identity through the `HeadlineWindow.choice(forClaude:)` that exists at that point (T018 and T020 change its argument and update this file); a model limit with nil reset reads "not started" like the plan window row (FR-006)
- [X] T016 [P] [US1] Reword the threshold help text and the plan description in Sources/AgentTacho/AccountSettingsView.swift per research R12 (FR-016)

**Checkpoint**: with today's answer shape the dropdown shows "7-day" and "Fable" only; `make test` green.

## Phase 3: User Story 2, a window that comes back or is new (P1)

**Goal**: unknown and returning windows appear with rows, thresholds and headline; vanished ones disappear cleanly. (Thresholds for appearing and vanishing windows are covered by T009 and T010.)

**Independent Test**: unit tests with a `five_hour` group entry, a `daily` group entry, then an answer without them.

- [X] T017 [US2] Write failing tests in Tests/UsageCoreTests/HeadlineChoiceTests.swift: `HeadlineChoice.claude(ClaudeWindow)`; `stored` is the identity raw value; `parse` accepts `fiveHour`, `sevenDay`, `model:Fable`, `model:Fable:daily_scoped`, `limit:daily_all` for a Claude account and rejects `model:`, `limit:`, `window:...` there; Codex parsing unchanged (FR-015)
- [X] T018 [US2] Implement T017 in Sources/UsageCore/Config/HeadlineChoice.swift (`claudeWindow` returns the identity) and migrate every use of `claudeFiveHour`, `claudeSevenDay`, `claudeModel` in the same task, so `make test` stays green: Sources/UsageCore/Bar/HeadlineWindow.swift, Sources/UsageCore/Config/Configuration.swift (the sevenDay-clears rule becomes `.claude(.sevenDay)`), Sources/AgentTacho (dropdown click), and the tests in HeadlineWindowTests, ConfigurationTests, ThresholdTrackerTests, BarLayoutTests, ConfigStoreTests, BurnRateTests
- [X] T019 [US2] Write failing tests in Tests/UsageCoreTests/HeadlineWindowTests.swift: default resolution per FR-009 (sevenDay; else longest with length; else first plan window; none gives percent nil and no tag); a chosen identity present applies, absent falls back to the default with the stored choice untouched (FR-010), including `fiveHour` (replaces the old "5h --" test); tags "5h" for `fiveHour`, "7d" for `sevenDay`, otherwise the display name cut to 7 plus "…" over 8 characters; `limit:daily_all` gets tag "daily" and no pace; accessibility "<name> window" for plan windows, "<model> weekly limit" for `model:<name>`, "<name> limit" for further model limits (FR-011); the at-or-above-100% style when the headline or the default window is at 100% or more; `choice(forClaude:status:)` gives nil for the default window and the identity otherwise; migrate this file's constructors to `SubscriptionStatus(windows:)`
- [X] T020 [US2] Implement T019 in Sources/UsageCore/Bar/HeadlineWindow.swift (new `choice(forClaude:status:)` and `tag(claude: ClaudeLimit)`) and the bar entry in Sources/UsageCore/Bar/BarLayout.swift (and Sources/UsageCore/Bar/BarPresentation.swift for the accessibility text); move the at-or-above-100% input from `barPercent` (7-day) to `defaultWindow` (test: a lone 5-hour window at 100% sets the style); in the same task update every caller of the changed signatures: Sources/AgentTacho/DropdownView.swift and Tests/UsageCoreTests/BarLayoutTests.swift (around line 1154); add the contracts/dropdown-rows.md bar table cases to Tests/UsageCoreTests/BarLayoutTests.swift first

**Checkpoint**: unknown and returning windows behave per US2 in unit tests.

## Phase 4: User Story 3, existing settings keep working (P2)

**Goal**: old configuration and last-good files load unchanged; the last-good file stays readable by the previous version.

**Independent Test**: load old `headlineWindow` values and an old last-good file; write a new file and decode it with the legacy fields only.

- [X] T021 [P] [US3] Write tests in Tests/UsageCoreTests/ConfigurationTests.swift and Tests/UsageCoreTests/ConfigStoreTests.swift: `headlineWindow` `fiveHour`, `sevenDay`, `model:Fable` load without a problem and keep their meaning; `limit:daily_all` and `model:Fable:daily_scoped` load for a Claude account; a save writes the same values back (FR-015); fix Sources/UsageCore/Config/Configuration.swift if one fails
- [X] T022 [P] [US3] Write failing tests in Tests/UsageCoreTests/LastGoodStoreTests.swift: a version-1 file with only `fiveHour`/`sevenDay`/`modelLimits` loads as the equivalent list (5-hour group window, weekly window, weekly model limits) without a problem; a new file holds `windows` plus legacy `sevenDay` and `modelLimits` (and `fiveHour` when present) and `"version": 1`; decoding a new file with the legacy keys only (the previous version's view) gives the same 7-day and model values; a saved 5-hour value past its reset shows as 0% without reset in the effective status (FR-014, US3 scenario 4)
- [X] T023 [US3] Implement T022 in Sources/UsageCore/Snapshot/LastGoodStore.swift (`SavedClaudeLimit`, `windows` key, legacy keys written and read)

**Checkpoint**: an upgrade and a downgrade keep saved values.

## Phase 5: Demo, docs and spec amendments

(User Story 4, the older answer shape, is covered by T007 and T008.)

- [X] T024 Write failing tests (lands with T025) in Tests/DemoModeTests/ScenarioTests.swift and Tests/DemoModeTests/ScenarioPlayerTests.swift for the scenario `limits` list, and update the expectations in Tests/DemoModeTests/DefaultScenarioTests.swift that depend on the format (not yet on the new values), (`kind`, `group`, optional `model`, `used`, optional `resetsIn`), validation paths `claude.<id>.limits[<n>]`, and frame changes keyed by identity (`claude.<id>.limits.sevenDay`, `claude.<id>.limits.model:Fable`) (FR-020, research R11)
- [X] T025 Implement T024 in Sources/DemoMode/Scenario.swift and Sources/DemoMode/ScenarioPlayer.swift; build the status in Sources/DemoMode/DemoSources.swift through `ClaudeLimits.build`; convert Resources/demo/default.json and Resources/demo/variants.json to the `limits` format in the same task, keeping today's values (including the 5-hour windows as `five_hour` group entries) so the bundled scenarios load; update Tests/DemoModeTests/DemoSourcesTests.swift; `make test` green
- [X] T026 Together with T027 (one commit), change the values in Resources/demo/default.json (`acc-max`: `weekly_all` 70% and `weekly_scoped` Fable 50%, `headlineWindow` `model:Fable`; `acc-max-personal`: `weekly_all` 35%; no 5-hour windows; frames moved to identities) and Resources/demo/variants.json (a Claude account gains a `daily_all`/`daily` window); tune values so the coverage checks keep all three levels, both markers, the pace states, the 7-day attention row and a bar tag
- [X] T027 Update Tests/DemoModeTests/DefaultScenarioTests.swift first (the `"5h"` bar tag expectation around line 96 becomes `"Fable"`), then Sources/DemoMode/ScenarioCoverage.swift: iterate `status.windows`, add the check "a Claude account without a 5-hour window shows no 5-hour row" and the tag check for `model:Fable` (FR-020)
- [X] T028 Add a test that budget alignment with no `sevenDay` window behaves as today without a 7-day window, in Tests/UsageCoreTests/RefreshCoordinatorTests.swift; Sources/UsageCore/Snapshot/RefreshCoordinator.swift reads `sevenDay` through the accessor (FR-017)
- [X] T029 [P] Reword docs/usage.md, docs/accounts-and-budgets.md, docs/configuration.md (headlineWindow values from contracts/config-and-last-good.md) and README.md (feature list line 10, image alt text line 5; check that "Security and privacy" line 66 still describes the request correctly) per research R12 (FR-016)
- [X] T030 [P] Add amendment notes to specs/001-agenttacho/spec.md (FR-005), specs/025-minimal-dropdown/contracts/dropdown-ui.md (row list), specs/027-headline-window-switch/spec.md (FR-005, FR-006, FR-008, US3 scenario 4), specs/027-headline-window-switch/contracts/config-file.md, specs/027-headline-window-switch/contracts/bar-and-dropdown.md (`✳ 5h --` row) and specs/010-keep-last-good-values/contracts/last-good-file.md (`windows` key; kind and group strings allowed), each citing spec 040 (FR-019)

## Phase 6: Polish

- [X] T031 Remove the legacy accessors and initializer of T006 and the `ModelLimit` struct; move every remaining caller in Sources and both test targets to `SubscriptionStatus(windows:)`, the `ClaudeLimit` fixtures and the new accessors; done when `rg -n "SubscriptionStatus\(fiveHour|ModelLimit|\.fiveHour\?\.|status\.sevenDay|\.modelLimits\b" Sources Tests` returns only `ClaudeWindow.fiveHour`/`.sevenDay` identity uses and `make test` is green
- [X] T032 Search for leftovers: `rg -n "5-hour|fiveHour|five_hour|migration shim" Sources Tests docs README.md` and confirm every hit is the 5-hour group mapping, the identity, the fallback, Codex, or a test of those; `rg -n "\x{2014}|\x{2013}"` over changed files gives nothing
- [X] T033 Run `make test` and `make test-release`; both pass
- [X] T034 Screenshots, README image and website (FR-021, AGENTS.md steps 4 to 7): captured from the demo build with the maintainer's go on 2026-11-02 (all 14 files; the `same-provider` crop needed a Fable limit on the second Max account to stay within 4:3), reviewed in both appearances, README `docs/images/glance-*.webp` replaced, site copy unchanged (already generic), site PR https://github.com/AgentTacho/agenttacho.github.io/pull/27 open; merging it (a deploy) stays the maintainer's call before the next release

## Dependencies

- Phase 1 (T001 to T006) blocks all stories; T003 needs T001, T004 needs T002, T006 needs T004 and T005.
- US1: T008 needs T007; T010 needs T009; T011 needs T006; T013 needs T012 and T008; T015 needs T011 and T014.
- US2: T018 needs T017 and T015; T020 needs T019, T011 and T015.
- US3: T023 needs T022; T021 needs T018.
- Phase 5: T025 needs T024 and T004; T026 needs T025 and T018; T027 needs T026.
- T031 after all call sites moved; T033 last of the code tasks; T034 only with the maintainer.

## Parallel opportunities

- T016, T029 and T030 are independent of the core work.
- T021 and T022 touch different test files.

## Implementation strategy

MVP is Phase 1 plus US1: today's answer renders without a dead row. US2 and US3 make the change robust and compatible; Phase 5 completes the demo and the docs. The screenshot capture (T034) waits for the maintainer.
