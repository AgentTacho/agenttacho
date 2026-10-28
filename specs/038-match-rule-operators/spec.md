# Feature Specification: Session Kinds and Match Conditions for Token-Based Accounts

**Feature Branch**: `038-match-rule-operators`

**Created**: 2026-10-27 (reworked 2026-10-28)

**Status**: Draft

**Input**: Brainstorm `brainstorm/38-match-rule-operators.md` with its revisit of 2026-10-28: "The account type already says pay per token. A session kind says which per-token sessions; an optional 'Only when' condition narrows that kind and never widens it. Claude Code: Directory only, Vertex, Other provider. Codex: API-key sessions, no pop-up. OpenCode: Vertex, OpenAI, Other provider (condition required). Section 'Which sessions count'; no 'profile', 'Match rule' or 'Custom' in the UI." The first version of this spec (operators, case-insensitive matching, the 50 ms limit, the layout pass) is kept and folded in.

## Background

Spec 037 (merged, not yet released; the last release is v0.8.0) gave every token-based account a match rule: a preset (Claude Code "Vertex", Codex "API key", OpenCode "Vertex" and "OpenAI"), "Custom" (a field and a text) or, for Claude Code, "None (profile only)". The first version of this spec added operators to custom rules and reworked the Settings layout.

Its walkthrough on 2026-10-28 showed that the rule pop-up mixes two different questions:

1. **Which sessions** the account pays for: Codex sessions signed in with an API key rather than a ChatGPT plan; OpenCode messages of one provider; Claude Code records billed through Vertex or through another provider such as a company gateway.
2. **Which of those**: an optional narrowing condition (field, operator, text).

"Custom" sat next to the presets as an alternative, but it only checks its text, never the sign-in or the provider, and it wins over every built-in rule (spec 037 FR-010). A Codex account with Custom "Model starts with gpt-5" therefore also takes the ChatGPT-plan sessions of the Codex subscription, and a broad Claude Code custom rule can take direct Anthropic records of a Claude subscription. For a token-based Codex account "API key" is always implied, so offering it as a choice confused the maintainer.

The walkthrough also found wording problems. "Profile" is a term of workspace managers such as cc-deck; Claude Code calls it the configuration directory, and AgentTacho's field is "Claude Code directory". "Match rule", "Custom" and "None (profile only)" describe the mechanism, not what the user wants to say.

## Clarifications

### Session 2026-10-27 (first version, still valid)

- Q: What happens when a regular expression is slow on every record line, not just one? → A: Matching one record (any field) gets a time limit of 50 ms; after the first record that exceeds it, the condition matches no further record for the rest of that refresh, and the log says so once per refresh (FR-007).
- Q: Do the built-in kinds (such as Vertex, request id starts with `req_vrtx_`) also ignore case? → A: No. Kinds keep their exact built-in checks; only conditions ignore case (FR-005).
- Q: When the Condition row is too narrow for both pop-ups and the text field, what gives way? → A: The text field moves to a second line inside the same row; the pop-ups keep their width and nothing is clipped (FR-015).
- Q: What does the operator pop-up call the regular expression choice? → A: "matches regex" (FR-005).

### Session 2026-10-28 (rework, from the brainstorm revisit)

- Q: Which session kinds does a token-based Claude Code account offer? → A: Directory only (default), Vertex, Other provider (FR-001).
- Q: How does the optional condition appear? → A: An "Only when" checkbox that reveals the Condition row (FR-014).
- Q: Which word replaces "profile" in the UI? → A: "Claude Code directory", Claude Code's own term is the configuration directory (FR-017).
- Q: How does a user with a per-token Anthropic API key (records like a subscription's, `req_011…`) set up a Claude Code account? → A: With its own Claude Code directory and kind Directory only; the documentation says so (edge cases, FR-020).
- Q: What does the account list subtitle show for a token-based account? → A: The kind's short name ("Directory only", "Vertex", "Other provider", "API key", "OpenAI") with the budget, as today; the condition is not shown there (FR-012).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Token-based accounts never take subscription sessions (Priority: P1)

A user has a Codex (Plus) subscription and a token-based Codex account for work billed per API key. The token-based account shows no session-kind choice, only the sentence that it counts Codex sessions signed in with an API key. To split API-key usage between two projects they tick "Only when" and enter Model starts with `gpt-5`. Their ChatGPT-plan sessions with `gpt-5` models keep counting for the subscription.

**Why this priority**: It is the defect the walkthrough found: a condition must never move a session to an account of another kind.

**Independent Test**: Configure a Codex subscription and a token-based Codex account with the condition Model starts with `gpt-5`; feed one ChatGPT-plan session and one API-key session, both with a `gpt-5` model; check that the first counts for the subscription and the second for the token-based account. Repeat for Claude Code: a token-based Vertex account with the condition Model contains `sonnet` must not take a direct Anthropic record of a Claude subscription.

**Acceptance Scenarios**:

1. **Given** a token-based Codex account with the condition Model starts with `gpt-5`, **When** a ChatGPT-plan session uses `gpt-5`, **Then** it does not count for the token-based account.
2. **Given** the same account, **When** an API-key session uses `gpt-5-mini`, **Then** it counts for the token-based account.
3. **Given** a token-based Claude Code account of kind Vertex with the condition Model contains `sonnet`, **When** a record with request id `req_011abc` (direct Anthropic) and model `claude-sonnet-5-5` has no Claude Code directory information, **Then** it does not count for the token-based account.
4. **Given** two token-based Codex accounts without a condition, **When** the user views either in Settings, **Then** the overlap warning names the other account.

---

### User Story 2 - A company gateway without typing a condition (Priority: P1)

A user runs Claude Code against a company gateway from its own Claude Code directory. Its records carry no Anthropic request id. They add a token-based Claude Code account with kind "Other provider". Sessions from that account's Claude Code directory count for it as before; older sessions without directory information count for it too when their records have no Anthropic request id, while Vertex and direct Anthropic records do not.

**Why this priority**: It is the maintainer's own setup, and it removes the need for a hand-typed condition in the common gateway case.

**Independent Test**: Configure a token-based Claude Code account of kind Other provider and a Vertex account on different Claude Code directories; feed records without directory information: one without a request id (model `intranet/glm-5`), one `req_vrtx_…`, one `req_011…`; check that only the first counts for the gateway account.

**Acceptance Scenarios**:

1. **Given** a token-based Claude Code account of kind Other provider, **When** a record without directory information has no request id, **Then** it counts for that account.
2. **Given** the same account, **When** a record without directory information has the request id `req_vrtx_123` or `req_011abc`, **Then** it does not count for that account.
3. **Given** a token-based Claude Code account of kind Directory only, **When** a record without directory information arrives, **Then** it never counts for that account; sessions from its Claude Code directory still do.
4. **Given** a session whose file names this account's Claude Code directory, **When** its records are of another kind or fail the condition, **Then** they still count for the account (spec 037: the directory decides first).

---

### User Story 3 - Narrow a kind with operators (Priority: P2)

A user has two gateway accounts of kind Other provider, one for GLM models and one for the rest. They tick "Only when" on the first and enter Model contains `glm`; on the second Model matches regex `^gateway-(a|b)/`. Case does not matter.

**Why this priority**: The operators from the first version of this spec stay the tool for narrowing; fewer users need them than the kinds.

**Independent Test**: Feed records of the account's kind with models `intranet/glm-5`, `intranet/GLM-5-Air`, `gateway-a/x`, `GATEWAY-B/y` and `gateway-c/z`; check each account's totals; then enter `^gateway-(a` in Settings and check that it is refused.

**Acceptance Scenarios**:

1. **Given** the condition Model contains `glm`, **When** a record of the kind has the model `intranet/GLM-5-Air`, **Then** it counts (case ignored).
2. **Given** the condition Model starts with `intranet/`, **When** a record has the model `INTRANET/glm-5`, **Then** it counts; with starts with `glm` the model `intranet/glm-5` does not.
3. **Given** the condition Model matches regex `^gateway-(a|b)/`, **When** records have `gateway-a/glm-5`, `GATEWAY-B/glm-5` and `gateway-c/glm-5`, **Then** the first two count and the third does not.
4. **Given** the condition Anywhere contains `gateway.example`, **When** a raw record line of the kind contains `Gateway.Example`, **Then** it counts.
5. **Given** the user types `^gateway-(a` in Settings, **When** the change would be saved, **Then** it is not saved, the section's notes say the regular expression is not valid, and the "Not applied" line shows the same problem.
6. **Given** a configuration file with an invalid pattern, **When** AgentTacho loads it, **Then** it loads, the condition matches no record, the log names the account once per load, and Settings shows the pattern with the note until it is corrected.

---

### User Story 4 - "Which sessions count" reads like plain settings (Priority: P2)

A user opens Settings > Accounts and selects a token-based account. The section "Which sessions count" shows a "Sessions" pop-up (not for Codex), an "Only when" checkbox and, when ticked, one Condition row `Model ▾  contains ▾  [glm]`. Below the controls, inside the group, small dimmed notes say what the chosen kind counts, what Anywhere searches, that sessions from the account's Claude Code directory always count, an invalid pattern, and the overlap warning. The words "profile", "Match rule" and "Custom" appear nowhere.

**Why this priority**: The confusion that led to this rework was a UI problem as much as a model problem.

**Independent Test**: Open the section for each harness and kind, with and without a condition, an overlapping pair and a subscription account; check rows, notes, wording and that pop-ups keep their width when the selection changes.

**Acceptance Scenarios**:

1. **Given** a token-based Claude Code account of kind Directory only, **When** the user views the section, **Then** it shows the Sessions pop-up and no "Only when" checkbox, and a note says that only sessions from this Claude Code directory count.
2. **Given** kind Vertex or Other provider, **When** the user ticks "Only when", **Then** the Condition row appears with Model, starts with and an empty text; unticking hides it and keeps it for the next tick.
3. **Given** a token-based Codex account, **When** the user views the section, **Then** there is no Sessions pop-up; a sentence says the account counts Codex sessions signed in with an API key; the "Only when" checkbox is there.
4. **Given** a token-based OpenCode account of kind Other provider, **When** the user views the section, **Then** the Condition row is shown without a checkbox to turn it off, and a blank text is refused.
5. **Given** the field Anywhere, **When** the user opens the operator pop-up, **Then** it offers only "contains" and "matches regex"; switching to Anywhere from "starts with" turns the operator into "contains".
6. **Given** any selection change in the Sessions, field or operator pop-up, **When** the user looks at the row, **Then** no control moves.
7. **Given** a subscription account, **When** the user views its section, **Then** it shows the Custom marker row with its two explanations as caption notes inside the group.

---

### User Story 5 - Existing configurations keep their meaning (Priority: P3)

A user updates from v0.8.0, or from a build of the unreleased specs 037 and 038, and finds every token-based account migrated as FR-011 says: a kind and, where needed, a condition, with a log note where the meaning narrows.

**Why this priority**: v0.8.0 is released; 037/038 builds are only on the maintainer's machine, but their files must still load.

**Independent Test**: Load configuration files of v0.8.0 (provider with and without a token-based marker), of spec 037 (presets, custom rules, "none") and of the first version of 038 (custom rules with operators) and check kind, condition and attribution.

**Acceptance Scenarios**:

1. **Given** a v0.8.0 account with provider "vertex" and a token-based marker `proj-alpha`, **When** AgentTacho loads it, **Then** it is a Claude Code account of kind Vertex with the condition Anywhere contains `proj-alpha`, and the log notes once that a company gateway needs kind Other provider.
2. **Given** a v0.8.0 account with provider "openai", **When** AgentTacho loads it, **Then** it is a Codex account (API-key sessions) without a condition.
3. **Given** a spec 037 Claude Code preset "vertex", **When** AgentTacho loads it, **Then** its kind is Vertex.
4. **Given** a spec 037 or 038 Claude Code custom rule Model starts with `intranet/`, **When** AgentTacho loads it, **Then** its kind is Other provider with that condition.
5. **Given** a spec 037 Claude Code rule "none", **When** AgentTacho loads it, **Then** its kind is Directory only.
6. **Given** a spec 037 or 038 Codex custom rule, **When** AgentTacho loads it, **Then** it counts API-key sessions with that condition; an OpenCode custom rule becomes kind Other provider with that condition.
7. **Given** a loaded file, **When** the next save writes it, **Then** it uses the new form only.

### Edge Cases

- **Blank condition text**: refused whenever the condition is on; turning the condition off is the way to have none.
- **Text with regex metacharacters under starts with or contains**: compared literally.
- **Regex that matches the empty string** (`x*`): valid; it matches every record of the kind whose field is not empty. An empty field never matches.
- **Very long or slow pattern**: matching one record stops after 50 ms and counts as no match; the condition sits out the rest of that refresh (FR-007).
- **Kind change**: the condition stays as it is (on or off, with its field, operator and text); for Directory only it is hidden and kept, and comes back with the next kind that shows it.
- **Harness change**: the kind becomes the harness's default; the condition is kept when its field exists for the new harness, else its field becomes Model.
- **OpenCode Other provider without a condition** in a hand-edited file: loads, matches no record, and Settings asks for a condition with a note.
- **Two accounts of the same kind without a condition** (two Codex API-key accounts, two Other provider accounts on the same Claude Code directory): overlap warning on both.
- **Directory only on a shared Claude Code directory** (for example the default `~/.claude` of a Claude subscription): the account would count nothing; the section shows a warning naming the other account (FR-013).
- **Anthropic API key billed per token**: its records look like a Claude subscription's, so no kind separates them; such an account uses its own Claude Code directory with kind Directory only.
- **A record of a kind no account has** (for example a direct Anthropic record without directory information and no Claude subscription): stays Unassigned, as today.
- **Unicode case**: ignored by the usual Unicode rules (`Ä` matches `ä`); diacritics are not ignored.
- **Overlap of two different patterns** that match the same records: no warning; the documentation says the warning compares conditions as written.

## Requirements *(mandatory)*

### Functional Requirements

**Session kinds**

- **FR-001**: Every token-based account MUST have a session kind, offered per harness in this order (default first):
  - Claude Code: **Directory only**, **Vertex**, **Other provider**.
  - Codex: **API key** only; Settings shows no pop-up for it.
  - OpenCode: **Vertex**, **OpenAI**, **Anthropic**, **Other provider** (Anthropic added at the walkthrough).
- **FR-002**: A kind MUST match only records of the account's harness, with these exact, case-sensitive checks:
  - Claude Code Vertex: the request id starts with `req_vrtx_`. Other provider: the record has no request id starting with `req_`. Directory only: no record (the account counts only sessions from its Claude Code directories).
  - Codex API key: the session signed in with an API key.
  - OpenCode Vertex: the provider is `google-vertex` or `google-vertex-anthropic`; OpenAI: the provider is `openai`; Anthropic: the provider is `anthropic`, which OpenCode reports for an API key and a Claude plan sign-in alike, so the caption says that plan usage counts too; Other provider: a provider other than these four.
- **FR-003**: Sessions that ran from a token-based Claude Code account's Claude Code directories MUST count for it whatever its kind and condition (spec 037 FR-001 to FR-005, unchanged). Kind and condition decide only for records without that information.

**Condition**

- **FR-004**: A token-based account MAY have one condition: a field, an operator and a text. A record counts for the account only when it is of the account's kind **and**, if the condition is on, matches it. A condition never makes a record of another kind count. Fields: Model, Request id, Message id and Anywhere for Claude Code; Model and Anywhere for Codex and OpenCode. Anywhere is the raw record line. The condition is not offered for Directory only, and it is required for OpenCode Other provider.
- **FR-005**: Operators: "starts with" (the field begins with the text), "contains" (the field contains the text) and "matches regex" (the ICU regular expression is found anywhere in the field; `^` and `$` anchor it), with exactly these labels. Anywhere offers "contains" and "matches regex" only. All three ignore case, including Unicode case, and do not ignore diacritics; a pattern may turn case sensitivity back on inline. "Starts with" and "contains" compare the text literally. An empty field never matches.
- **FR-006**: Among token-based accounts of the same harness that a record's kind matches, accounts whose condition matches MUST win over accounts without a condition; if exactly one account remains, the record counts for it, otherwise it stays Unassigned (spec 037 rule step, now inside one kind). Subscription accounts keep their implicit rules (direct Anthropic records for a Claude subscription, ChatGPT-plan sessions for a Codex subscription); a subscription's Custom marker now narrows too: it only decides among records its subscription's implicit rule matches, and can never take a record of a token-based kind. A token-based account never claims a record its kind does not match (maintainer's decision at the spec review).
- **FR-007**: Matching one record with a regular expression MUST stop after 50 ms, for every field. A record that exceeds the limit counts as no match, and the condition then matches no further record for the rest of that refresh; those records go through the remaining accounts as if this condition did not match them. Limit and sitting out apply to each account separately. The log notes it once per refresh with the account's name. The next refresh tries the condition again on the records it sat out; a value the pattern already ran out of time on keeps counting as no match without running again, and when a condition times out again during that retry, the records it sits out are no longer retried until a rule changes (the condition still runs on new records; first version FR-006, maintainer's decisions at the code review). A session file that grew since the sit-out counts as retried, including its new lines, so a time-out on a newly appended line also gives the condition up; after a time-out early in a first scan, the next refresh reads the affected session files once more from the start (maintainer's decisions at the code review of the rework).
- **FR-008**: Settings MUST refuse a regular expression that is not valid and a blank condition text: the change is not saved, the "Not applied" line names the problem, and the section's notes say what is wrong. A configuration file with an invalid pattern MUST still load; the condition matches no record, the log names the account once per load, and Settings shows the pattern with the note; until it is corrected (or the condition is turned off), every automatic save of the window is refused, as for any draft that does not pass the checks.

**Overlap**

- **FR-009**: Settings MUST warn on each of two or more token-based accounts that neither the Claude Code directory nor kind and condition can separate: same harness, same kind, same condition (both off, or same field and operator and texts equal, ignoring case for "starts with" and "contains", exactly as written for "matches regex"), and for Claude Code the same main Claude Code directory. Directory only accounts are separated by their directory alone. The warning names the other accounts and says that records matching both stay Unassigned.

**Configuration**

- **FR-010**: The configuration file MUST store a token-based account's kind and, when on, its condition (field, operator, text) in a form `docs/configuration.md` documents, with fixed values for kinds, fields and operators. Saving MUST always write the new form only.
- **FR-011**: Loading MUST read every earlier form:
  - v0.8.0 `provider` ("vertex" or none: Claude Code, kind Vertex; "openai": Codex), and a token-based `customMarker` as the condition Anywhere contains the marker. In v0.8.0 such a marker matched any record containing it, so a marker that caught gateway records now misses them; the log therefore notes, once per such account, that the marker became a condition of the Vertex kind and that a company gateway needs kind Other provider (maintainer's decision at the spec review).
  - spec 037/038 `matchRule`: a preset becomes its kind; "none" becomes Directory only for Claude Code, API key for Codex, and for OpenCode is read like an unknown value; a custom rule becomes Claude Code Other provider, Codex (API key) or OpenCode Other provider, with the rule's field, operator (missing: starts with, Anywhere: contains) and text as condition.
  - Unknown values make the setting unreadable: the account gets the harness's default kind without a condition (OpenCode: Other provider without a condition, which matches no record until the user sets a condition or chooses another kind, see the edge case "OpenCode Other provider without a condition"), with one load note naming the account. This also holds when only the stored condition is unreadable: a Codex account then counts every API-key session until the user sets the condition again (maintainer's decision at the code review of the rework).
  - The log names each migrated account once.

**Settings**

- **FR-012**: The token-based section MUST be titled "Which sessions count" and hold, in this order: the "Sessions" pop-up (not for Codex; Codex shows the sentence "Counts Codex sessions signed in with an API key."), the "Only when" checkbox (not for Directory only; for OpenCode Other provider the condition is always shown and cannot be turned off), and, when the condition is on, one "Condition" row with the field pop-up, the operator pop-up and the text field. The account list subtitle names the kind's short name ("Directory only", "Vertex", "Other provider", "API key", "OpenAI") with the budget; the condition is not shown there.
- **FR-013**: Below the controls, inside the same group, the section MUST show its notes as caption text (small, secondary color, leading aligned), in this order and only when they apply: what the kind counts (one sentence per kind), the Anywhere caption, the note that sessions from this account's Claude Code directory always count (Claude Code; it names the field's value, says when an empty field means `~/.claude`, and, when other accounts use the same directory, names them and says that the choices above decide among them instead; walkthrough feedback), the invalid pattern or blank text message, the overlap warning with its warning symbol, and, for kind Directory only, a warning with the warning symbol when another account uses the same main Claude Code directory (an empty field counts as `~/.claude`): it names that account, says that sessions from that directory count for it, and asks for this account's own Claude Code directory (maintainer's decision at the spec review).
- **FR-014**: Turning "Only when" on MUST show the Condition row with the account's last condition, or Model, starts with and an empty text the first time; turning it off hides the row and keeps the condition for the next time but stores no condition. Choosing OpenCode Other provider turns the condition on in the same way; choosing another kind afterwards leaves it on. Switching the field to Anywhere while the operator is "starts with" MUST change it to "contains".
- **FR-015**: Pop-ups MUST keep the width of their widest item whatever is selected; no control has a hard-coded width; the text field takes the rest of the row, starts its text at the leading edge, and the Condition row is one fixed line with its label above it, in Settings and in the (wider) sheet alike; field and operator are bordered pop-up buttons as wide as their widest item (walkthrough decisions). Nothing may be clipped at the Settings window's size. The Condition row has one visible label, "Condition"; its controls carry the accessibility labels "Field", "Operator" and "Text". The text field's prompt is an invented example that fits field and operator.
- **FR-016**: The new account sheet MUST offer the same Sessions pop-up (same order, same default), "Only when" checkbox and Condition row, with the same refusal of blank texts and invalid patterns in its validation message on "Add"; its notes stay caption text below the controls. The Directory only warning of FR-013 shows in the sheet too. For token-based Claude Code accounts the sheet also shows the "Claude Code directory" field, so the account gets its own directory in one step (maintainer's decision at the plan review). The sheet is sectioned like the account editor (account, "Which sessions count", Budget) and sized to its content; its Budget section is one pop-up with the existing budget groups and "Own budget", with a note that a shared budget needs a budget group made in the Groups tab first; the sheet no longer creates groups (walkthrough decisions, 2026-10-28).
- **FR-017**: The UI MUST NOT use the words "Match rule", "Custom" or "preset" for token-based accounts, and MUST NOT use "profile" anywhere (subscription captions included); it says "Claude Code directory" for the configuration directory. The field Anywhere is labeled "Anywhere".
- **FR-018**: The subscription "Session matching (advanced)" section keeps its Custom marker (the record line contains the text, case-sensitive), which now applies only to records of the subscription's own kind (FR-006); its two explanations are caption notes inside the group (updated to say so), and its text field has no fixed width.
- **FR-019**: The automatic save (about 0.6 s after an edit), undo, redo and the "Not applied" line MUST work for kind, checkbox and condition like for every other field.

**Documentation**

- **FR-020**: `docs/configuration.md` MUST describe the kinds per harness and what each checks, the condition with its fields and operators, case handling (conditions ignore case; kinds and subscription markers do not), the ICU syntax and the 50 ms limit, the stored form with its values, the migration from v0.8.0 and from spec 037/038 files, that a per-token Anthropic API key needs its own Claude Code directory with Directory only, and that the overlap warning compares conditions as written. `README.md` "How it works" MUST describe kinds and conditions in one or two sentences. The release notes MUST say that token-based accounts now choose a session kind with an optional condition, that conditions ignore case, that markers migrated from v0.8.0 became conditions of the Vertex kind (a gateway needs Other provider), and that subscription markers now only decide among their subscription's own records.

### Key Entities

- **Session kind**: per harness, which per-token sessions an account counts (FR-001, FR-002).
- **Condition**: optional field, operator and text that narrows the kind (FR-004, FR-005).
- **Token-based account**: harness, Claude Code directory (Claude Code) or Codex home, kind, optional condition, budget.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: No combination of kind and condition makes a token-based account count a ChatGPT-plan Codex session or a direct Anthropic record that lacks this account's Claude Code directory information (FR-003 still decides first) (tests over every kind and field with a condition that matches those records' text).
- **SC-002**: For every kind, records of that kind count and records of every other kind do not (test matrix, 100% of kinds per harness).
- **SC-003**: For every field and operator combination, matching and non-matching records behave as specified with case differences in both directions (test suite, 100% of combinations).
- **SC-004**: Configuration files of v0.8.0, spec 037 and the first version of 038 load as FR-011 says, with every account's kind and condition as listed there and the log notes where the meaning narrows (tests with one account per earlier form).
- **SC-005**: A refresh over 10,000 raw record lines with a regex condition on Anywhere finishes its rule step in under 1 second on the maintainer's Mac, and one pathological pattern delays a refresh by no more than 100 ms.
- **SC-006**: In the walkthrough, a user sets up a gateway account (Other provider) and a Codex API-key account without reading documentation, and the Settings text contains none of the words of FR-017 (checked by hand, both appearances).

## Assumptions

- Specs 037 and 038 are unreleased, so their `matchRule` form can be replaced; files written by their builds load through FR-011.
- A record without a request id starting with `req_` is a reliable sign of a non-Anthropic provider for Claude Code in the setups known today (company gateways). Bedrock and other proxies are not checked here; if their records carry request ids that do not start with `req_`, they count as Other provider, which matches the intent "billed elsewhere"; a `req_` id with another infix (neither `req_vrtx_` nor a direct id) matches no Claude Code kind and stays Unassigned. The plan checks real records of the known setups before relying on this (brainstorm open thread).
- Codex talks only to OpenAI, so it needs no Other provider kind.
- "Matches regex" uses ICU, the regular expression syntax macOS provides to apps.
- No screenshot stem shows Settings > Accounts; the plan confirms this (constitution V).
- Out of scope: several conditions per account, a "Test" affordance that counts matching records, a Provider field for OpenCode conditions, explaining Unassigned records in the dropdown.
