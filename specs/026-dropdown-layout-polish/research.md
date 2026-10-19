# Research: Dropdown Layout Polish

## R1: Member display in core (FR-002, FR-003, FR-007)

- **Decision**: `MemberDisplay.make(memberIds: [String], usage: [String: TokenAccountEntry]) -> MemberDisplay` with `lines: [String]` (members with a usage entry, only when the group has two or more members) and `tables: [String]` (members whose breakdown is not empty, only when there are two or more of them). `showsAccountsButton` is `!tables.isEmpty`. `BudgetSection` and `ScenarioCoverage` both use it.
- **Rationale**: one rule for the view and the demo coverage (idea inbox member-line-rule-in-core).

## R2: Σ value and tooltip (FR-009)

- **Decision**: `DayRowTotal.make(days: [DayUsage], showsCost: Bool, incomplete: Bool, locale:) -> DayRowTotal` with `text` and `tooltip`. Cost rows sum `costUSD` (nil counts 0) and format with `CompactFormat.usd` ("<1", whole below 1,000, then "1.6K"); token rows sum `totalTokens` with `CompactFormat.millions`. Tooltip "Total: $430.12" or "Total: 188.7M tokens" (spec 026 FR-009c), plus "\nincomplete: some usage is unpriced" when `incomplete`.
- **Rationale**: moves the day formatting into tested core; the app's `UsageFormat.millions` and `compactUSD` call the core functions.

## R3: Day columns and Σ placement (FR-009, FR-009a)

- **Decision**: every day column and Σ use `minWidth: 30`, spacing 6. Weekly: one row with the days then Σ. Monthly: rows of 7 days; Σ is appended to the last row (an 8th column when that row is full). The Σ label is "Σ" in the secondary style like day labels; the value is semibold.

## R4: "Show accounts" (FR-003 to FR-005)

- **Decision**: `@AppStorage("showsMemberTables") var showsMemberTables = false`, shared by all groups. `BreakdownView` gains `memberTables: [(name: String, icon: String, breakdown: UsageBreakdown)]`; when non-empty, a borderless caption button "Show accounts" / "Hide accounts" follows the group's day row, and when shown each member renders a header (icon and name, secondary) plus the table for the current `detailsMode` and its day row, with no extra leading indent. Member Details disclosures are removed from `BudgetSection`.

## R5: Pinned footer and panel height (FR-010, FR-011)

- **Decision**: `body` becomes a `VStack(spacing: 0)` of a `ScrollView(.vertical, showsIndicators: false)` holding the sections (with their height measured as today) and the footer (divider plus footer content, height measured separately). The panel height is `min(sectionsHeight + footerHeight, cap)`, the scroll view's height is `min(sectionsHeight, max(160, cap - footerHeight))`. `resizePanel` keeps anchoring at the top.
- **Rationale**: the footer is outside the scroll view, so it never scrolls; the 160 pt floor keeps sections usable.

## R6: Footer errors (FR-011)

- **Decision**: `FooterErrors.visible(_ errors: [SourceError], limit: 3) -> [FooterErrorLine]` returns up to 3 lines, the third replaced by "+N more" with a tooltip of all errors joined by newlines when there are more than 3. Each line renders with `.lineLimit(1)`, `.truncationMode(.tail)` and its full text as tooltip.

## R7: Status row and tooltip (FR-012, FR-013)

- **Decision**: the icon row becomes `HStack { refresh; status text (lineLimit 1, truncation tail, layoutPriority); stale marker; Spacer; settings; quit }`. `FooterText.statusTooltip(statusText:isTruncated:paceText:) -> String?` joins the full status text (when truncated) and the pace text with a newline; nil when neither. Truncation is detected in the view by comparing the text's ideal width with the available width (`ViewThatFits` or a measured width); the core function only builds the text. The accessibility value stays the pace text.

## R8: Capture script (FR-018)

- **Decision**: capture.sh launches the demo with `-showsMemberTables NO` (the argument domain overrides the stored preference), so the `details` crop shows the group's tables with the button but no member tables even after a walkthrough toggled it; `test_screenshots.sh` asserts the argument. No new stem.

## R9: Amendments and docs (FR-016, FR-017)

- **Decision**: rewrite the named requirements in place citing spec 026 (as spec 025 did); update `docs/usage.md` (Σ column, pinned status row) and `docs/accounts-and-budgets.md` (one budget Details, "Show accounts", the Details total).
