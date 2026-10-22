# Contract: Settings Layout and Texts

Exact labels, captions and order for spec 034. Strings marked (UsageCore) come from `GeneralSettingsPage` or `AccountDirectoryText`; all others are today's strings, moved unchanged (FR-002). The window stays 720 by 560 points; the tabs General, Menu Bar, Accounts, Groups, Prices, Log, About and their order stay (FR-005).

## General tab

```text
+--------------------+-------------------------------------------+
| (sidebar, 170 pt)  | (page: grouped Form)                      |
|  [arrow.clockwise] Refresh                                     |
|  [paintbrush]      Appearance                                  |
|  [calendar]        Weekly window                               |
|  [bell]            Notifications                               |
|  [folder]          Sources                                     |
|  [power]           Startup                                     |
+--------------------+-------------------------------------------+
```

- Sidebar: `List` with `.sidebar` style, one `Label(title, systemImage:)` per page (UsageCore), no counts, no descriptions. Exactly one entry selected.
- Selection is stored under the defaults key `generalSettingsPage`; first time and for an unknown value: Refresh (FR-003).
- Every page binds the Settings draft; apply, undo, redo and "Not applied: ..." work as today (FR-004).

### Page contents (in this order)

**Refresh**: `Section("Refresh")`
1. "Refresh interval" field with "seconds" (prompt `300`)
2. "The minimum is 60 seconds." (red, only below 60)
3. Toggle "Adapt refresh"
4. Caption "Refresh when the menu opens; check plan limits less often while no agent runs, while you are away or while the Mac saves power (still at least every 30 minutes)."

**Appearance**: `Section("Appearance")` (was "Display")
1. Segmented "Show usage as": Used, Remaining
2. Caption "Remaining counts down from 100% as you use a limit or budget. Thresholds and notifications follow."
3. Segmented "Dropdown theme": Auto, Dark, Light
4. Caption "Auto follows the system appearance. Settings and the menu bar always do."

**Weekly window**: `Section("Weekly window")`
1. Picker "Align with subscription account" ("First subscription account" plus each Claude subscription)
2. Picker "Fallback weekday"
3. Stepper "Fallback hour: HH:00"
4. Caption "The week that weekly budgets and the token details in the dropdown (per subscription account, and for usage that matches no account) count over. Aligned with a subscription account, it ends at that account's 7-day reset; the fallback applies until a reset has been fetched. Monthly budgets always run from the 1st to the end of the month." (walkthrough 2026-10-22; replaces the two earlier captions and keeps the monthly sentence of spec 003 FR-020)

**Notifications**: `Section("Notifications")`
1. Toggle "Notify when a sign-in stops working"
2. Toggle "Notify before a free limit reset expires"

**Sources**:
1. `Section("Additional OpenCode data directories")`: caption "~/.local/share/opencode is always read. Add other OpenCode data directories that hold an opencode.db."; one row per added directory with "Remove"; "Add directory" field (prompt `~/.local/share/opencode-lab` (UsageCore), width 200 to 320 points) and "Add" button.
2. `Section("Claude Code and Codex")` (UsageCore): caption "Claude Code directories and Codex homes are set per account in Accounts. An account without one uses ~/.claude or ~/.codex." (UsageCore)

**Startup**: `Section("Startup")`
1. Toggle "Start at login"
2. Toggle "Check for updates automatically"

Removed from Settings (FR-010): "Additional Claude Code directories", "Additional Codex homes".

## Accounts tab, account editor

Sections in order. Unchanged sections ("Account", "Notifications", "Session matching (advanced)", "Budget") are not repeated here.

### Claude subscription

`Section("Subscription")`
1. `LabeledContent("Claude Code directory")` (UsageCore): text field bound to the entered value, prompt `~/.claude`, width 320
2. Caption (UsageCore): "The Claude Code directory this account runs from: its sessions and its login come from here. Leave it empty for ~/.claude, or enter a profile directory such as ~/.claude-personal. Use the directory you run Claude Code with, so its login stays fresh."
3. Toggle "Show in menu bar", Times picker (unchanged)

### Codex subscription

`Section("Codex subscription")`
1. `LabeledContent("Codex home")`: text field bound to the entered value, prompt `~/.codex`, width 320
2. Caption (UsageCore): "The Codex home this ChatGPT plan runs from: its sessions are read from here and, with live limits on, its sign-in. Leave it empty for ~/.codex, or enter another home such as ~/.codex-lab."
3. Toggles and live limits caption, Times picker (unchanged)

### Token-based (Vertex or OpenAI)

1. `Section("Token-based")`: "Provider", "Budget", member share toggle (unchanged)
2. `Section("Usage source")` (UsageCore, FR-007):

| Provider | Label | Prompt | Caption |
|---|---|---|---|
| Vertex | Claude Code directory | `~/profiles/acme/claude` | "Sessions in this Claude Code directory are read for this account's usage. Leave it empty for ~/.claude. Only session files are read, never a login." |
| OpenAI | Codex home | `~/.codex-lab` | "Sessions in this Codex home are read for this account's usage. Leave it empty for ~/.codex. Only session files are read, never auth.json." |

   Field width 320, empty by default; an empty field stores no directory and reads the default (`~/.claude` or `~/.codex`). Changing "Provider" clears it.
3. `Section("Budget")` and its "Notifications" for an own budget (unchanged)

## New account sheet

- Claude subscription: label "Claude Code directory" (was "Credential directory"), prompt `~/.claude`, starts with `~/.claude`.
- Codex subscription: unchanged.
- Token-based: no directory field (research R11).

## Invariants checked by tests

- `GeneralSettingsPage.allCases.map(\.title) == ["Refresh", "Appearance", "Weekly window", "Notifications", "Sources", "Startup"]`.
- Every `AccountDirectoryText` caption and prompt is free of `cc-deck`, and each caption names its default (`~/.claude` or `~/.codex`).
- The subscription captions name an invented example (`~/.claude-personal`, `~/.codex-lab`).
