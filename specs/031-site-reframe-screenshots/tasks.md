# Tasks: Site Reframe Screenshots

**Input**: Design documents from `specs/031-site-reframe-screenshots/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/capture-stems.md, quickstart.md

**Tests**: required (constitution II, test first). Every implementation task follows a failing test task. Run tests only through the Makefile (`make test`, `make test-release`).

**Doc comments** cite `spec 031 FR-xxx`. No em dash or en dash anywhere.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] T001 Run `make test` and `make test-release` in the worktree and note that both pass before any change (baseline; no file changes)

---

## Phase 2: Foundational (blocks US1 and US2)

**Purpose**: the second Claude Max account in the demo and the shot markers that both new stems rely on.

- [ ] T002 [P] Write failing tests for `BarLayout.shotClaudeAccountIds(configuration:)` in `Tests/UsageCoreTests/ShotTargetTests.swift`: returns the ids of the first two Claude subscription accounts in arrangement order; one id when only one exists; empty without any; ignores Codex subscriptions and token-based accounts; keeps arrangement order when a group or a Codex account sits between them (spec 031 FR-010a, research R2)
- [ ] T003 Implement `public static func shotClaudeAccountIds(configuration: Configuration) -> [String]` in `Sources/UsageCore/Bar/BarLayout.swift` next to `shotBudgetOwner`, using `configuration.arrangedEntries` and the account kind `.subscription`, with a doc comment citing spec 031 FR-010a; `make test` passes T002
- [ ] T004 [P] Write failing coverage tests in `Tests/DemoModeTests/DefaultScenarioTests.swift` (new test `defaultScenarioHasTwoClaudeMaxAccounts`, at the last frame via `ScenarioCoverage.evaluate`): exactly two `subscription` accounts on `claudeCode` with different `credentialDirectory` values and distinct names "Claude Max · Work" and "Claude Max · Personal"; `BarLayout.shotClaudeAccountIds` returns `["acc-max", "acc-max-personal"]`; both are adjacent in `arrangedEntries` and both appear in `BarLayout.segments`; the first has a non-empty breakdown (`report.snapshot.subscriptions["acc-max"]`); the second's 5-hour and 7-day levels are normal, its rows are not attention rows, and each window differs from the first's by at least 15 points (spec 031 FR-001 to FR-007)
- [ ] T005 Update the existing default-scenario tests in `Tests/DemoModeTests/DefaultScenarioTests.swift` for the new scenario: `headlineRows` gains the second account's headline row; the band test expects `[.plain, .tinted, .plain, .tinted, .plain]` and its doc comment names five sections; comments that cite the dropped `pace`, `plan-limits`, `dropdown` or `details` shots now cite `glance`, `same-provider`, `menubar` or `harnesses` as appropriate (keep the 7-day attention row check, the `glance` shot shows it)
- [ ] T006 Edit `Resources/demo/default.json` per data-model.md: rename `acc-max` to "Claude Max · Work"; add account `acc-max-personal` ("Claude Max · Personal", `brands:claude`, `claudeCode`, `credentialDirectory` `~/.claude-personal`, `shownInBar` true, thresholds 80 and 100); arrangement `acc-max, acc-max-personal, acc-codex, grp-company, acc-side`; `claude.acc-max-personal` with plan `max`, 5-hour 20% resetting in 2h30m, 7-day 35% resetting in 3d12h; four usage records for `acc-max-personal` on `claudeCode` within the week with invented project paths; adjust the second account's numbers if T004 shows a pace note; `make test` passes T004, T005 and `demoFilesUseInventedNamesOnly`
- [ ] T007 Change `BreakdownView` in `Sources/AgentTacho/BreakdownView.swift` from `isShotTarget: Bool` to `shotIdentifier: String?` applied with `.shotContainer(shotIdentifier)`; update the budget call sites in `Sources/AgentTacho/DropdownView.swift` to pass `isShotTarget ? "agenttacho.details" : nil` (spec 031 FR-010a)
- [ ] T008 In `Sources/AgentTacho/DropdownView.swift`: give `SubscriptionSection` an optional `shotIdentifier` (from `BarLayout.shotClaudeAccountIds`: index 0 gets `agenttacho.claudeSection`, index 1 `agenttacho.claudeSection2`, others nil) applied with `.shotContainer` to the section's outer `VStack`; pass `agenttacho.claudeDetails` as the `BreakdownView` `shotIdentifier` for index 0 only; remove `.shotContainer("agenttacho.claudePlan")` and the `agenttacho.paceRow` identifier and update the comments that named the `plan-limits` and `pace` shots (spec 031 FR-010a); `make test` passes and `make app-demo` builds

**Checkpoint**: the demo shows two Claude Max sections; markers exist once each.

---

## Phase 3: User Story 1 - One image shows usage at a glance (P1)

**Goal**: `glance` light and dark, the first Claude Max section with plan windows, pace note and expanded details, cropped per FR-012.

**Independent Test**: `make test-release` asserts the `glance` capture steps and its exact `fill_crop` geometry; a capture run writes `glance-light.webp` and `glance-dark.webp`.

- [ ] T009 [US1] Extend the stubs in `scripts/release/tests/test_screenshots.sh`: the `uihelper frame|scrollto` stub returns per-identifier frames (`agenttacho.claudeSection` at `x=920 y=40 w=340 h=200` while collapsed and `h=380` after an odd number of `press ... agenttacho.claudeDetails` calls, tracked in a state file; `agenttacho.claudeSection2` at `x=920 y=248 w=340 h=140`; other identifiers keep `x=910 y=40 w=340 h=80`) and the window list gives the dropdown frame `x=910 y=30 w=360 h=800`, so geometry assertions are exact; keep existing tests green
- [ ] T010 [US1] Write failing release tests in `scripts/release/tests/test_screenshots.sh` for `fill_crop` (sourced or through a full run): uniform margin = smallest window distance capped at 4% of the region's shorter side, exact `-crop` geometry at 2x for the `glance` region; failure when the margin is below 4 px (region touching the window edge) and when the aspect lies outside 3:4 to 4:3, each naming the stem and leaving the target untouched (spec 031 FR-012, FR-015)
- [ ] T011 [US1] Write failing release tests in `scripts/release/tests/test_screenshots.sh` for the `glance` steps: `press 600 agenttacho.claudeDetails`, then `press 600 Models`, then `scrollto 600 agenttacho.claudeSection`, then a fresh window capture, then the `glance-light.png` crop, then a second `press 600 agenttacho.claudeDetails` (collapse) before `press 600 agenttacho.details` (spec 031 FR-008, FR-010, FR-010b)
- [ ] T012 [US1] Add `fill_crop <image> <window> <region> <out> <stem> <appearance>` to `scripts/screenshots/capture.sh` next to `crop`: one awk program computes the margin and geometry per data-model.md, prints `fail:<reason>` on a violation (the caller reports it with `shot_failed`), otherwise `magick ... -crop <geometry> +repage`; doc comment cites spec 031 FR-012
- [ ] T013 [US1] Add the `glance` block to `capture_pass` in `scripts/screenshots/capture.sh` after the `same-provider` block position (see T016): expand with `press agenttacho.claudeDetails`, `press Models`, `scrollto agenttacho.claudeSection`, re-read the dropdown window, `screencapture` to `raw/glance.png`, `frame agenttacho.claudeSection`, `fill_crop` to `png/glance-$appearance.png`, collapse with a second `press agenttacho.claudeDetails` (a failing collapse fails `glance`); `make test-release` passes T010 and T011

**Checkpoint**: US1 complete with stubs; real capture pending the maintainer.

---

## Phase 4: User Story 2 - One image shows two accounts on the same provider (P1)

**Goal**: `same-provider` light and dark, both Claude Max sections stacked, details collapsed.

**Independent Test**: `make test-release` asserts the union geometry and that `same-provider` is captured before any details press.

- [ ] T014 [US2] Write failing release tests in `scripts/release/tests/test_screenshots.sh`: `union` of the two collapsed stub section frames gives `x=920 y=40 w=340 h=348`; the `same-provider-light.png` crop uses that region through `fill_crop`; `scrollto 600 agenttacho.claudeSection` and a window capture come before it; no `press` of any details marker happens before the `same-provider` crop (spec 031 FR-009, FR-010b)
- [ ] T015 [US2] Add `union <frame> <frame>` (bounding frame in the `x= y= w= h=` format) to `scripts/screenshots/capture.sh` with a doc comment citing spec 031 FR-010a
- [ ] T016 [US2] Add the `same-provider` block to `capture_pass` in `scripts/screenshots/capture.sh` right after the dropdown opens: `scrollto agenttacho.claudeSection`, re-read the window, `screencapture` to `raw/same-provider.png`, frames of `agenttacho.claudeSection` and `agenttacho.claudeSection2`, `union`, `fill_crop` to `png/same-provider-$appearance.png`; `make test-release` passes T014

**Checkpoint**: US1 and US2 complete.

---

## Phase 5: User Story 3 - The capture produces exactly the set the site uses (P2)

**Goal**: 14 files, no notification setup, dropped stems gone.

**Independent Test**: `make test-release`: 14 files, no first-run or notification tests, a run without notification permission succeeds.

- [ ] T017 [US3] Update `scripts/release/tests/test_screenshots.sh` first: `STEMS` to `menubar budget harnesses prices menubar-settings glance same-provider`; rename the 22-file test to 14 files and assert `glance-light.webp` in the output instead of `dropdown-light.webp`; replace the `pace` crop and `hastext` alert assertions with `budget` assertions (`scrollto 600 agenttacho.budgetRow` before its window capture); the details scroll count assertion matches the new number of `scrollto agenttacho.details` calls (one per pass for `harnesses`); remove the tests for `--first-run`, notification permission, banner style, foreign banners and `pace-dark` failures (use `glance-dark` for the dwebp failure test); add a test that a run with no notification authorization line in the demo log still exits 0 (spec 031 FR-011, FR-014, FR-016, FR-017)
- [ ] T018 [US3] In `scripts/screenshots/capture.sh`: set `STEMS` per FR-011; remove the `alert` block, the `plan-limits`, `pace`, `details` and full `dropdown` outputs, the Groups `settings_tab` call, `check_notifications` and its call, the notification permission part of `preflight`, `first_run`, the `--first-run` argument handling and usage text, and constants or stubs only they used; capture `budget` after `scrollto agenttacho.budgetRow` and a fresh window capture; keep `harnesses` (press `agenttacho.details`, `Harnesses`, scroll, capture, crop, then `Models`); update the header comment and the order to `same-provider`, `glance`, `budget`, `harnesses` (spec 031 FR-010b, FR-011, FR-014); `make test-release` passes T017 and all earlier release tests
- [ ] T019 [US3] Check `scripts/screenshots/uihelper.swift` for helpers only the removed steps used (`hastext`, NotificationCenter window listing) and leave them if other code or tests still use them; no change unless one is now dead and untested (note the decision in the commit message)

**Checkpoint**: capture contract matches `contracts/capture-stems.md`.

---

## Phase 6: User Story 4 - Docs and tests describe the new set (P3)

**Goal**: instructions match the capture.

**Independent Test**: the SC-004 checks: stem lists and counts name no dropped stem or old count.

- [ ] T020 [P] [US4] Update `AGENTS.md`: "seven screenshots", "six feature cards and a one-line feature strip" instead of nine cards and five small things, "14 files" in step 4 and the examples, the plan template example row (`Shots that change | glance, menubar` or similar without dropped stems), and the Settings tab example (page test counting six cards) (spec 031 FR-018)
- [ ] T021 [P] [US4] Update `docs/website.md`: the "What feeds the page" rows (seven screenshots; six feature cards and the one-line strip), the stem list citing spec 031 FR-011, the page test description (six cards, the strip), and the recapture steps (no `--first-run`, no Banners setup, 14 files) (spec 031 FR-019)

---

## Phase 7: Polish

- [ ] T022 Run `make test` and `make test-release`; both pass
- [ ] T023 Run the SC-004 checks with `rg` outside `specs/` and `brainstorm/`: no `STEMS=` line, `<stem>-light`/`<stem>-dark` name, `docs/website.md` stem list or `AGENTS.md` template row names `plan-limits`, `pace`, `details`, `groups`, `alert` or `dropdown` as a stem; no "22 files", "eleven screenshots" or "nine feature cards" in instructions; no em dash or en dash in changed files
- [ ] T024 Do NOT run `scripts/screenshots/capture.sh`: it needs the maintainer's go-ahead (AGENTS.md step 4). Record in the final report that the capture run and the image review (AGENTS.md step 5) are pending

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 (T002 → T003; T004, T005 → T006; T003 → T008; T007 → T008) → Phases 3 and 4 → Phase 5 → Phase 6 → Phase 7.
- US1 and US2 both edit `capture.sh` and `test_screenshots.sh`; run them in sequence (T009 first, it sets up the stubs both use). The `same-provider` block (T016) sits before `glance` (T013) in the script; implementing US1 first is fine as long as the final order matches FR-010b.
- US3 (T017, T018) rewrites the remaining capture steps; it comes after US1 and US2 to avoid conflicting edits.
- US4 (T020, T021) is independent of the code and can run in parallel with Phase 5.

## Parallel Opportunities

- T002 and T004 (different test files).
- T020 and T021 (different docs).

## Implementation Strategy

MVP is Phase 2 plus US1 (`glance`), which replaces three site images. US2 adds the second new image; US3 trims the set and the notification setup; US4 aligns the docs. Each phase ends with `make test` or `make test-release` green.
