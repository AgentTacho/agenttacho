# Contract: build targets and capture script

## Make targets

| Command | Result |
|---|---|
| `make app-demo` | `build/AgentTacho Demo.app`, bundle id `dev.rhuss.agenttacho.demo`, compiled with `AGENTTACHO_DEMO` in `.build/demo`, holds `Contents/Resources/demo/*.json` |
| `make app` | unchanged; unsets `DEMO`; fails if the binary links any `DemoMode` symbol |
| `make release`, `make dmg` | fail with `error: DEMO is set; release builds never carry the demo flag` when `DEMO` is set |
| `DEMO=1 UPDATE_TEST=1 ...build-app.sh` | fails with `error: DEMO and UPDATE_TEST cannot be combined` |

## Demo app launch arguments

| Argument | Effect |
|---|---|
| `-demoScenario <name>` | scenario to play, default `default` |
| `-demoRenderBar <dir>` | after the last frame, writes `menubar-light.png` and `menubar-dark.png` (2x, transparent) into `<dir>` and logs `demo: bar rendered` |

The demo log is `~/Library/Logs/agenttacho-demo/usage.log`. Lines the script relies on: `demo build, scenario <name>`, `demo: last frame applied`, `demo: bar rendered`, `[notifications] authorization granted|denied|error`, `[notifications] alert style banner|alert|none` (after a granted authorization), `[notifications] sent: <name> (<id>) ...` (the crossing's notification was posted).

## `scripts/screenshots/capture.sh`

```text
scripts/screenshots/capture.sh [--first-run] <target-dir>
```

| Exit | Meaning |
|---|---|
| 0 | all 22 files written to `<target-dir>`, list printed with pixel sizes |
| 1 | preflight failed (nothing changed) or a capture failed (target unchanged, appearance restored) |
| 2 | usage error |
| 130 | interrupted (same cleanup as 1) |

Order of work:

1. Preflight (FR-018): tools (`swiftc`, `cwebp`, `dwebp`, `webpmux`, `magick`, `osascript`, `screencapture`), `uihelper perms` (Accessibility, Screen Recording, Automation for System Events), `uihelper display` is 2, Appearance not set to Auto, demo notification permission granted per the demo log. Each failure prints what is missing and where to fix it.
2. `--first-run`: launch the demo app, wait up to 120 s for the authorization log line and then the alert style line, quit it, exit 0 only for granted and Banners. No capture.
3. `make app-demo`, then a short launch of the demo app (AgentTacho may still run; the two never meet) that must log `alert style banner` within 30 s; the demo app is quit again. Nothing else has changed yet.
4. Remember the appearance and whether AgentTacho runs; quit AgentTacho. Install the cleanup trap.
5. For `light`, then `dark`: set the appearance, quit any demo app, launch it with English and `en_US`, `-demoScenario default -demoRenderBar <tmp>`; wait for `demo: last frame applied`; capture `alert` from the banner, only when the banner shows the crossing's title; capture `dropdown`, `plan-limits`, `pace`, `budget`, `details`, `harnesses` from the dropdown; capture `groups`, `menubar-settings`, `prices` from Settings; take `menubar` from the rendered PNG; quit the demo app. The two region shots (`pace`, `prices`) wait until no banner is on screen and fail when another app's window lies over the region.
6. Convert to WebP, validate all 22, move them into `<target-dir>`, print the list.
7. Cleanup (also from the trap): restore the appearance, quit the demo app, start AgentTacho if it ran before, remove the temporary folder.

Output files: `<stem>-light.webp` and `<stem>-dark.webp` for `menubar`, `plan-limits`, `pace`, `budget`, `groups`, `details`, `alert`, `prices`, `menubar-settings`, `harnesses`, `dropdown`.
