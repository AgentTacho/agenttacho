# Quickstart: Threshold Levels and Budget Direction

## Automated checks

```bash
make test           # UsageCore and DemoMode tests, including the new level, direction and text tests
make test-release   # release script tests (no shot list change expected)
```

Expected: all pass. `DefaultScenarioTests.defaultScenarioCoversTheShotList` asserts a row that is critical below 100% and keeps its earlier checks.

## Manual check in the demo build

```bash
make app-demo
```

1. **Threshold-driven red (US1).** Open the dropdown. The Side project budget (thresholds 75 and 85) shows its percent and bar in red at about 87%, and its menu bar entry is red. Claude Max's 7-day row keeps its orange bar and pace note; its percent is primary at 70% (below 80).
2. **Warning percent.** Change Claude Max's first threshold to 60 in Settings. The 7-day percent turns orange, its bar stays orange for pace only; the 5-hour percent (58%) stays primary.
3. **Direction (US2).** Settings, General, Display, "Show usage as": Remaining. The bar reads `✳ 5h 42%`, rows read 100 minus their used percent, bars fill to the remaining share, markers read `↘`/`↓`, budget lines read "$X left of $Y/period". Colors stay the same as in Used.
4. **Over budget (US3).** A budget above 100% (the Team budget of the `variants` scenario; otherwise covered by the UsageCore tests) reads "−N%" in red with an empty bar and "$N over $B/period" in Remaining.
5. **Thresholds editor (US4).** In Remaining, an account's fields read 20 and 0 with "% left". Enter 30: the configuration file stores 70. Switch back to Used: the field reads 70.
6. **Switch back.** Choose Used: everything returns to today's look at once.

## Screenshots

Capture only after asking the maintainer (AGENTS.md, step 4): `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho`.
