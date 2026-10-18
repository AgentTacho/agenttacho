# Code Review: Demo build and screenshot capture

**Spec:** specs/024-demo-mode-screenshots/spec.md
**Date:** 2026-10-18
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 95% (41 of 43)**

- Functional requirements: 23 of 24 compliant, 1 partial (FR-018)
- Success criteria: 6 of 7 compliant or covered by a manual quickstart step, 1 partial (SC-002)
- Edge cases: 12 of 12

The manual checks (SC-001, SC-003 rerun, SC-004 on the real Mac, SC-007, quickstart Q4 to Q8) are not deviations. They are open and recorded in quickstart.md.

## Functional requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `Makefile` app-demo, `scripts/release/lib.sh` release_defaults (APP, BUNDLE_ID), `build-app.sh` PlistBuddy identity and signing identifier; single instance, defaults and notifications key on the bundle id | Compliant |
| FR-002 | `make app` unsets DEMO, `release.sh` refuses DEMO (also `make dmg`), `build-app.sh` refuses DEMO with UPDATE_TEST | Compliant |
| FR-003 | `Package.swift` adds DemoMode to the executable only with DEMO=1; `build-app.sh` nm guard; Resources/demo copied only for the demo app | Compliant |
| FR-004 | `AboutSettingsTab.swift` "Build: Demo" row, `DemoRun.start` log line; no other marker | Compliant |
| FR-005 | `AppModel.dataPaths` = `Paths(appFolder: "agenttacho-demo")`; `DemoSetup.prepare/clear` write only there | Compliant |
| FR-006 | `DemoSetup.sources` (three demo sources), `NoCredentials`; scenario codexHome is a demo path, so validation never resolves `~/.codex` | Compliant |
| FR-007 | `Updater.start/runCheck` demo branches, `previewProviderImport` reads `demo/litellm-prices.json` | Compliant |
| FR-008 | `applyStartAtLogin` no-op, credential tracker calls compiled out | Compliant |
| FR-009 | `DemoRun.start` calls `DemoSetup.prepare` before the stores read; last-good deleted; no LastGoodStore | Compliant |
| FR-010 | `Scenario.swift` | Compliant |
| FR-011 | `ScenarioDuration`, reset times from launch; imports dated launch minus one day | Compliant |
| FR-012 | `DemoRun.scheduleFrames` (offset + 0.5 s, at once when past); live run applied the 12 s frame at +13 s | Compliant |
| FR-013 | `-demoScenario`, `DemoRun.start` error path, dropdown "Demo scenario error" label, `DemoSetup.clear` | Compliant |
| FR-014 | `Resources/demo/default.json`, `DefaultScenarioTests` coverage at three launch dates | Compliant |
| FR-015 | `DefaultScenarioTests.demoFileUsesInventedNamesOnly` | Compliant |
| FR-016 | `DefaultScenarioTests` (all scenarios load, coverage, crossing, names) | Compliant |
| FR-017 | `capture.sh` argument parsing, `mkdir -p` target, `make app-demo` | Compliant |
| FR-018 | `capture.sh` preflight: tools, Accessibility, Screen Recording, Automation, 2x display, notification authorization from the demo log, `--first-run` | Partial: "banners allowed" is not checkable; the log shows only granted or denied. A banner that does not show fails the `alert` shot, so no partial set is written |
| FR-019 | eleven stems in `capture.sh`, bar rendered by `DemoRun.renderBar` | Compliant |
| FR-020 | quit and restart of AgentTacho, English and en_US launch arguments | Compliant |
| FR-021 | one pass per appearance, `alert` first after `demo: last frame applied`, cleanup trap on EXIT, INT, TERM | Compliant |
| FR-022 | temporary folder, all 22 validated with dwebp before the move; failures name the failing shot and every shot not captured | Compliant (fixed in this review) |
| FR-023 | `finish` prints name and pixel size | Compliant |
| FR-024 | README Build and run, Development; Security and privacy unchanged | Compliant |

## Success criteria

- SC-002 Partial: `make test` checks the demo source list and scans the DemoMode sources for network and credential types. The app-side branches (updater, LiteLLM preview) are compiled code in the executable target and are covered only by quickstart Q5, not by `make test`.
- SC-005, SC-006: covered by `make test` and `make test-release`.
- SC-001, SC-003, SC-004, SC-007: manual, open (quickstart Q3 rerun, Q6 to Q8). SC-004 is covered by stub tests.

## Extra behavior (not in the spec)

- `Package.swift` makes the DemoMode dependency conditional on DEMO=1. Needed for FR-003 because dead stripping kept about 1500 DemoMode symbols. Recorded in research R2.
- `BarLayout.shotBudgetOwner` (UsageCore, tested) picks the budget whose row and details carry the capture identifiers.
- Claude Code on Vertex records in the Company budget, so one Details table shows all three harnesses for the `harnesses` shot (tested).
- `DemoSetup.clear` empties the demo folders when a scenario cannot be played (FR-013 "stays empty").
- `DemoSetup.prepare(launch:)` dates the imported prices one day before launch (FR-011).

All are helpful and inside the spec's intent.

## Spec evolution candidates

- FR-018: say that the notification check reads the authorization result, and that a missing banner fails the `alert` shot.
- SC-002: limit the automated check to the DemoMode target and name quickstart Q5 for the app layer.

## Conclusion

The code matches the spec apart from two wording-level gaps that the spec cannot be met to the letter on (banner style, unit-testing the executable). No critical findings. Ready for the deep review.
