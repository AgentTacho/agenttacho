# Quickstart: Burn Rate Escalation

## Prerequisites

- macOS 14+, the project's toolchain (see `Makefile`).
- Build and test only through the Makefile.

## Automated validation

```bash
make test
```

Expected: all suites pass, including the new `BurnRateTests` and `ObservationLogTests` and the extended `BarLayoutTests`, `BarPresentationTests`, `PaceTests` and `RefreshCoordinatorTests`. These cover the spec's acceptance scenarios with fixed dates (US1 AS1 to AS4, US2 AS1 to AS3, US3 text and accessibility) and the edge cases (lookback boundary, minimum span and change, reset and budget changes, price changes, stale entries, run-out already passed).

## Manual validation

1. `make app` and launch the app with a Claude subscription and a budget configured.
2. Run an agent for at least 15 minutes so the 7-day window or a budget rises by 2 points or more. Expected: when that rate is at least twice the sustainable rate, the bar entry shows `↑` instead of `↗` (or instead of no marker), unless `⚠` or `‼` shows.
3. Open the dropdown and hover the pace meter of that window. Expected: "<delta> · burning fast · runs out <time>", meter in orange (`contracts/burn-rate-display.md`).
4. Open Settings, Menu Bar tab. Expected: the toggle reads "Show ↗ or ↑ when an entry will run out before it resets"; turning it off removes both markers from the bar and the preview, the dropdown text stays.
5. Quit and relaunch. Expected: no new file in AgentTacho's data directory; `↑` from a recent burst needs 15 minutes of new observations again (values restored at launch may count as the first one).
6. Check the diagnostic log: no new request lines compared with before the feature.
