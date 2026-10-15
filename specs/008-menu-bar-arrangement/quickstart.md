# Quickstart: Menu Bar Arrangement

## Prerequisites

Xcode Command Line Tools; the repository at the feature branch. A configuration with at least one subscription account, one budget group with two members, and one account with its own budget makes every step visible (Settings > Accounts can add them).

## Automated checks

```bash
make test            # includes ArrangementTests, ArrangementReconcileTests, ArrangementEditorTests, BarLayoutTests
```

Expected: all suites pass.

## Manual validation

1. **Unchanged after update (SC-003).** Back up `~/.config/llm-usage-menubar/config.json`, run `make run`. The bar order matches the previous version (accounts, then groups). `config.json` has no `arrangement` key.
2. **Bar and dropdown agree (SC-001).** Open the dropdown: sections appear in the bar's order; hidden entries still have their section.
3. **Reorder (US2).** Settings > Menu Bar: drag the group to the top. The preview, then the bar and the dropdown, show it first. `config.json` now has `arrangement` (see [contracts/config-file.md](contracts/config-file.md)).
4. **Members stay with the group.** Drag a member row above its group: nothing changes. Reorder the two members: with both shares shown, the bar shows them in the new order after the group.
5. **Keyboard (SC-005).** Select a row, press Option-Command-Up Arrow while the list has focus: it moves up one position and stays selected. The buttons are disabled for the first or last row of a level and with no selection.
6. **Visibility (US3).** Clear an entry's checkbox: it leaves the preview and the bar; its editor toggle in Accounts or Groups is off. Turn it on in the editor: it returns at its old position.
7. **Undo.** Edit > Undo after a reorder restores the previous order. Move a group member to its own budget, then Edit > Undo: the previous order and membership return.
8. **Placement rules.** Add a new subscription account: it appears last. Move a group member to its own budget: it appears right after the group.
9. **Relaunch.** Quit and start again: the arrangement is kept (SC-004).
