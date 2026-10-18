# Quickstart: Demo build and screenshot capture

Validation scenarios for spec 024. Run on the maintainer's Mac (macOS 14+, Apple Silicon, 2x main display). Contracts: [capture-cli.md](contracts/capture-cli.md), [scenario-format.md](contracts/scenario-format.md).

## Q1: Tests

```bash
make test
make test-release
```

Expected: both pass. `make test` includes the scenario loader, the coverage check of the `default` scenario (FR-014, FR-016, SC-005) for launch dates on the 1st, 15th and last day of a month, and the source-list check (SC-002). `make test-release` includes the demo flag guards (FR-002, SC-006) and the capture script tests with stubs.

Result (2026-10-18): pass. `make test` runs 1444 UsageCore and 50 DemoMode tests, `make test-release` 244 tests, all passing.

## Q2: Demo build and identity

```bash
make app-demo
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "build/AgentTacho Demo.app/Contents/Info.plist"
ls "build/AgentTacho Demo.app/Contents/Resources/demo"
make app
ls build/AgentTacho.app/Contents/Resources | rg demo
```

Expected: `dev.rhuss.agenttacho.demo`; the demo folder lists `default.json` and `litellm-prices.json`; the regular app has no `demo` folder and `make app` passes its symbol check.

Result (2026-10-18): pass. Demo bundle id `dev.rhuss.agenttacho.demo`, `demo/` holds `default.json` and `litellm-prices.json`, the regular app has no `demo` folder, and `make app` passes the `nm` check (0 `DemoMode` symbols; 1500 in the demo binary). `DEMO=1 make dmg` stops with the demo flag error.

## Q3: Isolation (SC-003)

```bash
f=(~/.config/agenttacho/config.json ~/.config/agenttacho/imported-prices.json \
   ~/Library/Application\ Support/agenttacho/last-good.json ~/Library/Logs/agenttacho/usage.log \
   ~/Library/Preferences/dev.rhuss.agenttacho.plist)
shasum "${f[@]}" > /tmp/before.sha
open -n "build/AgentTacho Demo.app" --args -AppleLanguages '(en)' -AppleLocale en_US
# look at the bar and the dropdown for 30 s, open Settings, quit the demo app
shasum -c /tmp/before.sha
```

Expected: all files OK. The installed AgentTacho may keep running during this check; its log may grow, so stop it first if it runs.

Result (2026-10-18): partial. config.json, imported-prices.json and the preferences were unchanged. last-good.json changed because the installed AgentTacho kept running and refreshed during the check (06:24:37Z, its own log). Rerun with AgentTacho quit. `DemoSetupTests` covers the folder isolation.

## Q4: The story (US1, US2)

With the demo app open for at least 15 s:

- Bar: Claude Max with `↑`, Codex with `↗`, Company budget orange, Side project red.
- Dropdown: pace meters on pace (Claude 5-hour), behind (Codex 5-hour), ahead (Claude 7-day); Details > Harnesses lists Claude Code, Codex and OpenCode; no "incomplete" note.
- One notification "Company budget reached 80%" about 12 s after launch.
- Settings > About shows "Build: Demo"; "Check for Updates…" says "Demo build: updates are off".
- Settings > Prices > Import > OpenAI shows a preview at once.

Result (2026-10-18): partial. The demo log shows the launch at 76%, the frame refresh at +13 s with Company budget at 86%, exactly one crossing ("Company budget monthly 80%"), then `demo: last frame applied` and `demo: bar rendered`. The rendered bar shows Claude `70% ↑`, Codex `60% ↗`, Company budget orange, Side project red. The banner did not show because notifications for AgentTacho Demo are off on this Mac. Dropdown, Settings, About and the Prices import still need a visual check. `-demoScenario missing` logged the error and left the demo empty.

## Q5: No network, no credentials (SC-002, manual)

```bash
pid=$(pgrep -f "AgentTacho Demo.app/Contents/MacOS")
nettop -p "$pid" -n -x -L 0 -s 1 | head -20
sudo fs_usage -w -f filesys "$pid" | rg '/\.claude|/\.codex|opencode|Keychains'
/usr/bin/log stream --predicate 'process == "secd"' --style compact
```

Run while opening the dropdown, Settings and the Prices import. Expected: no connection rows for the demo process, no matching file access, no `secd` request from the demo app.

Result (2026-10-18): passed on the second run. The real AgentTacho was quit for the run, because both executables are named `AgentTacho` and `fs_usage` filters by name; the demo app ran alone from 14:55:42 to 14:56:13 while the dropdown, Settings, the OpenAI import preview and both update checks were opened. `nettop`: no row for the demo app. `fs_usage`: no access to `~/.claude`, `~/.codex`, OpenCode's data, a keychain or the `agenttacho` folders; files only in `agenttacho-demo`, the app bundle and system frameworks, plus `/System/Library/Keychains/SystemTrustSettings.plist` read by the system's code signature check. Unified log: no `secd` request for the demo app, no networking subsystem lines. The first run had found three `getattrlist` calls on the `~/.claude` folder itself: `Paths.expand` built paths with `URL.appendingPathComponent(_:)`, which stats the path; it now passes `isDirectory: false`. Note for a rerun: zsh's `log` builtin hides `/usr/bin/log`, so call it by full path.

## Q6: First run and capture (US3)

```bash
scripts/screenshots/capture.sh --first-run "$PWD/build/shots"   # once: allow notifications
scripts/screenshots/capture.sh "$HOME/Work/projects/agenttacho-site/src/assets/agenttacho"
```

Expected: 22 files listed with sizes; light appearance (or dark, whatever was set) restored; AgentTacho running again if it was running. Each image shows English text and US formats.

Result (2026-10-18): open. Needs notification permission for AgentTacho Demo; the script is covered by 17 stub tests in `test_screenshots.sh`.

## Q7: Failure and interrupt (FR-021, FR-022, SC-004)

1. Run the capture against an empty folder and press Ctrl-C during the dark pass. Expected: exit 130, appearance as before, demo app gone, folder still empty.
2. Turn on a Focus mode and run again. Expected: exit 1 naming `alert`, folder unchanged.

Result (2026-10-18): open, after Q6.

## Q8: Review (SC-007)

Open all 22 images. Expected: no real name, no German format, no clipped UI.

Result (2026-10-18): open, after Q6.
