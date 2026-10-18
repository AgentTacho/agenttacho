# Research: Demo build and screenshot capture

Findings from the code (2026-10-17) and from read-only probes on the maintainer's Mac (macOS 26.7, Swift 6.4, M4 Pro, external 2x display). File references are to the state of `main` at `c738746`.

## R1: Build flag and identity

**Decision**: Follow the update-test precedent. `make app-demo` runs `DEMO=1 bash scripts/release/build-app.sh`; `make app` runs `env -u DEMO -u UPDATE_TEST -u UPDATE_SOURCE ...`. With `DEMO=1`, `build-app.sh` compiles with `-Xswiftc -DAGENTTACHO_DEMO` into a separate scratch path `.build/demo`, assembles `build/AgentTacho Demo.app`, sets `CFBundleIdentifier` to `dev.rhuss.agenttacho.demo` and `CFBundleName`/`CFBundleDisplayName` to `AgentTacho Demo` with PlistBuddy, signs with that identifier, and copies `Resources/demo/` into `Contents/Resources/demo/`. `DEMO=1` together with `UPDATE_TEST=1` is refused. `release.sh` refuses `DEMO` like it refuses `UPDATE_TEST` (`release.sh:33-34`), and `scripts/release/tests/run.sh:128` unsets `DEMO` per test.

**Rationale**: The precedent is tested (`test_makefile.sh:36-57`, `test_build_scripts.sh:214-251`) and reviewers know it. A separate scratch path keeps the flagged objects out of `.build/release`, so a later `make app` or `make release` can never pick up a demo-compiled module. Today `APP` is fixed in `lib.sh:54` and the bundle identifier comes from the static `Resources/Info.plist:9-16`, so both need an override for the demo build only.

**Alternatives considered**: A launch argument in release builds (rejected in brainstorm 18: release builds must not contain demo paths). A separate Xcode-style scheme (the project has no Xcode project).

## R2: Where the demo code lives

**Decision**: A new library target `DemoMode` (depends on `UsageCore`) holds the scenario model, the scenario player, the three demo sources and the coverage helpers, with tests in a new test target `DemoModeTests`. The `AgentTacho` executable depends on `DemoMode` but references it only inside `#if AGENTTACHO_DEMO`. A regular build therefore links no `DemoMode` symbol (SwiftPM links release executables with dead stripping). `build-app.sh` checks this after every non-demo build: `nm` on the binary must list no `DemoMode` symbol, otherwise the build fails.

**Rationale**: AGENTS.md puts logic in a tested core target; `UsageCore` would carry demo types into every release binary. A separate target keeps the logic testable through `make test` and makes the release guard a precise symbol check (FR-003, SC-006).

**Alternatives considered**: Demo types in `UsageCore` under `#if AGENTTACHO_DEMO` (then `make test` would need the flag and would test a different build than the release). Demo types in the app target (not testable with Swift Testing, against AGENTS.md).

**Correction during implementation (2026-10-18)**: dead stripping does not remove the target. With an unconditional dependency, a regular `make app` binary listed about 1500 `DemoMode` symbols, because Swift type metadata and conformance records stay live. `Package.swift` therefore adds the `DemoMode` dependency to the executable only when `DEMO=1` is in the environment, which only `make app-demo` sets (its builds use the separate `.build/demo` scratch path). A regular build then lists 0 `DemoMode` symbols, and the `nm` guard in `build-app.sh` stays as the check.

## R3: One source per kind of value

**Decision**: Three sources, `DemoSubscriptionSource` (`.subscriptions`), `DemoCodexLimitsSource` (`.codexLimits`) and `DemoRecordSource` (`.records`), share one `ScenarioPlayer`. None conforms to `NetworkBoundSource`, `SavedValuesSource`, `EndpointGatedSource` or `WindowSensitiveSource`.

**Rationale**: `SourceOutput` is an enum (`RefreshCoordinator.swift:41-51`); a source returns one kind per `collect`. Adding a combined case would touch about ten switches in the coordinator for a dev-only feature. Without `SavedValuesSource`, `publishSavedValues()` yields nothing (`RefreshCoordinator.swift:264-278`), so no last good values are used. Without `NetworkBoundSource`, `EndpointPolicy.decide` always fetches (`EndpointPolicy.swift:93`). The spec's FR-006 was refined accordingly.

## R4: Pace, markers and history

**Decision**: No observation history. Every refresh reports `fetchedAt`/`observedAt = context.now`; the scenario chooses used percent and reset time so the app's own logic yields the intended states. The observation log fills by itself across refreshes, which does not matter for a run of a few minutes.

**Rationale**: `ObservationLog`, `RateObservation` and `UsageSnapshot.observations` are internal (`ObservationLog.swift:54`, `UsageSnapshot.swift:512`), and the recent rate needs observations at least 15 minutes apart (`BurnRate.swift:26-33`). The average-rate path does not need history: `↑` shows when `pace.runOut` is set and used/elapsed is at least twice the sustainable rate. At elapsed share `s`, `↑` needs used ≥ 200·s/(1+s), `↗` needs ahead by more than 5 points but less than that (`Pace.swift:29-31`, `BarLayout.swift:215`). Markers show only for entries below the lowest threshold (80 by the scenario's thresholds). Pace states: on pace if |used − 100·s| ≤ 5, ahead above, behind below (`Pace.swift:43`).

**Consequence for the story**: `↗` and `↑` must sit on bar entries whose window position the scenario controls: the Claude 7-day window (reset time) and the Codex weekly window. Monthly budgets follow the calendar month, so their elapsed share depends on the date of the capture.

## R5: Bar entries for the story

**Decision**: Five bar entries: Claude Max (7-day, `↑`), Codex on ChatGPT Plus (weekly, `↗`), "Company budget" (monthly group of a Vertex account and an OpenAI API account, orange after the frame), "Side project" (an OpenAI API account with its own weekly budget, red, over its limit), and the Claude 5-hour window is not in the bar. FR-014 allows extra accounts.

**Rationale**: Markers need normal level, so `↗`, `↑`, orange and red need four different entries. The brainstorm's group stays exactly as decided; the extra account carries the "over its limit" budget for the "Budgets you set" card, and the group carries "near its limit".

## R6: Monthly budget on any day

**Decision**: `DemoRecordSource` keeps each record's offset relative to launch, except that a record of an account in a monthly budget that would fall before the start of the current month is moved to the start of the month plus its time of day. The coverage test runs the scenario with launch dates on the 1st, the 15th and the last day of a month.

**Rationale**: Budget spend is summed over the current period (`Aggregator.swift:60-85`). Without the clamp, a capture on the 1st or 2nd shows an almost empty Company budget. The clamp only changes where records appear in the per-day trend, never the total.

## R7: Prices

**Decision**: The scenario carries an imported OpenAI price batch (written to the demo's `imported-prices.json` at launch, FR-009) for the OpenAI models it uses; Claude models (direct and on Vertex) use the built-in table. The coverage test asserts that no budget or token account is `incomplete`.

**Rationale**: `prices.json` holds only Claude models (12 entries); OpenAI and Gemini prices come only from imports or overrides (`ImportedPrices.swift:7`). Imported prices also make the Prices tab look used.

**LiteLLM preview**: Under the demo flag, `AppModel.previewProviderImport` (`App.swift:266-282`) reads `demo/litellm-prices.json` from the app bundle instead of `LiteLLMImporter().fetch()`, with origin `demo`. Everything after it (`LiteLLMImporter.batch`, the diff, `PriceImportSheet`) stays the same. The file uses LiteLLM's format, like `Tests/UsageCoreTests/Fixtures/litellm/excerpt.json`, with made-up prices that differ a little from the scenario's imported batch, so the preview shows changes.

## R8: App wiring under the flag

**Decision**: In `AppModel.init` (`App.swift:79-181`), `#if AGENTTACHO_DEMO` replaces:

| Real | Demo |
|---|---|
| `Paths()` | `Paths(appFolder: "agenttacho-demo")`: new `appFolder` parameter in `Paths`, default `agenttacho` |
| `SecurityToolCredentialReader` and the `makeDefault` keychain probe | `DemoMode.NoCredentials` (always "none"); the scenario's configuration is written before the store loads |
| `LastGoodStore.load` and the store | not created; the demo deletes its own `last-good.json` at launch |
| the five sources | the three demo sources |
| `Updater.start()` and `runCheck` | early return with the new `UpdateState.demoBuild` ("Demo build: updates are off") |
| `applyStartAtLogin` (`App.swift:394-412`) | no-op |
| credential notifications (`App.swift:236-239`, `477-480`) | not sent |

It also schedules one refresh per frame at `launch + offset + 0.5 s` (FR-012), logs `demo build, scenario <name>` at launch, and the About tab shows a "Build: Demo" row. Bundle-keyed parts need no change: the single-instance check (`SingleInstance.swift:16-32`), `@AppStorage` defaults and notification permission all key on `Bundle.main.bundleIdentifier`.

**Scenario choice**: launch argument `-demoScenario <name>` (read from `UserDefaults` argument domain), default `default`. A failed load is shown in the dropdown's existing error area and logged; no source is registered.

## R9: Threshold crossing

**Decision**: The Company budget starts at 76% and a frame at 12 s adds records that bring it to 86%: one notification "Company budget reached 80%". Thresholds `[80, 100]` are set explicitly in the scenario (the configuration default is `[]`, `Configuration.swift`). Only one entry crosses a threshold between the first refresh and the last frame; every other entry is already past its thresholds at launch (the first observation is the baseline, `ThresholdTracker.swift:262`).

## R10: Capture mechanics on macOS 26

**Decision**: `scripts/screenshots/capture.sh` (bash) plus one Swift helper `scripts/screenshots/uihelper.swift`, compiled by the script with `swiftc` into `build/screenshots/uihelper`. Subcommands:

| Subcommand | Use |
|---|---|
| `perms` | `AXIsProcessTrusted()`, `CGPreflightScreenCaptureAccess()`, Automation for System Events (`AEDeterminePermissionToAutomateTarget`, no prompt) |
| `display` | backing scale of the main display (must be 2) |
| `statusitem <pid>` | frame of the app's status item through Accessibility (`kAXExtrasMenuBarAttribute`); on macOS 26 the status item window belongs to Control Center, so window lists cannot find it |
| `windows <pid>` | window id, layer, frame and title (`CGWindowListCopyWindowInfo`), matched by pid because owner names are localized |
| `frame <pid> <identifier>` | screen frame of an element by accessibility identifier |
| `press <pid> <identifier or title>` | AX press (tabs, buttons, menu items) |
| `click x y`, `hover x y` | `CGEvent` mouse events; tooltips need `.mouseMoved` and about 1.5 s |
| `quit <bundle-id>` | `NSRunningApplication.terminate()` and wait; avoids per-app Automation prompts |

Other choices:

- **Appearance**: read with `osascript ... get dark mode`, set with `... set dark mode to <bool>` through System Events (Automation permission, checked by `perms`).
- **Windows and crops**: the dropdown (layer 101) and the Settings window are captured by id with `screencapture -x -o -l <id>` (2x on a 2x display, verified: 1280×681 pt gave 2560×1362 px). Card crops (`plan-limits`, `pace`, `budget`, `details`, `harnesses`) are cut from the window image with ImageMagick using element frames from `frame`, times 2. This needs `.accessibilityIdentifier`s on a few views (none exist today): the Claude plan section, the pace meter, a budget row, the Details disclosure and its mode picker, the status item button.
- **Menu bar item**: drawn by the demo app, not captured. With `-demoRenderBar <dir>`, the demo app renders its bar label view with `ImageRenderer` at scale 2 on a transparent background, once per appearance, after the last frame, and writes `menubar-light.png` and `menubar-dark.png`. The macOS 26 menu bar has no background of its own, so a region capture would include the wallpaper and neighboring items.
- **Notification banner**: owned by Notification Center (one full-screen window at layer 21, offscreen when idle). The script waits until it is on screen, captures it by id and trims the transparent area with `magick -trim +repage`.
- **Notification permission**: the demo app logs its authorization result (`[notifications] authorization granted|denied|error`) at launch; the script reads the demo log. The `group.com.apple.usernoted` preferences store it too, but the flag layout is undocumented, so the log is the check. `--first-run` launches the demo app alone so macOS asks, then waits for the log line.
- **WebP**: `cwebp -lossless` (libwebp 1.6 is installed); validation with `dwebp ... -o /dev/null` and sizes with `webpmux -info`. `sips` cannot write WebP.
- **Quit and restart AgentTacho**: `uihelper quit dev.rhuss.agenttacho`, restart with `open -b dev.rhuss.agenttacho`.
- **Launch**: `open -n "build/AgentTacho Demo.app" --args -AppleLanguages '(en)' -AppleLocale en_US -demoScenario default`.

**Tools**: cwebp, dwebp, webpmux, magick, swiftc, osascript, screencapture, plutil are present; cliclick is not and is not needed.

## R11: Verifying "no network, no credentials" (SC-002)

**Decision**: Automated: `DemoModeTests` assert that the demo source list contains no `NetworkBoundSource`, `SavedValuesSource` or `EndpointGatedSource`, and that the `DemoMode` target imports no networking or credential types (a source-level check of its import list and type references). Manual, once per release of the feature: `nettop -p <pid> -n -x -L 0 -s 1` (no sudo) during a capture shows no connection; `sudo fs_usage -w -f filesys <pid>` shows no access to `~/.claude`, `~/.codex`, OpenCode's folder or `Library/Keychains`. Data-protection keychain reads go through `secd`, so `log stream --predicate 'process == "secd"'` is watched as well.

## R12: Tests for the capture script

**Decision**: `scripts/release/tests/test_screenshots.sh`, run by `make test-release` with the existing runner and a stubbed `uihelper`, `osascript`, `screencapture`, `cwebp`, `open`: argument handling, preflight messages and stop before any change, the trap restoring appearance and quitting the demo on failure and on SIGINT, transactional output (target untouched on failure, 22 files on success), restart of AgentTacho only if it ran before.

**Rationale**: The runner and stub style already exist (`scripts/release/tests/run.sh`); a second runner would duplicate them.
