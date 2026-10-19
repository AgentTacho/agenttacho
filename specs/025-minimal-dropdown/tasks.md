# Tasks: Minimal Dropdown

**Input**: Design documents from `specs/025-minimal-dropdown/`

**Prerequisites**: plan.md, spec.md (FR-001 to FR-035, FR-019a), research.md (R1 to R14), data-model.md, contracts/dropdown-ui.md, contracts/config-file.md, quickstart.md

**Tests**: Required. Constitution II asks for test-first core logic: every new `UsageCore` or `DemoMode` behavior gets its tests first, and they must fail before the implementation. Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) like the existing suites. Run Swift tests only with `make test`, script tests only with `make test-release`, build only with `make app` and `make app-demo`.

## Format: `[ID] [P?] [Story] Description`

## Conventions for every task

- Doc comments of new or changed code cite the spec requirements they implement (for example `spec 025 FR-017`).
- No em dash or en dash characters anywhere (code, comments, JSON, docs, commit messages).
- `Sources/AgentTacho` only renders values from `UsageCore`; no wording, threshold or date logic in views.
- Fixed test inputs: `Calendar(identifier: .gregorian)` with `timeZone = TimeZone(identifier: "UTC")!`, `Locale(identifier: "en_US")`, and an explicit reference time.
- Commit at each checkpoint with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.
- Do NOT run `scripts/screenshots/capture.sh`, do NOT push, and do NOT touch the site repository: those steps need the maintainer's go (see "Maintainer-gated steps" at the end).

## Interfaces

Names shared between tasks (all `public` in `UsageCore` unless noted):

```swift
// T003, Sources/UsageCore/Config/TimeFormat.swift
enum TimeFormat: String, Codable, CaseIterable, Sendable { case relative, absolute }
// T003, Sources/UsageCore/Dropdown/TimeText.swift
struct TimeText: Sendable {
    init(format: TimeFormat, now: Date, calendar: Calendar, locale: Locale)
    func reset(_ date: Date) -> String          // "resets in 2h 26m" / "resets 17:20"
    func runOut(_ date: Date) -> String         // "in 2d 13h" / "Wed 05:30" (text after "runs out ")
    func resetTooltip(_ date: Date) -> String   // the other form
    func runOutTooltip(_ date: Date) -> String  // the other form
    static func relative(from now: Date, to date: Date) -> String   // "in 4d 16h", "in <1m", "now"
}
// T005, Sources/UsageCore/Pace/PaceReading.swift
struct PaceReading: Equatable, Sendable { let pace: Pace; let burn: BurnRate?; var callsForAttention: Bool }
extension UsageSnapshot { func paceReading(for key: BurnWindowKey) -> PaceReading?
                          var paceKeys: [BurnWindowKey] }   // today's internal burnWindowKeys, made public and renamed
// T007, Sources/UsageCore/Dropdown/RowBar.swift
enum RowBarTone: Equatable, Sendable { case neutral, attention, overLimit }
struct PaceNote: Equatable, Sendable { let pace: Pace; let fastRunOut: Date?
    func text(times: TimeText) -> String; func tooltip(times: TimeText) -> String }
struct RowBar: Equatable, Sendable { let fill: Double; let tick: Double?; let tone: RowBarTone; let note: PaceNote?
    static func make(usedPercent: Double, limitReached: Bool, reading: PaceReading?) -> RowBar
    let summaryPace: Pace?; let summaryFastRunOut: Date?
    func accessibilitySummary(times: TimeText) -> String? }   // pace summary or nil without a pace
extension GroupEntry { var usedPercent: Double }   // unrounded spend share, spentUSD / budgetUSD * 100; 0 for a budget of 0
// T009, Sources/UsageCore/Dropdown/SectionNote.swift
enum NoteStyle: Equatable, Sendable { case neutral, warning, alert }
struct SectionNote: Equatable, Sendable { let text: String; let style: NoteStyle }
struct NoteDates: Sendable { init(locale: Locale, timeZone: TimeZone)
    func dateTime(_ date: Date) -> String; func time(_ date: Date) -> String }   // as today's .abbreviated/.shortened and .omitted/.shortened
extension SectionNote {
    static func claude(state: SubscriptionState?, credentialDirectory: String, isPreliminary: Bool,
                       nextRetryAt: Date?, endpointBlockedUntil: Date?, dates: NoteDates) -> [SectionNote]   // empty for .ok
    static func codex(_ limits: CodexLimitsEntry, dates: NoteDates) -> SectionNote?                         // nil for .live
    static func budgetIncomplete(unpricedModels: [String]) -> SectionNote                                    // warning
    static func budgetStale(since: Date?, dates: NoteDates) -> SectionNote                                   // "stale since <dateTime>" or "stale since launch"
    static let emptyGroup: SectionNote                                                                        // neutral
    static let staleMarker: SectionNote                                                                       // "stale", warning
    static func noData(isPreliminary: Bool) -> SectionNote                                                   // "Refreshing…" or "No data", neutral
}
// T018, Sources/UsageCore/Dropdown/FooterText.swift
enum FooterText { static func lastRefreshed(at: Date?, hasSnapshot: Bool, isPreliminary: Bool, now: Date, calendar: Calendar, locale: Locale) -> String
                  static func paceTooltip(_ status: RefreshPaceStatus?, now: Date, calendar: Calendar) -> String? }
enum DetailsTotal { static func weekly(tokens: Int, locale: Locale) -> String }   // "This week: 45.1M tokens"
// T023, Sources/UsageCore/Config/Configuration.swift and TimeFormatResolution.swift
extension Account { var timeFormat: TimeFormat }; extension BudgetGroup { var timeFormat: TimeFormat }   // stored properties
extension Configuration { func timeFormat(for entry: ArrangedEntry) -> TimeFormat }
// T031, Sources/DemoMode/ScenarioCoverage.swift
// CoverageReport gains: attentionRows: [BurnWindowKey], singleMemberGroups: [String], absoluteTimeOwners: [String]
```

---

## Phase 1: Setup

- [X] T001 Run `make test` and `make test-release` once in the worktree to record the baseline; both must pass before any change (stop and report if not).

---

## Phase 2: Foundational (core types every story needs)

**Purpose**: the tested core values the views render. Blocks all user stories.

- [X] T002 [P] Write failing tests in `Tests/UsageCoreTests/TimeTextTests.swift` for every case of spec FR-017 to FR-019 and SC-006: relative "in <1m" (30 s), "in 45m", "in 2h 26m", "in 3h" (whole hours), "in 4d 16h", "in 4d" (whole days), rounding down (2h 26m 59s reads "in 2h 26m"), "now" (equal and past); absolute same day "17:20", next calendar day "Mon 09:00", six calendar days ahead weekday and time, seven calendar days ahead "Sun, Oct 25, 9:00 AM"-style long form (assert with the same `Date.FormatStyle` the implementation uses for the en_US locale, not a hard-coded string), an earlier day (past) long form, reset at local midnight tomorrow weekday-day-month without time, run-out at local midnight keeps its time (spec 011 FR-009); `reset(_:)` prefixes "resets "; tooltips return the other form; the day boundary is taken from the given calendar's time zone, not the process time zone; with `TimeZone(identifier: "Europe/Berlin")` and a reference time on Thu 22 Oct 2026, a time on Sun 25 Oct 2026 (the clock change) reads the weekday and time form and a time on Thu 29 Oct 2026 the long form, so day counting by calendar days (not seconds / 86400) is pinned.
- [X] T003 Implement `TimeFormat` in `Sources/UsageCore/Config/TimeFormat.swift` and `TimeText` in `Sources/UsageCore/Dropdown/TimeText.swift` (research R3) until T002 passes; formats use `Date.FormatStyle(date:time:locale:calendar:timeZone:)` or `.dateTime` components with explicit `locale`, `calendar` and `timeZone`.
- [X] T004 [P] Write failing tests in `Tests/UsageCoreTests/PaceReadingTests.swift`: for a Claude 5-hour, 7-day and model key, a Codex window key, a group and an own-budget key, `paceReading(for:)` returns the same `Pace` as the existing per-entry accessors and the same `BurnRate` as `burnRate(for:)`; nil for a key without a pace (no reset time, at 100%, reached Codex limit, empty group, unknown key); `callsForAttention` is true with a run-out, true with a fast burn on pace, false otherwise. Reuse fixtures from `BurnRateTests.swift`.
- [X] T005 Implement `PaceReading` and `UsageSnapshot.paceReading(for:)` in `Sources/UsageCore/Pace/PaceReading.swift` from `burnInputs(for:)` (research R1); make `burnRate(for:)` return `paceReading(for:)?.burn` so both share one path; make `burnWindowKeys` public as `paceKeys` (update its internal callers); T004 and `BurnRateTests` pass.
- [X] T006 [P] Write failing tests in `Tests/UsageCoreTests/RowBarTests.swift` for spec FR-002 to FR-004, FR-007, FR-009: fill clamps to 0...1 (38% gives 0.38, 532% gives 1, negative gives 0); tick equals `pace.expectedPercent / 100` and is nil without a reading; tone `.overLimit` at rounded 100 (99.6 rounds up) or `limitReached`, `.attention` with a run-out or a fast burn, `.neutral` otherwise; `note` non-nil exactly for `.attention`; `note.text(times:)` with a relative `TimeText` reads "20% ahead · runs out in 1d 12h" and with a fast burn "20% ahead · burning fast · runs out in 3h 10m"; `note.tooltip` uses the other form; `accessibilitySummary` returns "on pace" or "N% behind" without a note and nil without a pace; `GroupEntry.usedPercent` is the unrounded spend share and 0 for a budget of 0; a NaN or infinite used percent gives a fill of 0 and no tone other than `.neutral`.
- [X] T007 Implement `RowBarTone`, `PaceNote`, `RowBar` in `Sources/UsageCore/Dropdown/RowBar.swift` and `GroupEntry.usedPercent` in `Sources/UsageCore/Pace/Pace.swift` (reuse it in `GroupEntry.paceInputs(now:)`) per research R2 until T006 passes.
- [X] T008 [P] Write failing tests in `Tests/UsageCoreTests/SectionNoteTests.swift` pinning today's texts and the styles of spec FR-029 (copy the strings from `Sources/AgentTacho/DropdownView.swift`): Claude states `.stale` with and without last good time (warning, with "Retrying at" or "Rate limited until" lines), `.notSignedIn` (neutral, names the credential directory), `.credentialsExpired` (warning), `.retrying` (neutral, `GraceNote.reason(claudeError:)`), `.signInRejected` (alert, `SignInRejectedNote.text`, last good line), nil state ("Refreshing…" when preliminary, else "No data", neutral); Codex `.newerSnapshot` and `.localOnly` (neutral), `.stale` (warning, alert when `signInRejected`), `.unavailable` (neutral, alert when rejected), `.retrying` (neutral), `.live` (none); budget incomplete prices (warning, "incomplete, unpriced: a, b"), budget "stale since <date time>" and "stale since launch" (warning), empty group "No accounts in this group yet" (neutral), plain "stale" marker (warning).
- [X] T009 Implement `NoteStyle`, `SectionNote` with its builders and `NoteDates` in `Sources/UsageCore/Dropdown/SectionNote.swift` (research R5) until T008 passes.

**Checkpoint**: `make test` passes; commit `feat(core): time text, pace reading, row bar and section notes for spec 025`.

---

## Phase 3: User Story 1 - Read every limit at a glance (Priority: P1) 🎯 MVP

**Goal**: window rows in layout B with bars, tick and on-demand orange note; no pace tooltip.

**Independent Test**: `make app-demo`, open the default scenario: Claude's 7-day row shows an orange note and a fill ahead of the tick, the 5-hour row has no note, nothing needs hovering (quickstart, step 1 and 2).

- [X] T010 [US1] Add `RowBarView` in `Sources/AgentTacho/RowBarView.swift` (research R7): full-width 4 pt track `Color.secondary.opacity(0.25)`, fill in the tone color (neutral `Color.secondary`, attention `.orange`, over limit `.red`), optional 1.5 x 10 pt tick in `Color.primary` at `tick`, fixed height 10 pt, no `.help`, `accessibilityHidden(true)` (the row carries the label).
- [X] T011 [US1] In `Sources/AgentTacho/DropdownView.swift` delete `PaceMeter` and rewrite `WindowRow`, `ModelLimitRow` and `CodexWindowRow` as layout B (contracts/dropdown-ui.md "Window row"): line 1 name (60 pt), percent (50 pt, red at rounded 100 or more or limit reached in every row, FR-007), reset text from `times.reset(_:)` with `.help(times.resetTooltip(_:))`, or "not started", or no reset text after a reset, or "unavailable" without a bar (FR-008); line 2 `RowBarView`; line 3 the note in orange `.caption` with `.help(note.tooltip(times:))` only when `bar.note != nil`; Codex "Limit reached" stays. Rows take a `RowBar` built from `RowBar.make(usedPercent:limitReached:reading: snapshot?.paceReading(for: key))` and a `TimeText`; `ModelLimitRow`'s `.help` covers only the name (FR-019a). Each row is one accessibility element (`.accessibilityElement(children: .ignore)`) labeled "<name>, <percent>, <reset text>, <summary>" (FR-006). Remove `Pace.meterOffset`, `Pace.meterScalePoints` and their tests in `Tests/UsageCoreTests/PaceTests.swift`, and reword doc comments that mention the pace meter (`Pace.summary`, `CoverageReport.paceStates`) to the bar and note.
- [X] T012 [US1] In `SubscriptionSection` and `CodexPlanSection` (`Sources/AgentTacho/DropdownView.swift`) build each row's `RowBar` from `paceReading(for: .claude(id, .fiveHour|.sevenDay|.model(name)))` and `.codex(id, window.name)` only, removing the separate `fiveHourPace(now:)`, `pace(of:now:)` and `burnRate(for:)` calls (FR-030); give Claude's 7-day row the identifier `agenttacho.paceRow` (replaces `agenttacho.paceMeter`); keep `agenttacho.claudePlan`.
- [X] T013 [US1] Render section notes from `SectionNote` in `SubscriptionSection.stateLine` and `CodexPlanSection.stateLine` (`Sources/AgentTacho/DropdownView.swift`): one `Text` per note in `.caption`, color by `NoteStyle` (neutral `.secondary`, warning `.orange`, alert `.red`), wrapping as today (FR-015, FR-029).
- [X] T014 [US1] Wrap the dropdown `content` in `TimelineView(.periodic(from: .now, by: 30))` in `Sources/AgentTacho/DropdownView.swift` and build every section's `TimeText(format: .relative, now: context.date, calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)` (the per-section format comes in T026) (FR-020, research R8); remove `UsageFormat.resetText` and `UsageFormat.runOutText` once unused.

**Checkpoint**: `make test` and `make app` pass; commit `feat(dropdown): window rows with bars and on-demand pace notes`.

---

## Phase 4: User Story 2 - Budgets read the same way (Priority: P1)

**Goal**: budgets with amount line, bar, tick and note; single-member groups without member line.

**Independent Test**: default scenario: "Company budget" shows bar and two member lines; `variants` scenario (T032): the one-member group shows no member line.

- [X] T015 [US2] Rewrite `BudgetSection` in `Sources/AgentTacho/DropdownView.swift` (contracts/dropdown-ui.md "Budget section"): header unchanged (icon, name, bold percent); amount line "<spent> of <budget>/<period>" with `times.reset(entry.resetAt)` right-aligned and its tooltip; `RowBarView` from `RowBar.make(usedPercent: entry.usedPercent, limitReached: false, reading: snapshot?.paceReading(for: isGroup ? .group(ownerId) : .accountBudget(ownerId)))`; the note as in T011; the whole amount line and bar one accessibility element labeled "<name>, <spent> of <budget>/<period>, <reset text>, <summary>" (FR-006); `agenttacho.budgetRow` still covers header, amount line and bar of the shot budget.
- [X] T016 [US2] In `BudgetSection` show member lines only when `members.count >= 2` (FR-010); render the empty-group note, the incomplete-prices note and the "stale since" note from `SectionNote` (T009).

**Checkpoint**: `make test` and `make app` pass; commit `feat(dropdown): budgets with bars, no member line for a single member`.

---

## Phase 5: User Story 3 - A footer that stays put (Priority: P1)

**Goal**: errors, update line, "Last refreshed" with pace tooltip, icon row; no gear menu.

**Independent Test**: open the dropdown in the default scenario: three icons with tooltips, ⌘, opens Settings, "Last refreshed" is the last text line (quickstart step 5).

- [X] T017 [P] [US3] Write failing tests in `Tests/UsageCoreTests/FooterTextTests.swift`: "Last refreshed 16:54" for today, the date and time for an earlier day (assert with the implementation's format style), "Refreshing…" without snapshot or while preliminary without a last refresh time, "Last refreshed …" whenever a last refresh time exists (also while preliminary), "No successful refresh yet" otherwise; `paceTooltip` returns `RefreshPaceStatus.text(now:calendar:)` for a slowed status and nil for nil; `DetailsTotal.weekly(tokens: 45_100_000, locale: en_US)` is "This week: 45.1M tokens", 0 tokens "This week: 0 tokens".
- [X] T018 [US3] Implement `FooterText` and `DetailsTotal` in `Sources/UsageCore/Dropdown/FooterText.swift` until T017 passes.
- [X] T019 [US3] Rewrite `footer` in `Sources/AgentTacho/DropdownView.swift` (contracts/dropdown-ui.md "Footer", FR-023 to FR-028): order source errors (red), `UpdateLine` when `model.updater.display.lineState` is non-nil, the "Last refreshed" `HStack` (text from `FooterText.lastRefreshed`, "stale" marker, `.help` and `.accessibilityValue` from `FooterText.paceTooltip`), then the icon row: borderless buttons `arrow.clockwise` (left, `model.refreshNow()`), `gearshape` (`showSettings()`, `.keyboardShortcut(",")`) and `power` (`NSApplication.shared.terminate(nil)`, `.keyboardShortcut("q")`) on the right, each with `.help` and `.accessibilityLabel` ("Refresh now", "Settings…", "Quit AgentTacho") and identifiers `agenttacho.refreshButton`, `agenttacho.settingsButton`, `agenttacho.quitButton`. Delete `appMenu`, the hidden shortcut buttons, the separate pace line and the dropdown's `checkNow(from: .dropdown)` call; keep `dismissTransient()` on close.
- [X] T020 [US3] In `scripts/screenshots/capture.sh` open Settings with `"$UIHELPER" press "$pid" agenttacho.settingsButton` instead of the `agenttacho.appMenu` menu and its "Settings…" item (research R12); update `scripts/release/tests/test_screenshots.sh` stubs for the new step; `make test-release` passes.
- [X] T021 [US3] Add an idea inbox entry `remove-dropdown-check-origin` to `brainstorm/idea-inbox.md` (source: spec 025, summary: `CheckOrigin.dropdown` and `showsResultOnLine` are unused since the dropdown lost its check; removing them is a spec 013 change).

**Checkpoint**: `make test`, `make test-release` and `make app` pass; commit `feat(dropdown): fixed footer with icon row, pace line as tooltip`.

---

## Phase 6: User Story 4 - Choose how times read (Priority: P2)

**Goal**: `timeFormat` per account and group, Settings picker, sections follow it.

**Independent Test**: set the Claude account to Absolute in Settings, apply: only its section reads absolute; relaunch keeps it; `config.json` has `"timeFormat": "absolute"` (quickstart, Settings).

- [X] T022 [P] [US4] Write failing tests in `Tests/UsageCoreTests/ConfigurationTests.swift` per contracts/config-file.md: decode absent, `"relative"`, `"absolute"`, unknown string (load note "timeFormat \"x\" is not known, using relative"), `null` and a number (load note "timeFormat is not readable, using relative") for a subscription, a Codex, a token-based (group and own budget) account and a group; the rest of the file loads; encode always writes the key; round trip; `Configuration.timeFormat(for:)` returns the account's or group's value; a token-based account in a group keeps its stored value.
- [X] T023 [US4] Add `timeFormat` to `Account` and `BudgetGroup` in `Sources/UsageCore/Config/Configuration.swift` (stored property, init parameter with default `.relative`, `CodingKeys.timeFormat`, decoding through a `decodeTimeFormat` helper modeled on `decodeLevelColor` with `ConfigurationLoadNotes`, always encoded) and `Configuration.timeFormat(for:)` in `Sources/UsageCore/Config/TimeFormatResolution.swift` until T022 passes.
- [X] T024 [US4] Add a segmented `Picker("Times", selection:)` with "Relative" and "Absolute" to `Sources/AgentTacho/AccountSettingsView.swift` (FR-021, clarification): in the Claude "Subscription" section, the "Codex subscription" section and the own-budget "Budget" section of the account detail, and in `GroupSettingsView`'s group detail; bound to the Settings draft; not shown for a token-based account in a group.
- [X] T025 [US4] Read `Sources/AgentTacho/SettingsView.swift` and confirm that the automatic apply after the pause and the ⌘Z undo work on the whole `Configuration` draft, so `timeFormat` needs no extra code; if any field-wise comparison, copy or undo step exists, add `timeFormat` to it. Record the ⌘Z check ("Times" back to the previous value) in quickstart.md's Settings step (already listed).
- [X] T026 [US4] In `Sources/AgentTacho/DropdownView.swift` build each section's `TimeText` with `configuration.timeFormat(for: arranged)` instead of `.relative` (FR-016); tooltips already show the other form (FR-019).

**Checkpoint**: `make test` and `make app` pass; commit `feat(settings): per account and group time format`.

---

## Phase 7: User Story 5 - Lighter Codex section (Priority: P2)

**Goal**: Codex section without plan and token lines; token total in Details for Claude and Codex.

**Independent Test**: default scenario: the Codex section has no plan or token line; its name has no tooltip; expanded Details of Claude and Codex start with "This week: …".

- [X] T027 [US5] In `CodexPlanSection` (`Sources/AgentTacho/DropdownView.swift`) remove the "ChatGPT <plan> plan" line and the "Tokens this week" line (the header name has no tooltip, FR-013) and remove the then unused `CodexLimitsEntry.planDisplayName` with its test (FR-014); render the plain "stale" marker from `SectionNote`.
- [X] T028 [US5] Add `totalLine: String? = nil` to `BreakdownView` in `Sources/AgentTacho/BreakdownView.swift`, shown as the first line of the expanded content above the view picker in `.caption`; pass `DetailsTotal.weekly(tokens: breakdown.totalTokens, locale: .autoupdatingCurrent)` from `SubscriptionSection` and `CodexPlanSection`, nil from budgets and Unassigned (FR-014).

**Checkpoint**: `make test` and `make app` pass; commit `feat(dropdown): lighter Codex section, token total in Details`.

---

## Phase 8: User Story 6 - Clear separation of sections (Priority: P3)

**Goal**: dividers between sections.

**Independent Test**: default scenario shows a divider between each pair of sections and one before the footer.

- [X] T029 [US6] In `content` of `Sources/AgentTacho/DropdownView.swift` emit a `Divider()` before every arranged section except the first and before `UnassignedSection` when other sections exist; keep the one divider before the footer (FR-011); render the Unassigned "stale" marker from `SectionNote`.

**Checkpoint**: `make app` passes; commit `feat(dropdown): dividers between sections`.

---

## Phase 9: Demo scenarios and capture (constitution V, FR-035)

- [X] T030 [P] Write failing tests in `Tests/DemoModeTests/DefaultScenarioTests.swift`: the default report has `.claude("acc-max", .sevenDay)` in `attentionRows` (the `pace` shot row), a group with two or more members, and empty `absoluteTimeOwners`; a new test for the `variants` scenario expects `absoluteTimeOwners` to contain "Claude Max" and `singleMemberGroups` to be non-empty; the existing "every JSON file in Resources/demo loads" check covers `variants.json`.
- [X] T031 Extend `CoverageReport` and `ScenarioCoverage.evaluate` in `Sources/DemoMode/ScenarioCoverage.swift` with `attentionRows` (the keys of `snapshot.paceKeys` whose `snapshot.paceReading(for:)?.callsForAttention` is true), `singleMemberGroups` and `absoluteTimeOwners` (research R11).
- [X] T032 Add `Resources/demo/variants.json`: the default story's Claude Max account with `"timeFormat": "absolute"` and its windows, plus a group with exactly one token-based member and usage for it; no frames needed beyond what the scenario format requires; T030 passes. `Resources/demo/default.json` keeps no `timeFormat` keys.
- [X] T033 Change the `pace` capture step in `scripts/screenshots/capture.sh` to crop the frame of `agenttacho.paceRow` from the dropdown capture (like `budget`), removing the hover, tooltip wait and composite steps that only served the old step; update the spec 024 comment there and `scripts/release/tests/test_screenshots.sh`; `make test-release` passes.

**Checkpoint**: `make test`, `make test-release` and `make app-demo` pass; commit `feat(demo): coverage for pace notes and a variants scenario`.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [X] T034 [P] Update `README.md` (research R14, FR-034): hero image alt text describing the new layout (its values are finalized when the image is replaced in the maintainer-gated steps), the Updates paragraph and the "Check for Updates…" sentence (only Settings > About), the configuration paragraph (the Settings icon in the dropdown, or ⌘,), the About bullet (no gear menu), the subscription and Codex paragraphs (bars, orange note, plan type on hover, token total in Details), and `timeFormat` in the configuration reference for accounts and groups.
- [X] T035 [P] Amend earlier specs in place, citing spec 025 (research R13, FR-033): `specs/004-icon-labels-standalone-budgets/spec.md` FR-018a, `specs/007-codex-plan-limits/spec.md` FR-011 and FR-013, `specs/011-pace-forecast/spec.md` FR-008 to FR-010, `specs/013-auto-update/spec.md` FR-003 and FR-009 and its `contracts/update-ui.md` dropdown section, `specs/016-adaptive-refresh/spec.md` FR-016, `specs/019-pace-line-names-plan/spec.md` (line placement), `specs/017-burn-rate-escalation/spec.md` FR-012, `specs/020-about-tab-update-layout/spec.md` FR-010, `specs/024-demo-mode-screenshots/spec.md` FR-014 and FR-019 (stem table: `plan-limits` with bars, `pace` a row with its bar and orange note).
- [X] T036 Search the repository for leftovers: `rg -n "paceMeter|PaceMeter|meterOffset|meterScalePoints|appMenu|Tokens this week|resetText\(|runOutText\(" Sources scripts Tests` and `rg -n -i "pace meter" Sources` return nothing relevant; `rg -n "[\x{2013}\x{2014}]"` over changed files returns nothing.
- [X] T037 Run `make test`, `make test-release`, `make app` and `make app-demo`; all pass. Walk through `quickstart.md` "Demo build by hand" with both scenarios if a display session is available, otherwise record it for the walkthrough. (Recorded for the walkthrough: the automated pipeline ran no interactive demo session.)

---

## Maintainer-gated steps (not part of implement; constitution V and AGENTS.md steps 4 to 8)

These run only after the maintainer says go, before the pull request merges:

1. Capture: `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho`.
2. Review the changed stems (`plan-limits`, `pace`, `budget`, `details`, `harnesses`, `groups`, `dropdown`) in light and dark.
3. Replace `docs/images/agenttacho-dropdown.png` from `dropdown-light.webp` and update the README alt text with the shown values.
4. Site copy in `src/data/features.ts` (the `pace` card: tick on the bar, orange line when a limit will run out; no gear menu wording), `npm run check`, `npm run build`, `npm test`.
5. Open the site pull request and link it from the app pull request.

---

## Dependencies & Execution Order

- Phase 1 then Phase 2 (T002 to T009) block every story.
- US1 (T010 to T014) before US2 (T015, T016 reuse `RowBarView` and the note rendering), US4 (T026 replaces T014's fixed format) and US5 (T027, T028 edit the same sections).
- US3 (T017 to T021) after T014, because the footer uses the `TimelineView` date for "Last refreshed".
- US6 (T029) after US1 (same `content` view).
- Phase 9 after US1, US2, US3 and US4 (identifiers, footer button, `timeFormat`).
- Phase 10 last.

## Parallel Opportunities

- T002, T004, T006, T008 (four test files) in parallel; then T003, T005, T007, T009 in parallel (different files).
- T017 and T022 (test files) in parallel with US1 work.
- T034 and T035 (README and earlier specs) in parallel.

## Implementation Strategy

MVP is Phase 2 plus US1 (window rows) and US3 (footer): the two most visible changes. US2 and US5 complete the look; US4 adds the setting; US6 and Phase 9 finish the feature for screenshots; Phase 10 documents it.
