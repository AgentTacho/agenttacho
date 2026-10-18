# Tasks: Demo build and screenshot capture

**Input**: Design documents from `specs/024-demo-mode-screenshots/`

**Prerequisites**: plan.md, spec.md, research.md (R1 to R12), data-model.md, contracts/scenario-format.md, contracts/capture-cli.md, quickstart.md (Q1 to Q8)

**Tests**: Required. AGENTS.md asks for test-first development of core logic; new test cases come before their implementation and must fail first. Bash script behavior is tested first in `scripts/release/tests/` with stubs. Run Swift tests only with `make test`, script tests only with `make test-release`, build only with `make app` and `make app-demo`.

## Format: `[ID] [P?] [Story] Description`

## Conventions for every task

- Doc comments of new or changed code cite the spec requirements they implement (for example `spec 024 FR-012`).
- No em dash or en dash characters anywhere (code, comments, JSON, docs, commit messages).
- Every use of `DemoMode` in `Sources/AgentTacho/` sits inside `#if AGENTTACHO_DEMO`, including the `import DemoMode` line.
- Identity: app `AgentTacho Demo`, bundle id `dev.rhuss.agenttacho.demo`, folders `agenttacho-demo`, compile flag `AGENTTACHO_DEMO`, env var `DEMO`, scratch path `.build/demo`.
- Commit at each checkpoint with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.

## Interfaces

Names and signatures shared between tasks (all in `Sources/DemoMode/` unless noted; all `public`):

```swift
// T006
struct ScenarioDuration { let seconds: TimeInterval; init(parsing: String) throws }
// T007
struct Scenario: Decodable, Sendable { let name: String; let configuration: Configuration; let importedPrices: ImportedPrices?
    let claude: [String: ClaudeWindows]; let codex: [String: CodexWindows]; let usage: [UsageEntry]; let frames: [Frame]
    static func load(from url: URL) throws -> Scenario }
struct ScenarioError: Error, Equatable, CustomStringConvertible { let path: String; let message: String }
// T008
actor ScenarioPlayer { init(scenario: Scenario, launch: Date); func state(at now: Date) -> ScenarioState }
struct ScenarioState: Sendable { let claude: [String: ClaudeWindows]; let codex: [String: CodexWindows]; let usage: [UsageEntry] }
// T012
struct DemoSubscriptionSource: UsageSource; struct DemoCodexLimitsSource: UsageSource; struct DemoRecordSource: UsageSource
// T013
enum DemoSetup {
    static func prepare(scenario: Scenario, paths: Paths) throws
    static func sources(player: ScenarioPlayer, scenario: Scenario, launch: Date,
                        builtInPrices: PriceTable, importedPrices: ImportedPrices) -> [any UsageSource]
    static func frameOffsets(_ scenario: Scenario) -> [TimeInterval] }
struct NoCredentials: CredentialReader
// T014, T023
enum ScenarioCoverage { static func evaluate(scenario: Scenario, launch: Date) async throws -> CoverageReport }
struct CoverageReport { let levels: Set<BarLevel>; let markers: Set<String>; let paceStates: Set<String> // "onPace", "behind", "ahead"
    let incompleteOwners: [String]; let harnesses: Set<Harness>; let crossings: [String] } // "<display name>@<threshold>", filled by T023
```

`Paths(home:appFolder:)` (T003) and `UpdateState.demoBuild` (T004) are in UsageCore. `ImportedPrices` is UsageCore's type for the content of `imported-prices.json` (`Sources/UsageCore/Pricing/ImportedPrices.swift:140`). The package uses tools version 5.10, so no typed throws. The launch log lines and arguments are fixed in `contracts/capture-cli.md`.

---

## Phase 1: Setup

- [X] T001 Commit the spec artifacts in `specs/024-demo-mode-screenshots/` (`docs(spec): demo build and screenshot capture spec, plan and tasks`).
- [X] T002 Run `make test` and `make test-release` once to record the baseline (both must pass before any change).

---

## Phase 2: Foundational (core types every story needs)

- [X] T003 Add tests in `Tests/UsageCoreTests/PathsTests.swift` for `Paths(home:appFolder:)`: default `agenttacho` keeps today's four URLs; `appFolder: "agenttacho-demo"` gives `.config/agenttacho-demo/config.json`, `.config/agenttacho-demo/imported-prices.json`, `Library/Logs/agenttacho-demo/usage.log`, `Library/Application Support/agenttacho-demo/last-good.json`. Run `make test` (fails), then add the `appFolder` parameter (default `"agenttacho"`) to `Sources/UsageCore/Config/Paths.swift` (spec 024 FR-005). `make test` passes.
- [X] T004 [P] Add a test in `Tests/UsageCoreTests/UpdateStateTests.swift` that `UpdateState.demoBuild` has title and line text "Demo build: updates are off"; then add the case to `Sources/UsageCore/Update/UpdateState.swift` and handle it in every switch over `UpdateState` (`rg -n "case .developmentBuild" Sources` lists them; treat it like `.developmentBuild`) (spec 024 FR-007).
- [X] T005 Add the library target `DemoMode` (path `Sources/DemoMode`, depends on `UsageCore`) and the test target `DemoModeTests` (path `Tests/DemoModeTests`, depends on `DemoMode` and `UsageCore`) to `Package.swift`; add `DemoMode` as a dependency of the `AgentTacho` executable target. Create `Sources/DemoMode/DemoMode.swift` with a doc comment explaining the target (research R2) and `Tests/DemoModeTests/SmokeTests.swift` with one passing test. `make test` passes.
- [X] T006 [P] Write `Tests/DemoModeTests/ScenarioDurationTests.swift` (`"2h10m"` is 7800 s, `"-3d"` is -259200 s, `"12s"`, `"1d2h3m4s"`; rejects `""`, `"2x"`, `"3m2h"` wrong order, `"--1d"`), then implement `Sources/DemoMode/ScenarioDuration.swift` (data-model "Durations").
- [X] T007 Write `Tests/DemoModeTests/ScenarioTests.swift` with JSON fixtures inline: decodes the example of `contracts/scenario-format.md`; `configuration` decodes through UsageCore's `Configuration` decoder; errors carry the JSON path for a used percent of 101, an unknown account id in `claude`, `codex` and `usage`, a `claude` id that is not a subscription account, a positive usage `at`, frames out of order, a `name` different from the file name. Then implement `Sources/DemoMode/Scenario.swift` (`Scenario`, `ClaudeWindows`, `CodexWindows`, `WindowValue`, `UsageEntry`, `Frame`, `ScenarioError`, `Scenario.load(from: URL)`), per data-model.md (spec 024 FR-010, FR-011, FR-013).
- [X] T008 Write `Tests/DemoModeTests/ScenarioPlayerTests.swift`: with launch `L`, `state(at: L)` has the base values; a frame at 12 s is not applied at `L + 11 s` and is applied at `L + 12 s`; frames change only the named fields; frame usage entries are added from that frame on; reset times stay `L + resetsIn` for the whole run. Then implement `Sources/DemoMode/ScenarioPlayer.swift` (actor) (spec 024 FR-011, FR-012).

**Checkpoint**: `make test` passes; commit `feat(demo): scenario model, durations and player`.

---

## Phase 3: User Story 1 - See the demo story in a separate demo app (Priority: P1) MVP

**Goal**: `make app-demo` builds AgentTacho Demo, which shows the default scenario with its own folders and no credential, agent file or network access.

**Independent Test**: quickstart Q2, Q3, Q4 (without the notification), Q5.

### Tests first

- [X] T009 [P] [US1] Write `Tests/DemoModeTests/DemoSourcesTests.swift`: `DemoSubscriptionSource` returns `.subscriptions` keyed by account id with `fetchedAt == context.now`, state `.ok`, reset times from the player; `DemoCodexLimitsSource` returns `.codexLimits` with `origin: .live`, `observedAt == context.now`, state `.live`, window names from `lengthMinutes`; `DemoRecordSource` returns `.records` with `timestamp = launch + at`, a stable `messageId` (`<scenario>-<index>`), `harness`, `project`, and `costUSD` from `PriceTable.effective(builtIn:imported:overrides:)` (nil only for an unpriced model); a record of an account in a monthly budget that falls before the first of the launch month moves to the first of the month at the same time of day (research R6), others never move. Use launch dates 2026-10-01 09:00, 2026-10-15 09:00 and 2026-10-31 09:00 UTC.
- [X] T010 [P] [US1] Write `Tests/DemoModeTests/DemoSetupTests.swift`: `DemoSetup.prepare(scenario:paths:)` in a temp home writes the scenario's configuration to `paths.configFileURL` and its imported prices to `paths.importedPricesFileURL` (replacing existing files), deletes `paths.lastGoodFileURL`, and never touches a sibling `agenttacho` folder; `DemoSetup.sources(player:...)` returns exactly three sources, none of which conforms to `NetworkBoundSource`, `SavedValuesSource`, `EndpointGatedSource` or `WindowSensitiveSource` (spec 024 FR-006, FR-009, SC-002); `NoCredentials` reports no default credential. Add a test that reads every file in `Sources/DemoMode/` and fails if it mentions `URLSession`, `SecurityToolCredentialReader`, `FileCodexCredentialReader`, `UsageEndpointClient`, `CodexUsageClient`, `LiteLLMImporter(` or `/usr/bin/security` (research R11).
- [X] T011 [P] [US1] Write `Tests/DemoModeTests/DefaultScenarioTests.swift` loading `Resources/demo/default.json` (path from `#filePath`): it loads and validates; it contains no "Red Hat" in any spelling (case-insensitive, with or without space or hyphen) and no email-shaped string (spec 024 FR-015); and `ScenarioCoverage.evaluate` at each of the three launch dates of T009, after the last frame, reports: bar levels include normal, warning and critical; markers include `↗` and `↑`; dropdown pace meters include on pace, behind and ahead; no group or token account is incomplete; harnesses with usage are Claude Code, Codex and OpenCode; a group named "Company budget" with a building icon holding a Vertex and an OpenAI account (spec 024 FR-014, FR-016, SC-005).

### Implementation

- [X] T012 [US1] Implement `Sources/DemoMode/DemoSources.swift` (`DemoSubscriptionSource`, `DemoCodexLimitsSource`, `DemoRecordSource`, all reading one `ScenarioPlayer`; pricing like `Sources/UsageCore/Logs/SessionLogSource.swift:58`; monthly clamp) until T009 passes (spec 024 FR-006, FR-010).
- [X] T013 [US1] Implement `Sources/DemoMode/DemoSetup.swift` (`prepare`, `sources`, `NoCredentials` conforming to `CredentialReader` (`Sources/UsageCore/Subscription/CredentialReader.swift:6`), `frameOffsets`) until T010 passes (spec 024 FR-005, FR-006, FR-009).
- [X] T014 [US1] Implement `Sources/DemoMode/ScenarioCoverage.swift`: build a `RefreshCoordinator` with an in-memory config store from the scenario, register the three demo sources, use an injected clock (follow `MutableClock` in `Tests/UsageCoreTests/RefreshCoordinatorTests.swift:121`), refresh at launch and after each frame, and return levels and markers from `BarLayout.segments`, pace states from the dropdown's pace computation (`Sources/UsageCore/Pace/Pace.swift`), `incomplete` flags, harnesses from the breakdown. Make any UsageCore initializer it needs `public` without changing behavior.
- [X] T015 [US1] Write `Resources/demo/default.json` per `contracts/scenario-format.md` and research R5, R7, R9: accounts Claude Max (`acc-max`, subscription, thresholds [80, 100], 7-day 70% resetting in 3d12h, 5-hour 58% resetting in 2h), Codex on ChatGPT Plus (`acc-codex`, `liveLimits: true`, 5-hour 40% resetting in 1h30m, weekly 60% resetting in 3d12h), Vertex (`acc-vertex`, provider vertex) and OpenAI API (`acc-openai-company`, provider openai) in group `grp-company` "Company budget" (monthly, building icon from the bundled Font Awesome set, thresholds [80, 100], spend about 76% at launch), "Side project" (`acc-side`, provider openai, own weekly budget, about 104%); `alignmentAccountId` `acc-max`; bar order Claude, Codex, Company budget, Side project; `importedPrices` with an OpenAI batch for the OpenAI models used; usage records over the last 7 days across Claude Code, Codex and OpenCode with current model names (Claude models from `Sources/UsageCore/Resources/prices.json`) and invented project names; the frame at `12s` that adds Company budget spend to about 86%. Tune numbers until T011 passes (spec 024 FR-014).
- [X] T016 [P] [US1] Write `Resources/demo/litellm-prices.json` in LiteLLM's format (see `Tests/UsageCoreTests/Fixtures/litellm/excerpt.json`) with made-up prices for a few Anthropic, OpenAI and Gemini models, a little different from the scenario's imported batch so the preview shows changes. Add a test in `Tests/DemoModeTests/DefaultScenarioTests.swift` that `LiteLLMImporter.batch(from:kind:origin:importedAt:)` accepts it for `.anthropic`, `.openai` and `.gemini` (spec 024 FR-007).
- [X] T017 [US1] Add a demo build to `scripts/release/build-app.sh`, tests first in `scripts/release/tests/test_build_scripts.sh` (follow `test_build_app_update_test_compiles_the_flag_and_stamps_the_source` at line 214): with `DEMO=1` it runs `swift build -c release --scratch-path .build/demo -Xswiftc -DAGENTTACHO_DEMO`, takes the binary and resource bundle from `.build/demo/release/`, writes `build/AgentTacho Demo.app`, sets `CFBundleIdentifier` `dev.rhuss.agenttacho.demo` and `CFBundleName`/`CFBundleDisplayName` `AgentTacho Demo` with PlistBuddy, signs with that identifier, copies `Resources/demo/` to `Contents/Resources/demo/`; without `DEMO` nothing changes and no `demo` folder is copied. Make `APP` and the bundle id overridable in `scripts/release/lib.sh` (`release_defaults`) for this. Add the `app-demo` target to `Makefile` (`@DEMO=1 bash scripts/release/build-app.sh`, listed in `.PHONY`, `DEMO ?=` exported) and to the target loop in `scripts/release/tests/test_makefile.sh:9`; add a test that `make -n app-demo` sets `DEMO=1` (spec 024 FR-001, FR-003). `make test-release` passes.
- [X] T018 [US1] Wire the demo into `Sources/AgentTacho/App.swift` under `#if AGENTTACHO_DEMO` (research R8): `Paths(appFolder: "agenttacho-demo")`; read the scenario name from `UserDefaults.standard.string(forKey: "demoScenario") ?? "default"`; load `Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "demo")`; on success call `DemoSetup.prepare`, use `NoCredentials` in place of `SecurityToolCredentialReader`, skip `LastGoodStore.load` and the store, register `DemoSetup.sources` instead of the five real sources, log `demo build, scenario <name>`; on failure log the `ScenarioError` and show it in the dropdown's existing error area, registering no source (spec 024 FR-004, FR-005, FR-006, FR-009, FR-013).
- [X] T019 [US1] In `Sources/AgentTacho/App.swift` under the flag, make `applyStartAtLogin` (around line 394) a no-op and drop credential notifications (the two places that send `credentialTracker` events, around lines 236 and 477) (spec 024 FR-008). In `Sources/AgentTacho/Updater.swift` under the flag, `start()` skips the launch cleanup and environment probes and sets the state to `.demoBuild`; `checkNow` and `runCheck` return with `.demoBuild` before any `UpdateClient` is created (spec 024 FR-007).
- [X] T020 [US1] In `Sources/AgentTacho/App.swift` `previewProviderImport` (around line 266), under the flag read `demo/litellm-prices.json` from `Bundle.main` instead of `LiteLLMImporter().fetch()`, with origin `demo`; the rest of the method stays as is (spec 024 FR-007).
- [X] T021 [US1] In `Sources/AgentTacho/AboutSettingsTab.swift` add a `row("Build") { Text("Demo") }` to `releaseGrid` under the flag (spec 024 FR-004).
- [ ] T022 [US1] Run `make test`, `make test-release`, `make app` and `make app-demo`; walk through quickstart Q2, Q3, Q4 (bar, dropdown, Settings, About, Prices import) and Q5; launch once with `-demoScenario missing` and confirm the dropdown shows the scenario error and no account (spec 024 FR-013). Commit `feat(demo): AgentTacho Demo app with the default scenario`.

**Checkpoint**: US1 complete; screenshots can be taken by hand.

---

## Phase 4: User Story 2 - A scripted change fires a real alert (Priority: P2)

**Goal**: frames apply on time and the Company budget crossing fires one real notification.

**Independent Test**: quickstart Q4 notification line.

- [X] T023 [US2] Extend `Tests/DemoModeTests/DefaultScenarioTests.swift`: with `ScenarioCoverage` and UsageCore's `ThresholdTracker`, the snapshots from launch to the last frame produce exactly one crossing, "Company budget" at 80, at each launch date of T009; the last frame is at most 20 s after launch (spec 024 FR-012, FR-014). Extend `ScenarioCoverage` with the crossing list, and tune the frame values in `Resources/demo/default.json`, until it passes.
- [X] T024 [US2] In `Sources/AgentTacho/App.swift` under the flag, after the launch refresh schedule one `Task` per `DemoSetup.frameOffsets` that sleeps until `launch + offset + 0.5 s` (no sleep when that time has already passed, so a late start applies the frame at once) and calls `coordinator.requestRefresh(trigger: .scheduled)`; after the last one, log `demo: last frame applied` once its snapshot has been applied (spec 024 FR-012).
- [ ] T025 [US2] `make app-demo`, launch it, allow notifications, and confirm the "Company budget reached 80%" banner about 12 s after launch and the log lines. Commit `feat(demo): timed frames and the threshold alert`.

**Checkpoint**: US2 complete.

---

## Phase 5: User Story 3 - One command captures every screenshot (Priority: P3)

**Goal**: `scripts/screenshots/capture.sh <dir>` writes all 22 files.

**Independent Test**: quickstart Q6, Q7.

- [X] T026 [P] [US3] Add accessibility identifiers in all builds: `agenttacho.claudePlan` on the Claude plan section and `agenttacho.paceMeter` on its 7-day pace meter in `Sources/AgentTacho/DropdownView.swift`, `agenttacho.budgetRow` on a budget row there, `agenttacho.details` on the Details disclosure and `agenttacho.detailsMode` on its mode picker in `Sources/AgentTacho/BreakdownView.swift`, `agenttacho.statusItem` on the status item button (`Sources/AgentTacho/BarLabel.swift` or where the label is installed). For `agenttacho.budgetRow`, use the row of the first budget owner whose level is warning or critical, falling back to the first budget row. No visible change.
- [X] T027 [US3] Under the flag in `Sources/AgentTacho/App.swift`, handle `-demoRenderBar <dir>`: after `demo: last frame applied`, render the bar label view with `ImageRenderer` at scale 2 on a transparent background with `.environment(\.colorScheme, .light)` and `.dark`, write `menubar-light.png` and `menubar-dark.png` into `<dir>`, log `demo: bar rendered` (spec 024 FR-019, research R10).
- [X] T028 [US3] Write `scripts/screenshots/uihelper.swift` with the subcommands of research R10 (`perms`, `display`, `statusitem`, `windows`, `frame`, `press`, `click`, `hover`, `quit`); output one line per result, `key=value` pairs, exit 1 with `error: <message>` on failure. Start from the probes in the research (the AX status item frame via `kAXExtrasMenuBarAttribute`, `CGWindowListCopyWindowInfo` by pid, `AEDeterminePermissionToAutomateTarget` with `askUserIfNeeded: false`). Compile it once by hand with `swiftc -O -o build/screenshots/uihelper scripts/screenshots/uihelper.swift` and run `perms` and `display` (read-only).
- [X] T029 [US3] Write `scripts/release/tests/test_screenshots.sh` first, with stubs on `PATH` for `uihelper`, `osascript`, `screencapture`, `cwebp`, `dwebp`, `webpmux`, `magick`, `open`, `make`, `pgrep`, and a fake demo log (follow the stub style of `scripts/release/tests/test_build_scripts.sh`). Cases: no argument exits 2; each missing tool or permission, a scale of 1 and a missing notification grant exit 1 with a message naming it and make no appearance call and no quit; a successful run with stubbed captures writes exactly the 22 names into the target and restores the appearance; a capture failure in the dark pass exits 1, leaves a pre-filled target unchanged, restores the appearance and quits the demo; SIGINT during the run exits 130 with the same cleanup; AgentTacho is restarted with `open -b dev.rhuss.agenttacho` only if it ran before; `--first-run` launches the demo once and exits on the log line without capturing; a missing target folder is created; a demo app still running from an earlier run is quit before the first launch; AgentTacho that does not quit within 10 s stops the run with a message and no other change; a status item that `uihelper statusitem` cannot find fails the pass naming `menubar item not found`; a failing appearance switch stops the run and restores what was changed. Add `DEMO` to the unset list at `scripts/release/tests/run.sh:128` (the runner picks up `test_*.sh` files by itself, `run.sh:152`).
- [X] T030 [US3] Write `scripts/screenshots/capture.sh` per `contracts/capture-cli.md` until T029 passes: argument parsing, preflight (FR-018), `--first-run`, `make app-demo`, compile `uihelper` into `build/screenshots/` when missing or older than its source, remember appearance and AgentTacho state, trap on EXIT INT TERM, one pass per appearance (launch demo with `-AppleLanguages '(en)' -AppleLocale en_US -demoScenario default -demoRenderBar <tmp>`, wait for `demo: last frame applied` with a 60 s timeout, capture `alert` from the Notification Center window, open the dropdown with `uihelper click` on the status item, capture `dropdown` by window id with `screencapture -x -o -l`, expand Details and switch modes with `press`, crop `plan-limits`, `pace` (after `hover` on the pace meter and 1.5 s), `budget`, `details`, `harnesses` with `magick -crop` from `frame` values times 2, open Settings and capture `groups`, `menubar-settings` and `prices` (with the OpenAI import preview open), take `menubar` from the rendered PNG, quit the demo), convert with `cwebp -lossless`, validate with `dwebp` and `webpmux -info`, move into the target, print names and sizes (spec 024 FR-017 to FR-023).
- [ ] T031 [US3] `make test-release`; then run quickstart Q6 under `time` (SC-001: under 5 minutes, no manual step) and Q7 on the maintainer's Mac. Commit `feat(screenshots): capture script for the landing page shots`.

**Checkpoint**: US3 complete.

---

## Phase 6: User Story 4 - Release builds stay free of demo code (Priority: P4)

**Goal**: no demo code, scenario or identity can reach a release.

**Independent Test**: quickstart Q1 (`make test-release`), Q2 last two commands.

- [X] T032 [US4] Tests first in `scripts/release/tests/test_makefile.sh`: `make -n app` unsets `DEMO` (extend `test_app_never_passes_update_test_on` at line 36 to expect `env -u DEMO -u UPDATE_TEST -u UPDATE_SOURCE`). Then change the `app:` recipe in `Makefile` (spec 024 FR-002).
- [X] T033 [US4] Tests first in `scripts/release/tests/test_build_scripts.sh`: `release.sh` with `DEMO=1` exits 1 with `error: DEMO is set; release builds never carry the demo flag`, for `--dry-run` and a full release (follow `test_release_refuses_update_test` at line 242); `build-app.sh` with `DEMO=1 UPDATE_TEST=1` exits 1 with `error: DEMO and UPDATE_TEST cannot be combined`; a regular build whose stubbed `nm` lists a `DemoMode` symbol exits 1 with `error: the app links DemoMode symbols`, and passes when it lists none. Then implement in `scripts/release/release.sh` (next to line 34) and `scripts/release/build-app.sh` (the `nm -U "$APP/Contents/MacOS/AgentTacho" | rg -q DemoMode` check after a non-demo build) (spec 024 FR-002, FR-003, SC-006).
- [X] T034 [US4] `make test-release`, `make app` (the real `nm` check passes on a real build), `make app-demo`; quickstart Q2. Commit `feat(release): keep the demo build out of releases`.

**Checkpoint**: US4 complete.

---

## Phase 7: Polish

- [X] T035 [P] Update `README.md` `## Build and run` (around line 57) with `make app-demo`, and `## Development` (around line 209) with `Sources/DemoMode`, `Resources/demo/` and `scripts/screenshots/capture.sh` including `--first-run` and the one-time permissions (Accessibility, Screen Recording, Automation for System Events, notifications for AgentTacho Demo). Leave `## Security and privacy` unchanged (spec 024 FR-024).
- [X] T036 [P] Run `rg -n "\x{2014}|\x{2013}" Sources Tests Resources/demo scripts README.md specs/024-demo-mode-screenshots` and fix any hit.
- [ ] T037 Run `make test`, `make test-release`, `make app`, `make app-demo`. Then run quickstart Q8 with the maintainer: review all 22 images. Record the results of Q1 to Q8 in `specs/024-demo-mode-screenshots/quickstart.md` (a `Result (date):` line under each). Commit `docs: demo build and screenshot capture`.

---

## Dependencies & Execution Order

- Phase 1 then Phase 2 (T003 to T008) block everything.
- US1 (Phase 3) needs Phase 2. Within it: T009, T010, T011 in parallel; T012 after T009; T013 after T010; T014 after T012 and T013; T015 after T014; T016 any time; T017 independent of the Swift tasks; T018 to T021 after T013 and T017; T022 last.
- US2 needs US1 (the app wiring and `ScenarioCoverage`).
- US3 needs US2 (`demo: last frame applied`, the banner) and US1. T026, T028 and T029 can run in parallel; T030 after T028 and T029; T027 after T024.
- US4 needs only T017 (the `DEMO` variable); it can run in parallel with US2 and US3.
- Polish last.

## Parallel examples

- Phase 2: T004 and T006 next to T003.
- US1: T009, T010, T011 and T016 together; T017 next to the Swift work.
- US3: T026 (Swift views), T028 (helper) and T029 (bash tests) together.
- US4 next to US3.

## Implementation strategy

1. **MVP**: Phases 1 to 3. The demo app alone lets the maintainer take every shot by hand, with honest made-up data.
2. **Alert**: Phase 4 adds the timed crossing for the "Alerts and colors" card.
3. **Automation**: Phase 5 makes the shots reproducible with one command.
4. **Guards**: Phase 6 can land any time after T017 and must land before the branch is merged.
