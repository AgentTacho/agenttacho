# Data Model: Fix-Soon Review Batch

No new persisted data and no configuration keys. The changes affect in-memory state and one release variable.

## ThresholdTracker.State (changed behavior)

| Field | Meaning | Change |
|---|---|---|
| `windowStart` | Budget owners only | unchanged |
| `windowEnd` | Identity of the window | unchanged |
| `lastPercent` | Last observed percent, `nil` before the baseline | On a window reset of an existing state: set to 0 instead of `nil` (FR-001) |
| `memberIds` | Budget owners only | A different member set still replaces the state with `lastPercent == nil`, and wins over a reset (FR-002) |

Transitions for one key:

```text
no state ──first observation──▶ baseline (no notification)          [launch, new key: period switch, live-limits toggle, new Codex window]
state ──same window──▶ compare with lastPercent                      [unchanged]
state ──member set differs──▶ baseline (no notification)             [spec 004 FR-015, spec 009]
state ──credential directory / Codex home differs──▶ baseline        [NEW, FR-002, verification follow-up]
state ──budget owner: window end/start differs──▶ compare with 0 (notify crossed)              [NEW, FR-001]
state ──subscription/Codex: known end later than recorded known end──▶ compare with 0           [NEW, FR-001]
state ──subscription/Codex: known end earlier than recorded──▶ observation ignored, state kept  [NEW]
state ──subscription/Codex: to/from unknown reset time──▶ baseline (no notify)                  [unchanged]
```

## Carried-over budget entry (GroupEntry in UsageSnapshot.groups / accountBudgets)

- Validation added after carry-over: `entry.period == owner.budget.period`, otherwise the entry is removed from the snapshot (FR-004). An owner without an entry shows the existing no-data presentation.

## Claude scan directories (derived, not stored)

- `[default ~/.claude] + logDirectories + credentialDirectory of every Claude subscription account`, deduplicated by canonical path (FR-006).

## Release environment variable (new)

| Variable | Values | Meaning |
|---|---|---|
| `ALLOW_TIER_DOWNGRADE` | empty or `1` | Permits a release to fall back from an expired or revoked Developer ID to the next tier (FR-013). Does not replace `ALLOW_ADHOC`. |
