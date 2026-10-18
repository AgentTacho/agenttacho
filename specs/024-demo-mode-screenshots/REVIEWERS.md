# Review Guide: Demo build and screenshot capture

**Generated**: 2026-10-18 | **Spec**: [spec.md](spec.md)

## Why This Change

The landing page needs eleven screenshots that show every current feature, in light and dark. The only screenshot today shows the maintainer's real usage, real account names and German number formats, so it cannot be published. Taking new shots by hand with real data would leak the same things and could not be repeated after a UI change.

## What Changes

A dev-only "AgentTacho Demo" app shows a scripted, made-up story (Claude Max, Codex on ChatGPT Plus, a shared "Company budget", a "Side project" budget) with every visual state the site needs, and fires one real threshold notification shortly after launch. It runs next to the installed AgentTacho without touching its settings, reads no credentials or agent files and makes no network request. A capture script drives the demo app in light and dark appearance and writes 22 WebP files into a folder, restoring the system afterwards. Release builds, DMGs and the Homebrew cask are unchanged and contain no demo code.

## How It Works

The demo code lives in a new library target `DemoMode` next to `UsageCore`: a JSON scenario model (times relative to launch, timed frames), a scenario player, and three demo sources (Claude windows, Codex limits, usage records) that plug into the existing `RefreshCoordinator`. The app references `DemoMode` only under the compile flag `AGENTTACHO_DEMO`; `make app-demo` builds with it into a separate scratch path and gives the bundle its own identifier and `agenttacho-demo` folders. Under the flag the app writes the scenario's configuration at launch, skips the credential reader, the last good store, the updater, the login item and credential alerts, serves the LiteLLM preview from a bundled file, and schedules one refresh per frame. The capture script uses a small Swift helper for Accessibility (status item, buttons, element frames), window ids and permission checks; the demo app draws the menu bar item itself on a transparent background. `build-app.sh` fails a regular build whose binary links any `DemoMode` symbol, and `make release` refuses the `DEMO` variable.

## When It Applies

**Applies when**:
- The maintainer builds `make app-demo` or runs `scripts/screenshots/capture.sh` on their Mac (Apple Silicon, 2x main display, permissions granted once).
- The site's Task 9 needs fresh screenshots, now or after a UI change.

**Does not apply when**:
- Building, releasing or installing AgentTacho for users: nothing changes there.
- Working in the site repository: swapping in the images and launching the page is stream C's Task 9.
- Other display setups (1x displays, Intel Macs): the script stops with a message instead of supporting them.

## Key Decisions

1. **Compile-time flag, not a launch argument.** Alternatives: a hidden argument in release builds. Chosen so release builds cannot contain demo paths and the README's privacy section stays true without changes.
2. **A separate `DemoMode` target with a symbol guard.** Alternatives: demo types in `UsageCore` (would ship in every release) or `#if` inside `UsageCore` (tests would run a different build than the release). This deviates from "logic in UsageCore" in AGENTS.md, justified in the plan's Complexity Tracking.
3. **Three demo sources instead of one.** A source returns one kind of value per refresh; a combined output case would touch about ten switches in the coordinator for a dev-only feature. The spec's FR-006 was refined to say so.
4. **No injected observation history.** The observation log is internal and the recent-rate path needs 15 minutes of observations. The scenario picks values for which the app's own logic yields the intended pace states and markers from the current values alone.
5. **One extra account ("Side project").** Markers show only on uncolored entries, so `↗`, `↑`, orange and red need four bar entries. The brainstorm's Company budget stays as decided.
6. **The menu bar shot is rendered, not captured.** On macOS 26 the menu bar has no background of its own and the status item window belongs to Control Center, so a region capture would include wallpaper and other items.
7. **Transactional output.** The script writes to a temporary folder and moves files only when all 22 are valid, so a failed run never leaves a mixed set in the site repository.

## Areas Needing Attention

- **Monthly budget clamp** (research R6): records before the first of the month are moved into it, so a capture on the 1st still shows a full budget. This changes the per-day trend shape near month starts. Is that acceptable for marketing shots?
- **UI scripting is fragile across macOS versions.** The helper relies on the Accessibility tree for the status item and on Notification Center's window for the banner. Errors should name exactly what was not found.
- **Accessibility identifiers in all builds** (T026). They are invisible, but they are a small change to release code for a dev tool.
- **Notification permission check** reads the demo app's own log line. The system's notification preferences hold the same data in an undocumented format, deliberately not used.
- **SC-002 is partly manual**: `fs_usage` needs sudo and keychain reads go through `secd`. The automated part is a source list check and a source text scan of `DemoMode`.

## Open Questions

No open questions identified.

## Review Checklist

- [ ] Key decisions are justified
- [ ] Breaking changes are documented with migration guidance (none expected)
- [ ] Scope matches the stated boundaries
- [ ] Success criteria are achievable
- [ ] No unstated assumptions
- [ ] Nothing under `#if AGENTTACHO_DEMO` leaks into the regular build path
- [ ] The README's "Security and privacy" section stays accurate without changes

---

<!-- Code phase sections are appended below this line by the phase-manager command -->
