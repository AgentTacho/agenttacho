# Tasks: Headline Window Switch

**Input**: Design documents from `specs/027-headline-window-switch/`

**Prerequisites**: plan.md, spec.md (FR-001 to FR-016), research.md (R1 to R9), data-model.md, contracts/config-file.md, contracts/bar-and-dropdown.md, quickstart.md

**Tests**: Required. Constitution II: every new `UsageCore` or `DemoMode` behavior gets its tests first (Swift Testing, `@Test`, `#expect`), and they must fail before the implementation. Run tests only with `make test` / `make test-release`, build only with `make app` / `make app-demo`.

## Conventions for every task

- Doc comments cite the spec requirements they implement (for example `spec 027 FR-007`).
- No em dash or en dash anywhere (code, comments, JSON, docs, commit messages).
- `Sources/AgentTacho` only renders values from `UsageCore` and forwards taps.
- Fixed test inputs: `Locale(identifier: "en_US")`, UTC calendar, fixed dates.
- Commit at each checkpoint with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.
- Do NOT run `scripts/screenshots/capture.sh`, do NOT push, do NOT touch the site repository.

## Interfaces

```swift
// T002, Sources/UsageCore/Config/HeadlineChoice.swift (all public; the app is a separate module)
public enum HeadlineChoice: Equatable, Hashable, Sendable {
    case claudeFiveHour, claudeSevenDay, claudeModel(String), codexWindow(String)
    public var stored: String                                   // "fiveHour", "sevenDay", "model:<name>", "window:<name>"
    public static func parse(_ raw: String, forCodex: Bool) -> HeadlineChoice?   // nil: invalid or wrong kind (FR-010)
    public var claudeWindow: ClaudeWindow? }                    // nil for codexWindow
// T004, Configuration.swift
// SubscriptionSettings.headlineWindow: HeadlineChoice?   CodexSubscriptionSettings.headlineWindow: HeadlineChoice?
extension Configuration {
    public func settingHeadline(_ choice: HeadlineChoice?, accountId: String) -> Configuration   // a default-window choice (claudeSevenDay) stores nil
    public func keepingHeadlineChoices(of current: Configuration) -> Configuration }             // FR-010, research R7
// T006, Sources/UsageCore/Bar/HeadlineWindow.swift
public struct ResolvedHeadline: Equatable, Sendable {
    public let claudeWindow: ClaudeWindow?   // set for Claude accounts
    public let codexName: String?            // set for Codex accounts
    public let isDefault: Bool
    public let percent: Int?                 // nil: fixed window without values
    public let pace: Pace?
    public let burnKey: BurnWindowKey
    public let tag: String?                  // nil when isDefault
    public let rowName: String               // the row's name: "5-hour", "7-day", "Fable", "weekly"
    public let accessibilityName: String }   // "5-hour window", "Fable weekly limit", "weekly window"
public enum HeadlineWindow {
    // status nil (signed in, but no values yet or no last good values): a fixed choice still resolves (percent nil, tag kept);
    // a model choice or no choice resolves to the default 7-day window with percent nil.
    public static func claude(accountId: String, status: SubscriptionStatus?, choice: HeadlineChoice?, now: Date) -> ResolvedHeadline
    public static func codex(accountId: String, entry: CodexLimitsEntry, choice: HeadlineChoice?, now: Date) -> ResolvedHeadline?   // nil without windows
    public static func tag(claude window: ClaudeWindow) -> String?
    public static func tag(codexName: String) -> String
    public static func choice(forClaude window: ClaudeWindow) -> HeadlineChoice?   // what a click on that row stores (nil for 7-day)
    public static func choice(forCodex name: String, entry: CodexLimitsEntry, now: Date) -> HeadlineChoice? }   // nil for the longest window
// T009, BarLayout.swift: BarItem gains `public let tag: String?` and `public let windowName: String?` (init params default nil)
// T011, BarPresentation.swift: BarEntryPresentation gains `public let tag: String?`; accessibility text names windowName before the value
// T010: BarPresentation accessibility text, today's format "<name> [warning|over limit] <valueText>" with the window name after the name:
//   "Claude Max 5-hour window 58%", "Claude Max 5-hour window warning ~85%", "Claude Max 5-hour window --"; no tag: unchanged
// T011a, Sources/UsageCore/Dropdown/RowText.swift: RowText.window gains `isHeadline: Bool = false`; true appends ", shown in menu bar" to the label
// T014, Sources/AgentTacho/DropdownView.swift (view wiring, internal):
//   LimitRowLayout(..., isHeadline: Bool? = nil, onSelect: (() -> Void)? = nil)   // nil isHeadline: no marker slot (budget rows)
//   WindowRow, ModelLimitRow, CodexWindowRow pass isHeadline and onSelect through
//   SubscriptionSection(..., headline: ResolvedHeadline?, onSelect: (HeadlineChoice?) -> Void)
//   CodexPlanSection(..., headline: ResolvedHeadline?, onSelect: (HeadlineChoice?) -> Void)
//   DropdownView resolves the headline with HeadlineWindow and passes { model.setHeadline(accountId: account.id, choice: $0) }
// T015, Sources/DemoMode/ScenarioCoverage.swift: CoverageReport gains barTags: [String: String] (bar entry id to tag),
//   headlineRows: [String: String] (account id to ResolvedHeadline.rowName)
```

---

## Phase 1: Setup

- [X] T001 Read spec.md, research.md, data-model.md and both contracts in `specs/027-headline-window-switch/`; run `make test` once and note the passing baseline in the checkpoint commit message of T005.

---

## Phase 2: Foundational (stored choice; blocks all stories)

- [X] T002 [P] Write failing tests in `Tests/UsageCoreTests/HeadlineChoiceTests.swift`: `stored` round trip for every case; `parse` accepts `"fiveHour"`, `"sevenDay"`, `"model:Fable"` for Claude and `"window:5-hour"`, `"window:weekly"`, `"window:30-day"`, `"window:2-hour"` for Codex; rejects `"model:"`, `"window:week"`, `"window:0-hour"`, `"FIVEHOUR"`, `""`, a Codex value with `forCodex: false` and a Claude value with `forCodex: true`; model names keep their case and may contain spaces and colons (`"model:Opus 4.6"`, `"model:a:b"` round trip).
- [X] T003 Implement `HeadlineChoice` in `Sources/UsageCore/Config/HeadlineChoice.swift` until T002 passes (research R2, spec 027 FR-010).
- [X] T004 Write failing tests in `Tests/UsageCoreTests/ConfigurationTests.swift`, then implement in `Sources/UsageCore/Config/Configuration.swift`: `headlineWindow` in `SubscriptionSettings` and `CodexSubscriptionSettings` (default nil); `Account` decodes key `headlineWindow` tolerantly like `timeFormat` (invalid, wrong kind, non-string or `null` give nil and one `ConfigurationLoadNotes` entry, the file stays valid) and encodes it only when set; a file without it loads unchanged and re-encodes byte-identical to today's output; `dataRelevant()` clears it so `needsRefresh` is false for a choice change; `settingHeadline` sets or clears (claudeSevenDay stores nil) only for the given subscription account and ignores token-based accounts; `keepingHeadlineChoices(of:)` copies each account's choice by id from `current` and leaves accounts missing in `current` as they are; a choice saved through one `ConfigStore` is loaded by a new `ConfigStore` on the same file (restart, SC-004) (spec 027 FR-010, FR-011, contracts/config-file.md).
- [X] T005 Run `make test`; commit `feat(config): store the headline window per subscription account`.

**Checkpoint**: the choice can be stored, loaded and merged.

---

## Phase 3: User Story 1 and 2, the switch in bar and header (Priority: P1)

**Goal**: a chosen window drives the bar entry and the section header of Claude and Codex accounts, with tag, level and markers.

**Independent Test**: unit tests of T006 and T008; in the demo build, clicking the 5-hour row of either section changes `●`, header and bar (quickstart steps 1 to 3).

- [X] T006 [US1] Write failing tests in `Tests/UsageCoreTests/HeadlineWindowTests.swift` for `HeadlineWindow.claude`: no choice and `claudeSevenDay` give the 7-day window, `isDefault`, no tag, row name "7-day"; `claudeFiveHour` gives the 5-hour percent, tag "5h", row name "5-hour", accessibility name "5-hour window", the 5-hour pace and `BurnWindowKey.claude(id, .fiveHour)`; `claudeFiveHour` without a 5-hour window, and with a nil status, gives percent nil with tag "5h"; `claudeModel("Fable")` with a Fable limit gives tag "Fable", name "Fable weekly limit"; without it (or with "fable") falls back to the default without tag; a model name of 9 characters gives its first 7 plus "…", one of 8 stays whole; a reset 5-hour window shows 0 (spec 010 FR-016).
- [X] T007 [US2] Add failing tests to `Tests/UsageCoreTests/HeadlineWindowTests.swift` for `HeadlineWindow.codex`: no choice gives the longest window as default; `codexWindow("5-hour")` gives tag "5h", row name "5-hour" and name "5-hour window"; two effective windows with the same name resolve to the last one, like `barWindow` and the burn inputs, and the view marks only that row; tags "2h", "30d", "wk"; a chosen name equal to the longest window is default without tag; a missing name falls back to the longest; no windows gives nil; `choice(forCodex:)` returns nil for the longest window and `codexWindow(name)` otherwise; `choice(forClaude: .sevenDay)` is nil.
- [X] T008 [US1] Implement `Sources/UsageCore/Bar/HeadlineWindow.swift` until T006 and T007 pass, reusing `SubscriptionStatus.effective(now:)`, `fiveHourPace`, `sevenDayPace`, `pace(of:)`, `CodexLimitsEntry.windows(now:)`, `barWindow(now:)` and `pace(of:now:)` (research R3, R5; spec 027 FR-005, FR-006, FR-008).
- [X] T009 [US1] Write failing tests in `Tests/UsageCoreTests/BarLayoutTests.swift`, then change `Sources/UsageCore/Bar/BarLayout.swift`: `BarItem` gains `tag` and `windowName`; `subscriptionItem` and `codexItem` take percent, pace, burn key, tag and window name from `HeadlineWindow`; Claude level is critical when the headline or the 7-day percent is at or above 100, otherwise the threshold level of the headline percent (spec 027 FR-007, clarification); Codex keeps `anyLimitReached` critical; "…" and "--" for not signed in or no windows carry no tag; a chosen fixed window without values gives "--" with tag, also for a signed-in entry whose status is nil (stale without last good values, expired credentials); stale values keep the tag; budget and member items have no tag; with no choice every existing test still passes unchanged. Include the US1 scenarios 3, 3a and 4 (warning level and `↗`/`↑` from the 5-hour window) and US2 scenario 2.
- [X] T010 [P] [US1] Write failing tests in `Tests/UsageCoreTests/BarPresentationTests.swift`, then change `Sources/UsageCore/Bar/BarPresentation.swift`: `BarEntryPresentation.tag` passes the item's tag; the accessibility text names `windowName` after the entry name and before the level word and the value only when a tag is shown, with the exact strings of the Interfaces block, unchanged otherwise (spec 027 FR-009, contracts/bar-and-dropdown.md).
- [X] T011a [P] [US1] Write a failing test in `Tests/UsageCoreTests/RowTextTests.swift` (or the existing RowText test file), then add `isHeadline` to `RowText.window` in `Sources/UsageCore/Dropdown/RowText.swift`: true appends ", shown in menu bar" to the row's accessibility label, false leaves it unchanged (spec 027 FR-003).
- [X] T011 [US1] Change `Sources/AgentTacho/BarLabel.swift` to draw the tag after the icon and before glyph, stale marker and value, separated by spaces, in the icon's tone and inside the pill when the entry has one (spec 027 FR-009). The Menu Bar tab preview uses the same view, so it needs no change; verify in `Sources/AgentTacho/MenuBarSettingsTab.swift` that it still calls `BarLayout.segments` with the draft.
- [X] T012 [US1] Change the headers of `SubscriptionSection` (the Claude section) and `CodexPlanSection` in `Sources/AgentTacho/DropdownView.swift` to show the resolved headline: the tag in `.secondary` and regular weight, then the bold percent, or "--" for a chosen fixed window without values; the default window looks exactly as today (spec 027 FR-008, clarification).
- [X] T013 [US1] Add `setHeadline(accountId: String, choice: HeadlineChoice?)` to the app model in `Sources/AgentTacho/App.swift`: builds `configuration.settingHeadline(choice, accountId:)`, saves it through `configStore.save`, sets `configuration`, logs `config: headline window of <id>: <stored value or default>`, and triggers no refresh, no timer restart and no notification. When `save` throws, it logs `config: headline window of <id> not saved: <error>` and leaves `configuration` unchanged (spec 027 FR-011, research R6).
- [X] T014 [US1] In `Sources/AgentTacho/DropdownView.swift` give `LimitRowLayout` a marker slot (12 pt) with `●` for the headline row, `○` while hovered on another row; `contentShape(Rectangle())` plus `onTapGesture` on the whole row calling `setHeadline` with `HeadlineWindow.choice(forClaude:)` or `choice(forCodex:)`; an `onHover` rounded rectangle in `Color.primary.opacity(0.06)` behind name line and bar, none on the headline row; `accessibilityAction(named: "Show in menu bar")`, `.isSelected` and the label from `RowText.window(isHeadline:)` on the headline row; keep every existing tooltip, note and identifier (`agenttacho.paceRow`); wire the views as in the Interfaces block (spec 027 FR-001 to FR-003, research R8). The `●` follows the resolved headline, so on a fallback it is on the default row, and a click there passes nil and clears the stored choice (US3 scenario 3). Budget, member and Unassigned rows get no slot.
- [X] T015 [US1] Write failing tests in `Tests/DemoModeTests/DefaultScenarioTests.swift`, then extend `Sources/DemoMode/ScenarioCoverage.swift` with `barTags` and `headlineRows`, and add `"headlineWindow": "fiveHour"` to `acc-max` in `Resources/demo/default.json`: the default scenario has tag "5h" for `acc-max`, headline row "5-hour" for `acc-max` and "weekly" for `acc-codex`. Keep the existing checks (levels, both markers, pace states, 7-day attention row) passing; if the 5-hour headline removes one, tune the demo values in `Resources/demo/default.json` (for example the 5-hour window's used percent or reset) and note why in the commit (spec 027 FR-015, research R9).
- [X] T016 [US1] Run `make test` and `make app-demo`; commit `feat(dropdown): click a window row to show it in the menu bar`.

**Checkpoint**: US1 and US2 work end to end in the demo build.

---

## Phase 4: User Story 3, a window that disappears (Priority: P2)

**Goal**: a vanished model limit or Codex window falls back to the default without losing the stored choice.

**Independent Test**: unit tests with snapshots without and with the chosen window.

- [X] T017 [US3] Add tests to `Tests/UsageCoreTests/BarLayoutTests.swift`: a configuration with `claudeModel("Fable")` and a snapshot without Fable gives the 7-day value without tag; the same configuration with a later snapshot that has Fable gives the Fable value with tag; a `codexWindow("5-hour")` choice with a snapshot that has only a weekly window gives the weekly value without tag; the configuration is unchanged in all cases; during the fallback `HeadlineWindow.claude` reports row name "7-day" (where the view puts the `●`), and `settingHeadline(HeadlineWindow.choice(forClaude: .sevenDay), accountId:)` clears the stored choice. Fix `HeadlineWindow` or `BarLayout` if any fails (spec 027 FR-006, US3).
- [X] T018 [US3] Run `make test`; commit `test(bar): fall back to the default window when the chosen one is gone`.

---

## Phase 5: User Story 4, find and operate the switch (Priority: P2)

**Goal**: the Settings window keeps dropdown choices; hover and VoiceOver behave as specified.

**Independent Test**: unit test of the merge; by hand, hover, VoiceOver and the Settings preview (quickstart steps 2, 5, 6).

- [X] T019 [US4] In `Sources/AgentTacho/SettingsView.swift`, apply `keepingHeadlineChoices(of: model.configuration)` to the candidate in `applyNow()`, and in `onChange(of: model.configuration)` patch `draft`, `applied` and a pending `undoTarget` with the new choices when the draft has unapplied edits, so a dropdown click never counts as a Settings edit or an extra undo step (spec 027 FR-010, research R7). Add a `ConfigurationTests` case that a candidate built from an old draft keeps a newer choice.
- [X] T020 [US4] Run `make app-demo`, check quickstart steps 2, 5 and 6 by hand where possible (hover highlight and `○`, preview tag, VoiceOver action name); commit `feat(settings): keep headline choices made in the dropdown`.

---

## Phase 6: Polish and cross-cutting

- [X] T021 [P] Amend earlier specs (spec 027 FR-014): `specs/001-agenttacho/spec.md` FR-005, `specs/007-codex-plan-limits/spec.md` FR-012, `specs/011-pace-forecast/spec.md` FR-012, `specs/017-burn-rate-escalation/spec.md` FR-008 (each: "the headline window, spec 027", default as before), and `specs/025-minimal-dropdown/contracts/dropdown-ui.md` (marker slot, clickable rows, header tag).
- [X] T022 [P] Update `docs/usage.md` (click a window row, `●`, tag in the menu bar, fallback) and `docs/configuration.md` (`headlineWindow` field with values and an example) (spec 027 FR-014).
- [X] T022a [P] Extend the idea inbox entry `minimal-dropdown-screenshots` in `brainstorm/idea-inbox.md` with this spec's shots (`menubar`, `menubar-settings`, `plan-limits`, `pace`, `dropdown`) and the "Plan limits" card copy (click a window to show it in the menu bar) (spec 027 FR-016).
- [X] T023 Run `make test` and `make test-release`; scan the diff for em and en dashes (`rg "[\x{2013}\x{2014}]"` over changed files); commit `docs: describe the headline window switch`.

---

## Dependencies

- Phase 2 (T002 to T005) blocks everything.
- T008 needs T006 and T007 (one file, written one after the other); T009 needs T008; T010 and T011a can run beside T009; T011 needs T010; T012 needs T008; T014 needs T008, T011a and T013; T015 needs T009.
- US3 (T017, T018) needs T009 and T014. US4 (T019, T020) needs T004 and T013.
- Polish (T021 to T023) after all stories.

## Parallel examples

- T002 alongside reading the contracts.
- T009, T010 and T011a (different files).
- T021, T022 and T022a (specs, docs, idea inbox).

## Implementation strategy

MVP is Phase 2 plus Phase 3 (US1 and US2): the switch works in bar and header for both plan types. US3 hardens the fallback, US4 the Settings merge and the affordance check; the polish phase updates the earlier specs and the docs. Screenshots are recaptured later in the shared round (spec 027 FR-016), not in this pull request.
