# Research: Menu Bar Arrangement

All decisions below resolve the open questions of the spec and the review notes. Code references are to `main` at the start of this feature.

## R1: Storage format of the arrangement

- **Decision**: An optional top-level `arrangement` object in `config.json`:
  `{"entries": [{"kind": "account", "id": "..."}, {"kind": "group", "id": "..."}], "members": {"<groupId>": ["<accountId>", ...]}}`.
  Absent key means "no stored arrangement". The file version stays 1.
- **Rationale**: Kind-qualified entry references are needed because `Configuration.validate()` allows a group and an account to share an id (spec review finding). Keeping the arrangement separate from the `accounts` and `groups` arrays leaves the Accounts and Groups tabs untouched (FR-015) and keeps visibility in the existing shown-in-bar settings. Members are keyed by group id, which is unique among groups.
- **Alternatives considered**: Reordering the `accounts` and `groups` arrays plus a position field (cannot interleave groups and accounts without a second order anyway, and changes the Settings lists). A flat list of `"account:<id>"` strings (ids could in principle contain the separator; an object is self-describing).

## R2: Resolution and tolerance

- **Decision**: `Configuration.arrangedEntries` builds the effective order in one pass:
  1. Walk the stored entry references; keep a reference when it names an existing entry of that kind (an account that is a subscription, Codex subscription or own-budget account; or a group) and was not seen before.
  2. Append every entry not yet placed, in default order (accounts that are entries in accounts-list order, then groups in groups-list order).
  3. For each group, walk its stored member list; keep ids of accounts that are members of that group and not seen before; append the remaining members in accounts-list order.
  With no stored arrangement, steps 1 and 3 have nothing to walk, which yields the previous bar order of spec 004 FR-020.
- **Rationale**: One function implements FR-011 completely, including references at the wrong level (an id that is not an entry of the named kind, or not a member of that group, is simply not kept). Nothing throws, so no new configuration error exists.
- **Alternatives considered**: Validating the arrangement in `validate()` (would turn a hand-edit slip into a config error, against FR-011).

## R3: Where the placement rules run

- **Decision**: A pure `Configuration.reconcilingArrangement(previous: Configuration) -> Configuration`, called in `SettingsView.applyNow` on the pruned candidate with the last applied configuration as `previous`, except when the candidate equals the configuration an undo just restored: that configuration was already reconciled when it was first applied, so it is saved as is (FR-014). Comparing with the undo target, instead of checking the `restoringUndo` flag alone, keeps the placement rules active for a structural edit made during the debounce after Cmd-Z.
  1. **Base order.** If `next.arrangement != previous.arrangement`, the edit reordered (the Menu Bar tab wrote a full order): the base is `next.arrangement`. Otherwise the base is `previous`'s resolved order, expressed as an arrangement.
  2. **Placement rules on top of the base**, judged against `previous`, in this order:
     1. Let *moved* be the accounts that were a member of some group G in `previous` and are entries in `next`, and *joined* the accounts that are members of a group in `next` but were not members of that group in `previous`. Remove both from the base wherever they appear (a reorder base built from the draft may already contain them).
     2. For each former group G of a moved account, find the anchor: G if G is still in the base; otherwise the nearest entry before G in `previous`'s resolved order that is still in the base; otherwise the start of the list. Insert G's moved accounts right after the anchor in accounts-list order (FR-006).
     3. Append every joined account last in its new group, in accounts-list order (FR-005, FR-007).
     4. Append any other entry of `next` missing from the base at the end, in default order (FR-005).
     5. Drop references that are no longer entries or members of `next` (FR-008).
  0. **No-op check (first).** When `next.arrangement == previous.arrangement` and the structure is the same (same kind-qualified entries, same members per group), return `next` unchanged. A hand-edited stored order with stale ids is therefore never rewritten just because Settings was opened and closed (FR-004).
  3. **Store decision.** The result is stored when `previous.arrangement` was stored, or when the result differs from `next.defaultArrangement` (FR-004a). Otherwise `arrangement` stays nil (FR-004), also after a reorder that ends at the default order; Settings then drops the draft's copy of that order.
- **Rationale**: Account and group changes happen in many places (new-account sheet, membership picker, `movingAccountToOwnBudget`, `movingAccountToGroup`, removal, `pruningEmptyGroups`). Comparing before and after in one function covers all of them, including group deletion through pruning. Applying the placement rules on top of a reorder keeps FR-006 correct when a drag and a structural change land in the same debounce window. Skipping reconciliation for undo makes Undo restore exactly the previous state.
- **Alternatives considered**: Updating the arrangement inside every mutating helper (many call sites, easy to miss one). Reconciling on every draft change via `onChange(of: draft)` (would fight the undo flow and run on every keystroke). Treating any changed arrangement as final (breaks FR-006 when edits coalesce, see plan review).

## R3a: Presentation-only edits do not refresh

- **Decision**: `Configuration.dataRelevant()` clears `arrangement`, so `needsRefresh(comparedTo:)` is false when only the order changes. A reorder redraws the bar and dropdown without a re-price (spec 004 R8).

## R4: Reorder interaction in SwiftUI on macOS

- **Decision**: A single flat `List` with selection, one row per entry and per member (members indented), and one `ForEach(...).onMove`. The move handler calls the pure `ArrangementEditor.move(_:from:to:)`. `onMove` passes the destination in pre-removal coordinates (`Array.move(fromOffsets:toOffset:)` semantics), and the editor uses the same convention:
  - a source `IndexSet` with more than one element returns nil;
  - **member row** of group G whose member rows occupy flat indices f...l: accepted for destinations f...l+1, which reorders G's members, except d == source and d == source + 1, which are no-ops and return nil; any other destination returns nil;
  - **entry row** (with a group, its whole block of group row plus member rows): accepted for destination d only when d == rows.count or rows[d] is an entry row; a destination inside or at the start of a member block returns nil; a destination inside the moved block itself (d from the source index to the end of its block + 1) is a no-op and returns nil.
  Move Up and Move Down buttons with `.keyboardShortcut(.upArrow / .downArrow, modifiers: [.option, .command])` call `ArrangementEditor.moveUp/moveDown`, disabled via `ArrangementEditor.canMoveUp/canMoveDown` (FR-010a). Row ids are stable, so the moved row stays selected.
- **Rationale**: `onMove` on a flat list is the standard macOS drag-to-reorder control and shows the insertion indicator. Nested `ForEach` with separate `onMove` handlers does not move a group's member rows along with it. Keeping the index arithmetic in `UsageCore` makes the tricky part testable.
- **Alternatives considered**: `OutlineGroup` or a disclosure hierarchy (no reorder support); custom `onDrag`/`onDrop` with `NSItemProvider` (more code, worse insertion feedback).

## R5: Preview

- **Decision**: The tab renders `BarLabelView(items: BarLayout.segments(snapshot: model.snapshot, configuration: draft))` on a dark rounded capsule that mimics the menu bar. The bar image is a template image drawn in black, so the preview renders it with `.renderingMode(.template)` and a white foreground.
- **Rationale**: Same function and renderer as the real bar (FR-013); `draft` gives the order and visibility being edited, the snapshot the latest values, and `BarLayout` already shows "…" for entries without data and the `AgentMeter` placeholder when empty.

## R6: Shown-in-bar helpers

- **Decision**: `Configuration.isShownInBar(_ row: ArrangementRow) -> Bool` and `settingShownInBar(_ row:, _ shown: Bool) -> Configuration` in `UsageCore`, mapping a row to `SubscriptionSettings.shownInBar`, `CodexSubscriptionSettings.shownInBar`, the own `BudgetSettings.shownInBar`, `BudgetGroup.shownInBar` or the member's `TokenMembership.group(id:shownInBar:)`.
- **Rationale**: The checkbox changes exactly the setting the editors change (FR-012), and the mapping is unit tested.

## R7: Dropdown

- **Decision**: `DropdownView` iterates `configuration.arrangedEntries`, switching on the entry kind to render `SubscriptionSection`, `CodexPlanSection` or `BudgetSection`; group sections receive their members in member order. `UnassignedSection` stays last (FR-003).
- **Rationale**: One iteration replaces the four fixed `ForEach` blocks. `ArrangedEntry` has a kind-qualified `id`, so `ForEach` identity stays unique when a group and an account share an id.

## R8: Bar item identity

- **Decision**: `BarItem.id` stays as it is. The bar renders items into one image by index, and the preview uses the same renderer, so no SwiftUI identity depends on it. `ArrangedEntry.id` (kind-qualified) is used wherever a `ForEach` iterates entries.
- **Rationale**: Changing `BarItem.id` would ripple into logs and tests without a user-visible gain.
