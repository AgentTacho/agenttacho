# Feature Specification: Multi-Harness Usage (Codex and OpenCode)

**Feature Branch**: `006-multi-harness-usage`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Build the feature described in brainstorm/05-multi-harness-usage.md (part A): count token usage from Codex and OpenCode in addition to Claude Code, through per-harness adapters with shared attribution. Accounts are billing sources; Codex is attributed by auth mode; all cost comes from AgentMeter's price table."

## Context

Today AgentMeter reads only Claude Code session logs. Spec 001 FR-017 promised that further harnesses could be added without changing the stored configuration of existing accounts, but every reading and attribution step assumes Claude Code's log layout and record format.

Two other agent harnesses are in daily use on the same machine.

**Codex** writes one log file per session. Each turn records:
- tokens: input (including cached input and cache-write input), output (including reasoning output)
- the model and the working directory
- a snapshot of the rate limits, whose plan type is set for ChatGPT-plan logins

**OpenCode** keeps its history in a local database. Each assistant message records:
- the provider it used (for example `google-vertex` or `litellm`)
- the model
- tokens: input, output, reasoning, cache read, and cache write
- its own cost estimate

Usage from these harnesses is invisible today, even when it draws from a budget the user tracks. OpenCode on `google-vertex` bills the same Vertex project as Claude Code on Vertex, yet it never counts toward the Vertex budget.

This feature is **part A**: it counts token usage from Codex and OpenCode. **Part B**, live Codex/ChatGPT plan limits with percent, reset times, and thresholds, is a separate follow-up.

## Clarifications

### Session 2026-10-14

- Q: Is a Codex session's auth mode decided per turn or per session, given that the first turns may not carry a rate-limit snapshot yet? → A: Per session. If any record in the session carries a ChatGPT plan marker, the whole session is plan usage; otherwise the whole session is API-key usage.
- Q: Which window does a Codex subscription account's token breakdown cover while it has no plan limits? → A: The weekly window, like the token breakdown of Claude subscription accounts and the Unassigned entry (spec 001 FR-008, FR-009).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - OpenCode usage counts toward the right budget (Priority: P1)

The developer uses OpenCode with the `google-vertex` provider next to Claude Code on Vertex. After the update, the existing Vertex account's spend includes the OpenCode messages, priced like Claude Code usage. The budget percent, the bar, and the threshold notifications reflect both harnesses, with no extra setup.

**Why this priority**: This is the most direct value. A budget the user already tracks becomes complete.

**Independent Test**: With a Vertex account and OpenCode messages on `google-vertex` inside the current window, confirm that the account's spend equals the priced Claude Code usage plus the priced OpenCode usage. The per-harness split in the breakdown should show both parts.

**Acceptance Scenarios**:

1. **Given** a Vertex token-based account, $20 of Claude Code usage, and $10 of OpenCode `google-vertex` usage in the current window, **When** the refresh runs, **Then** the account (and its budget) shows $30 spent.
2. **Given** the same setup, **When** the user expands the breakdown, **Then** a per-harness split lists Claude Code $20 and OpenCode $10, next to the existing per-model and per-project views.
3. **Given** an OpenCode message with a provider that matches no configured account (for example `litellm`), **When** the refresh runs, **Then** its tokens appear under Unassigned and count toward no account.
4. **Given** OpenCode records its own cost for a message, **When** the refresh runs, **Then** AgentMeter ignores that value and prices the message from its own price table, overrides, and imports.

---

### User Story 2 - Codex usage with an API key is priced (Priority: P2)

The developer runs Codex with an OpenAI API key, which is billed per token. They add a token-based account with the OpenAI provider and give it a budget. Codex usage from API-key sessions is priced from AgentMeter's price table and counts toward that budget like any other token-based account.

**Why this priority**: This brings a second per-token billing source under budget control. It depends on the shared reading and attribution from User Story 1.

**Independent Test**: Configure an OpenAI token-based account with a budget, provide Codex sessions without a ChatGPT plan marker, and confirm the account's spend equals the priced token usage of those sessions.

**Acceptance Scenarios**:

1. **Given** an OpenAI token-based account and Codex API-key sessions in the current window, **When** the refresh runs, **Then** their tokens are priced per model and counted toward that account.
2. **Given** a Codex model has no price entry, **When** the refresh runs, **Then** its tokens are counted and flagged as unpriced, and the total is marked incomplete (spec 001 FR-016).
3. **Given** no OpenAI token-based account exists, **When** Codex API-key sessions are read, **Then** their tokens appear under Unassigned.

---

### User Story 3 - Codex usage with a ChatGPT plan is visible (Priority: P2)

The developer also uses Codex with a ChatGPT plan login. They add a Codex subscription account. Until plan limits are supported (part B), the account shows the tokens used through the plan with a per-model, per-day, and per-project breakdown. It has no percent, no bar entry, and no thresholds.

**Why this priority**: Plan usage becomes visible now, and part B can attach the limits later without changing how usage is attributed.

**Independent Test**: Configure a Codex subscription account, provide Codex sessions that carry a ChatGPT plan marker, and confirm the account lists their tokens. It has no percent, no bar entry, and no threshold settings.

**Acceptance Scenarios**:

1. **Given** a Codex subscription account and Codex sessions with a ChatGPT plan marker in the current window, **When** the refresh runs, **Then** the account shows their token counts and breakdown, without cost.
2. **Given** the same account, **When** the bar is drawn, **Then** the account does not appear in the bar, and settings offer no threshold or shown-in-bar option for it.
3. **Given** no Codex subscription account exists, **When** Codex plan sessions are read, **Then** their tokens appear under Unassigned.

---

### User Story 4 - Harness locations and visibility (Priority: P3)

The developer keeps a second Codex home or OpenCode data directory in a non-default place, for example for a separate work profile. In settings they add the extra location, and its usage is read like the default one. The diagnostic log shows which harnesses and locations were found and read, and problems with a location appear as source errors in the dropdown.

**Why this priority**: The default locations cover most setups. This handles the rest and makes problems diagnosable.

**Independent Test**: Add a second Codex sessions location in settings that holds a session in the current window, and confirm its usage is counted. Remove an unreadable location and confirm the refresh still succeeds for the others.

**Acceptance Scenarios**:

1. **Given** an extra Codex location configured in settings, **When** the refresh runs, **Then** sessions found there are read and attributed like those in the default location, and a session reachable through two configured paths is counted once.
2. **Given** a configured location that does not exist or cannot be read, **When** the refresh runs, **Then** the other harnesses and locations refresh normally, and the problem is reported in the diagnostic log and as a source error in the dropdown.
3. **Given** a harness that is not installed (no default location exists), **When** the refresh runs, **Then** it is skipped silently with no error.

---

### Edge Cases

- **Codex session file mid-write:** the partial last record is ignored without failing the file, as for Claude Code.
- **OpenCode database busy:** the database is being written or is locked during a refresh. The refresh must not fail or block. OpenCode usage keeps its last values, marked stale, and is read again on the next refresh.
- **OpenCode message still streaming:** a message has no completion time yet. It is counted once it is complete, and never twice when it later changes.
- **Codex auth mode changes:** the same Codex home switches between an API key and a ChatGPT login. Each session is attributed by the auth mode visible in that session's own records, not by the current login.
- **Sessions crossing a window boundary:** a Codex or OpenCode session started before the window boundary and continued after it. Only usage timestamped inside the window counts (spec 001 FR-023).
- **Working directory outside a git repository:** project resolution falls back the same way as for Claude Code sessions.
- **Unknown OpenCode provider:** a provider value AgentMeter does not know is matched only by an account's custom marker. Otherwise it goes to Unassigned.
- **Token category mismatch:** Codex reports cached input and cache writes as part of input, and reasoning as part of output. AgentMeter splits input into input, cache read and cache write, and keeps reasoning inside output, so no token is counted twice.
- **Repeated Codex events:** Codex sometimes writes the same token count event twice in a row, or an event without usage information. These add no usage.
- **Different model ids for the same model:** OpenCode writes Vertex model ids with a suffix (for example `claude-opus-4-6@default`). They are priced like the same model from Claude Code.
- **Harness removed:** a harness's data disappears (uninstalled, data deleted). Its usage simply stops appearing. Nothing else fails.
- **Very large OpenCode database:** a refresh reads only rows that changed since the last refresh, after the first full read.

## Requirements *(mandatory)*

### Functional Requirements

Harnesses and reading:

- **FR-001**: The app MUST read token usage from three harnesses: Claude Code (existing behaviour unchanged), Codex, and OpenCode.
- **FR-002**: Each harness MUST be discovered in its default location: Codex in the user's Codex home session logs, OpenCode in its local data directory. A harness whose default location does not exist MUST be skipped silently.
- **FR-003**: The user MUST be able to configure additional locations per harness in settings, as for Claude Code log directories today (spec 001 FR-012). The same session or message reachable through more than one configured path MUST be counted once.
- **FR-004**: Reading MUST be incremental. Only session files changed since the previous refresh are re-read, and after the first read, only new or changed OpenCode messages are read (spec 001 FR-018). A partially written record MUST be ignored without failing the rest of the data.
- **FR-005**: An OpenCode database that is busy, locked, or temporarily unreadable MUST NOT fail or block the refresh. OpenCode usage MUST keep its previous values, marked stale (spec 001 FR-007), until the next successful read.
- **FR-006**: A failure in one harness or location MUST NOT prevent other harnesses or locations from refreshing (spec 001 FR-026). It MUST be reported as a source error naming the harness and location.

Usage records:

- **FR-007**: Every usage record, whichever harness it comes from, MUST carry the harness, a provider hint, the model, a timestamp, the session, the working directory when known, and the token counts. The token counts are input, output, cache write, cache read, and reasoning, where the harness reports them.
- **FR-008**: Codex input tokens MUST be split into three parts: cache read (the reported cached input), cache write (the reported cache-write input), and input (the reported input minus both). Codex reports reasoning tokens as part of output. They MUST be kept inside output for pricing and shown as reasoning only for information.
- **FR-008a**: Codex usage MUST be derived from changes in a session's running token total. An event whose running total equals the previous one, an event without usage information, and an event whose token fields are all zero MUST add no usage.
- **FR-008b**: OpenCode reports reasoning tokens separately from output. They MUST be priced per FR-020 and also shown as reasoning.
- **FR-009**: Each completed OpenCode assistant message MUST produce exactly one usage record. A message counts as completed when it has a completion time, and that completion time is the record's timestamp. A message that is still in progress MUST NOT be counted until it completes, and a later update of an already counted message MUST replace its record, not add to it. A message that ended with an error counts with whatever tokens it reports. One with no tokens adds nothing.
- **FR-010**: Codex and OpenCode records MUST resolve to projects through their working directory, the same way Claude Code records do, so the per-project breakdown includes them.

Attribution:

- **FR-011**: An account MUST represent a billing source, not a harness. A token-based account MUST collect matching usage from every harness.
- **FR-012**: Built-in matching MUST attribute records as follows:
  - OpenCode `google-vertex` provider (and its Anthropic-on-Vertex variant): to Vertex token-based accounts.
  - Codex API-key usage and OpenCode `openai` provider: to OpenAI token-based accounts.
  - Codex ChatGPT-plan usage: to Codex subscription accounts.
  - Claude Code records: existing rules unchanged.
- **FR-013**: An account's custom marker MUST be matched against the raw record of any harness, and MUST take precedence over the built-in rule, as for Claude Code today (spec 001 FR-013).
- **FR-014**: A Codex session MUST be treated as ChatGPT-plan usage when any of its own records carries a ChatGPT plan marker (a non-empty plan type in its rate-limit snapshot), and as API-key usage otherwise. The decision applies to the whole session, so all of its turns go to the same account. When a marker first appears in a later read, the session's earlier turns MUST be re-attributed at that refresh. A Codex subagent session without a marker of its own MUST inherit the auth mode of its parent session when the parent is found.
- **FR-015**: Records that match no account, or more than one account after the existing tie-breakers, MUST be attributed to Unassigned (spec 001 FR-009). When several Codex subscription accounts exist, the Codex home a session was found in MUST decide between them, in the same way the credential directory decides between Claude subscription accounts.

Accounts and providers:

- **FR-016**: The token-based account type MUST offer a new provider, OpenAI, next to Vertex. OpenAI accounts behave like Vertex accounts: group membership or own budget, pricing, thresholds, the bar, and notifications.
- **FR-017**: A new Codex subscription account type MUST be available. In this feature it shows token counts with the per-model, per-day, and per-project breakdown. It has no percent, no bar entry, no thresholds, no shown-in-bar setting, and no cost. It references a Codex home location (default: the user's Codex home), which is used for FR-015. The default icon is the OpenAI icon. Its breakdown covers the weekly window, like Claude subscription accounts (spec 001 FR-008).
- **FR-018**: Existing configurations MUST load unchanged. Accounts without a harness-specific setting keep their current behaviour, and the stored harness value on existing accounts MUST be accepted but no longer restrict attribution.

Pricing and display:

- **FR-019**: All cost MUST come from AgentMeter's price table (built-in, imported, overrides). Costs recorded by a harness, such as OpenCode's per-message cost, MUST NOT be used.
- **FR-020**: Reasoning tokens that a harness reports separately from output (OpenCode) MUST be priced at the model's output price, unless the price table has a dedicated reasoning price for that model. Reasoning that a harness already includes in output (Codex) MUST NOT be priced again.
- **FR-020a**: Model ids MUST be normalized before price lookup, so that harness-specific variants of the same model share one price entry. For example, a trailing `@<suffix>` such as `claude-opus-4-6@default` is dropped. Provider-specific id matching from spec 001 still applies.
- **FR-020b**: Cache writes from Codex and OpenCode MUST be priced at the model's 5-minute cache-write price, because those harnesses do not distinguish cache-write durations.
- **FR-021**: The breakdown of every account, group, and the Unassigned entry MUST offer a per-harness split (tokens and, where priced, cost) in addition to the existing per-model and per-project views.
- **FR-022**: The diagnostic log MUST record, per refresh, each harness and location read with its record count, or the reason it was skipped or failed.

### Key Entities

- **Harness**: A coding agent that leaves usage data on disk: Claude Code, Codex, or OpenCode. It has default locations and user-added locations.
- **Usage record**: One unit of model usage. It carries the harness, provider hint, model, time, session, working directory, and token counts (input, output, cache write, cache read, reasoning).
- **Provider hint**: What a record reveals about who bills it. For Claude Code, request id markers. For OpenCode, the provider id. For Codex, the auth mode (ChatGPT plan or API key).
- **Token-based account**: A billing source priced per token. The providers are now Vertex and OpenAI. It collects matching usage from all harnesses.
- **Codex subscription account**: A ChatGPT-plan billing source. For now it shows tokens only, and later gains plan limits (part B).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With OpenCode on `google-vertex` in use, the Vertex budget's spend matches the sum of the priced Claude Code and OpenCode usage in the window to the cent.
- **SC-002**: The token totals shown for Codex and OpenCode match the totals recorded by those harnesses for the same window, after the cached-input split, with zero double counting.
- **SC-003**: A refresh with all three harnesses present (up to 5,000 Claude Code files, 1,000 Codex sessions, and an OpenCode history of 100,000 messages) completes within spec 001 SC-004 limits: under 10 seconds for a full refresh and under 1 second for an incremental refresh with no changes.
- **SC-004**: A busy or locked OpenCode database never makes a refresh fail. The other harnesses' values are current after every such refresh.
- **SC-005**: 100% of configuration files from the previous version load unchanged and produce the same Claude Code attribution as before.

## Assumptions

- Default locations are the Codex home under the user's home directory (`~/.codex`) and OpenCode's data directory (`~/.local/share/opencode`). Their on-disk formats are as observed on the user's machine in October 2026.
- OpenAI model prices are added through the existing LiteLLM price import or overrides. Built-in OpenAI prices are not required.
- A non-empty plan type in a Codex session's rate-limit snapshot is the auth-mode marker. Sessions without a marker (and without a marked parent) are API-key usage. A misclassified session can be claimed by an account's custom marker.
- The OpenCode `anthropic` provider is ambiguous between a Claude plan and the Anthropic API. It has no built-in match and goes to Unassigned unless an account's custom marker claims it.
- Live plan limits for Codex (percent, reset, thresholds, bar entry), and any call to an OpenAI endpoint, are part B and out of scope here.
- Harnesses beyond Claude Code, Codex, and OpenCode are out of scope.
