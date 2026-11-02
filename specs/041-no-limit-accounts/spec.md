# Feature Specification: Accounts without a Limit

**Feature Branch**: `041-no-limit-accounts`

**Created**: 2026-11-02

**Status**: Implemented

**Input**: User description: brainstorm `brainstorm/41-no-limit-accounts.md` (Accounts without a limit): a "No limit" budget choice for token-based accounts with an optional "Value as" reference model, shown only in the dropdown, without menu bar entry, thresholds or pace.

This feature changes rules from earlier specs (where spec 004 and spec 009 disagree, spec 009 holds): spec 004 FR-008, FR-013, FR-014, FR-015 (budget choice of a token-based account and its threshold state), spec 008 FR-006 (arrangement when leaving a group), spec 011 FR-011 (no pace meter), spec 018 FR-001, FR-005, FR-007a (Accounts list subtitle), spec 025 FR-016, FR-021, FR-029 (time format and section notes) and spec 026 FR-009 (token day rows).

Examples assume the en_US locale, as published screenshots do.

## Clarifications

### Session 2026-11-02

- Q: How precise is the value line's amount? → A: Whole US dollars in en_US currency format (amended 2026-11-02, english-number-format; before: the user's locale currency format), prefixed by "≈"; an amount of exactly 0 shows "≈ $0", an amount above 0 and below one dollar shows "≈ <$1", other amounts round half up to whole dollars (the value is an estimate, cents would suggest precision it does not have).
- Q: Which models does the Value as pop-up list when imports bring hundreds of models? → A: "None", then the built-in and manually priced models sorted by model id, then a "More" submenu with the imported (provider and CSV) models sorted by model id; a model priced by several sources appears once, by its effective source.
- Q: Which harnesses can use No limit? → A: Every token-based account, whatever its harness (Claude Code, Codex, OpenCode).
- Q: Does the section need a separate "tokens this month" line? → A: No. The headline carries the bare count ("48.2M"; exact count, unit and period in its tooltip), and the second line holds the value line, or the period without one, left of the reset text (maintainer, walkthrough step 4).
- Q: How are reference models named in the value line and the pop-up? → A: By their model id, as the Prices tab shows them (for example `claude-opus-5-5`); AgentTacho has no display names for models (maintainer, review-spec).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Track usage of free models without a made-up limit (Priority: P1)

The developer uses a company model gateway whose open-weight models (model ids starting with `rits/`) are free to use without any limit. They add a token-based account for these models and choose "No limit" instead of an own budget or a group. The account counts the tokens of its period (weekly or monthly) and shows them in its dropdown section. There is no percentage, no bar, no threshold color, no pace and no menu bar entry, because there is no limit to measure against.

**Why this priority**: Without it, the free account either has to pretend to have a budget (a percentage of an invented amount) or its usage stays near 0 US$ with an "incomplete, unpriced" warning. Counting the tokens honestly is the core of the feature.

**Independent Test**: Configure a token-based account with No limit and a monthly period, feed session records with `rits/` models, and check that the dropdown section shows the month's tokens, that the menu bar has no entry for it and that no threshold notification or pace note appears.

**Acceptance Scenarios**:

1. **Given** a token-based account with No limit and a monthly period and no Value as model, **When** records with 48.2 million tokens fall into the current month, **Then** its dropdown section shows "48.2M" as its headline in place of a percent, a line "this month" with the reset text, and no bar or pace note.
2. **Given** that account, **When** the menu bar is drawn, **Then** it has no entry for the account, and Settings offers no "Show in menu bar" setting for it.
3. **Given** that account's models have no price in the price table, **When** the refresh runs, **Then** the section shows no "incomplete, unpriced" note.
4. **Given** that account, **When** its usage grows by any amount, **Then** no threshold notification is ever sent for it.

---

### User Story 2 - See what the free usage would have cost (Priority: P1)

The developer wants to know what the free models save them. They set the account's "Value as" model to `claude-opus-5-5`. The section then adds a value line: "≈ $412 at claude-opus-5-5 prices", computed as if every token of the account had been used with `claude-opus-5-5`.

**Why this priority**: The maintainer named "what it saves me" as the second reason to look at the account. It needs no new price data, since the reference model's price is already in the price table.

**Independent Test**: Give the No limit account a Value as model with known rates, feed records with known token counts of each kind, and check the value line against the hand-computed amount.

**Acceptance Scenarios**:

1. **Given** a No limit account valued as `claude-opus-5-5`, **When** its records in the period hold 2 million input, 0.5 million output, 0.6 million 5-minute cache-write, 0.4 million 1-hour cache-write and 30 million cache-read tokens, **Then** the value line shows those counts priced at `claude-opus-5-5`'s rate for each of these kinds, exactly as a record of that model would be priced, as an approximate US dollar amount naming the model.
2. **Given** a No limit account without a Value as model, **When** the section is shown, **Then** it shows tokens only and no value line.
3. **Given** a No limit account valued as a model that an import later removes from the price table, **When** the next refresh runs, **Then** the value line is replaced by a neutral note naming the missing model, and the tokens still show.
4. **Given** a No limit account valued as `claude-opus-5-5`, **When** the user changes the override price of `claude-opus-5-5` on the Prices tab, **Then** the value line follows the new price after the change is applied.

---

### User Story 3 - Set up and switch a No limit account in Settings (Priority: P2)

In Settings > Accounts, the account's budget choice offers "No limit" next to its own budget and the groups. With No limit selected, the editor shows the period, the Value as model and the time format, and hides the amount, thresholds and "Show in menu bar". The account can be switched between No limit, an own budget and a group in every direction.

**Why this priority**: Needed to use stories 1 and 2 without editing the configuration file by hand, but the behavior of the account itself is defined by stories 1 and 2.

**Independent Test**: Create an account with No limit in Settings, save, reopen, switch it to an own budget, then to a group and back to No limit, and check the stored configuration and the Accounts list subtitle after each step.

**Acceptance Scenarios**:

1. **Given** the user adds a token-based account, **When** they choose No limit as its budget, **Then** the account starts with a weekly period, no Value as model and the Relative time format, and saving stores it without an amount or thresholds.
2. **Given** a No limit account, **When** the user switches it to an own budget, **Then** the own budget is prefilled with the account's period, thresholds 80% and 100% and shown in bar, and the user must enter an amount greater than 0 before the change can be saved.
3. **Given** an account with an own budget or in a group, **When** the user switches it to No limit, **Then** the amount, thresholds and shown-in-bar settings are discarded, the period is kept (an own budget's or the group's), and the threshold state of the previous budget is dropped.
4. **Given** a No limit account with a monthly period, **When** the Accounts list is shown, **Then** its subtitle reads "<session kind> · no limit / month".
5. **Given** the Value as pop-up is open, **When** the user looks at its entries, **Then** it offers "None" first, then the built-in and manually priced models, then a "More" submenu with the imported models.

---

### User Story 4 - Free and paid models of one gateway as two accounts (Priority: P3)

The developer's gateway profile uses free `rits/` models and paid Anthropic and OpenAI models that count against a monthly allowance of 300 US$. They create two token-based Claude Code accounts with the same Claude Code directory and the session kind "Other provider" (spec 038 FR-002): a No limit account with the condition "Model starts with `rits/`", and an account with an own monthly budget of 300 US$ whose condition selects the paid models. Each gateway record counts for exactly one of them.

**Why this priority**: The attribution rules of specs 037 and 038 already allow it; this story only confirms that a No limit account takes part in attribution like any token-based account.

**Independent Test**: Configure both accounts on one directory with their conditions and check that `rits/` records count for the No limit account and the paid records for the budgeted one.

**Acceptance Scenarios**:

1. **Given** two token-based accounts of the kind "Other provider" that name the same Claude Code directory, one No limit with "Model starts with `rits/`" and one with an own budget and a condition matching the paid models, **When** a session of that directory holds gateway records of both kinds, **Then** the `rits/` records count for the No limit account and the paid records for the budgeted account, and neither goes to Unassigned.

---

### Edge Cases

- **Only No limit accounts are configured.** The menu bar shows what it shows today when no entry is shown in bar.
- **A No limit account has no usage in its period.** The section shows the headline "0" with "this week" (or "this month", or the value line) left of the reset text and no Details, as a section without usage does today.
- **The Value as model is the model the records actually name.** The value equals what the records would cost with their real price; no special handling.
- **Records of several models in one No limit account.** All are valued at the one Value as model, whatever model they name.
- **A hand-edited configuration gives a No limit account an amount, thresholds, shown-in-bar or a group.** The configuration is invalid (spec 001 FR-033), as for an account with both a group and an own budget today.
- **A hand-edited configuration names a Value as model that is not in the price table.** The configuration is valid; the section shows the missing-model note (story 2, scenario 3). The price table changes through imports, so the reference can go missing at any time.
- **The period changes from weekly to monthly.** The section recounts the tokens for the new window at the next refresh; there is no threshold state to reset.
- **Remaining mode (spec 030).** A No limit account has no thresholds and no percent, so remaining mode does not change it.
- **Demo mode.** The demo app shows the No limit account from its scenario like any other account and makes no network request.

## Requirements *(mandatory)*

### Functional Requirements

Budget choice:

- **FR-001**: Every token-based account MUST have exactly one of: membership in a budget group, its own budget, or **No limit**, whatever its harness (Claude Code, Codex, OpenCode). A configuration where a token-based account has more than one, or none, MUST be invalid (spec 001 FR-033). This replaces spec 004 FR-008.
- **FR-002**: A No limit account MUST have a period (weekly or monthly, with the same window rules and start settings as a budget of that period, spec 003). Absent means weekly. It MUST NOT have an amount, thresholds or a shown-in-bar setting; a configuration that gives it any of these MUST be invalid.
- **FR-003**: A No limit account MAY have one Value as model, given by its model id and looked up in the effective price table with the same model id normalization and fallback used to price records (spec 006 FR-020a, spec 002 FR-003). A Value as model that is not found MUST NOT make the configuration invalid. A Value as model stored for an account with an own budget or in a group MUST be kept, MUST have no effect, and MUST NOT make the configuration invalid.
- **FR-004**: A No limit account MUST NOT be a member of a budget group.

Counting and value:

- **FR-005**: A No limit account MUST take part in attribution like every token-based account (harness, Claude Code directory, session kind and condition; specs 037 and 038). Its records MUST count toward no group and no other account.
- **FR-006**: A No limit account's total MUST be the sum of input, output, cache-write and cache-read tokens of its records in the current window of its period, the same total other sections use.
- **FR-007**: With a Value as model, the account's value MUST be the sum, over its records in the current window, of each record's cost priced exactly as the price table prices a record of the Value as model (every rate it has, including separate 5-minute and 1-hour cache-write rates), as if each record had named the Value as model. Without a Value as model there MUST be no value.
- **FR-008**: The prices of the account's own models MUST NOT be used for anything this account shows, and unpriced models in the account MUST NOT produce an "incomplete, unpriced" note.

Menu bar, thresholds and pace:

- **FR-009**: A No limit account MUST NOT appear in the menu bar, MUST NOT have thresholds or threshold notifications, and MUST NOT show a pace tick, pace note, burn-rate escalation or run-out time (extends spec 011 FR-011).
- **FR-010**: A No limit account MUST keep its place in the arrangement (spec 008 FR-001), so its dropdown section appears in arrangement order. The Menu Bar tab MUST list it without a shown-in-bar control.

Dropdown section:

- **FR-011**: A No limit account's section MUST show a header with its icon and name and, in place of the bold percent, its token total in the format the dropdown uses for token totals, without a unit (for example "48.2M"), with a tooltip giving the exact count, unit and period ("48,213,507 tokens this month"). Below the header it MUST show one line with the value line (FR-012) on the left, or "this week" / "this month" when there is no value line, and the reset text right-aligned, in the section's time format (spec 025 FR-016); when both do not fit on one line, the reset text moves below instead of clipping. No bar.
- **FR-012**: With a value (FR-007), the section MUST show a value line on that line, left of the reset text: "≈ <amount> at <model> prices", the amount rounded to whole US dollars in en_US currency format (amended 2026-11-02, english-number-format; before: the user's locale currency format) ("≈ $0" for exactly 0, "≈ <$1" above 0 and below one dollar, otherwise rounded half up), the model by the model id of the price entry the Value as model resolves to, as the Prices tab shows it (for example `claude-opus-5-5`, also for a stored `claude-opus-5-5@default`); there are no display names for models. Its tooltip MUST say that the value is what the tokens would have cost with that model, and that nothing was spent. The value line MUST NOT use "spent" or "of".
- **FR-013**: When the Value as model is set but not in the effective price table, the section MUST show the neutral note "Value as model <model id> has no price" in place of the value line. The note's text and style MUST be decided by tested core logic like every section note (spec 025 FR-029).
- **FR-014**: The section's Details MUST show the per-model table and the day row in tokens, like a subscription section (spec 026 FR-009: tokens in whole millions, "<1" for small amounts, Σ at the end). A section without usage in its period MUST have no Details.
- **FR-015**: The section's accessibility element MUST read the name, the token total with its period, the reset time and, when present, the value line or the missing-model note.
- **FR-015a**: The headline, the period line, the value line, its tooltip and the accessibility text MUST be produced by tested core logic; the view only renders them (constitution II).
- **FR-015b**: A No limit section MUST show the same stale and no-data notes as an own budget's section (spec 025 FR-029).

Settings:

- **FR-016**: Creating a token-based account MUST offer No limit next to joining an existing group and an own budget (amends spec 004 FR-013). A new No limit account MUST start weekly, without a Value as model, with the time format Relative.
- **FR-017**: The editor of a No limit account MUST show the period, a "Value as" pop-up and the "Times" picker (spec 025 FR-021 applies to No limit accounts too), and MUST NOT show amount, thresholds or "Show in menu bar". The Value as pop-up MUST offer "None" first, then the built-in and manually priced models sorted by model id, then a "More" submenu with the imported models (provider and CSV imports) sorted by model id, each model by its model id as the Prices tab shows it and once only, under its effective source. A configured Value as model that is missing from the price table MUST appear selected and marked as missing, and one that is priced only through model id normalization or prefix fallback MUST appear selected as stored, so opening the editor does not change it.
- **FR-018**: Settings MUST let the user switch a token-based account between No limit, an own budget and a group in every direction (amends spec 004 FR-014):
  - From No limit to an own budget: prefilled with the account's period, thresholds 80% and 100% and shown in bar; the amount is empty and MUST be entered (greater than 0, spec 003 FR-019) before the change can be saved.
  - From No limit to a group: as joining a group today; the member's shown-in-bar setting starts off (spec 004 FR-016).
  - From an own budget or a group to No limit: the period and its start setting are taken from the own budget or the group; amount, thresholds and shown-in-bar are discarded. The time format is the account's stored value, else the own budget's, else Relative.
  - Leaving a group for No limit keeps the group, also when it is left without members (spec 009 FR-002: a group is never deleted implicitly), and spec 008 FR-006 (the account's place in the arrangement after leaving a group).
  - The Value as model is kept in the configuration when the account leaves No limit and applies again when it returns.
- **FR-019**: When an account changes to or from No limit, threshold state tied to its previous budget MUST be dropped, and the first refresh after a change to a budget MUST establish a baseline without notifying for thresholds already exceeded (spec 004 FR-015).
- **FR-020**: The Accounts list subtitle of a No limit account MUST read "<session kind> · no limit / week" or "<session kind> · no limit / month" (amends spec 018 FR-001), and VoiceOver MUST read it as "<session kind>, no limit, per week" or "per month" (spec 018 FR-007a). The subtitle MUST follow the unsaved Settings draft (spec 018 FR-005).

Documentation and website:

- **FR-021**: `docs/configuration.md` MUST describe the No limit choice, its configuration keys and validation, and the Value as model, with the gateway example of story 4 (free models under a gateway prefix and a paid budget on one directory, with invented ids). The release notes MUST name the feature.
- **FR-022**: The demo scenario MUST include a No limit account valued as a built-in model, with usage in its period, and the demo coverage test MUST check that its section shows a token headline and a value line and that it has no menu bar entry (constitution V). The plan's "Screenshots and website" section MUST name the shots that change and whether the feature earns a card candidate.

### Key Entities

- **Budget choice**: what a token-based account is measured against: group membership, own budget, or No limit. Exactly one per account.
- **No limit setting**: period (weekly or monthly with its start), optional Value as model, time format. No amount, thresholds or shown-in-bar.
- **Value as model**: a reference to one price table entry; its rates value all tokens of the account. Notional: it never counts as spend anywhere.
- **Value**: the computed approximate US dollar amount for the current window, or absent (no Value as model, or the model missing from the price table).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can set up an account for unlimited models, including its period and Value as model, entirely in one Settings account editor, without editing the configuration file.
- **SC-002**: For 100% of No limit accounts, the menu bar shows no entry, and no threshold notification, pace note or "incomplete, unpriced" note appears for them, whatever their usage.
- **SC-003**: The computed value matches a hand computation from the record token counts and the reference model's rates to the cent, and the value line shows it rounded to whole dollars, in 100% of tested cases.
- **SC-004**: Every switch between No limit, own budget and group in Settings leaves a valid configuration that loads again unchanged, in 100% of tested switch paths.
- **SC-005**: In the gateway setup of story 4, every "Other provider" record of the shared directory that one of the two conditions matches counts for exactly one of the two accounts, and none of them goes to Unassigned.

## Assumptions

- The paid gateway models carry model ids that a condition (spec 038) can tell apart from the free `rits/` models and from Vertex records in the same directory, for example "Model matches `^(claude|gpt)`". The exact ids are checked against real records during planning; if they need a new kind of condition, that is a separate change.
- One Value as model per account is enough; a per-model mapping is out of scope (brainstorm 41, approach B).
- The value is shown per account only; a total across No limit accounts is out of scope.
- Quarterly, yearly and one-time budgets are out of scope; the paid allowance of 300 US$ is monthly and fits an own budget.
- The token-total format of the dropdown (as used by subscription sections and Unassigned) is reused for the headline; no new number format is introduced.
- Configurations written before this feature load unchanged, since none of them has a No limit account.
