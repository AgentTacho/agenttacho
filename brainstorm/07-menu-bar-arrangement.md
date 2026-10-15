# Brainstorm: Menu Bar Arrangement

**Date:** 2026-10-15
**Status:** active

## Problem Framing

The order of the entries in the menu bar looks random and does not match the order in Settings. It is not actually random: three places use three different fixed orders, and none of them can be changed.

| Where | Order today |
|---|---|
| Settings > Accounts | `config.json` order; new accounts are appended; the list cannot be reordered |
| Menu bar (`BarLayout.segments`, spec 004 FR-020) | all accounts in list order first, then groups, each group followed by its shown members |
| Dropdown (`DropdownView`) | Claude subscriptions, Codex subscriptions, groups, then accounts with their own budget |

With the maintainer's configuration, Settings lists "Claude Max, Claude Code via Vertex, Codex", the bar shows "Claude, Codex, Vertex" (the Vertex group comes after all accounts), and the dropdown follows yet another rule.

The goal: one order, set by the user, that the bar and the dropdown both follow, covering accounts and budget groups together. A placement inside the Accounts tab cannot express where a group goes, because groups live in a separate tab.

Things that can appear in the bar:

- subscription accounts (Claude, Codex)
- token-based accounts with their own budget
- budget groups
- group members shown on their own (member shares, spec 004 FR-017 to FR-019)

## Approaches Considered

### A: Arrangement list in a new "Menu Bar" settings tab (chosen)

One list of every entry that can appear, with members indented under their group. Rows are reordered by dragging, each row has a "Show in bar" checkbox, and a live preview of the bar sits on top.

```
Settings > Menu Bar

Preview:  ✳ 51%  ֍ 14%  ☁ ‼520%

 ≡ [x] ✳ Claude Max (OS Licence)   subscription
 ≡ [x] ֍ Codex (ChatGPT Plus)      Codex plan
 ≡ [x] ☁ Vertex                    budget group
     ≡ [ ] ✳ Claude Code via Vertex  member share
     ≡ [ ] ◻ OpenCode via Vertex     member share
 ≡ [ ] $ OpenAI API                own budget
```

- Pros: answers "where do groups go" directly; one place for the whole bar instead of toggles spread over the account and group editors; the preview shows the effect immediately; leaves the Accounts and Groups editors untouched.
- Cons: one more settings tab; the "Show in bar" setting is reachable from two places (here and in the editors).

### B: Unified "Accounts & Groups" outline

Merge the Accounts and Groups tabs into one outline: standalone accounts and groups at the top level, members as children of their group. The outline order is the bar and dropdown order.

- Pros: one mental model for accounts, groups and order; no extra tab; overlaps with the inbox idea of explicit group management.
- Cons: a much larger change (two editors merged); dragging a member into another group would change its membership, a powerful but risky side effect of a reorder gesture.

### C: Drag in the menu bar itself

Each entry becomes its own status item, rearranged with the macOS Command-drag.

- Pros: direct manipulation where the entries are seen.
- Cons: macOS owns the positions, so the order cannot drive the dropdown or show in Settings; one dropdown per entry instead of one; entries hidden from the bar cannot be placed; items can disappear behind the notch. A custom drag inside the single status item would be non-standard and hard to discover.

## Decision

Approach A: a "Menu Bar" settings tab with one ordered list of all entries.

Decisions made along the way:

- The order applies to the bar and to the dropdown sections alike. Entries hidden from the bar keep their place in the dropdown.
- Members stay with their group: they can be reordered among themselves but always follow their group in the bar, or take its place when the group is hidden (as today, spec 004 FR-019). The dropdown keeps listing members inside their group.

## Key Requirements

- A new settings tab "Menu Bar" lists all top-level entries (subscription accounts, Codex subscription accounts, accounts with their own budget, budget groups) in one order, with each group's members indented below it.
- Drag reorders top-level entries anywhere in the list, and members only within their group. Rows have a drag handle; a keyboard or menu alternative (Move Up / Move Down) keeps it accessible.
- Each row has a "Show in bar" checkbox bound to the same setting as the existing toggle in the account or group editor (subscription `shownInBar`, own budget `shownInBar`, group `shownInBar`, member `memberShownInBar`).
- A live preview of the bar at the top of the tab reflects order and visibility as they are edited.
- The menu bar and the dropdown both follow this order. Hidden entries keep their dropdown position. A hidden group's shown members take the group's position in the bar.
- The order is stored in the configuration file and survives restarts.
- New accounts and groups are appended at the end; removed ones disappear from the order; an account that joins a group, leaves a group or gets its own budget moves accordingly without disturbing the rest.
- Accounts that cannot appear (token-based accounts in no group and without their own budget) are not listed.

## Open Questions

- Initial order for existing configurations: the current bar order (accounts, then groups) so nothing moves on upgrade, or the Settings list order.
- Where an account lands when it gets its own budget or leaves a group: at the end, or where its group was.
- Whether the "Show in bar" toggles stay in the account and group editors as well, or move to the new tab only.
- Config format for the order: a separate ordered id list, or the order of the accounts and groups arrays plus a position field.
- Whether the Accounts and Groups lists in Settings should also follow the new order.
- Name of the tab ("Menu Bar", "Layout", "Arrangement").
