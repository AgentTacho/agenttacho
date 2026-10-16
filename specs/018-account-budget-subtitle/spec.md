# Feature Specification: Account Budget Subtitle

**Feature Branch**: `018-account-budget-subtitle`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Account budget subtitle (from brainstorm/17-account-budget-subtitle.md). In Settings > Accounts, the subtitle of a token-based account names its provider and the budget its spend counts against, with amount and period: 'Vertex · [group icon] Vertex, $400 / month' or 'OpenAI · own budget, $50 / week'. The Groups list uses the same amount style: '$400 / month, 2 member(s)'. Planned as release 0.4.1, also the first end-to-end test of the one-click update from 0.4.0."

This feature changes two lines of text in Settings. In Settings > Accounts, each account row shows the account name and a subtitle; for a token-based account the subtitle today says only "token-based (Vertex)". In Settings > Groups, each group row shows the group name and a subtitle "$400.00 per month, 2 member(s)". The **budget** of a token-based account is either a budget group it belongs to (spec 004, spec 009) or its own budget. A **missing group** is a group id that names no existing group. Configuration validation rejects such a file, so it should never reach Settings; the subtitle still handles it defensively, and this case is verified at unit level (SC-002), not by hand-editing the file.

## Clarifications

### Session 2026-10-16

- Q: What does the subtitle say for an account whose group does not exist? → A: "<provider> · no group", for example "Vertex · no group"; the dangling id is not shown.
- Q: What does VoiceOver read for the Accounts subtitle? → A: The icon glyph is hidden from accessibility; the subtitle is read as "<provider>, group <name>, <amount> per <period>" (or "own budget", "no group"), for example "Vertex, group Vertex, $400 per month".
- Q: Which icon is shown for a group whose icon id is not in the catalog? → A: The same fallback the Budget picker uses for that group.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See where an account's spend counts (Priority: P1)

A user with several token-based accounts opens Settings > Accounts. Without selecting each account, they see for every token-based account its provider, which budget its spend counts against (a group, shown with the group's icon and name as in the account editor's Budget picker, or its own budget), and how large that budget is per week or month. When they move an account to another group, rename or re-icon a group, or change an amount, the subtitle follows at once, before they save.

**Why this priority**: This is the reason for the feature: since explicit group management, accounts move between groups and groups can stay empty, and the list does not say where spend counts.

**Independent Test**: Configure an account in a monthly group of 400 USD, an account with its own weekly budget of 50 USD, and a subscription account; open Settings > Accounts and read the three subtitles; move the first account to its own budget and watch the subtitle change before saving.

**Acceptance Scenarios**:

1. **Given** a Vertex account in the monthly group "Vertex" with a budget of 400 USD, **When** the Accounts list is shown, **Then** its subtitle reads "Vertex · " followed by the group's icon, then "Vertex, $400 / month".
2. **Given** an OpenAI account with its own weekly budget of 50 USD, **When** the Accounts list is shown, **Then** its subtitle reads "OpenAI · own budget, $50 / week".
3. **Given** a budget with cents, for example 99.50 USD per month, **When** the subtitle is shown, **Then** the amount keeps its cents: "$99.50 / month".
4. **Given** the Accounts tab is open, **When** the user changes an account's provider, moves an account to another group or to its own budget, removes a group with members (spec 009 FR-010), changes a group's name, icon, period or amount, or changes an own budget's amount or period, **Then** the affected subtitles show the new values without saving first (for a group removed in the Groups tab, when the user returns to the Accounts tab).
5. **Given** a Claude or ChatGPT subscription account, **When** the Accounts list is shown, **Then** its subtitle is unchanged ("Claude subscription", "ChatGPT subscription").
6. **Given** a token-based account whose group id names no existing group (a defensive case that validation normally prevents; verified in unit tests), **When** its subtitle is built, **Then** its subtitle names the provider and says that no group exists, for example "Vertex · no group", instead of an empty or broken name.

---

### User Story 2 - One amount style in Settings (Priority: P2)

The same user opens Settings > Groups. Each group's subtitle shows its amount in the same compact style as the Accounts list, followed by its member count, so both lists read alike.

**Why this priority**: Consistency of the two lists; the group list already shows the right information, only its style changes.

**Independent Test**: With the groups of User Story 1, open Settings > Groups and read the subtitles.

**Acceptance Scenarios**:

1. **Given** the monthly group "Vertex" of 400 USD with 2 members, **When** the Groups list is shown, **Then** its subtitle reads "$400 / month, 2 member(s)".
2. **Given** a weekly group of 99.50 USD with no members, **When** the Groups list is shown, **Then** its subtitle reads "$99.50 / week, 0 member(s)".

---

### Edge Cases

- A long group name: the subtitle stays on one line, truncated at the tail, so the provider and the start of the budget stay visible.
- A group whose icon id is not in the icon catalog shows the same fallback the Budget picker shows for it.
- An account that moves from a group to its own budget shows "own budget" with the group's former period and amount, which moving out of a group prefills (spec 004 FR-014).
- An amount of 0 or less (the editor already reports it as invalid) is shown as entered, for example "$0 / month".
- Currency symbol, its position and digit grouping follow the user's locale, as the other amounts in the app do; a German locale may show "400 $ / month" (symbol after the number) but keeps the " / month" or " / week" wording of the app.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Accounts list subtitle of a token-based account MUST consist of the provider's display name, a middle dot, and the budget: for a group member, the group's icon, a space, and the group's name; for an own budget, the words "own budget". After the budget, separated by a comma, MUST follow the budget's amount and period in the style of FR-003.
- **FR-002**: For a token-based account whose group id names no existing group, the subtitle MUST name the provider and say that there is no group ("Vertex · no group"), without an amount.
- **FR-003**: Budget amounts in both Settings lists MUST be shown as a currency amount in US dollars, rounded to cents, then without decimals when the rounded amount is a whole number and with exactly two decimals otherwise, followed by " / month" for a monthly or " / week" for a weekly budget. Number and currency formatting MUST follow the user's locale.
- **FR-004**: The Groups list subtitle MUST show the amount in the style of FR-003 followed by ", N member(s)", replacing today's "$400.00 per month, 2 member(s)".
- **FR-005**: Both subtitles MUST reflect the unsaved Settings draft: a change to an account's provider or budget membership, the removal of a group with members, a group's name, icon, period or amount, or an own budget's period or amount MUST show in the subtitles without saving.
- **FR-005a**: The Accounts subtitle MUST stay on one line, truncated at the tail.
- **FR-006**: Subscription account subtitles MUST stay unchanged.
- **FR-007**: The group's icon in the Accounts subtitle MUST be the same icon the account editor's Budget picker shows for that group, sized to the subtitle text.
- **FR-007a**: The Accounts subtitle MUST be read by VoiceOver without the icon glyph, as "<provider>, group <name>, <amount> per <period>", "<provider>, own budget, <amount> per <period>" or "<provider>, no group".
- **FR-008**: The subtitle text (provider, budget, amount and period) MUST be produced by logic that can be tested without the user interface; only drawing the icon glyph is left to the view.

### Key Entities

- **Account budget description**: for one account, the provider name, the kind of budget (group with icon and name, own budget, or missing group) and, unless the group is missing, the amount and period.
- **Budget amount text**: an amount and a period rendered in the FR-003 style; shared by both lists.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the configuration of User Story 1, a user names the budget and its size for every token-based account from the Accounts list alone, without selecting any account.
- **SC-002**: Tests cover each budget kind (group, own budget, missing group), both periods, whole and fractional amounts, and the Groups list text, and all pass.
- **SC-003**: After any of the edits in User Story 1 scenario 4, the affected subtitles show the new values in the same Settings session, before saving, in 100% of tested cases.
- **SC-004**: The Accounts and Groups lists use one amount style: for the same budget, both show the identical amount text.

## Assumptions

- "$400 / month" describes the style; the literal examples in this spec assume an en_US locale, tests pin the locale, and the symbol placement otherwise follows the locale (FR-003).
- The amount formatter is new testable logic (FR-008); the app's existing `UsageFormat.budget` drops a trailing zero ("$99.5") and is not reused unchanged.
- The dropdown's budget line ("1.595 of 300 US$/month") keeps its style; this feature changes only the two Settings lists.
- The middle dot and the comma separators are fixed; no localization of the wording beyond number formatting, as in the rest of the app.
- No configuration, network, credential or README change is needed; the README does not describe these subtitles.
- This change ships as 0.4.1; the release itself (tag, notarization, cask) follows the existing release process and is not part of this spec.
