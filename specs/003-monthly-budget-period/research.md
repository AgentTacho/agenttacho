# Research: Monthly Budget Period

All decisions below were made against the current code on `main` (commit 1777675 and later). No external research was needed; every unknown is a design choice inside the existing architecture.

## R1: Computing the monthly window

- **Decision**: `calendar.dateInterval(of: .month, for: now)` with the injected `Calendar` (its time zone is the Mac's local zone in production, fixed in tests). The result is `[1st 00:00 local, next 1st 00:00 local)`.
- **Rationale**: Calendar arithmetic handles 28 to 31 day months and DST transitions (a month containing a DST change is 1 hour shorter or longer than `days * 86400`). To follow a time zone change at the next refresh (FR-016, edge cases), the coordinator's default calendar becomes `Calendar.autoupdatingCurrent` instead of a `Calendar.current` value captured at init.
- **Alternatives considered**: Building the start from date components and adding `days * 86400`: wrong across DST. Adding a month to the start with `date(byAdding: .month)`: equivalent but needs two calls; `dateInterval(of:)` is one call and the idiomatic API.

## R2: Several windows in one refresh (collection window)

- **Decision**: Each refresh resolves the weekly window as today (`WindowResolver.resolve`) and, when at least one monthly group exists, the monthly window. The record source receives a **collection window** that spans the earliest start of all needed windows to the latest end. The aggregator then filters per group. `RefreshContext.window` becomes this collection window; the weekly window is passed to the aggregator separately.
- **Rationale**: `LogIndex` keeps one record set pruned to `timestamp >= window.start` and resets when the start moves earlier. Giving it the union start keeps a single index and a single scan, so the cost of a monthly group is only the extra records kept in memory (up to 31 days instead of 7), well within SC-004 of spec 001 (spec 003 SC-006). The existing "re-run window-sensitive sources when the start moved earlier" logic (T040) keeps working unchanged when it compares collection starts instead of weekly starts.
- **Alternatives considered**: One `LogIndex` per period: duplicates scanning and parsing work for no gain. Always collecting 31 days even with no monthly group: wastes memory for weekly-only users and changes the diagnostic log line for them.

## R3: Where per-group windows live in the snapshot

- **Decision**: `GroupEntry` gains `period: BudgetPeriod` and `window: DateInterval` (its `resetAt` stays `window.end`). `UsageSnapshot.window` and `windowSource` keep meaning the weekly window, which still drives the Unassigned entry and subscription-account breakdowns (FR-009). The breakdown of a token-based account is computed over its group's window (FR-008, FR-013).
- **Rationale**: Minimal change for existing consumers (dropdown, notifications, refresh log): only code that needs the group window reads the new field.
- **Alternatives considered**: Replacing `snapshot.window` with a dictionary of windows: touches every consumer and the stale-carry-over logic for no user-visible benefit.

## R4: Threshold state per period

- **Decision**: `WindowKind` gains `.monthly` (display name "monthly"). The tracker key of a group is `(groupId, group.period.windowKind)`. A period switch therefore makes the old key non-live (its state is dropped by the existing "entities no longer configured lose their state" filter) and the new key starts with a baseline observation (FR-017). Month rollover and a time zone change both change `windowEnd`, which the tracker already treats as a reset (FR-016).
- **Rationale**: Reuses the existing reset and baseline mechanics; no new state machine. Notification text and the notification identifier already derive from `windowKind`, so "monthly window at 55%" comes for free (FR-015).
- **Alternatives considered**: Keeping `.weekly` for all groups and relying only on `windowEnd` changes: a weekly window ending exactly at a month boundary would not reset on a switch, violating FR-017.

## R5: Configuration format and legacy decoding

- **Decision**: `BudgetGroup` stores `period: BudgetPeriod` (`"weekly"` or `"monthly"`, raw-value `String` enum) and `budgetUSD: Decimal`. Decoding:
  1. `period` absent → weekly; present with another value → decode error (FR-004a).
  2. `budgetUSD` present → used; legacy `weeklyBudgetUSD` ignored.
  3. Else `weeklyBudgetUSD` present and period weekly (explicit or absent) → used as `budgetUSD`.
  4. Else (no amount, or monthly with only the legacy amount) → decode error.
  Encoding always writes `period` and `budgetUSD`, never `weeklyBudgetUSD` (FR-004).
- **Rationale**: A decode error already rejects the whole file and keeps the last valid configuration (spec 001 FR-033, config contract rule on wrong types), so FR-004a needs no new error path. `ConfigStore.load` never writes, so a legacy file is only rewritten when the user saves from settings (FR-004).
- **Alternatives considered**: Bumping `version` to 2 with a migration: unnecessary because both forms decode unambiguously, and it would make a downgrade impossible for files that were never edited.

## R6: Per-day trend for a 31-day window

- **Decision**: `Aggregator.perDay` takes an explicit last day. Weekly windows keep today's behaviour (every day of the window, including future days shown as 0). Monthly windows end at today (FR-013: "from the 1st up to today"). In the dropdown, `BreakdownView` lays the day row out as a grid that wraps after 7 columns; weekly columns keep the weekday initial, monthly columns are labelled with the day of the month.
- **Rationale**: Seven columns already fit the dropdown at `minWidth: 34`, so wrapping at 7 keeps a 31-day trend within the existing width with at most 5 rows (SC-006, no horizontal scrolling). Showing future days of a month would add up to 30 zero columns of noise.
- **Alternatives considered**: A sparkline chart: new visual vocabulary and loses exact values. Horizontal scrolling: rejected by SC-006.

## R7: Period-dependent wording

- **Decision**: `BudgetPeriod` exposes the strings the UI needs: `adjective` ("weekly"/"monthly"), `perUnit` ("per week"/"per month"), `budgetLabel` ("Weekly budget"/"Monthly budget"). Settings, the group summary, the thresholds editor description, the validation message, the breakdown legend, and notifications use them (FR-014, FR-019).
- **Rationale**: One source of truth for wording, testable in `UsageCore` without UI tests.
- **Alternatives considered**: Inline string switches in each view: easy to miss one label.

## R8: Settings for the week alignment

- **Decision**: The "Weekly window" section in `SettingsView` stays as is and gets one caption: "Applies to weekly budget groups and the Unassigned entry. Monthly groups always run from the 1st to the end of the month." (FR-020).
- **Rationale**: Smallest change that removes the confusion a monthly-only user could have.

## R9: Session logs older than the harness retention

- **Decision**: No change. Usage from deleted logs is not counted, as documented in the spec's edge cases and assumptions.
- **Rationale**: Out of scope per the spec; the app keeps no own copy of usage.
