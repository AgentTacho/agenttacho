# Brainstorm: Explicit Group Management

**Date:** 2026-10-15
**Status:** active

## Problem Framing

Budget groups have no life of their own. They are created only inside the new-account sheet ("Budget: New group"), and they disappear as soon as they have no members: applying settings prunes empty groups (`pruningEmptyGroups`), and validation rejects an empty group in `config.json` ("has no member accounts", spec 001 FR-019, spec 004 FR-014). The Groups tab says so: "Groups are created with their first token-based account and removed with their last one."

This leads to a dead end found in the spec 004 walkthrough: move the only member of a group (for example "Vertex") to its own budget, and the group is gone with its budget, thresholds and position in the menu bar order. To get it back you have to create a new account. You also cannot set up a company budget before adding the first account, or remove a group that still has members.

Seeded from the idea inbox entry `explicit-group-management`.

## Approaches Considered

### A: First-class groups (chosen)

The Groups tab gets Add and Remove buttons. Empty groups are valid and kept; nothing deletes a group implicitly anymore. Removing a group that has members asks where they go.

- Pros: solves the dead end; lets you prepare a budget before adding accounts; one clear place to manage groups; simpler rules (no hidden deletion).
- Cons: touches validation and the group lifecycle rules of specs 001 and 004; empty groups need a sensible display.

### B: Ask before auto-delete

Keep the current model, but when the last member leaves, ask "Keep the empty group?".

- Pros: smaller change.
- Cons: still no way to create a group on its own or to remove a group with members; the prompt interrupts a membership change.

## Decision

Approach A. Decisions taken along the way:

- An empty group is kept with its budget, thresholds and position. Its spend is honestly zero, so the bar shows 0% when the group is shown in the bar, and its dropdown section says that the group has no accounts yet.
- Removing a group that has members asks where the members go: their own budgets (each prefilled with the group's period, amount, thresholds and shown-in-bar setting, as moving out of a group works today) or another existing group.
- Membership stays editable only from the account side (the account editor's Budget picker). The group editor lists its members but does not change them.

## Key Requirements

- The Groups tab has Add and Remove... buttons. Add creates a group with the same defaults as a group created in the new-account sheet (weekly, shown in the bar, thresholds 80% and 100%) and selects it for editing.
- The new-account sheet keeps its "New group" option.
- Empty groups are valid in the configuration and never deleted implicitly: not when the last member leaves, not when the last member is removed, not on load or apply. Spec 001 FR-019 and the group deletion in spec 004 FR-014 are replaced.
- An empty group shows 0% in the bar (when shown) and a "no accounts yet" note in its dropdown section; it never crosses a threshold and never notifies.
- Removing a group with members shows a confirmation that lets the user choose one destination for all members: own budgets (prefilled from the group) or another existing group. Removing an empty group asks for a plain confirmation.
- A removed group drops out of the menu bar arrangement and its notification state is cleared; the remaining order is kept (spec 008 FR-008).
- Undo in Settings restores a removed group, including its members' previous membership.
- The Groups tab caption describes the new behavior.

## Open Questions

- Default budget amount for a group added from the Groups tab (the new-account sheet uses its own default).
- Whether moving all members to another group in the remove dialog should offer only groups with the same period, or any group.
- Wording of the empty-group note in the dropdown and the remove dialog.
- How existing configurations without empty groups migrate (expected: nothing to do), and whether an older version that rejects empty groups needs a note in the release.
