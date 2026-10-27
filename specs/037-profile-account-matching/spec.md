# Feature Specification: Account Matching by Profile and Match Rules

**Feature Branch**: `037-profile-account-matching`

**Created**: 2026-10-27

**Status**: Draft

**Input**: Brainstorm `brainstorm/37-profile-account-matching.md`: "An account counts everything its profile did. When a session file names no profile, the account's match rule decides. The 'Provider' picker is replaced by a visible harness choice plus a match rule. Each account has exactly one harness; spend across harnesses comes together in budget groups. Backward compatibility is not a goal yet; the release notes say what changed."

## Background

Workspace managers such as cc-deck give each Claude Code profile its own configuration directory (for example `~/agent-profiles/work/claude`), but link every profile's `projects` folder to the same `~/.claude/projects`. One user runs three such profiles: a Claude Max subscription, Claude Code via Vertex, and Claude Code against a company gateway that serves other models (model names such as `intranet/glm-5`).

Today AgentTacho cannot tell these profiles apart:

- A token-based account matches only through its provider's built-in rule (for Claude Code with "Vertex": the request id starts with `req_vrtx_`). Its Claude Code directory plays no part in attribution.
- Two token-based accounts with the same rule both match every such record, and a tie between token-based accounts is Unassigned. Adding the gateway profile as a second "Vertex" account sent a whole week of Vertex usage to Unassigned and dropped the Vertex account to 0%.
- The gateway's records carry none of the known markers (no request id, a message id `chatcmpl-...`, a model outside Claude's names), so they match no account.
- The directory tie-breaker for subscriptions resolves symlinks, so all profiles that share `projects` look like `~/.claude`.

The "Provider" picker adds to the confusion: for Claude Code, "Vertex" only means "the request id starts with `req_vrtx_`", yet the same choice also decides the harness behind the scenes (Vertex means Claude Code, OpenAI means Codex), the directory key in the configuration file and the default icon.

**Research (2026-10-27, on the maintainer's machine).** Since Claude Code 2.1.300, session files contain `api-request-shape` lines with the shape of each API request, including the system prompt. With auto-memory on, that prompt names the memory folder, `<configuration directory>/projects/<project>/memory/`. Of 42 main session files from three days, 39 named exactly one configuration directory and the other 3 held no usage; none named two. All 156 subagent files carried their own shape lines. One session of the gateway profile also made Vertex calls. `.claude.json` keeps only the last session per project and cannot separate history. Codex profiles keep separate `sessions` folders and are not affected.

## Clarifications

### Session 2026-10-27

- Q: Since profile matching only looks for configured directories, how many buckets should the per-refresh log count report? → A: Two: files that named a configured directory and files that named none; a directory of no account is not detected separately (FR-001, FR-012).
- Q: Are custom rule texts compared case-sensitively? → A: Yes, exactly as entered, for prefixes and for "Anywhere in the record line", as custom markers are today (FR-007).
- Q: Where does Settings show the overlap warning? → A: Inline in the affected account's "Session matching" section, as a caption with a warning symbol; the sidebar rows stay unchanged (FR-013).
- Q: Should the Unassigned section explain why records stayed unassigned? → A: No, out of scope for this feature; the diagnostic log counts (FR-012) and the overlap warning (FR-013) cover the need for now.
- Q: Which match rule does a new token-based account start with? → A: The first preset of its harness (Claude Code "Vertex", Codex "API key", OpenCode "Vertex"), as today's default provider is Vertex (FR-007).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Profiles that share one projects folder count separately (Priority: P1)

A user runs three Claude Code profiles whose `projects` folders all link to `~/.claude/projects`: `~/agent-profiles/personal/claude` (Claude Max subscription), `~/agent-profiles/work/claude` (Vertex) and `~/agent-profiles/lab/claude` (company gateway). Each profile is configured as one account with that directory. After a refresh, each account shows exactly the usage of its own profile's sessions, including a Vertex call made from inside the lab profile, which counts for the lab account.

**Why this priority**: It is the reported failure: today all of this usage lands in Unassigned and the Vertex account shows 0%.

**Independent Test**: Build fixture session files in one shared `projects` tree whose shape lines name three different configuration directories, configure three accounts with those directories, refresh, and check each account's totals and that Unassigned is empty.

**Acceptance Scenarios**:

1. **Given** a session file whose shape lines name `~/agent-profiles/work/claude` and an account whose Claude Code directory is `~/agent-profiles/work/claude`, **When** AgentTacho refreshes, **Then** every usage record of that file counts for that account, whatever its request id, message id or model.
2. **Given** two token-based Claude Code accounts with the Vertex preset and the directories `~/agent-profiles/work/claude` and `~/agent-profiles/lab/claude`, **When** both profiles' sessions hold `req_vrtx_` records, **Then** each account counts its own profile's records and none are Unassigned.
3. **Given** a session file of the lab profile with gateway records (no request id, model `intranet/glm-5`) and `req_vrtx_` records, **When** AgentTacho refreshes, **Then** both count for the lab account.
4. **Given** a session file of the personal profile (a Claude subscription account's directory) that also holds `req_vrtx_` records, **When** AgentTacho refreshes, **Then** those records count for the subscription account.
5. **Given** a profile directory written with `~` in Settings and as an absolute path in the session file, or reached through a symlinked parent, **When** AgentTacho compares them, **Then** they match.
6. **Given** a subagent session file with its own shape lines, **When** AgentTacho refreshes, **Then** it is matched by the profile its own shape lines name.
7. **Given** a Claude subscription and a Vertex account both on `~/.claude` and a second Vertex account on `~/agent-profiles/work/claude`, **When** a session file that names `~/.claude` holds `req_vrtx_` records, **Then** they count for the Vertex account on `~/.claude` and none are Unassigned.

---

### User Story 2 - A harness and a match rule instead of "Provider" (Priority: P1)

A user adds a token-based account for the company gateway. In the new account sheet they choose the harness "Claude Code", then the match rule "Custom" with "Model starts with" and `intranet/`. Sessions older than the profile signal, or written without it, still count for the account through this rule.

**Why this priority**: The profile signal is missing in older sessions and in setups without separate profiles; the match rule is how those records find their account, and the visible harness removes the confusion of the "Provider" picker.

**Independent Test**: Configure accounts with each preset and with custom rules, feed fixture records without profile signal, and check which account each record counts for; check that the Settings form offers the presets of the chosen harness only.

**Acceptance Scenarios**:

1. **Given** the new account sheet with the kind "Token-based", **When** the user opens it, **Then** it asks for the harness (Claude Code, Codex, OpenCode) and the match rule, and no longer shows a "Provider" picker.
2. **Given** the harness Claude Code, **When** the user opens the match rule popup, **Then** it offers "Vertex", "Custom", and "None (profile only)"; for Codex it offers "API key" and "Custom"; for OpenCode it offers "Vertex", "OpenAI" and "Custom".
3. **Given** a preset is chosen, **When** the user looks below the popup, **Then** a read-only caption says what the preset checks (for example "Request id starts with `req_vrtx_`").
4. **Given** "Custom", **When** the user edits the rule, **Then** they choose a field ("Model", "Request id", "Message id" for Claude Code; "Model" for Codex and OpenCode; "Anywhere in the record line" last, for every harness) and enter a prefix or, for "Anywhere in the record line", a text.
5. **Given** a Claude Code account with the custom rule "Model starts with `intranet/`" and a record without profile signal whose model is `intranet/deepseek-v4`, **When** AgentTacho refreshes, **Then** the record counts for that account.
6. **Given** a Claude Code account with "None (profile only)", **When** a record without profile signal arrives, **Then** this account never claims it.
7. **Given** any change of harness or match rule, **When** the user applies, undoes or redoes it, **Then** usage is re-attributed from the next refresh on, and no plan-limit request is sent because of it.

---

### User Story 3 - Settings warns about accounts it cannot tell apart (Priority: P2)

A user configures two token-based Claude Code accounts, both with the Vertex preset and both with the default directory. Settings shows a warning on both accounts that records matching both will stay Unassigned, and names the other account.

**Why this priority**: The silent drop to Unassigned is what made the reported problem hard to understand.

**Independent Test**: Configure overlapping and non-overlapping account pairs and check which accounts carry a warning.

**Acceptance Scenarios**:

1. **Given** two token-based accounts of the same harness with the same rule and the same Claude Code directory (an empty field counts as `~/.claude`), **When** the user opens either one in Settings, **Then** a warning names the other account and says that records matching both stay Unassigned.
2. **Given** the same two accounts with different Claude Code directories, **When** the user opens them, **Then** no warning is shown.
3. **Given** two token-based Codex or OpenCode accounts with the same rule, **When** the user opens them, **Then** the warning is shown, since no profile separates those harnesses.
4. **Given** a Claude subscription and a Vertex account sharing `~/.claude`, **When** the user opens them, **Then** no warning is shown, since their rules separate their records.

---

### User Story 4 - Existing configurations keep working (Priority: P2)

A user upgrades with a configuration file from before this feature. It loads without user action: each Vertex account becomes a Claude Code account with the Vertex preset, each OpenAI account a Codex account with the API key preset, and a custom marker becomes a custom rule.

**Why this priority**: Upgrades must not need hand edits, even though full backward compatibility is not a goal.

**Independent Test**: Load configuration files written before this feature and check the resulting accounts, the load notes and what the next save writes.

**Acceptance Scenarios**:

1. **Given** an account with `"provider": "vertex"`, a `claudeCodeDirectory` and no custom marker, **When** AgentTacho loads it, **Then** it becomes a Claude Code account with the Vertex preset and the same directory.
2. **Given** an account with `"provider": "openai"` and a `codexHome`, **When** AgentTacho loads it, **Then** it becomes a Codex account with the API key preset and the same Codex home.
3. **Given** a token-based account with `"customMarker": "proj-alpha"`, **When** AgentTacho loads it, **Then** its match rule is "Custom", field "Anywhere in the record line", text `proj-alpha`.
4. **Given** a subscription account with a custom marker, **When** AgentTacho loads it, **Then** the marker stays on the account as it is today.
5. **Given** a migrated configuration, **When** AgentTacho saves it, **Then** the new keys are written and the old `provider` and token-based `customMarker` keys are not.
6. **Given** a Vertex account that also counted OpenCode `google-vertex` records before, **When** the configuration is migrated, **Then** those OpenCode records no longer count for it, and the diagnostic log names each migrated account once.

---

### User Story 5 - Spend across harnesses through a budget group (Priority: P3)

A user calls Vertex both from Claude Code and from OpenCode and wants one Vertex budget. They create a Claude Code account and an OpenCode account, both with the Vertex preset, and put both into the budget group "Vertex". The group's section shows the combined spend against its budget.

**Why this priority**: It replaces the special rule by which one Vertex account counted two harnesses, using a feature that already exists.

**Independent Test**: Configure two members of one budget group with different harnesses and check that the group's spend is the sum of both.

**Acceptance Scenarios**:

1. **Given** a Claude Code account and an OpenCode account, both with the Vertex preset, in one budget group, **When** AgentTacho refreshes, **Then** the group's spend is the sum of both accounts' spend and its harness breakdown lists both harnesses.

---

### Edge Cases

- **Several accounts with the same Claude Code directory** (for example a Claude subscription and a Vertex account, both on `~/.claude`): the profile step does not decide; the match rules do, as today, but only among the accounts that own that directory. This is the normal setup without separate profiles and never makes records Unassigned by itself. An account on another directory with the same rule (for example a second Vertex account on `~/agent-profiles/work/claude`) does not compete for these records.
- **Two token-based accounts with the same rule but different directories, and a record without profile signal**: both rules match, so the record stays Unassigned, as today. No overlap warning is shown (FR-013), because the profile step separates every record that has a profile signal.
- **A single shape line that names more than one configured directory**: the line is skipped for profile matching, as if it were not a shape line.
- **A named directory that belongs to no account** (for example a sandbox copy whose shape lines name `/sandbox/.claude`): the match rules decide, including spec 035's directory tie-breaker for subscriptions.
- **A session file without shape lines** (Claude Code before 2.1.300, or with auto-memory off): the match rules decide.
- **A session file that names two directories**: each record takes the directory of the latest shape line before it; records before the first shape line take the first one in the file.
- **A record from a Vertex call in a profile whose account is a subscription**: it counts for the subscription (profile beats rule); its tokens show in the subscription's details.
- **An account's additional session directory (spec 035) that a session file names**: it counts like a main directory in the profile step, ranked below main directories: exactly one main claim wins, else exactly one additional claim, wildcard matches included.
- **A custom rule and a preset both match a record without profile signal**: the custom rule wins, as a custom marker does today.
- **"Anywhere in the record line"**: it searches the whole record line, including tool inputs and outputs, so a session that merely mentions the text matches; its caption says so.
- **An empty custom prefix or text**: Settings refuses it with a "Not applied" problem line; loading drops the rule with a load note and treats the account as "None (profile only)" for Claude Code, or as matching nothing for Codex and OpenCode.
- **Changing an account's harness**: its main directory and additional directories clear, and its match rule resets to the first preset of the new harness.
- **OpenCode accounts**: they have no directory of their own; OpenCode data directories stay global on General > Sources, and the profile step does not apply to OpenCode records.
- **The shape line format changes in a later Claude Code release**: files without a recognizable profile fall back to the rules; the diagnostic log's counts (FR-012) show the shift.
- **A shape line that names a directory no account has**: it is not told apart from a file without a profile; both fall back to the rules and count as "named none" in the log (FR-012).
- **Why a record is Unassigned**: the Unassigned section does not explain it; this is out of scope.
- **Demo build**: the demo scenario has no shape lines; its accounts match through rules.

## Requirements *(mandatory)*

### Functional Requirements

**Profile matching**

- **FR-001**: For each Claude Code session file, AgentTacho MUST determine the configuration directory the session ran under from its `api-request-shape` lines: the path that precedes `/projects/` and is the Claude Code directory of a configured account (main or additional). Matching MUST look for the configured directories in the line rather than depend on the wording around the path. Each record MUST use the directory of the latest shape line before it in the file; records before the first shape line MUST use the first one. A shape line that names more than one configured directory MUST be skipped, as if it were not a shape line. The directory in effect at the end of a file MUST carry over to records appended later; when a file's first shape line appears only in a later refresh, the records read before it MUST be attributed again with that directory. A change to the configured directories (main, additional, or the folders a wildcard matches) MUST re-determine the profile of Claude Code session files from the next refresh on.
- **FR-002**: Directories MUST be compared after `~` expansion and standardization, with symlinks resolved on the configuration directory itself but never on the `projects` folder inside it, so profiles whose `projects` link to one shared folder stay apart. An empty Claude Code directory field MUST count as `~/.claude`.
- **FR-003**: Attribution of a Claude Code record MUST follow this order:
  1. **Profile.** If the record's file names a directory and exactly one account (of any kind: Claude subscription or token-based Claude Code) has it as its main directory, the record counts for that account. Otherwise, if exactly one account lists it as an additional session directory (literal or wildcard match), the record counts for that account.
  2. **Match rules.** Otherwise (no directory named, or the named directory belongs to no account or to several at the deciding rank), the match rules decide. When the named directory belongs to several accounts at the deciding rank, only those accounts are considered; otherwise all accounts are. Custom rules come first, as custom markers do today; then presets and the subscription rule; then the existing directory tie-breaker for subscriptions (spec 006 FR-015, spec 035 FR-012).
  3. **Unassigned** when neither step decides.
- **FR-004**: AgentTacho MUST read from a shape line only what FR-001 needs and MUST NOT keep, log or display any other part of it (the system prompt, instructions or file contents it holds).
- **FR-005**: Codex and OpenCode records MUST be attributed as today apart from FR-008 to FR-010; the profile step applies to Claude Code records only.

**Harness and match rule**

- **FR-006**: Every token-based account MUST have exactly one harness (Claude Code, Codex or OpenCode), shown and chosen in Settings > Accounts and in the new account sheet. The harness MUST decide which session sources feed the account, which directory fields it shows (a Claude Code directory, a Codex home, or none for OpenCode), and which rules are offered. The "Provider" picker MUST be removed.
- **FR-007**: Every token-based account MUST have a match rule, chosen in a popup:
  - **Presets**, each matching records of its harness only, with a read-only caption naming what it checks: Claude Code "Vertex" (request id starts with `req_vrtx_`); Codex "API key" (the session's auth mode is API key); OpenCode "Vertex" (provider is `google-vertex` or `google-vertex-anthropic`) and "OpenAI" (provider is `openai`).
  - **Custom**: a field and a text. Fields: "Model", "Request id" and "Message id" for Claude Code, "Model" for Codex and OpenCode, each matching when the record's field starts with the text; and "Anywhere in the record line" for every harness, offered last, matching when the raw record line contains the text, with a caption that it also searches tool inputs and outputs.
  - **None (profile only)**, for Claude Code only: the account claims records through the profile step only.

  Custom texts MUST be compared case-sensitively, exactly as entered. A new token-based account MUST start with the first preset of its harness (Claude Code "Vertex", Codex "API key", OpenCode "Vertex").
- **FR-008**: An account MUST match only records of its own harness, in the profile step and in the rule step. A Vertex account MUST no longer count OpenCode records, nor an OpenAI account OpenCode records; such spend comes together through budget groups (User Story 5).
- **FR-009**: Claude subscription and Codex subscription accounts MUST keep their implicit rules (a direct request id for Claude, the ChatGPT plan for Codex) and their existing custom marker field and behavior; they get no rule picker.
- **FR-010**: A custom rule MUST be more specific than any preset or implicit rule: when at least one account's custom rule matches a record in the rule step, only accounts whose custom rule matched are considered, as for custom markers today.
- **FR-011**: Apply, undo, redo and the "Not applied" problem line MUST work for the harness and the match rule as for the account's other fields. A change MUST re-attribute usage and MUST NOT by itself send a plan-limit request. An empty custom text MUST be refused with a "Not applied" problem line.

**Warnings, diagnostics and migration**

- **FR-012**: The diagnostic log line of each Claude Code refresh MUST say, for the session files read in that refresh, how many named a configured directory and how many named none, so a change in Claude Code's file format shows up.
- **FR-013**: Settings MUST show a warning on each of two or more token-based accounts that neither step can separate: same harness and the same rule (the same preset, or the same custom field and text, or both "None (profile only)"), and, for Claude Code, the same main Claude Code directory. The warning MUST appear inline in the account's "Session matching" section as a caption with a warning symbol (the sidebar rows stay unchanged), MUST name the other accounts and MUST say that records matching both stay Unassigned. Accounts that differ in directory (Claude Code) or rule MUST get no warning. Two subscription accounts keep today's handling.
- **FR-014**: A configuration file written before this feature MUST load without user action: `provider: vertex` becomes harness Claude Code with the Vertex preset, keeping its Claude Code directory and additional directories; `provider: openai` becomes harness Codex with the API key preset, keeping its Codex home and additional directories; a token-based `customMarker` becomes the custom rule "Anywhere in the record line" with that text. The stored `harness` value of old files MUST NOT be trusted (it reads `claudeCode` for every account today). The next save MUST write the new form only. The diagnostic log MUST name each migrated account once.
- **FR-015**: A match rule value that cannot be read MUST be dropped with a load note naming the account, MUST NOT make the configuration invalid, and the account MUST behave as with "None (profile only)" (Claude Code) or as matching nothing (Codex, OpenCode) until the user sets a rule.

**Docs, privacy, release and screenshots**

- **FR-016**: The README ("How it works" and the "Agent session data" row of "Security and privacy"), the website's privacy section and `docs/configuration.md` MUST say that AgentTacho reads the request shape lines of Claude Code session files to learn which configuration directory a session ran under, that it takes only that directory from them and keeps nothing else, and that it still only reads. `docs/configuration.md` MUST describe harness, presets, custom rules, the profile step, the overlap warning, budget groups for spend across harnesses, and the migration (constitution III).
- **FR-017**: `docs/configuration.md` MUST hold the migration note: accounts now match by profile and rule, and OpenCode usage that a Vertex or OpenAI account counted before needs its own OpenCode account. (Process note, not verifiable before landing: the squash commit that lands the feature carries the release-notes subject `feat(accounts): match accounts by profile and rule; OpenCode usage needs its own account`; evolved at finish on 2026-10-27, since verification runs before the squash.)
- **FR-018**: User-visible text, documentation and tests MUST use invented paths and model names (for example `~/agent-profiles/work/claude`, `intranet/glm-5`); no real local tool path or company model name may appear.
- **FR-019**: The plan MUST name the shots that change. The demo scenario MUST keep every shot's content, which means the demo's token accounts get explicit harnesses and the harness breakdown shot still shows several harnesses (through a budget group if needed), and the coverage test MUST check it (constitution V).

### Key Entities

- **Configuration directory (profile)**: the Claude Code directory a session ran under, read from its shape lines. Compared with the accounts' main and additional directories.
- **Harness**: the agent whose logs an account reads: Claude Code, Codex or OpenCode. Exactly one per token-based account.
- **Match rule**: how an account recognizes records without a decisive profile: a preset of its harness, a custom field and text, or none (Claude Code only).
- **Preset**: a named built-in rule of one harness, shown with what it checks.
- **Overlap**: two or more token-based accounts that neither the profile step nor their rules can tell apart.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With three profiles sharing one `projects` folder, each configured as an account, 100% of the fixture records with a profile signal count for the account of their profile and none are Unassigned, verified by tests.
- **SC-002**: Records without a profile signal count exactly as the match rules say, for every preset and custom field, verified by a table of fixture records per harness.
- **SC-003**: Every configuration file in the test suite from before this feature loads without error and keeps each account's directories, budget and group, verified by migration tests.
- **SC-004**: No part of a shape line other than the configuration directory reaches the log, the index or the user interface, verified by a test whose fixture shape line holds a marker text that must not appear anywhere.
- **SC-005**: A refresh over unchanged session files reads no session file again, as before this feature, verified by a test that refreshes twice.
- **SC-006**: Overlap warnings appear for exactly the account pairs that neither step can separate, verified by a table of account pairs.
- **SC-007**: No real local tool path or company model name appears in `Sources`, `Tests`, `docs` or `README.md`: a search for `cc-deck` finds nothing, and every model name in tests and docs is one of the invented examples (for example `intranet/glm-5`).

## Assumptions

- The profile signal relies on an internal Claude Code format (shape lines since 2.1.300, memory path with auto-memory on). It may change; the rules remain the fallback, and FR-012 makes a change visible.
- The brainstorm said "without resolving symlinks"; resolving the configuration directory itself while never resolving the `projects` folder below it keeps profiles apart and still matches a configuration directory reached through a symlink (FR-002).
- A directory shared by several accounts falls through to the rules instead of going Unassigned, so setups without separate profiles keep today's results (builder check of brainstorm 37).
- Custom rules keep today's precedence over presets, and subscriptions keep their marker field (builder check of brainstorm 37).
- "None (profile only)" is offered for Claude Code because a profile-based account (like the gateway profile) may need no rule; it is a call made in this spec, not in the brainstorm.
- Backward compatibility is not a goal (maintainer, 2026-10-27): a Vertex or OpenAI account that also counted OpenCode records loses them until the user adds an OpenCode account, and the release notes say so.
- Prices for models without a price, and token budgets, are out of scope (idea inbox `unpriced-model-accounts`).
- Changes to workspace managers such as cc-deck are out of scope, as is profile detection for Codex and OpenCode.
- The Accounts tab is not part of any captured shot (the Settings shots are `menubar-settings` and `prices`); the demo accounts' harnesses can still change dropdown shots, which FR-019 covers.
