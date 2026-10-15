# Contract: Settings > Menu Bar tab

Position: second tab, after General, tab label "Menu Bar", SF Symbol `menubar.rectangle`, tag `"menubar"`.

Layout, top to bottom:

1. **Preview**: the bar as `BarLayout.segments(snapshot:configuration: draft)` renders it, on a dark capsule; caption "Preview".
2. **List** (selection: one row):
   - Entry row: drag handle area (whole row), checkbox "Show in bar", icon, name, kind caption (`Subscription`, `Codex plan`, `Own budget`, `Budget group`).
   - Member row: indented by one level, checkbox "Show in bar" (member share), icon, name, caption `Member share`.
   - Rows of entries hidden from the bar stay in place; their text is secondary-colored.
3. **Buttons** below the list: "Move Up" (Option-Command-Up Arrow) and "Move Down" (Option-Command-Down Arrow), disabled when no row is selected or the row is first or last in its level. A caption explains: "Drag to reorder. Members stay inside their group. The dropdown uses the same order."

Behavior:

| Action | Effect |
|---|---|
| Drag entry row | Entry (and a group's members) moves among entries; `draft.arrangement` set to the full new order. |
| Drag member row within its group | Member order changes. |
| Drag member row outside its group, or entry row into a member block | No change. |
| Move Up / Move Down | One position within the row's level; group moves with members. |
| Checkbox | Same setting as the editor toggle (FR-012); preview updates. |
| Any change | Applied by the Settings debounce (about 0.6 s); Edit > Undo restores the previous state. |

Empty state (no entries): "No accounts configured. Add one in the Accounts tab."
