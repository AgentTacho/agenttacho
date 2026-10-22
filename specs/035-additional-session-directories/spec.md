# Feature Specification: Additional Session Directories per Account

**Feature Branch**: `035-additional-session-directories`

**Created**: 2026-10-22

**Status**: Draft

**Input**: Brainstorm `brainstorm/34-additional-session-directories.md`: "One account needs one login directory plus any number of session locations, many of them created by other tools, one per sandbox. Each account keeps its one main directory from spec 034 and gets an optional list of additional session directories with `*` wildcards; OpenCode's global list on the Sources page gets the same wildcard rule. Getting sessions out of sandboxes is the deliverer's job."

## Background

Spec 034 gives every account exactly one agent directory: the Claude Code directory of a Claude subscription or Vertex account, the Codex home of a Codex subscription or OpenAI account. Its sessions are read there, and a subscription's login comes from it. Real setups already spread one account's sessions over several places: a review tool runs `codex exec` with the default `~/.codex` while interactive work runs from a profile directory such as `~/.codex-lab`, and the walkthrough of spec 034 showed how easily one of them drops out of the count.

OpenShell support makes this the normal case:

- OpenShell runs each agent in a sandbox whose home is `/sandbox`, and keeps that storage per sandbox: a Podman volume inside the Podman machine, a container layer, a MicroVM disk or a Kubernetes volume. None of it is a host path AgentTacho could read.
- Host bind mounts exist but are off by default and discouraged. The supported way to get files out is `openshell sandbox download` or `exec`.
- Credentials inside a sandbox are placeholders behind a provider proxy, so plan limits keep coming from the host login; sandboxes only add session usage.
- A workspace tool may destroy a sandbox when its workspace stops, so its sessions are lost unless something copies them out first.

So one account needs one login directory plus any number of session locations, many of them created by other tools, often one per sandbox. AgentTacho stays read-only and runs no external tool (constitution III): other tools (a workspace manager, a script, a later OpenShell export) copy session trees into host folders, and AgentTacho reads the folders an account lists. A wildcard entry such as `~/agent-sessions/openshell/*/claude` covers every current and future sandbox folder without a Settings change.

## Clarifications

### Session 2026-10-22

- Q: When two subscription accounts of the same kind both claim a directory, one as its main directory and the other as an additional directory, which account gets a session found there? → A: The account whose main directory it is; additional directories rank below main directories in the tie-breaker, and only several claims of the same rank leave a session Unassigned (FR-012).
- Q: Should an entry that is a relative path (starting with neither `~/` nor `/`) be accepted? → A: No. It is refused in an account's list, and in the OpenCode list when it contains `*`; literal OpenCode entries keep today's behavior (FR-006).
- Q: Can a missing or unreadable additional directory make a session source fail or show a problem in the dropdown? → A: No. It is reported in the diagnostic log only; a source still fails only when no directory at all could be scanned and a main directory reported the error (FR-008).
- Q: Does the Codex source keep its per-home log line for every directory it reads? → A: For main directories and literal entries, yes; the folders matched by one wildcard entry share at most one summary line per entry and refresh (FR-016).
- Q: Does the cap of 100 matches per entry count every matched folder or only folders that hold sessions? → A: Every matched folder, before its contents are checked and whether or not it is also reached another way (FR-005).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Add a second session directory to an account (Priority: P1)

A user runs Codex interactively from the Codex home `~/.codex-lab`, the home of their Codex subscription account. A review tool runs `codex exec` with the default `~/.codex`, so those sessions do not count. In Settings > Accounts they select the Codex subscription account, add `~/.codex` under "Additional session directories" and apply. From the next refresh on, the review tool's sessions count for the account, while its sign-in and plan limits still come from `~/.codex-lab`.

**Why this priority**: It closes the gap the walkthrough of spec 034 found, for every account kind, without any wildcard.

**Independent Test**: Give an account a main directory and one additional directory (test fixtures with session files in both), refresh, and check that the sessions of both count with the same totals as if each were an account's main directory; check that no login or `auth.json` is read from the additional directory.

**Acceptance Scenarios**:

1. **Given** any Claude subscription, Vertex, Codex subscription or OpenAI account, **When** the user opens it in Settings > Accounts, **Then** a section "Additional session directories" sits directly below the section that holds the account's main directory, with a caption and a list of its entries with add and remove buttons below it (FR-002).
2. **Given** the caption of that section, **When** the user reads it, **Then** it says that the sessions in these directories are read for usage in addition to the main directory, that `*` stands for any folder name at one level, and that no login is read from them, with an invented example (`~/agent-sessions/openshell/*/claude` for a Claude account, `~/agent-sessions/openshell/*/codex` for a Codex account).
3. **Given** a Codex subscription account with the Codex home `~/.codex-lab` and the additional directory `~/.codex`, **When** AgentTacho refreshes, **Then** the ChatGPT-plan sessions in both count for the account, and its sign-in and local limit snapshots are read only from `~/.codex-lab`.
4. **Given** a Claude subscription account with the additional directory `~/.claude-lab`, **When** AgentTacho refreshes, **Then** the subscription sessions in `~/.claude-lab/projects` count for the account, and no keychain item is looked up for `~/.claude-lab`.
5. **Given** an OpenAI account with the additional directory `~/.codex`, **When** AgentTacho refreshes, **Then** the API-key sessions in `~/.codex/sessions` count for the OpenAI account and `~/.codex/auth.json` is never opened.
6. **Given** an account with additional directories, **When** the user removes an entry and applies, **Then** that directory is no longer read from the next refresh on, unless another account or entry still names it.
7. **Given** any change to an account's additional directories, **When** the user applies, undoes or redoes it, **Then** usage is refreshed with the new set of directories, and no plan-limit request is sent because of it (FR-003).

---

### User Story 2 - Cover every sandbox with one wildcard entry (Priority: P1)

A user's workspace tool copies the Claude Code session tree of each OpenShell sandbox to `~/agent-sessions/openshell/<sandbox>/claude` before it destroys the sandbox. The user adds `~/agent-sessions/openshell/*/claude` to their Claude Max account once. Every sandbox folder that exists now or appears later counts from the next refresh on, without another Settings change.

**Why this priority**: It is the case that motivates the feature: sandbox folders come and go, and nobody wants to edit Settings for each.

**Independent Test**: Create fixture folders `sandbox-a/claude` and `sandbox-b/claude` under a test root, list the wildcard entry on an account, refresh, add `sandbox-c/claude`, refresh again, and check that each refresh counts exactly the folders present at that moment.

**Acceptance Scenarios**:

1. **Given** the entry `~/agent-sessions/openshell/*/claude` on a Claude subscription account and the folders `~/agent-sessions/openshell/alpha/claude` and `~/agent-sessions/openshell/beta/claude`, **When** AgentTacho refreshes, **Then** the sessions in both folders' `projects` trees count by the usual rules.
2. **Given** that entry, **When** a new folder `~/agent-sessions/openshell/gamma/claude` appears between two refreshes, **Then** its sessions count from the second refresh on, without a Settings change.
3. **Given** that entry, **When** the folder `beta` is deleted between two refreshes, **Then** its sessions no longer count from the second refresh on, as for a deleted session file today, and nothing fails.
4. **Given** the entry `~/agent-sessions/openshell/*/claude`, **When** a folder `~/agent-sessions/openshell/team/alpha/claude` exists, **Then** it does not match, since `*` covers one folder level only.
5. **Given** the entry `~/agent-sessions/openshell/*/claude`, **When** a folder `~/agent-sessions/openshell/.cache/claude` exists, **Then** it does not match, since a `*` at the start of a name does not match a name that begins with `.`.
6. **Given** the entry `~/.claude-*`, **When** the folders `~/.claude-lab` and `~/.claude-personal` exist, **Then** both match.
7. **Given** an entry that matches nothing, **When** AgentTacho refreshes, **Then** nothing is read for it, nothing fails, and no error is shown.

---

### User Story 3 - Hand-edit the configuration (Priority: P2)

A user or a provisioning script writes `additionalSessionDirectories` into the configuration file. Valid entries are read like ones added in Settings; an entry AgentTacho refuses is named in the diagnostic log and dropped on the next save.

**Why this priority**: Deliverers and dotfile setups write the file directly; they need the same rules and a clear trace when an entry is refused.

**Independent Test**: Load configurations with valid, blank, refused and malformed `additionalSessionDirectories` values and check the directories read, the load notes, that the configuration stays valid, and what the next save writes.

**Acceptance Scenarios**:

1. **Given** an account with `"additionalSessionDirectories": ["~/.claude-lab", "~/agent-sessions/openshell/*/claude"]`, **When** AgentTacho loads it, **Then** both entries are read from the next refresh on and Settings shows them on the account.
2. **Given** an entry with `**`, a bare `*` folder directly under the home folder or `/`, the home folder or `/` itself, or a relative path, **When** AgentTacho loads it, **Then** the entry is not read, a load note names the entry and why it is refused, and the next save does not write it.
3. **Given** a value that is not a list of strings (for example a string, `null`, or a list with a number), **When** AgentTacho loads it, **Then** the key is ignored with one load note naming the account, the rest of the configuration loads, and the next save writes no such key.
4. **Given** an account with an empty list or only blank entries, **When** the configuration is saved, **Then** no `additionalSessionDirectories` key is written for it.

---

### User Story 4 - Wildcards for OpenCode data directories (Priority: P3)

A user's deliverer also copies each sandbox's OpenCode database to `~/agent-sessions/openshell/<sandbox>/opencode/opencode.db`. On General > Sources they add `~/agent-sessions/openshell/*/opencode` to the OpenCode data directories, and every sandbox database counts.

**Why this priority**: OpenCode in sandboxes is less common, and its list is already global; it needs only the same wildcard rule.

**Independent Test**: Put fixture databases in two matched folders, list the wildcard entry, refresh, and check that both databases are read once each.

**Acceptance Scenarios**:

1. **Given** the OpenCode entry `~/agent-sessions/openshell/*/opencode` and two matched folders that hold an `opencode.db`, **When** AgentTacho refreshes, **Then** both databases are read, in addition to the default `~/.local/share/opencode`.
2. **Given** the Sources page, **When** the user reads the OpenCode caption, **Then** it says that `*` stands for any folder name at one level, with the invented example `~/agent-sessions/openshell/*/opencode`.
3. **Given** a matched folder that holds no `opencode.db`, **When** AgentTacho refreshes, **Then** it is skipped silently.

---

### Edge Cases

- **A directory reached several ways** (an account's main directory, an additional entry, several wildcard matches, another account's directory or entry, a symlink, `~/x` and `/Users/name/x`): it is read once, compared by canonical path (FR-008).
- **An additional directory equal to the account's main directory**: read once; nothing changes.
- **An additional entry equal to another account's main directory**: read once; attribution decides per session as today, and where the subscription tie-breaker applies, the account whose main directory it is wins over the account that lists it as an additional directory. Two subscription accounts of the same kind that both list it only as an additional directory leave a session Unassigned, as two accounts sharing one main directory do today (FR-012).
- **A Vertex or OpenAI account with an empty main directory and additional directories**: the main directory still means the default (`~/.claude` or `~/.codex`, spec 034 FR-008); the additional directories are read on top.
- **More than 100 matches for one entry**: the first 100 in name order are read, the rest are skipped, and the log says so once per entry and not on every refresh (FR-005).
- **A matched folder without a `projects` folder, `sessions` folder or `opencode.db`**: it adds no session and no error.
- **A literal additional directory that does not exist**: nothing is read from it, a log line says it was skipped, and nothing fails; it never makes the source fail or adds a problem to the dropdown (FR-008).
- **An additional directory or matched folder that is not readable**: it is named in the diagnostic log, the other directories and matches are read, and it never makes the source fail or adds a problem to the dropdown (FR-008).
- **A relative entry** (for example `agent-sessions/*/claude`): refused, since an app has no meaningful working folder (FR-006).
- **Wildcard characters other than `*`** (`?`, `[`, `]`, `{`, `}`): they are ordinary characters of a folder name.
- **A `*` in the main directory field**: it stays an ordinary character; only the additional lists and the OpenCode list expand wildcards.
- **Switching a token-based account's provider**: its additional directories clear with its main directory, since a Claude Code directory is no Codex home (spec 034 FR-007).
- **Removing an account**: its additional directories are no longer read from the next refresh on, unless another account names them.
- **A deliverer writing into a folder during a refresh**: a partly written session file is read as far as it is complete, as for a session an agent is still writing today.
- **Demo build**: the demo scenario needs no additional directories; the Accounts tab shows the new section empty.

## Requirements *(mandatory)*

### Functional Requirements

**Additional session directories per account**

- **FR-001**: Every Claude subscription, Vertex, Codex subscription and OpenAI account MUST have an optional list of additional session directories, empty by default, stored on the account under the configuration key `additionalSessionDirectories` (a list of strings). Entries are written as entered (without surrounding whitespace), blank entries are dropped, and the key is omitted while the list is empty.
- **FR-002**: Settings > Accounts MUST show, for each of these accounts, a section "Additional session directories" directly below the section that holds the main directory ("Subscription", "Codex subscription" or "Usage source"): a caption, then a list in the macOS style with one row per entry (one line, shortened in the middle, the full entry as tooltip) and an add button (plus) and a remove button (minus) below it. The add button MUST offer "Choose Folder…", a folder chooser that shows hidden folders, allows several folders and adds each with the home folder written as `~`, and "Enter Path…", a sheet with a text field (invented example prompt) for entries a chooser cannot pick, such as `*` entries, whose "Add" button is disabled while the field is blank. The remove button and the Delete key MUST remove the selected rows; the remove button is disabled without a selection. A double-click on a row (or Return, or "Edit" in its context menu, which also offers "Remove") MUST edit the entry in place: Return or leaving the field applies it, Escape cancels, and a blank text or the text of another entry leaves the list unchanged (walkthrough 2026-10-22: the earlier per-row "Remove" buttons and inline "Add directory" field did not follow the macOS list pattern). The caption MUST say that the sessions in these directories are read for this account's usage in addition to the main directory, that `*` stands for any folder name at one level, and that no login is read from them, with an invented example (`~/agent-sessions/openshell/*/claude` for Claude Code, `~/agent-sessions/openshell/*/codex` for Codex). Adding an entry already in the list (after trimming) MUST leave the list unchanged. The new account sheet MUST NOT show the list.
- **FR-003**: Apply, undo, redo and the "Not applied" problem line MUST work for the list as for the account's other fields. A change of the list MUST refresh usage (the session sources read the new set of directories at the next refresh) and MUST NOT by itself send a plan-limit request, unlike a change of a subscription's main directory, which changes where its login comes from.

**Wildcards**

- **FR-004**: An entry of an account's list or of the OpenCode data directory list MAY contain `*`. A `*` matches any run of characters within one folder name, including none, and never a `/`; it may stand for a whole folder name (`~/agent-sessions/openshell/*/claude`) or part of one (`~/.claude-*`). A `*` at the start of a folder name MUST NOT match a name that begins with `.`. Only folders match (files never do), and symlinks to folders match. `~` expands before matching. No other character has a wildcard meaning.
- **FR-005**: Matches MUST be evaluated anew on every refresh, so folders that appear or disappear between refreshes count or stop counting without a Settings change. One entry MUST read at most 100 matched folders, the first 100 by path in name order. The cap counts every matched folder before its contents are checked, whether or not it holds a `projects` folder, `sessions` folder or `opencode.db` and whether or not it is also reached another way; when an entry matches more, the diagnostic log MUST name the entry, the number of matches and that only 100 are read, once after launch or after the configuration changes and again only when the number of matches changes.
- **FR-006**: Settings MUST refuse (with a "Not applied" problem line naming the entry and the reason) and loading MUST drop (with a load note naming the account, or the OpenCode list, and the entry, clipped like other load notes) an entry that contains `**`, an entry whose folder name directly under the home folder or `/` is a bare `*` (for example `~/*/claude` or `/*`), an entry that is the home folder or `/`, and a relative entry, one that starts with neither `~/` nor `/` (in an account's list always, in the OpenCode list only when it contains `*`, so literal OpenCode entries keep today's behavior). A wildcard match that resolves to the home folder or `/` MUST never be read. Dropped entries MUST NOT be written back.
- **FR-007**: A value of `additionalSessionDirectories` that is not a list of strings (including `null`, a string, or a list holding a non-string) MUST be ignored with one load note naming the account, MUST NOT make the configuration invalid, and MUST NOT be written back.

**What is read**

- **FR-008**: AgentTacho MUST read Claude Code sessions from the main directories of spec 034 FR-008 plus the additional directories (literal entries and wildcard matches) of every Claude subscription and Vertex account, and Codex sessions from the main directories plus the additional directories of every Codex subscription and OpenAI account. Each distinct directory MUST be read once per refresh, compared by canonical path (symlinks resolved, `..` removed, trailing slash dropped), wherever it is named: as a main directory, an entry, a match of one or several wildcard entries, or on several accounts. An additional directory or matched folder that is missing or unreadable MUST be reported in the diagnostic log only: it MUST NOT make a source fail or add a problem to the dropdown. A source that fails today because no directory could be scanned fails only when neither a main directory nor an additional directory could be scanned and at least one main directory reported the error.
- **FR-009**: From an additional directory AgentTacho MUST read only session files: the `projects` folder of a Claude Code directory, the `sessions` folder of a Codex home. It MUST never open a login, keychain item, `auth.json` or other credential file because of an additional directory, MUST run no external program and MUST make no network request for it (constitution III).
- **FR-010**: Plan limits MUST come only from an account's main directory: the Claude login, the Codex sign-in and the Codex local limit snapshots (the fallback with live limits on, the only source with them off). Additional directories add session usage only: the rate-limit data in a Codex session found there still decides that session's auth mode (FR-011), but it MUST never feed an account's plan limits.
- **FR-011**: Which account a session counts for MUST follow the existing rules: ChatGPT-plan sessions for a Codex subscription, API-key sessions for an OpenAI account, request ids, provider hints and custom markers for Claude accounts. Listing a directory on an account MUST NOT force its sessions onto that account; a session in it that the rules give to another account or to none counts there.
- **FR-012**: Where the rules fall back to the directory to separate subscription accounts of the same kind (spec 006 FR-015), an account's additional directories (literal entries and their wildcard matches) MUST count as that account's directories, ranked below main directories. A session found in a directory that is the main directory of exactly one of the matching accounts goes to that account, even when other matching accounts list it as an additional directory. Otherwise a session found in a directory that exactly one of the matching accounts lists as an additional directory goes to that account. In every other case it stays Unassigned, as it does today for two accounts sharing one main directory. Main directories are scanned before additional directories, so a session file reached through both is found in the main directory.

**OpenCode**

- **FR-013**: The OpenCode data directories on General > Sources MUST accept `*` entries by the rules of FR-004 to FR-006. A matched folder counts when it holds an `opencode.db`; other matches are skipped silently. A matched database that is unreadable or busy is handled like the database of a literal entry today. The type check of `openCodeDirectories` stays as it is; FR-007 applies to the account key only. The default `~/.local/share/opencode` stays always read, and each database is read once, compared by canonical path. The caption of the list MUST mention `*` with the invented example `~/agent-sessions/openshell/*/opencode`. The list MUST use the same list, add and remove controls as FR-002.

**Examples, docs, log and privacy**

- **FR-014**: Prompts, captions, documentation and tests MUST use invented paths (for example `~/agent-sessions/openshell/*/claude`, `~/agent-sessions/openshell/*/codex`, `~/.claude-lab`, `~/.codex-lab`); no real local tool path may appear.
- **FR-015**: README ("How it works" and the "Agent session data" row of "Security and privacy"), `docs/configuration.md` and `docs/development.md` (which today says no other Claude Code directory is read) MUST describe the additional directories: what is read from them (session files only), that they are read-only, that wildcards are re-evaluated on every refresh, and that AgentTacho runs no tool and pulls nothing from sandboxes. `docs/configuration.md` MUST get a short section on feeding sessions from sandboxes: a deliverer copies the agent's `projects` tree (Claude Code), `sessions` tree (Codex) or `opencode.db` (OpenCode) into a host folder listed on the account (Claude Code, Codex) or on General > Sources (OpenCode), with the recommended layout `~/agent-sessions/<tool>/<sandbox>/<claude|codex|opencode>`, and keeps the copy at least as long as the budget period it should count for. The website's privacy copy MUST be checked for the same wording and changed with the README (constitution III).
- **FR-016**: The diagnostic log line of each refresh of the Claude Code and Codex session sources MUST name the number of session directories read, so a user can tell whether a wildcard entry matched. Main directories and literal entries keep today's per-location lines (the Codex source's line per home). The folders matched by one wildcard entry MUST share at most one summary line per entry and refresh; a matched folder MUST get a line of its own only when it fails to be read.
- **FR-017**: The plan MUST confirm which screenshots, if any, show the Accounts tab or General > Sources; a shot that does MUST be recaptured.

### Key Entities

- **Main directory**: an account's one agent directory from spec 034 (Claude Code directory or Codex home). Source of sessions and, for subscriptions, of the login and plan limits. Unchanged by this feature.
- **Additional session directory**: an entry in an account's `additionalSessionDirectories` list, literal or with `*`. Source of session files only.
- **Wildcard match**: a folder that an entry with `*` names at the time of a refresh; at most 100 per entry.
- **Deliverer**: any tool or script outside AgentTacho that copies session trees from sandboxes or other hosts into host folders. Not part of AgentTacho.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Sessions in an account's additional directory count with the same totals as the same sessions in an account's main directory, verified by tests with fixture sessions for all four account kinds.
- **SC-002**: One wildcard entry covers any number of sandbox folders up to 100 with zero Settings changes when folders appear or disappear, verified by a test that adds and removes matched folders between refreshes.
- **SC-003**: A directory reached through two or more routes contributes each session exactly once, verified by a test that names one fixture directory as a main directory, a literal entry and a wildcard match.
- **SC-004**: No credential file, keychain item or network request is touched because of an additional directory, verified by tests whose fixture directories hold an `auth.json` and whose credential readers and clients are test doubles that record every call.
- **SC-005**: After a refresh in which no matched session file changed, the log line of each session source reports zero files read again (Claude Code: "re-read 0"; Codex: "0 file(s) parsed"), verified by a test that refreshes twice over unchanged wildcard matches.
- **SC-006**: No real local tool path appears in the app's user-visible text, documentation or tests: a search for `cc-deck` in `Sources`, `Tests`, `docs` and `README.md` finds nothing.

## Assumptions

- Spec 034 (per-account main directories, the General sidebar) has landed and stays unchanged; this feature adds to it.
- The brainstorm's open questions are decided as follows: `*` covers one folder level and `**` is refused (FR-004, FR-006); at most 100 matches per entry, with a log line beyond (FR-005); deleted or moved sandbox folders need no handling beyond dropping out at the next refresh (User Story 2, scenario 3); the key is `additionalSessionDirectories` on all four account kinds (FR-001); the recommended deliverer layout is `~/agent-sessions/<tool>/<sandbox>/<claude|codex|opencode>` (FR-015).
- Additional directories feed session usage only. Sandbox credentials are placeholders behind a provider proxy, so plan limits stay with the host login of the main directory (FR-010).
- Treating additional directories as the account's own for the subscription tie-breaker, ranked below main directories (FR-012), keeps the attribution rules unchanged in substance: it only lets two subscription accounts of the same kind keep apart the sessions their own listed folders hold, and listing a folder on one account never takes sessions away from the account whose main directory it is.
- Copying sessions out of sandboxes is out of scope: AgentTacho pulls nothing from OpenShell or any remote host, runs no `openshell` command, and takes no OTLP intake (a possible later source). The export itself belongs to a deliverer (a workspace manager, a script, a later OpenShell export).
- No screenshot shows the Accounts tab or General > Sources: the shot list in `scripts/screenshots/capture.sh` is `menubar budget harnesses prices menubar-settings glance same-provider`, and its only Settings shots are `menubar-settings` (Menu Bar tab) and `prices` (Prices tab). No recapture and no new stem are expected; FR-017 confirms it in the plan.
- The demo scenario needs no change; its Settings are reachable but not captured.
- The cap of 100 matches per entry is well above the number of sandboxes one user keeps; it bounds a mistyped entry, not normal use.
- Settings shows no match count, so it never reads the file system; the log line of FR-016 serves that need.
- The Settings window size and the other tabs stay as they are.
