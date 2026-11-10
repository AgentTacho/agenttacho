# Feature Specification: Budget Groups Without an Amount

**Feature Branch**: `044-no-limit-groups`

**Created**: 2026-11-10

**Status**: Draft

**Input**: User description: brainstorm `brainstorm/44-no-limit-groups.md` (Budget groups without an amount): a budget group's amount becomes optional, mirroring spec 043 for own budgets. A group without an amount has no limit, gains "Price tokens as" (`valueAs`) and "Dropdown shows" (`show`) with the spec 043 meaning applied to its members' combined records, lists each member with its spend or tokens without a share percent, and puts no restriction on which accounts share a group. Approach A of the brainstorm (groups mirror spec 043); merging own budgets and groups (B) and a display-only section (C) were rejected.

This feature changes rules from earlier specs: spec 003 FR-001 (a group's amount is required), spec 043 FR-002 (restates that a group's amount stays required) and its assumption that groups without an amount and a Show choice for groups are out of scope, spec 004 FR-017 and FR-018a and spec 025 FR-010 (member shares in the bar and in the dropdown, and member lines with amount and share, which need an amount), spec 026 FR-001 to FR-003 (for a group without an amount, the member tables behind "Show account details" follow the group's measure), spec 043 FR-010 (the Show setting now also exists on groups), and spec 009's group editor, which now accepts an empty amount (spec 009 FR-007's Add defaults are unchanged).

Examples assume the en_US locale, as published screenshots do.

## Clarifications

### Session 2026-11-10

- Q: Under a Money headline of a group without an amount, what does the member line of a member with only unpriced records show? → A: Its real spend, "$0"; member lines never use "≈". The group's value line covers the estimate, and the member line's tooltip names the member's unpriced tokens ("$0 spent this month, 48.2 million tokens without a price").
- Q: Under a Tokens or Money headline of a group with an amount, do member lines and Details change? → A: No (review-spec decision, maintainer, 2026-11-10). As spec 043 FR-014 does for accounts, a group with an amount changes only its headline; Details and member lines (spend and share, including remaining mode) stay as today. Only a group without an amount follows its headline in member lines and Details.
- Q: Does the account editor show a member's own "Price tokens as" while it is in a group? → A: No (review-spec decision, maintainer, 2026-11-10). It is hidden, as spec 043 FR-018a hides "Dropdown shows" for group members; the stored value is kept and applies again when the account returns to an own budget.
- Q: Can a group created from the new-account sheet start without an amount? → A: The question does not arise: the new-account sheet only joins existing groups (planning found no group creation there), so groups are created only by Groups > Add and edited in the group editor (FR-016, FR-017).
- Q: What does the refresh log line of a group without an amount say? → A: It mirrors the line of an account without an amount: `[refresh] no limit group <name> (<period>, <window>): <tokens> tokens, <spend> USD spent`, followed by `, unpriced: <models>` when there are unpriced records.
- Q: In a group with an amount, does a member line count a model that has both priced and unpriced records? → A: Yes (review-code decision, maintainer, 2026-11-10). The line shows the member's full priced spend; before this feature such a model's cost was left out, which undercounted.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One section for free models across harnesses (Priority: P1)

The maintainer uses free open-weight models (GLM, DeepSeek) through a company gateway from both Claude Code and Codex. One token-based account reads one harness, so there are two accounts, "Free models (Claude Code)" and "Free models (Codex)". Today each needs its own budget without an amount and shows as its own dropdown section. With this feature the maintainer puts both into a budget group "Free models" and leaves the group's amount empty. The dropdown shows one section with the combined spend, the two members below it with their own spend, and no percent, bar or menu bar entry.

**Why this priority**: This is the gap that started the feature; everything else refines it.

**Independent Test**: Configure a group without an amount with one Claude Code and one Codex member whose records are priced, and check that the dropdown shows one section with the summed spend, two member lines with their spend and no percent, and that the menu bar has no entry for the group.

**Acceptance Scenarios**:

1. **Given** a group without an amount, monthly, "Dropdown shows" Automatic, with two members whose priced records of the current month cost 92.84 US$ and 0.62 US$, **When** the dropdown is shown, **Then** the group's section headline shows "$93" with the tooltip "$93.46 spent this month", the line below it reads "spent this month" with the reset text, and no percent, bar, pace tick or pace note appears.
2. **Given** that group, **When** the dropdown is shown, **Then** each member line shows the member's icon, name and spend ("$93", "<$1") and no share percent.
3. **Given** that group, **When** the menu bar is drawn and the usage grows by any amount, **Then** the menu bar has no entry for the group and no threshold notification is sent for it.
4. **Given** a group without an amount, **When** its Details are expanded, **Then** they show the cost per model for the whole group, and "Show account details" (spec 026) adds each member's tables in the same measure.

---

### User Story 2 - Set up a group without a limit in Settings (Priority: P1)

In Settings > Groups the user selects a group and clears its Amount field. The field shows the placeholder "No limit". The thresholds and "Show in menu bar" stay visible but are disabled, with a help text that they need a budget. "Price tokens as" and "Dropdown shows" appear, as in an own budget's editor. Saving succeeds.

**Why this priority**: Without it the feature exists only for hand-edited files.

**Independent Test**: Clear a group's amount in Settings, save, reopen Settings and the configuration file, and check the stored form and the editor's controls.

**Acceptance Scenarios**:

1. **Given** a group with an amount, **When** the user clears the Amount field, **Then** the field shows the placeholder "No limit", and the thresholds and "Show in menu bar" are visible and disabled with a help text naming the period's budget ("Set a monthly budget to use thresholds and the menu bar.").
2. **Given** a group with an empty amount, **When** the user saves, **Then** saving succeeds, the configuration stores the group without `budgetUSD`, and the group's period, thresholds and shown-in-bar setting are kept.
3. **Given** the group editor, **When** it is shown, **Then** it has a "Price tokens as" pop-up and a "Dropdown shows" pop-up (Automatic, Percent, Tokens, Money) with the entries and rules of spec 043 FR-018, applied to the group.
4. **Given** the Groups tab list, **When** a group without an amount is listed, **Then** its subtitle reads "no limit / month" (or "/ week"), as an own budget without an amount reads in the Accounts list (spec 043 FR-021).

---

### User Story 3 - Choose what a group's section shows and value free tokens (Priority: P2)

A group without an amount whose members use only unpriced free models shows its token count by default. The user sets "Price tokens as" to `claude-opus-5-5`; the section then also shows "≈ $412 at claude-opus-5-5 prices". A user who prefers tokens over spend sets "Dropdown shows" to Tokens.

**Why this priority**: It completes the mirror of spec 043; groups without priced records already work with Automatic.

**Independent Test**: For one group with an amount and one without, step "Dropdown shows" through every entry and set and clear "Price tokens as", checking the headline and the line below it after each step.

**Acceptance Scenarios**:

1. **Given** a group without an amount whose members' records of the period are all unpriced and hold 48.2 million tokens, Show Automatic, no Price tokens as model, **When** the dropdown is shown, **Then** the headline shows "48.2M" with "this month" and the reset text, and no "incomplete, unpriced" note.
2. **Given** that group with Price tokens as `claude-opus-5-5`, **When** the dropdown is shown, **Then** the line below the headline reads "≈ $412 at claude-opus-5-5 prices", worded and rounded as spec 043 FR-014 and FR-015 describe.
3. **Given** a group with an amount of 500 US$, **When** "Dropdown shows" is Money or Tokens, **Then** the headline shows the spend or the tokens, the amount line, bar and pace stay as today, and member lines follow FR-013.
4. **Given** a group without an amount, **When** the "Dropdown shows" pop-up is open, **Then** Percent is disabled.

---

### User Story 4 - Adding and removing a group's amount (Priority: P3)

The user starts a group without an amount and later sets a monthly cap of 500. The thresholds and "Show in menu bar" become enabled with their kept values, the headline switches to percent (under Automatic), member lines show their shares again, and members that are shown in the bar return there with their share. Clearing the amount again reverses this.

**Why this priority**: It follows from stories 1 and 2 and must be smooth, but it is not the main use.

**Independent Test**: Toggle a group's amount between empty and 500 several times and check the controls, the stored configuration, the bar entries of the group and its members, and the threshold state after each change.

**Acceptance Scenarios**:

1. **Given** a group without an amount whose kept thresholds are 50% and 90% and kept shown-in-bar is off, **When** the user enters 500, **Then** the thresholds show 50% and 90%, "Show in menu bar" is off, and both controls are enabled.
2. **Given** a group whose amount was cleared, **When** an amount is entered again, **Then** the first refresh establishes a threshold baseline without notifying for thresholds already exceeded, for the group and for every member shown in the bar.
3. **Given** a member shown in the bar of a group with an amount, **When** the group's amount is cleared, **Then** the member's bar entry disappears, its shown-in-bar setting is kept, and the entry returns once an amount is entered.

---

### Edge Cases

- **A group mixes priced and unpriced members.** No rule restricts membership. Automatic shows Money as soon as one record of any member in the window has a price; the unpriced records produce the "incomplete, unpriced" note under Money unless the group's Price tokens as model values them, as spec 043 FR-007 says for one account.
- **A paid account in a group without an amount.** Allowed; its spend shows without a limit. Nothing warns about it.
- **A group without an amount has no members.** It stays (spec 009), shows "0" with its period line under Automatic or Tokens, or "$0" under Money, keeps its place in the bar arrangement, and has no menu bar entry.
- **A group without an amount has one member.** As today (spec 025 FR-010), the section has no member lines, since they would repeat the group's headline.
- **A group without an amount has no usage in its period.** Automatic shows Tokens, "0", as an account without an amount does (spec 043).
- **A member has its own Price tokens as model or Show setting.** Both are kept, hidden in the account editor and without effect while it is in the group (spec 043 FR-018a; FR-008 of this spec); the group's settings apply to the section and its member lines.
- **A Price tokens as model on a group with an amount.** It is kept and has no effect; the editor shows the pop-up disabled with spec 043's help text.
- **A hand-edited configuration gives a group an amount of 0 or less.** The configuration stays invalid (spec 003 FR-019); only an absent amount or `null` means no limit.
- **Kept thresholds of a group without an amount.** They are validated like a budget's (a threshold of 0 or less makes the file invalid), since they apply once an amount is entered.
- **An account switches from a group without an amount to an own budget.** The prefill of spec 004 FR-014 copies the group's period, thresholds and shown-in-bar setting and its empty amount, so the account gets an own budget without an amount.
- **A group without an amount is removed while it has members, choosing "each to its own budget with the group's settings".** Each member gets an own budget without an amount (spec 009).
- **Remaining mode (spec 030).** Applies to groups with an amount as today, and a Money headline on them shows the amount left or over (spec 043 FR-013); a group without an amount has no percent and is not changed by it.
- **Refresh log.** The diagnostic log line of a group without an amount reads `[refresh] no limit group <name> (<period>, <window>): <tokens> tokens, <spend> USD spent`, followed by `, unpriced: <models>` when there are unpriced records, as the line of an account without an amount does (FR-025).
- **A member with only unpriced records under a Money headline.** Its member line shows "$0", never "≈"; its tooltip names its tokens without a price (FR-013).
- **A `valueAs` or `show` key on a group in a file of an older version.** Older versions do not read them; downgrades are not supported (Assumptions).

## Requirements *(mandatory)*

### Functional Requirements

Amount and gating:

- **FR-001**: A budget group's amount MUST be optional. A group without an amount MUST have no limit. A stored amount MUST be greater than 0 (spec 003 FR-019); 0 or less MUST stay invalid. In the configuration file, an absent `budgetUSD` and `"budgetUSD": null` both mean no amount. This amends spec 003 FR-001 and spec 043 FR-002 for groups.
- **FR-002**: A group without an amount MUST keep its period (with its start setting), thresholds and shown-in-bar setting in the configuration. They MUST have no effect while the amount is absent and MUST apply again when an amount is entered.
- **FR-003**: A group without an amount MUST NOT appear in the menu bar, MUST NOT have threshold notifications, and MUST NOT show a percent, bar, pace tick, pace note, burn-rate escalation or run-out time (as spec 043 FR-008 for accounts).
- **FR-004**: While its group has no amount, a member MUST NOT appear in the menu bar as a share of the group budget (spec 004 FR-017) and MUST NOT have share notifications; its shown-in-bar setting MUST be kept and MUST apply again when the group gets an amount.
- **FR-005**: Threshold state tied to a group's amount, for the group and for its members' shares, MUST be dropped when the amount is removed, and the first refresh after an amount is entered MUST establish a baseline without notifying for thresholds already exceeded (spec 043 FR-009, spec 004 FR-015).
- **FR-006**: Any token-based account MAY be a member of a group with or without an amount. There MUST be no rule about the members' harnesses, session kinds or prices.

Pricing and value:

- **FR-007**: Records of a group's members MUST be priced from the effective price table as today, with or without an amount.
- **FR-008**: A group MUST have an optional Price tokens as model (`valueAs`). It MUST apply only to a group without an amount, and only to the unpriced records of its members, computed as spec 043 FR-006 computes it for one account. On a group with an amount, a stored model MUST be kept and MUST have no effect. A member's own Price tokens as model MUST have no effect while it is in a group; the account editor MUST hide its pop-up then and keep the stored value (as spec 043 FR-018a for "Dropdown shows").
- **FR-009**: For a group without an amount, the "incomplete, unpriced" note, the value line and the missing-model note MUST follow spec 043 FR-007 and FR-015, applied to the group's combined records.

Show choice and section:

- **FR-010**: Every group MUST have a Show setting (`show`) with the values Automatic, Percent, Tokens and Money. Absent means Automatic, and Automatic MUST NOT be written to the file. The setting MUST affect only the headline of the group's dropdown section and, for a group without an amount, the measure of its member lines and Details (FR-013, FR-014); the menu bar MUST NOT change. Changing it MUST NOT trigger a refresh.
- **FR-011**: Automatic MUST resolve as spec 043 FR-011 resolves it, over the group's combined records: Percent with an amount; without an amount, Money when at least one member record in the current window of the group's period has a price, and Tokens otherwise. Percent stored for a group without an amount MUST display as Automatic would, without changing the stored setting (spec 043 FR-012).
- **FR-012**: The group's headline, the line below it, their tooltips and the section's accessibility text MUST follow spec 043 FR-013, FR-014 and FR-016, applied to the group's combined records and its period, including remaining mode on a group with an amount.
- **FR-013**: In a group with two or more members and an amount, member lines MUST show the member's spend and share as today (spec 004 FR-018a, spec 030), whatever the Show setting, also when a Money headline reads in remaining mode; the spend is the member's full priced spend (all priced records), also of a model that has unpriced records too. In a group with two or more members and no amount, member lines MUST follow the group's resolved headline: the member's real spend in the Money headline format ("$93", "<$1", "$0") under Money, or its tokens ("48.2M") under Tokens, with no share percent. Member lines MUST NOT use "≈". A member line's tooltip and accessibility text MUST give the exact amount or token count with the period, as the headline's do; under Money, when the member has unpriced records, the tooltip MUST also name their tokens ("$0 spent this month, 48.2 million tokens without a price").
- **FR-014**: With an amount, the group's Details MUST stay as today whatever the Show setting (spec 043 FR-014). Without an amount, they MUST follow the resolved headline: cost per model under Money, tokens under Tokens. The member tables shown by "Show account details" (spec 026) MUST use the same measure as the group's Details.
- **FR-015**: The headline, the member lines, their tooltips and the accessibility texts MUST be produced by tested core logic (constitution II), sharing the rules of spec 043 rather than duplicating them for groups.

Settings:

- **FR-016**: The group editor MUST show the Amount field with the placeholder "No limit" when empty, the period, the thresholds, "Show in menu bar", "Price tokens as" (spec 043 FR-018's entries), "Dropdown shows" (Automatic, Percent, Tokens, Money) and the Times picker, with spec 043 FR-018's enabling rules: without an amount the thresholds and "Show in menu bar" are disabled, not hidden, "Show in menu bar" shows unchecked, and the help text reads "Set a <period> budget to use thresholds and the menu bar." (spec 043 FR-018); with an amount "Price tokens as" is disabled with its help text; Percent is disabled without an amount, and a stored Percent shows selected and disabled with its help text.
- **FR-017**: Saving a group with an empty amount MUST succeed. Groups > Add MUST keep its defaults (spec 009 FR-007: weekly, 60 US$, shown in the bar, thresholds 80% and 100%), plus Price tokens as none and Show Automatic.
- **FR-018**: The Groups tab list subtitle of a group without an amount MUST read "no limit / week" or "no limit / month", including its VoiceOver text and the unsaved draft. The Accounts list subtitle of a member of such a group MUST name the group with "no limit / month" in place of the amount ("Free models, no limit / month").
- **FR-019**: The Menu Bar tab MUST list a group without an amount with the caption "No limit" and its shown-in-bar control disabled and unchecked with the help text "Set a <adjective> budget to show this group in the menu bar." (worded like spec 043 FR-020's account help). Its members' rows MUST show their shown-in-bar controls disabled and unchecked with the help text "Set a <adjective> budget for the group to show this account in the menu bar." while the group has no amount. The live preview of the bar MUST show none of them.
- **FR-020**: The account editor of a member MUST show its "Show in menu bar" control (its share of the group budget) disabled and unchecked with that help text while its group has no amount; the stored value is kept.
- **FR-021**: Switching an account from a group to an own budget MUST keep spec 004 FR-014's prefill; from a group without an amount, the own budget therefore starts without an amount. Removing a group whose members move "each to its own budget with the group's settings" MUST give each an own budget without an amount when the group had none (spec 009).

Configuration:

- **FR-022**: A group's `valueAs` and `show` keys MUST be read and written with the values and validation of an own budget's keys (spec 043): an unknown `show` value reads as Automatic with a note in the log; a `valueAs` model without a price is valid and shows the missing-model note. Files written before this feature MUST load unchanged.

Documentation and website:

- **FR-023**: `docs/configuration.md` and `docs/accounts-and-budgets.md` MUST describe groups without an amount, the group keys `valueAs` and `show`, and the member lines without shares. The README's "Shared budgets" wording MUST cover groups with or without a limit. The release notes MUST name the change.
- **FR-024**: The demo scenario MUST include a group without an amount with a Claude Code and a Codex member whose records are priced, so the dropdown shows a Money headline with two member lines without shares; the demo coverage test MUST check the headline, the member lines and that neither the group nor its members have a menu bar entry (constitution V). The plan's "Screenshots and website" section MUST name the shots and copy that change.

Diagnostics:

- **FR-025**: Each refresh MUST log one line for a group without an amount: `[refresh] no limit group <name> (<period>, <window>): <tokens> tokens, <spend> USD spent`, followed by `, unpriced: <models>` when the window has unpriced records, worded like the line of an account without an amount.

### Key Entities

- **Budget group**: name, icon, members, period (weekly or monthly with its start), optional amount greater than 0, thresholds, shown-in-bar, optional Price tokens as model, Show setting, time format. Without an amount it has no limit.
- **Member line**: one member's row in a group section: icon, name, and either spend and share (with an amount) or spend or tokens alone (without one).
- **Show setting** and **Price tokens as model**: as in spec 043, now also on groups.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can combine free-model accounts of two harnesses into one dropdown section without a limit, entirely in Settings, without editing the configuration file.
- **SC-002**: For 100% of groups without an amount, the menu bar shows no entry for the group or its members, and no threshold notification, percent, share or pace appears, whatever their usage.
- **SC-003**: The exact amount in a group's Money headline tooltip equals the sum of its members' priced records to the cent, and each member line's exact amount matches that member's priced records, in 100% of tested cases.
- **SC-004**: Every change between an empty amount and an amount of a group in Settings leaves a valid configuration that loads again unchanged, in 100% of tested paths, and every configuration written before this feature loads without change in meaning.

## Assumptions

- Groups get the spec 043 settings as they are; no new headline measure, number format or setting is introduced.
- Groups > Add keeps the 60 US$ weekly default: a new group is more often a shared cap, and the amount can be cleared in the editor (brainstorm 44, my call).
- Without an amount, the group's Show setting decides the measure of its member lines and Details too, so such a section never mixes money and tokens; with an amount, only the headline changes, as for accounts (brainstorm 44 open question, resolved in review).
- A total across groups, price aliases for free models and restrictions on group membership are out of scope.
- Older AgentTacho versions cannot read a configuration with a group without an amount; downgrades are not supported, as for earlier configuration changes.
- The per-refresh aggregation cost of no-amount budgets (idea inbox `single-pass-no-amount-aggregation`) is left to the plan: it may be addressed if a group adds a measurable cost.
