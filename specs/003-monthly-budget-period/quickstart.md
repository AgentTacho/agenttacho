# Quickstart: Monthly Budget Period

## Prerequisites

- macOS 14 or later, Swift 5.10 toolchain (Xcode 16).
- Run from the repository root.

## Automated validation

```bash
make test          # or: swift test
```

Expected: all suites pass, including the new or extended ones:

| Suite | Proves |
|-------|--------|
| `WindowResolverTests` | Monthly window starts at local midnight on the 1st and ends at the next 1st for 28/29/30/31-day months and across a DST change (FR-005, R1) |
| `ConfigurationTests` | Legacy `weeklyBudgetUSD` loads as weekly; new form round-trips; the error rows of [contracts/config-file.md](contracts/config-file.md) are rejected; validation message names the period (FR-001 to FR-004a, FR-019) |
| `AggregatorTests` | Monthly group counts only usage since the 1st; member account breakdown uses the group window; Unassigned stays weekly; monthly per-day trend ends today (FR-008, FR-009, FR-011, FR-013) |
| `ThresholdTrackerTests` | Monthly crossings name the monthly window; month rollover and period switch reset with a baseline (FR-015 to FR-017) |
| `RefreshCoordinatorTests` | Record source receives the collection window spanning the month when a monthly group exists, and only the weekly window otherwise (R2) |

## Manual validation

1. Build and run the app: `make run` (or `swift run AgentTacho`).
2. Open Settings → Accounts, select a budget group, switch **Period** to **Monthly**, keep or change the amount, save.
   - Expected: the group summary reads "$N per month"; the amount field is labelled "Monthly budget".
3. Open the dropdown after the next refresh.
   - Expected: the group shows month-to-date spend of the monthly budget and "resets" at 00:00 on the 1st of next month; Details shows a day row from the 1st to today, wrapped in rows of 7 with day-of-month labels.
4. In Settings → General, check the "Weekly window" section.
   - Expected: a caption says it applies to weekly groups and the Unassigned entry only.
5. Copy a configuration file from the previous version (with `weeklyBudgetUSD`) to `~/.config/agenttacho/config.json` and restart.
   - Expected: groups load as weekly with the same amounts; the file is unchanged until you save from settings, after which it contains `period` and `budgetUSD`.
6. Hand-edit a group to `"period": "monthly"` with only `weeklyBudgetUSD`.
   - Expected: the dropdown shows a configuration error and the previous configuration stays in effect.
