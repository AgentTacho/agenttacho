# Data Model: Menu Bar Arrangement

## Arrangement (stored, `UsageCore/Config/Arrangement.swift`)

| Field | Type | Notes |
|---|---|---|
| `entries` | `[EntryRef]` | Order of top-level entries. May contain stale, duplicate or misplaced references (ignored on resolution, FR-011). |
| `members` | `[String: [String]]` | Group id to ordered member account ids. Missing groups or members are appended on resolution. |

`Configuration.arrangement: Arrangement?`. `nil` means no stored arrangement (FR-004). Codable, Equatable, Sendable. Encoded only when non-nil.

## EntryRef

| Field | Type | Notes |
|---|---|---|
| `kind` | `EntryKind` (`account`, `group`) | Disambiguates a group and an account sharing an id. |
| `id` | `String` | Account id or group id. |

## ArrangedEntry (derived, never stored)

| Case | Payload | Notes |
|---|---|---|
| `.account(Account)` | a Claude subscription, Codex subscription, or token-based account with its own budget | |
| `.group(BudgetGroup, members: [Account])` | members in resolved member order | |

`id: String` is kind-qualified (`"account:<id>"`, `"group:<id>"`) for `ForEach` identity. `ref: EntryRef` returns the stored form.

Derivation: `Configuration.arrangedEntries: [ArrangedEntry]` (research R2). `Configuration.defaultArrangement: Arrangement` is `asArrangement` applied to the order resolved with nothing stored, so it lists every entry and every group's members (an empty list for a group without members) exactly as `asArrangement` does, (used for the FR-004a "differs from default" check).

**Entry eligibility**: an account is an entry when its kind is `.subscription`, `.codexSubscription`, or `.tokenBased` with `ownBudget != nil`. A token-based account with a group is a member of that group. Any other account (invalid per spec 004 FR-008) is neither.

## ArrangementRow (derived, `UsageCore/Bar/ArrangementEditor.swift`)

Flat list rows for the Menu Bar tab, in display order.

| Case | Payload |
|---|---|
| `.entry(EntryRef)` | top-level row |
| `.member(groupId: String, accountId: String)` | indented row under its group |

`id: String`: `"account:<id>"`, `"group:<id>"`, `"member:<accountId>"` (an account belongs to at most one group).

## Operations

| Operation | Input | Output | Requirement |
|---|---|---|---|
| `Configuration.arrangedEntries` | configuration | `[ArrangedEntry]` | FR-001, FR-011 |
| `Configuration.isEntry(_:)` | account | `Bool` (subscription, Codex subscription, or own budget) | FR-009 |
| `Configuration.asArrangement(_:)` | `[ArrangedEntry]` | complete `Arrangement` | FR-004a |
| `Configuration.reconcilingArrangement(previous:)` | previous applied config, next candidate | candidate with updated or unchanged `arrangement` | FR-004, FR-004a, FR-005 to FR-008 |
| `ArrangementEditor.rows(_:)` | configuration | `[ArrangementRow]` | FR-009 |
| `ArrangementEditor.move(_:from:to:)` | configuration, `IndexSet`, destination row index | new `Arrangement` or `nil` (drop rejected) | FR-010 |
| `ArrangementEditor.moveUp/moveDown(_:row:)` | configuration, row | new `Arrangement` or `nil` | FR-010a |
| `ArrangementEditor.canMoveUp/canMoveDown(_:row:)` | configuration, optional row | `Bool` (false for nil row, first/last in level) | FR-010a |
| `Configuration.isShownInBar(_:)` / `settingShownInBar(_:_:)` | row, flag | `Bool` / new configuration | FR-012 |

Every operation that returns a new arrangement returns the full resolved order (all entries and all members), so storing it makes the current order explicit.

## Reconciliation (research R3)

| Situation | Base order | Result |
|---|---|---|
| candidate equals the configuration an undo restored | none | saved as is, no reconciliation |
| arrangements equal and structure unchanged | n/a | unchanged (checked first) |
| `next.arrangement != previous.arrangement` (reorder) | `next.arrangement` | placement rules (research R3 step 2) applied on top; stored |
| arrangements equal, structure changed | `previous.arrangedEntries` | placement rules applied; stored if previous was stored or result differs from `next.defaultArrangement`, else nil |
