# Feature Specification: Claude Code Auto-mode Classifier Usage

**Feature Branch**: `045-claude-automode-classifier-usage`

**Created**: 2026-11-13

**Status**: Draft

**Input**: Brainstorm `brainstorm/45-claude-automode-classifier-usage.md` (revisit 2026-11-13): "Approach A with time-based attribution. Classifier rows from Claude Code's `.automode_decisions.jsonl` become ordinary usage records, assigned to the session in the same working directory whose time span covers them. No visible UI change. AgentTacho only reads the log and never enables it; aprofile's `features` command (aprofile brainstorm 007) or the user's own `settings.json` `env` block enables it."

## Background

In Auto mode, Claude Code asks a classifier model whether each tool call may run. Each classifier call is a separate API request to the same provider as the main model, but its usage appears neither in the session transcript nor in Claude Code's standard OTel usage events. AgentTacho reads the transcript only, so its totals miss these calls.

A controlled probe on Claude Code 2.1.319 with a GLM model (run by the maintainer on 2026-11-12) made three main requests (80,168 tokens) and two classifier requests (69,624 tokens: 969 input, 68,608 cache read, 47 output). The backend's request counter rose by five. AgentTacho counted 80,168 tokens. The classifier share depends on the task, so no fixed correction factor is possible.

With the undocumented environment variable `AUTOMODE_DECISION_LOG=1`, Claude Code appends one JSON line per classifier decision to `.automode_decisions.jsonl` in the session's working directory. A usage-bearing line carries, among other fields:

| Field | Example | Meaning |
|---|---|---|
| `ts` | `1794505114575` | Decision time, epoch milliseconds |
| `classifierModel` | `rits/zai-org/glm-5-3[1m]` | Model of the classifier call |
| `inputTokens` | `512` | Uncached input tokens |
| `cacheReadInputTokens` | `34304` | Cache read tokens |
| `cacheCreationInputTokens` | `0` | Cache write tokens |
| `outputTokens` | `23` | Output tokens |

It carries no session id and no request id. The main records of the same session name the model `rits/zai-org/glm-5-3`, without the `[1m]` context marker. A row is about 550 bytes. In the probe, both classifier rows fell between the session's first record (17:36:23 UTC) and its last record (17:38:51 UTC).

AgentTacho already reads the working directory (`cwd`) and session id of every Claude Code record, and resolves each working directory to its project. Session files are read incrementally: unchanged files are skipped, grown files are read from the last parsed byte, and a file shorter than its parsed offset is read again from the start.

## Clarifications

### Decisions from the brainstorm (2026-11-13)

- Q: Who turns the log on? → A: The user, through aprofile's `features` command or by hand in Claude Code's `settings.json` `env` block. AgentTacho has no switch of its own and never writes Claude settings (brainstorm 45 revisit).
- Q: Should the classifier share be visible in the dropdown? → A: No, approach A: totals only. Records are marked as classifier usage internally, so a visible line can follow later without a data model change.
- Q: How are rows assigned to accounts? → A: Time-based, through the session in the same working directory whose time span covers the row. Ambiguous rows stay unassigned.

### Session 2026-11-13

- Q: What counts as one session when computing the time span that covers a classifier row? → A: The pair of Claude Code session id and working directory; records without a session id use their session file as the session.
- Q: Where do classifier rows that end up unassigned show? → A: In the existing Unassigned totals, like any other unassigned record; no new UI element.
- Q: Should the row's own `costUSD` value be used for cost? → A: No; classifier records are priced by AgentTacho's price table like every other record, and `costUSD` is not read.
- Q: Does the 2-second limit for checking decision logs apply to the whole check or to each working directory? → A: To each working directory; the others continue, and records already read from a directory that timed out keep counting.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Classifier usage counts toward the account (Priority: P1)

A user runs Claude Code in Auto mode with a GLM model through a token-based account, with the decision log enabled for that profile. After a session that triggered classifier calls, the account's token total in AgentTacho includes the classifier tokens, in the same model row as the session's main requests.

**Why this priority**: This is the whole point of the feature: totals that match what the provider counts, without a guessed multiplier.

**Independent Test**: A fixture with one Claude Code session file (working directory `W`, three usage records) and a decision log in `W` with two usage-bearing rows inside the session's time span. The account's totals equal the sum of the main records plus both classifier rows, split into input, cache read, cache write and output.

**Acceptance Scenarios**:

1. **Given** a session in working directory `W` assigned to account A, and a decision log in `W` with two usage-bearing rows inside the session's time span, **When** AgentTacho refreshes, **Then** account A's totals include both rows' input, cache read, cache write and output tokens.
2. **Given** the same fixture, **When** AgentTacho refreshes, **Then** the classifier tokens appear under the same model as the session's main records (`rits/zai-org/glm-5-3`), not as a separate `[1m]` model, and are priced by the same price entry.
3. **Given** the same fixture, **When** AgentTacho refreshes, **Then** the classifier records belong to the project of `W`, like the session's main records.
4. **Given** a session in working directory `W` and no decision log in `W`, **When** AgentTacho refreshes, **Then** totals are exactly what they are without this feature.
5. **Given** a row in `W`'s log written 6 minutes after the session's last record (so it is unassigned), **When** the session writes another record and AgentTacho refreshes, **Then** the row is assigned to the session's account without the decision log being read again.

---

### User Story 2 - Repeated refreshes never count a row twice (Priority: P1)

The decision log grows while the user works. AgentTacho refreshes many times a day. Each row is counted once, whether the file grows, stays the same, or is replaced.

**Why this priority**: Double counting would make totals worse than missing the classifier usage.

**Independent Test**: Refresh an index over a fixture three times: unchanged, after appending one row, after appending half a row and then its second half. Totals grow by exactly one row at each completed append.

**Acceptance Scenarios**:

1. **Given** a decision log already read, **When** AgentTacho refreshes and the file is unchanged, **Then** totals do not change and the file is not read again.
2. **Given** a decision log already read, **When** one row is appended and AgentTacho refreshes, **Then** totals grow by exactly that row and only the appended bytes are read.
3. **Given** a decision log whose last line is incomplete (no trailing newline), **When** AgentTacho refreshes, **Then** the incomplete line is not counted; **When** the line is completed and AgentTacho refreshes again, **Then** it is counted once.
4. **Given** a decision log that was replaced by a shorter file, **When** AgentTacho refreshes, **Then** the file is read again from the start and the rows of the old file no longer count.
5. **Given** a decision log that was deleted, **When** AgentTacho refreshes, **Then** its rows no longer count, the same rule that applies to a deleted session file.

---

### User Story 3 - Unclear rows stay unassigned rather than guessed (Priority: P2)

A user works in one repository with two Claude Code profiles that bill different accounts, sometimes at the same time. Classifier rows that could belong to either account are not given to one of them.

**Why this priority**: A wrong account is worse than an unassigned row; it can trip another account's limit or notification.

**Independent Test**: A fixture with two overlapping sessions in the same working directory on different accounts and one classifier row inside both time spans. The row is unassigned; a second row that falls only inside one session's span goes to that session's account.

**Acceptance Scenarios**:

1. **Given** two sessions in working directory `W` assigned to different accounts whose time spans both cover a row, **When** AgentTacho refreshes, **Then** the row is unassigned.
2. **Given** two sessions in `W` assigned to the same account whose spans both cover a row, **When** AgentTacho refreshes, **Then** the row goes to that account.
3. **Given** a row in `W`'s log that falls inside no session span of `W`, **When** AgentTacho refreshes, **Then** the row is unassigned.
4. **Given** a session in `W` that is itself unassigned, **When** a row falls inside its span only, **Then** the row is unassigned.

---

### User Story 4 - A changed log format fails quietly (Priority: P3)

The decision log is an internal Claude Code diagnostic. A future version may rename fields or drop the usage counters. AgentTacho keeps working and keeps its other totals correct.

**Why this priority**: The format is undocumented; robustness matters, but a format change is not expected often.

**Independent Test**: A decision log mixing valid rows, rows without usage counters, rows with all counters zero, rows with unknown extra fields and lines that are not JSON. Only the valid usage-bearing rows count, and the diagnostic log notes how many rows were skipped.

**Acceptance Scenarios**:

1. **Given** a row without any of the four usage counters, **When** AgentTacho refreshes, **Then** the row is skipped and counted as a row without usage in the diagnostic log, separately from malformed rows.
2. **Given** a row whose four counters are all zero, **When** AgentTacho refreshes, **Then** the row is skipped and creates no model or account row.
3. **Given** a row with additional unknown fields, **When** AgentTacho refreshes, **Then** the row counts normally.
4. **Given** a line that is not valid JSON or has no usable timestamp, **When** AgentTacho refreshes, **Then** the line is skipped, counted as malformed in the diagnostic log, and the other rows of the file still count.

### Edge Cases

- A working directory that no longer exists (a removed worktree): no decision log is found there; nothing is counted and nothing is reported as an error.
- A working directory on a slow, sleeping or unmounted volume: the check must not stall the refresh of all other data (FR-012).
- A decision log in a working directory whose sessions all lie before the current usage window: not read (FR-002).
- A session whose working directory is missing from its records: no decision log is looked for.
- Several sessions in the same working directory at different times on different accounts: each row goes to the session whose span covers it; only overlap makes a row ambiguous.
- A row timestamp slightly after the session's last record (the session ended right after a tool call): covered by the grace period (FR-005).
- The same working directory reached through two spellings (a symlink, a trailing slash): the decision log is read once (FR-001).
- A row with a `classifierModel` that differs from the session's main model (a separately configured classifier model): the row counts under its own model and is priced by that model's price entry.
- A row that holds no `classifierModel`: skipped and counted as malformed.
- A working directory on an external volume that is currently unmounted: the decision log is not found, so its rows stop counting until the volume is mounted again, while the session records stay. Accepted, the same as a removed worktree.
- A session record whose rows went to two accounts (a profile change in the middle of a file, or a rule that matches only some records): rows covered by that session stay unassigned (FR-006).
- Decisions that made no API call (a rule decided without the classifier, so the row has no counters): skipped (User Story 4 scenario 1).

## Requirements *(mandatory)*

### Functional Requirements

**Discovery and reading**

- **FR-001**: AgentTacho MUST look for a decision log only at `<cwd>/.automode_decisions.jsonl`, where `cwd` is a working directory named by a Claude Code session record that AgentTacho already read. Each distinct working directory MUST be checked at most once per refresh, after standardizing its path so two spellings of one directory count once. AgentTacho MUST NOT search any other location. The decision log MUST be read only when it is a regular file and not a symbolic link, opened without blocking; a file larger than 64 MB (about 120,000 decisions) MUST be skipped and the skip logged once per file.
- **FR-002**: Only working directories of sessions with at least one record inside the current usage window MUST be checked. A decision log whose modification date lies before the window start MUST NOT be read.
- **FR-003**: Decision logs MUST be read incrementally with the same rules as session files: an unchanged file (same size and modification date) is not read; a grown file is read from the last parsed byte; a file shorter than its parsed offset is read again from the start; an incomplete last line is left for a later refresh; a file that is gone or no longer qualifies (FR-002) stops counting.
- **FR-004**: A row MUST count only when it is a JSON object with a numeric `ts` (epoch milliseconds) at or after the usage window start, a non-empty `classifierModel`, every present counter of `inputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`, `outputTokens` a non-negative integer, and at least one of them greater than zero. All other lines MUST be skipped without affecting the other rows. Unknown fields MUST be ignored.

**Attribution**

- **FR-005**: A session is the pair of Claude Code session id and working directory; records without a session id use their session file as the session. A session's time span is the time from its first to its last usage record, extended by a grace period of 5 minutes after the last record. A row is covered by a session when the session's working directory is the decision log's directory and the row's `ts` lies inside that span. Only records inside the usage window count toward a span; for a session that started before the window, a row between the window start and the session's first in-window record finds no span, which is accepted.
- **FR-006**: A row covered by one or more sessions that are all assigned to the same account MUST be assigned to that account. A row covered by sessions on different accounts, by an unassigned session, by a session whose own records went to more than one account (or partly to Unassigned), or by no session MUST be unassigned; unassigned classifier records join the existing Unassigned totals like any other unassigned record. Account match rules (request id prefixes, record markers, spec 037 rules) MUST NOT be applied to the row itself; its account comes only from the covering sessions. Reading is incremental (FR-003), but every refresh MUST recompute the account of every counted row from the current session spans, also when no decision log changed, so a row becomes assigned when a later record extends its session's span, and ambiguous when a session on another account appears.
- **FR-007**: A classifier record MUST belong to the project of its working directory, resolved the same way as for session records.

**Data semantics**

- **FR-008**: Each counted row MUST become one usage record with the row's time, model, and token counters mapped as: `inputTokens` to input, `cacheReadInputTokens` to cache read, `cacheCreationInputTokens` to cache write (5-minute tier), `outputTokens` to output. Missing counters count as zero. The record is priced by AgentTacho's price table like every other record; the row's `costUSD` is not used. The log does not say which cache write tier was used; the 5-minute tier is the cheaper default and matches what Claude Code records for main requests without a tier split.
- **FR-008a**: A classifier record MUST be identified by its decision log's standardized path and the byte offset of its line. Two identical lines count as two calls. Classifier records MUST NOT be deduplicated against session records or against each other by message or request id.
- **FR-009**: The record's model MUST be `classifierModel` with a trailing Claude Code context marker in square brackets (such as `[1m]`) removed, so classifier usage lines up with the session's main records in per-model rows and price lookup.
- **FR-010**: Classifier records MUST be marked internally as classifier usage. The mark MUST NOT change totals, pricing, limits, groups, notifications or any visible text in this feature.
- **FR-011**: Main-request records MUST be unchanged by this feature: no session record is dropped, altered or counted twice.

**Robustness and diagnostics**

- **FR-012**: Checking working directories for decision logs MUST NOT block the processing of session records: the check of one working directory that has not finished within 2 seconds MUST be given up for that refresh and tried again on a later refresh. Standardizing the directory's path counts as part of the check and falls under the same limit. A directory whose earlier check is still running MUST be skipped, not checked again, so stuck checks cannot pile up. The problem is logged once per directory until a check of it finishes again. The other working directories continue, and records already read from the directory that timed out keep counting.
- **FR-013**: For each refresh that checked at least one decision log, the diagnostic log MUST report the number of decision logs read, rows counted, rows assigned, rows unassigned, rows without usage (a valid row with no counter above zero, normal for decisions made without a classifier call) and malformed rows (not JSON, no usable `ts`, no `classifierModel`, or an invalid counter). It MUST also note each session in which a session record and a covered classifier row carry the same four token counters (a possible double recording by a future Claude Code version). It MUST NOT log row contents, tool names or paths beyond the working directory.

**Read-only and privacy**

- **FR-014**: AgentTacho MUST NOT create, modify or delete a decision log, MUST NOT set `AUTOMODE_DECISION_LOG`, and MUST NOT edit Claude Code settings.
- **FR-015**: AgentTacho MUST read only the fields `ts`, `classifierModel` and the four token counters from a row, and MUST NOT keep the row's other content (tool name, decision, reason, routing fields) in memory beyond parsing the line.
- **FR-016**: The README MUST describe how to enable the decision log (aprofile's `features` command, or `AUTOMODE_DECISION_LOG=1` in the `env` block of Claude Code's `settings.json`), state that it is an undocumented Claude Code diagnostic that may change, and recommend adding `.automode_decisions.jsonl` to a global gitignore. The README's "Security and privacy" section and the website's privacy section MUST state that AgentTacho reads this file in session working directories.

### Key Entities

- **Decision log**: Claude Code's `.automode_decisions.jsonl` in a session working directory; append-only JSON lines, one per Auto-mode decision. Identified by its standardized path.
- **Classifier row**: One usage-bearing line of a decision log: time, classifier model, four token counters.
- **Session span**: Per Claude Code session id (or session file, without an id) and working directory: first record time to last record time plus the grace period, with the session's account.
- **Classifier usage record**: A usage record created from a classifier row, marked as classifier usage, with the account and project derived from the covering session.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For the 2026-11-12 probe (three main requests, two classifier rows), AgentTacho's total for the account is 149,792 tokens instead of 80,168, matching the client-reported combined total exactly.
- **SC-002**: Ten consecutive refreshes over unchanged data produce identical totals; appending N rows changes totals by exactly those N rows.
- **SC-003**: With no decision log present anywhere, all totals are identical to the release before this feature.
- **SC-004**: A refresh with 50 working directories, each with a 100 KB decision log already read, takes at most 50 ms longer than the same refresh without decision logs, measured by an automated test of the whole classifier step in steady state (logs already read, files unchanged) that runs with every test run.
- **SC-005**: No row in the test fixtures is assigned to an account when its covering sessions disagree on the account.

## Screenshots and Website

No visible UI change: classifier usage enters existing totals, model rows, project rows and the existing Unassigned totals only; no new view, label or setting. Website copy: the privacy section gains the sentence of FR-016, mirrored from the README.

## Assumptions

- Claude Code's decision log format observed in 2.1.319 (field names above, epoch milliseconds in `ts`) is the reference; fixtures are sanitized copies of captured rows.
- The classifier is billed by the same provider and account as the session that triggered it. This held in the probe (same GLM backend); a separately configured classifier provider is out of scope.
- The 5-minute grace period is a proposal: a classifier call follows the assistant message that requested the tool, so it can only trail the session's last record, and a tool approval rarely waits longer.
- Users without aprofile can enable the log by hand; AgentTacho does not detect whether it is enabled.
- Accepted limitation: a session AgentTacho cannot see (in a Claude Code configuration directory no account knows) writes to the same decision log. If its row falls inside a known session's span, the row goes to the known session's account; FR-006 cannot detect this.
- Claude Code 2.1.319 writes classifier usage only to the decision log, not to the transcript. If a later version also writes it to the transcript, totals would count it twice. To make that visible, the diagnostic log notes a session in which a session record and a covered classifier row carry the same four token counters, a strong sign the same call is recorded twice (the counting itself is unchanged; see FR-013).
- Out of scope: enabling the log from AgentTacho, a visible classifier share (brainstorm 45 approach B), Codex Guardian review usage, a request relay, any scaling factor, and explaining the larger run's remaining request excess.
