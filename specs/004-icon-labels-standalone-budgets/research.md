# Research: Icon Labels and Standalone Budgets

Decisions made against the code on `main` at `f9a077f` (after spec 003). No external research was needed.

## R1: Icon as the only label

- **Decision**: `Account.label` and `BudgetGroup.label` are removed. `icon` becomes a non-optional `String` (`"style:name"`). `LabelContent` (text-or-icon) is removed. Views and the bar resolve the icon through `IconCatalog.shared.icon(for:)` into an `IconEntry`. A small `IconDefaults` in `UsageCore` provides `subscription = "brands:claude"`, `vertex = "brands:google"`, `group = "solid:wallet"`, plus `defaultIcon(for: AccountKind)`.
- **Rationale**: FR-001 and FR-003 remove both the text fallback and the uniqueness identity (`LabelContent.key`). That is everything `LabelContent` existed for. Keeping a single representation avoids dead branches in the bar renderer, the dropdown, and settings.
- **Alternatives considered**: keeping `LabelContent` with only the `.icon` case was rejected as an indirection without value. Keeping `label` in the model "for later" was rejected because FR-007 forbids writing it.

## R2: Legacy decoding of labels and icons

- **Decision**:
  - Decoding ignores the `label` key entirely.
  - A missing `icon` key, a `null` icon, or an empty string means "use the default for this entry's type" (FR-006). The account type is known by then, since `type` is decoded first.
  - Encoding writes `icon` and never `label` (FR-007).
  - An icon that is present but not in the catalog still fails validation (FR-005), as today.
- **Rationale**: Today's files can hold `"icon": null` (written by `encodeIfPresent`, or by hand) or no icon at all. Both must load (SC-002). `ConfigStore.load` never writes, so legacy files stay untouched until the next save.
- **Alternatives considered**: deriving an icon from the old text label was rejected, because no mapping exists. A "first unused icon" default was rejected, because duplicates are allowed now.

## R3: Shape of an account's own budget

- **Decision**:
  - Introduce `public struct BudgetSettings: Codable, Equatable, Sendable { period, budgetUSD, shownInBar, thresholds }`. It decodes with the rules of spec 003, and its validation is shared with groups.
  - `TokenBasedSettings` replaces `groupId: String` with `membership: TokenMembership`, where:
    ```swift
    enum TokenMembership {
        case group(id: String, shownInBar: Bool)
        case ownBudget(BudgetSettings)
    }
    ```
  - In JSON, a member keeps `"groupId"` and gains an optional account-level `"shownInBar"` (default `false`). A standalone account has a nested `"budget": { "period", "budgetUSD", "shownInBar", "thresholds" }` and no `groupId`.
  - Both `groupId` and `budget` present, or neither present, is a decode error (FR-008).
  - `BudgetGroup` keeps its flat JSON keys for backward compatibility but exposes `budget: BudgetSettings` as a computed get/set view. Aggregation, thresholds, and validation then treat both owners alike.
- **Rationale**:
  - A nested object keeps the standalone account's budget visibly grouped in hand edits.
  - Members reuse the account-level `shownInBar` key that subscription accounts already use.
  - The convenience `TokenBasedSettings.groupId: String?` keeps `members(of:)` and the attribution code unchanged.
- **Alternatives considered**: flat budget keys on the token account (`period`, `budgetUSD`, ... next to `groupId`) were rejected, because they make "both present" easy to write by accident and are harder to read. Converting groups to a nested `budget` object too was rejected, because it changes the group format again only one feature after spec 003.

## R4: Budget owners in aggregation and the snapshot

- **Decision**:
  - `Configuration.budgetOwners` returns one value per budget: `BudgetOwner { id, name, icon, budget: BudgetSettings, memberIds: [String], kind: .group | .account }`. It lists groups in groups-list order, then standalone accounts in accounts-list order. The aggregator builds one `GroupEntry` per owner.
  - `UsageSnapshot` gains `accountBudgets: [String: GroupEntry]`, keyed by account id, for standalone accounts. `groups` keeps group entries.
  - `GroupEntry` gains `memberSpendUSD: [String: Decimal]`: each member's spend in the group window. A helper `memberPercent(_:)` returns `PercentFormatter.rounded(spent:budget:)` (FR-017, FR-018a).
  - A standalone account's `TokenAccountEntry` uses its own budget's window and period.
- **Rationale**: Every per-group code path (window per period, breakdown, stale carry-over, refresh log line) works unchanged for a one-member owner. `memberSpendUSD` comes from the same filtered records the group total uses, so member percents always add up to the group percent within rounding (SC-004).
- **Alternatives considered**: storing standalone budgets inside `groups` keyed by account id was rejected, because ids can collide in principle and the bar or dropdown would need to tell the two apart anyway. Computing member percent in the bar from `TokenAccountEntry.breakdown.pricedCostUSD` was rejected, because it diverges from the group's cost sum when models are unpriced.

## R5: Threshold state across membership changes

- **Decision**:
  - `ThresholdTracker` iterates `budgetOwners`. The key stays `(ownerId, period.windowKind)`, and the stored state gains `memberIds: [String]`.
  - When an owner's member set differs from the stored one, the state resets: the next observation is a baseline.
  - An account that switches from its own budget to a group drops its own key (no longer live). The group's member set changes, so the group re-baselines. The reverse works the same way (FR-015).
  - Notifications name the owner's `name` (`displayName` for accounts).
- **Rationale**: FR-015 requires a baseline after the change for the new budget. Without the member-set check, a group gaining a high-spend member would notify immediately.
- **Alternatives considered**: resetting all group state on any configuration change was rejected, because it would swallow genuine crossings after unrelated edits.

## R6: Bar layout in UsageCore

- **Decision**:
  - Move ordering, value, and level computation out of `BarLabelBuilder` (app target) into `UsageCore` as `BarLayout.segments(snapshot:configuration:) -> [BarItem]`.
  - Each item holds `id`, `icon: String`, `name`, `value`, `level`, and `stale`. `BarLabelBuilder` keeps only rendering: the template image and the accessibility text, built from names (FR-004).
  - Order follows FR-020. First, subscription accounts and standalone accounts that are shown in bar, in accounts-list order. Then groups in groups-list order, each followed by its shown members in accounts-list order. A hidden group's shown members still appear at that position.
  - A member's value is `memberPercent`. Its level uses the group's warning threshold. Its data state copies the group's: `…` before data, stale when the group is stale (FR-018).
- **Rationale**:
  - FR-017 to FR-020 are pure ordering and arithmetic rules that deserve unit tests. The app target has none, which is the idea-inbox item `testable-bar-label`.
  - Rendering stays in AppKit.
- **Alternatives considered**: keeping the builder in the app with UI tests was rejected, because the project has no UI test target.

## R7: Settings flows

- **Decision**:
  - `LabelEditor` becomes `IconField`: it shows the glyph, the icon name, and "Choose…", with no remove button and no text field. The picker cannot clear the selection.
  - Token-based accounts get a "Budget" picker with "Own budget" followed by every group. "Own budget" shows `BudgetFields`, which is extracted from the group editor (period, amount, shown in bar, thresholds). Group membership shows a "Show this account's share in the menu bar" toggle.
  - Transitions are pure `Configuration` helpers in `UsageCore`, so they can be tested:
    - `movingAccountToGroup(accountId:groupId:)` deletes the old group when it empties.
    - `movingAccountToOwnBudget(accountId:)` prefills the budget from the former group (FR-014) and deletes that group when it empties.
  - The new-account sheet offers three choices: existing group, new group, or own budget. A new own budget starts as weekly, $60, shown in bar, thresholds `[80, 100]`, matching the new-group defaults (FR-013).
- **Rationale**: Keeps the view code thin. The emptied-group deletion (spec 001 FR-019) already lives in `removingAccount(id:)`, and the new helpers reuse it.

## R8: Refresh relevance of edits

- **Decision**: `dataRelevant()` ignores the following:
  - icons and names
  - member `shownInBar`
  - own-budget `shownInBar` and `thresholds`

  Own-budget `period` and `budgetUSD`, and membership changes, stay data-relevant and trigger a local reprice. None of these edits needs a network refresh.
- **Rationale**: This mirrors the existing split for groups (presentation edits apply without a refresh).

## R9: Default configuration on first launch

- **Decision**: `ConfigStore`'s generated default account uses `icon: IconDefaults.subscription` instead of `label: "M"`.
- **Rationale**: FR-001 and FR-002 apply to generated entries too.
