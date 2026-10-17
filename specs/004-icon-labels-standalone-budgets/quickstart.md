# Quickstart: Icon Labels and Standalone Budgets

## Prerequisites

- macOS 14 or later, Swift 5.10 toolchain.
- Run all commands from the repository root.

## Automated validation

```bash
make test
```

| Suite | Proves |
|-------|--------|
| `ConfigurationTests` | Labels are ignored and never written; a missing, `null` or empty icon falls back to the type default; duplicate icons are valid; an unknown icon is invalid. Membership and own-budget decoding follows every row of [contracts/config-file.md](contracts/config-file.md). Covers the move helpers and `dataRelevant` (FR-001 to FR-009, FR-014, research R8). |
| `AggregatorTests` | A standalone account gets a budget entry over its own period window; member spend and percent add up to the group total (FR-010, FR-017, FR-018a, SC-004). |
| `ThresholdTrackerTests` | Own-budget crossings name the account. A membership change re-baselines both budgets (FR-012, FR-015). |
| `BarLayoutTests` (new) | Bar order follows FR-020. Member values, levels, the `…` placeholder and stale state follow FR-017 to FR-019. Names are used for plain text (FR-004). |
| `ConfigStoreTests` | A legacy file stays byte-identical on load; saving it drops `label` (FR-007). |

## Manual validation

1. Back up `~/.config/agenttacho/config.json`, then run `make run`.
2. Open Settings, then Accounts. Expected: no text label fields; each account and group shows one icon with "Choose…" and no way to remove it.
3. Give two accounts the same icon and save. Expected: the save is accepted.
4. Add a token-based account and choose "Own budget", Monthly, 100. Expected: it appears in the dropdown as its own entry with "of $100.00 per month", and in the bar with its icon.
5. On a group member, enable "Show this account's share in the menu bar". Expected: the bar shows that member's icon right after the group, with its share percent. The dropdown shows the same percent next to the member.
6. Switch the member to "Own budget", then back into the group. Expected: the group is kept or deleted according to FR-014, and no notification fires right after the switch.
7. Restore the backup.
