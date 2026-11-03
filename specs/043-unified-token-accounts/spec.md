# Feature Specification: Unified Token Accounts

**Feature Branch**: `043-unified-token-accounts`

**Created**: 2026-11-03

**Status**: Implemented

**Input**: User description: brainstorm `brainstorm/43-unified-token-accounts.md` (Unified token accounts): one kind of token-based account with an optional amount, pricing derived from the price table, and a per-account Show choice (Automatic, Percent, Tokens, Money) for the dropdown. Spec 041's "No limit" becomes an own budget without an amount. Supersedes brainstorm 42.

This feature changes rules from earlier specs: spec 041 FR-001, FR-002, FR-003, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-016, FR-017, FR-018, FR-019, FR-020, FR-022 (No limit as a separate budget choice, its value, Settings and demo), spec 004 FR-008, FR-013, FR-014, FR-015 (budget choice of a token-based account and its threshold state), spec 003 FR-001 and FR-019 (a budget's amount is required and greater than 0), spec 030 FR-012 (a Money headline in remaining mode).

Examples assume the en_US locale, as published screenshots do.

## Clarifications

### Session 2026-11-03

- Q: Does a menu bar entry need priced models in addition to an amount above 0? → A: No, the amount alone decides. Pricing is derived from records, which an empty period does not have, so Settings cannot know it in advance; an account with an amount and only unpriced models shows the "incomplete, unpriced" note, as today.
- Q: How precise is the Money headline? → A: Whole US dollars in en_US format, rounded half up ("$37"; "$0" for exactly 0; "<$1" above 0 and below one dollar), like the token headline it is compact; its tooltip gives the exact amount with cents ("$37.42 spent this month").
- Q: What is the Show pop-up called in the account editor? → A: "Dropdown shows", with the entries Automatic, Percent, Tokens and Money, so it is not confused with "Show in menu bar".
- Q: Does a Money headline follow remaining mode (spec 030) on an account with an amount? → A: Yes, like the percent: in remaining mode it shows the amount left, or over, as the amount line does ("$63", tooltip "$62.58 left of $100/month"); a Tokens headline always shows the tokens used.
- Review-spec decisions (maintainer, 2026-11-03): migrated accounts look unchanged only when their records are all unpriced; switching from a group to an own budget keeps today's prefill; a Money headline over the amount shows "−$12"; Details follow the headline (cost per model under Money); a set Value as model always shows its value line, "≈ $0" included; a missing Value as model also lets the "incomplete, unpriced" note through under Money; the Menu Bar tab captions an account without an amount "No limit"; "Dropdown shows" is hidden for group members and kept; `"budgetUSD": null` means no amount.
- Walkthrough decision (maintainer, 2026-11-03): spec 041's "Value as" pop-up is labeled "Price tokens as" in Settings and in the missing-model note ("Price tokens as: <model id> has no price"); the configuration key stays `valueAs`. The help texts of controls that need an amount name the period's budget ("Set a monthly budget to use thresholds and the menu bar.") instead of "an amount".
- Walkthrough decision (maintainer, 2026-11-03): the token tooltip uses the scale word ("48.2 million tokens this month") from a million on instead of the exact count.
- Review-plan decisions (maintainer, 2026-11-03): a Money headline in remaining mode shows "<$1" left and "−<$1" over; the new account sheet keeps today's preselection; the Menu Bar tab's disabled checkbox of an account without an amount is unchecked.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - An account without a limit is an own budget without an amount (Priority: P1)

The developer adds a token-based account for free gateway models. In the account editor, the budget choice offers only "Own budget" and the groups. They leave the Amount field empty; it shows the placeholder "No limit". The thresholds and "Show in menu bar" are visible but disabled, because there is no amount to measure against. The account counts the tokens of its period and shows them in the dropdown, exactly as a spec 041 No limit account does today.

**Why this priority**: This is the simplification the maintainer asked for: one kind of token account and one fewer budget choice. Everything else builds on it.

**Independent Test**: Create a token-based account with an own budget and an empty amount in Settings, save, reopen, and check that the configuration stores no amount, that the dropdown section shows the token headline and that the menu bar has no entry for it.

**Acceptance Scenarios**:

1. **Given** the user adds a token-based account, **When** they look at its budget choice, **Then** it offers "Own budget" and the existing groups, and no "No limit" entry.
2. **Given** an own budget with an empty Amount field, **When** the editor is shown, **Then** the field shows the placeholder "No limit", and the thresholds and "Show in menu bar" controls are visible and disabled.
3. **Given** an own budget with an empty amount, **When** the user saves, **Then** saving succeeds and the account has no limit.
4. **Given** an own budget without an amount, monthly, whose records of the current month are all unpriced and hold 48.2 million tokens, **When** the dropdown is shown, **Then** its section shows "48.2M" as its headline and "this month" with the reset text, as spec 041 FR-011 describes, and no bar, pace or "incomplete, unpriced" note.
5. **Given** an own budget without an amount, **When** the menu bar is drawn and the usage grows by any amount, **Then** the menu bar has no entry for it and no threshold notification is sent for it.

---

### User Story 2 - Pay-as-you-go spend without a cap (Priority: P1)

A user tracks a direct API key that is billed per token without any monthly cap. They create a token-based account with an own budget and leave the amount empty. Its models are in the price table, so the dropdown headline shows the real money spent this period ("$37.42"), worded as spend, without "≈". No percent, bar, pace, thresholds or menu bar entry appear, because there is no limit.

**Why this priority**: This is the case brainstorm 42 wanted to cover. With the unified account it needs no new account kind, only the money headline.

**Independent Test**: Configure an own budget without an amount whose records name priced models, and check that the section headline is the summed real cost, that the period line says "spent this month" and that no value line or "≈" appears.

**Acceptance Scenarios**:

1. **Given** an own budget without an amount, monthly, Show set to Automatic, whose records in the current month name priced models and cost 37.42 US$ in total, **When** the dropdown is shown, **Then** the section headline shows "$37" with the tooltip "$37.42 spent this month", the line below it reads "spent this month" with the reset text, and nothing in the section uses "≈".
2. **Given** that account also has records of an unpriced model and no Value as model, **When** the dropdown is shown, **Then** the section shows the usual "incomplete, unpriced" note, as an own budget does today.
3. **Given** that account, **When** the menu bar is drawn, **Then** it has no entry for the account.

---

### User Story 3 - Choose what the dropdown shows (Priority: P2)

The account editor has a "Dropdown shows" pop-up with Automatic, Percent, Tokens and Money. Automatic picks the measure that fits the account: percent with an amount, money without an amount when the period has priced usage, tokens otherwise. A user who thinks in tokens sets their budgeted account to Tokens; the headline then shows the token count while the amount line, bar and pace stay as they are.

**Why this priority**: The maintainer chose to keep this override (approach B). Automatic covers every account without any setting, so the choice is a refinement, not a requirement for stories 1 and 2.

**Independent Test**: For one account with an amount and one without, step the "Dropdown shows" pop-up through every entry and check the headline of the dropdown section after each step.

**Acceptance Scenarios**:

1. **Given** a new token-based account with Own budget, **When** the editor is shown, **Then** "Dropdown shows" is Automatic.
2. **Given** an own budget with an amount of 100 US$ and 37.42 US$ spent, **When** "Dropdown shows" is Automatic or Percent, **Then** the headline is "37%" and the section is unchanged from today.
3. **Given** the same account, **When** "Dropdown shows" is Money, **Then** the headline is the spent amount; **When** it is Tokens, **Then** the headline is the token total; in both cases the amount line, bar, pace and thresholds stay as they are.
4. **Given** an own budget without an amount, **When** the "Dropdown shows" pop-up is open, **Then** Percent is disabled.
5. **Given** an own budget without an amount and only unpriced records, **When** "Dropdown shows" is Money, **Then** the headline is "$0" and the section shows the "incomplete, unpriced" note, unless a Value as model is set.
6. **Given** an account whose "Dropdown shows" is Percent, **When** the user empties its amount, **Then** the dropdown shows what Automatic would show, and the stored Show stays Percent, so it applies again once an amount is entered.

---

### User Story 4 - Existing No limit accounts keep working (Priority: P2)

A user upgrades with a configuration from spec 041 that has a No limit account valued as `claude-opus-5-5`. AgentTacho loads it as an own budget without an amount, with its period and Value as model. For an account whose records are all unpriced, as for free gateway models, the dropdown looks as before. The next save writes the account in the new form.

**Why this priority**: The maintainer's own configuration has such an account; it must not break.

**Independent Test**: Load a configuration with a spec 041 No limit account, compare its dropdown section with the one before the change, save, and check the written configuration.

**Acceptance Scenarios**:

1. **Given** a configuration with a No limit account (monthly, Value as `claude-opus-5-5`) whose records are all unpriced, **When** it loads, **Then** the account is an own budget without an amount, monthly, with that Value as model, Show Automatic, and its section shows the token headline and "≈ $412 at claude-opus-5-5 prices" as before.
2. **Given** that loaded account, **When** the configuration is saved, **Then** the account is written as an own budget without an amount, and the No limit form is no longer written.
3. **Given** that account in the Accounts list, **When** the list is shown, **Then** its subtitle still reads "<session kind> · no limit / month".

---

### User Story 5 - Adding and removing an amount (Priority: P3)

The user starts an account without an amount and later decides on a monthly cap. They type 300 into the Amount field; the thresholds and "Show in menu bar" become enabled, with 80%, 100% and shown in bar as defaults, and Automatic switches the headline to percent. Clearing the amount again disables them and returns the account to its no-limit headline.

**Why this priority**: The switch is the price of having one account kind; it must be smooth, but it follows from stories 1 and 3.

**Independent Test**: Toggle the amount of one account between empty and 300 several times and check the controls, the stored configuration, the menu bar entry and the threshold state after each change.

**Acceptance Scenarios**:

1. **Given** a new account without an amount, **When** the user enters 300, **Then** the thresholds show 80% and 100%, "Show in menu bar" is on, and both controls are enabled.
2. **Given** an account with an amount, thresholds 50% and 90% and shown in bar off, **When** the user clears the amount and saves, **Then** the thresholds and shown-in-bar setting are kept in the configuration, have no effect, and come back when an amount is entered again.
3. **Given** an account whose amount was cleared, **When** an amount is entered again, **Then** the first refresh establishes a threshold baseline without notifying for thresholds already exceeded.

---

### Edge Cases

- **An account mixes priced and free models and has no amount.** Automatic shows Money (the period has priced usage). The headline is the real spend of the priced records. Without a Value as model the unpriced records produce the "incomplete, unpriced" note; with a Value as model they are valued in the value line instead, worded as spec 041 FR-012 words it, so the real headline and the notional value line never look alike.
- **An account without an amount has no usage in its period.** Automatic shows Tokens, so the headline is "0" with the period line, as a spec 041 section without usage does today. The headline moves to money with the first priced record of the period.
- **A migrated No limit account with priced records.** Automatic shows Money, and only its unpriced records are valued at the Value as model (FR-006), where spec 041 valued every record and always showed tokens. Setting "Dropdown shows" to Tokens keeps the token headline.
- **A Value as model on an account with an amount.** It is kept and has no effect; the editor shows it disabled.
- **A hand-edited configuration gives an own budget an amount of 0 or less.** The configuration stays invalid (spec 003 FR-019); only an absent amount means no limit.
- **A hand-edited configuration gives a spec 041 No limit account an amount, thresholds or shown-in-bar.** The configuration stays invalid (spec 041 FR-002), so an old file never changes its meaning silently.
- **An account has both a No limit form and an own budget in the file.** Invalid, as an account with two budget choices is today (spec 001 FR-033).
- **Remaining mode (spec 030).** Applies to accounts with an amount as today, and a Money headline on them shows the amount left or over; an account without an amount has no percent and is not changed by it.
- **Group members.** A group always has an amount; "Dropdown shows" applies to accounts with their own budget only (FR-018a).
- **Demo mode.** The demo shows the scenario's accounts as configured and makes no network request.
- **A `show` key on a subscription or Codex account.** It does not apply there: the load gives a note, and the next save drops it.
- **Kept thresholds of an account without an amount.** They are validated like a budget's (a threshold of 0 or less makes the file invalid), since they apply once an amount is entered (FR-003).
- **A hand-written `budget` without `budgetUSD` and without `thresholds`.** It loads with no thresholds, as a budget object without `thresholds` does today; only new accounts from Settings and the spec 041 form get 80% and 100% (FR-004, FR-017).
- **Refresh log.** The diagnostic log line of an account without an amount names its tokens, its spend and its unpriced models, so a headline that changes between Tokens and Money can be explained from the log.

## Requirements *(mandatory)*

### Functional Requirements

Budget choice and amount:

- **FR-001**: Every token-based account MUST have exactly one of: membership in a budget group, or its own budget. A configuration where a token-based account has both, or neither, MUST be invalid (spec 001 FR-033). This replaces spec 041 FR-001 and spec 004 FR-008.
- **FR-002**: An own budget's amount MUST be optional. An own budget without an amount MUST have no limit. A stored amount MUST be greater than 0 (spec 003 FR-019); 0 or less MUST stay invalid. A group's amount stays required (spec 003 FR-001). In the configuration file, an absent amount and an amount of `null` both mean no amount.
- **FR-003**: An own budget without an amount MUST keep its period (with its start setting), thresholds and shown-in-bar setting in the configuration. They MUST have no effect while the amount is absent and MUST apply again when an amount is entered.
- **FR-004**: A configuration written before this feature with a spec 041 No limit account MUST load as an own budget without an amount, with the No limit account's period and Value as model, thresholds 80% and 100%, and shown in bar on. Each converted account MUST add exactly one load note to the diagnostic log, worded like the other migration notes (`account "<name>": No limit is now an own budget without an amount; the next save writes the new form`). Configurations written by this version MUST NOT use the No limit form. A No limit form that spec 041 treats as invalid MUST stay invalid.

Pricing and value:

- **FR-005**: Records of an own budget MUST be priced from the effective price table as today, with or without an amount. There MUST be no per-account pricing setting.
- **FR-006**: A Value as model MUST apply only to an own budget without an amount, and only to its unpriced records: their value is computed as spec 041 FR-007 computes it, as if each unpriced record had named the Value as model. Priced records MUST NOT be valued at the Value as model. On an account with an amount, a stored Value as model MUST be kept and MUST have no effect.
- **FR-007**: For an own budget without an amount, unpriced records MUST produce the "incomplete, unpriced" note when the headline is Money and no Value as model is set, and MUST NOT produce it when the headline is Tokens (spec 041 FR-008) or when a Value as model values them. When the Value as model has no price (spec 041 FR-013), the missing-model note replaces the value line, and under a Money headline the unpriced records also produce the "incomplete, unpriced" note.

Gating:

- **FR-008**: An own budget without an amount MUST NOT appear in the menu bar, MUST NOT have threshold notifications, and MUST NOT show a percent, bar, pace tick, pace note, burn-rate escalation or run-out time (spec 041 FR-009 applies to it).
- **FR-009**: Threshold state tied to an account's amount MUST be dropped when the amount is removed, and the first refresh after an amount is entered MUST establish a baseline without notifying for thresholds already exceeded (spec 004 FR-015).

Show choice:

- **FR-010**: Every token-based account with its own budget MUST have a Show setting with the values Automatic, Percent, Tokens and Money. Absent means Automatic. The setting MUST affect only the headline of the account's dropdown section; the menu bar MUST NOT change. Changing it MUST NOT trigger a refresh (presentation only, like the time format).
- **FR-011**: Automatic MUST resolve to Percent when the account has an amount; without an amount, to Money when at least one record in the current window of its period has a price, and to Tokens otherwise.
- **FR-012**: Percent stored for an account without an amount MUST display as Automatic would, without changing the stored setting.
- **FR-013**: The headline MUST show, for Percent, the used percent as today; for Tokens, the token total in the format spec 041 FR-011 uses ("48.2M"), with a tooltip giving the count with its scale word from a million on ("48.2 million tokens this month", "1.2 billion tokens this month") and the exact count below a million ("950,000 tokens this week") (amends spec 041 FR-011, which showed the exact count, walkthrough step 4); for Money, the real spend of the account's priced records in the current window in whole US dollars in en_US format, rounded half up ("$37"; "$0" for exactly 0; "<$1" above 0 and below one dollar), with a tooltip giving the exact amount with cents ("$37.42 spent this month"). On an account with an amount in remaining mode (spec 030), the Money headline MUST show the amount left, or over, as the amount line does (spec 030 FR-012), with the tooltip worded like the amount line ("$62.58 left of $100/month"); over the amount it shows a typographic minus ("−$12"), as the percent headline does ("−15%"), and its tooltip and accessibility text say "over" ("$12.40 over $100/month"); less than one dollar left shows "<$1", less than one dollar over "−<$1". A Money headline MUST NOT use "≈". A Tokens headline MUST always show the tokens used, also in remaining mode.
- **FR-014**: With an amount, the rest of the section (amount line, bar, pace, notes, Details) MUST stay as today whatever the Show setting. Without an amount, the section MUST show spec 041's section (FR-011 to FR-015b) with the headline of FR-013; the line below the headline MUST show the value line whenever a Value as model is set, also as "≈ $0 at <model> prices" when the window has no unpriced records (as spec 041 shows it), otherwise "spent this week" or "spent this month" under a Money headline and "this week" or "this month" under a Tokens headline, left of the reset text. Under a Money headline, the Details MUST show the cost per model as an own budget's Details do today; under a Tokens headline they MUST show tokens (spec 041 FR-014).
- **FR-015**: The value line (spec 041 FR-012) MUST keep its wording, "≈", rounding and the tooltip that nothing was spent. When the account also has priced records, its tooltip MUST say that the value covers the tokens of models without a price.
- **FR-016**: The headline, the line below it, their tooltips and the section's accessibility text MUST be produced by tested core logic (constitution II); the accessibility text MUST read the exact amount with its period ("$37.42 spent this month"; in remaining mode "$62.58 left of $100/month") or the token count with unit and period ("48.2 million tokens this month").

Settings:

- **FR-017**: The budget choice of a token-based account MUST offer Own budget and the existing groups, and MUST NOT offer No limit (amends spec 041 FR-016 and spec 004 FR-013). The new account sheet keeps today's preselection (the first group when one exists); when the user picks Own budget, it MUST start without an amount, weekly, thresholds 80% and 100%, shown in bar on, no Value as model, Show Automatic and time format Relative.
- **FR-018**: The own budget editor MUST show the Amount field with the placeholder "No limit" when empty, the period, the thresholds, "Show in menu bar", the Value as pop-up (spec 041 FR-017's entries), the Show pop-up, labeled "Dropdown shows" with the entries Automatic, Percent, Tokens and Money, and the Times picker. Without an amount, the thresholds and "Show in menu bar" MUST be disabled, not hidden, with a help text saying that they need an amount; "Show in menu bar" is then disabled and unchecked, the kept value applies again once an amount is entered. With an amount, the Value as pop-up MUST be disabled with a help text saying that it applies only without an amount. Percent in the Show pop-up MUST be disabled without an amount; when Percent is stored and the amount is empty, the pop-up MUST show Percent selected and disabled, with a help text saying that the headline follows Automatic.
- **FR-018a**: The "Dropdown shows" pop-up MUST be hidden for group members. The stored Show setting MUST be kept while the account is in a group and MUST apply again when it returns to an own budget.
- **FR-019**: Saving an own budget with an empty amount MUST succeed (amends spec 041 FR-018, which refused it). Switching between an own budget and a group MUST work in both directions as today; switching from a group to an own budget MUST prefill the group's period, amount, thresholds and shown-in-bar setting (spec 004 FR-014, unchanged).
- **FR-020**: The Menu Bar tab MUST list an account without an amount with its shown-in-bar control disabled and unchecked (the bar shows no entry for it) and a help text saying that it needs an amount, and with the caption "No limit", as the Accounts list subtitle names it (amends spec 041 FR-010).
- **FR-021**: The Accounts list subtitle of an own budget without an amount MUST read as spec 041 FR-020 defines for a No limit account ("<session kind> · no limit / month"), including its VoiceOver text and the unsaved draft.

Documentation and website:

- **FR-022**: `docs/configuration.md` and `docs/accounts-and-budgets.md` MUST describe the optional amount, the Show setting with its configuration key, the Value as rule for unpriced records and the migration of the No limit form. The release notes MUST name the change.
- **FR-023**: The demo scenario MUST keep the free-models account (now an own budget without an amount, valued as a built-in model) and MUST add an own budget without an amount whose records are priced, so the dropdown shows a Money headline; the demo coverage test MUST check both headlines and that neither has a menu bar entry (constitution V). The `no-limit` shot MUST keep cropping the free-models section, the first account without an amount in arrangement order; the new priced account comes after it. The plan's "Screenshots and website" section MUST name the shots and copy that change.

### Key Entities

- **Own budget**: period (weekly or monthly with its start), optional amount greater than 0, thresholds, shown-in-bar, optional Value as model, Show setting. Without an amount it has no limit. The time format stays an account setting.
- **Show setting**: Automatic, Percent, Tokens or Money; decides the dropdown headline only.
- **Resolved headline**: the measure the section shows after Automatic and the amount rule are applied.
- **Value as model**: a reference to one price table entry that values the unpriced records of an account without an amount. Notional: it never counts as spend.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The budget choice of a token-based account has two kinds of entries (own budget, groups) instead of three, and a user can set up an account with no limit, with real spend or with a cap in one editor without editing the configuration file.
- **SC-002**: For 100% of accounts without an amount, the menu bar shows no entry and no threshold notification, pace note or percent appears, whatever their usage.
- **SC-003**: 100% of configurations with spec 041 No limit accounts load without error, and for every such account whose records in the period are all unpriced, the dropdown section shows the same headline, value line and reset text as before the change.
- **SC-004**: The exact amount in the Money headline's tooltip matches the hand-computed real cost of the priced records to the cent, and the headline shows it rounded to whole dollars, in 100% of tested cases; no Money headline contains "≈".
- **SC-005**: Every change between an empty amount, an amount and a group in Settings leaves a valid configuration that loads again unchanged, in 100% of tested paths.

## Assumptions

- Group budgets always have an amount; groups without an amount and a Show choice for groups are out of scope.
- The Show choice does not apply to the menu bar; a total across accounts and price aliases for free models are out of scope (brainstorm 43).
- Older AgentTacho versions cannot read a configuration written by this version when it has an own budget without an amount; downgrades are not supported, as for earlier configuration changes.
- The Money headline reuses the whole-dollar rounding of spec 041's value line, without "≈"; no new number format is introduced.
