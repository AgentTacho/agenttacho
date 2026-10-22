# Feature Specification: Settings Sidebar and Per-Account Directories

**Feature Branch**: `034-settings-sidebar-directories`

**Created**: 2026-10-22

**Status**: Draft

**Input**: Brainstorm `brainstorm/33-settings-sidebar-directories.md`: "Update the layout of the General settings to include a sidebar to group options. The additional directories are configured per account, too: keep account-specific configuration in the Accounts section. Avoid real local directories in examples; make up profile paths."

## Background

The General tab of Settings is one long scrolling form with nine sections: Refresh, Display, Weekly window, Launch, Updates, Notifications, and three lists of additional directories (Claude Code, Codex, OpenCode). Every feature adds to it.

The directory lists overlap with the accounts. A Claude subscription account names its Claude Code directory ("Credential directory") and a Codex subscription account its Codex home; both are already read for session usage (spec 015 FR-006). The global lists invite entering the same directory twice, while a Vertex or OpenAI account has no directory of its own and depends on the global list when its agent runs from a profile directory. Directory configuration belongs to the account it serves, and AgentTacho reads exactly the directories the accounts name: an account whose field is empty uses the default (`~/.claude` or `~/.codex`), and an agent without an account has none of its sessions read. OpenCode is different: one OpenCode database holds usage for every provider, so its directories stay global.

Prompts, captions, documentation and tests also show a real local profile path. Examples should be invented.

## Clarifications

### Session 2026-10-22

- Q: Where does the directory field of a Vertex or OpenAI account sit? → A: In its own "Usage source" section of the account, below the account's provider and group settings, so subscription and token-based accounts read alike (FR-007).
- Q: Are the load notes for dropped global entries shown in Settings too? → A: No; they go to the diagnostic log like every other load note (Settings > Log shows them), once per load (FR-011).
- Q: Does the sidebar have a fixed width and icons from the system symbol set? → A: Yes; a fixed-width list with one system symbol per entry, no counts or descriptions, so the page area keeps today's form width inside the unchanged window (FR-001, FR-005).
- Q: Are ~/.claude and ~/.codex still always read? → A: No; only the accounts' directories are read, an empty field meaning the default (walkthrough 2026-10-22).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find a General option through a sidebar (Priority: P1)

A user opens Settings > General to turn off the update check. Instead of scrolling a long form, they see a sidebar with Refresh, Appearance, Weekly window, Notifications, Sources and Startup, click Startup, and find the switch.

**Why this priority**: The General tab is the most visited one and has outgrown a single form; this is the visible core of the request.

**Independent Test**: Open General, click each sidebar entry and check that each page shows exactly its options, and that every option of the old General tab is on exactly one page.

**Acceptance Scenarios**:

1. **Given** Settings is open on General, **When** the user looks at the tab, **Then** a sidebar lists, in this order: Refresh, Appearance, Weekly window, Notifications, Sources, Startup; one entry is selected and its page is shown next to the sidebar.
2. **Given** the sidebar, **When** the user selects Refresh, **Then** the page shows the refresh interval with its minimum hint and Adapt refresh with its caption.
3. **Given** the sidebar, **When** the user selects Appearance, **Then** the page shows "Show usage as" and "Dropdown theme" with their captions.
4. **Given** the sidebar, **When** the user selects Weekly window, **Then** the page shows the alignment account, the fallback weekday and hour, and one caption naming what the week counts for (weekly budgets, the token details per subscription account and for usage that matches no account) and that monthly budgets run by calendar month.
5. **Given** the sidebar, **When** the user selects Notifications, **Then** the page shows "Notify when a sign-in stops working" and "Notify before a free limit reset expires".
6. **Given** the sidebar, **When** the user selects Sources, **Then** the page shows the OpenCode data directories (the default, always read, and the added ones with add and remove) and a caption saying that Claude Code directories and Codex homes are set per account in Accounts and that an account without one uses `~/.claude` or `~/.codex`.
7. **Given** the sidebar, **When** the user selects Startup, **Then** the page shows "Start at login" and "Check for updates automatically".
8. **Given** the user selected a page, **When** they close and reopen Settings or switch tabs and come back, **Then** the same page is selected.
9. **Given** any option on any page, **When** the user changes it, **Then** it applies, undoes and redoes exactly as it does today.

---

### User Story 2 - Set the agent directory on the account (Priority: P1)

A user runs Claude Code through Vertex from a profile directory `~/profiles/acme/claude`. In Settings > Accounts they select the Vertex account and enter that directory as its Claude Code directory. From the next refresh on, the sessions in that directory count. Their Claude Max account runs from `~/.claude-personal`; its field, now called "Claude Code directory", is where both its sessions and its login come from.

**Why this priority**: It removes the double configuration and gives token-based accounts the directory they lack today.

**Independent Test**: Give a Vertex account and an OpenAI account their own directories (test fixtures with session files), refresh, and check that their sessions are read and attributed as before; check that the global lists are gone.

**Acceptance Scenarios**:

1. **Given** a Claude subscription account, **When** the user opens it in Accounts, **Then** its directory field is labeled "Claude Code directory", and its caption says that the account's sessions and its login come from this directory and that `~/.claude` applies when the field is empty.
2. **Given** a Vertex account, **When** the user opens it in Accounts, **Then** it has a "Claude Code directory" field (empty by default) whose caption says that the sessions in it are read for usage and that an empty field uses `~/.claude`.
3. **Given** an OpenAI account, **When** the user opens it in Accounts, **Then** it has a "Codex home" field (empty by default) whose caption says that the sessions in it are read for usage and that an empty field uses `~/.codex`.
4. **Given** a Vertex account with the directory `~/profiles/acme/claude` holding Vertex sessions, **When** AgentTacho refreshes, **Then** those sessions count for the Vertex account.
5. **Given** an OpenAI account with the Codex home `~/.codex-lab` holding API-key sessions, **When** AgentTacho refreshes, **Then** those sessions count for the OpenAI account.
6. **Given** any account, **When** its directory field is emptied, **Then** the account uses the default directory (`~/.claude` for a Claude subscription or Vertex account, `~/.codex` for a Codex subscription or OpenAI account), which is read from the next refresh on, and its old directory is no longer read unless another account names it.
7. **Given** Settings, **When** the user looks for "Additional Claude Code directories" or "Additional Codex homes", **Then** they exist nowhere.
8. **Given** a Codex subscription account, **When** the user opens it in Accounts, **Then** the caption of its "Codex home" says that the account's sessions are read from it and, with live limits on, its sign-in.

---

### User Story 3 - Upgrade with old global entries (Priority: P2)

A user upgrades with two entries in the old global lists. AgentTacho no longer reads them, and the diagnostic log names each one, so the user can set it on the right account.

**Why this priority**: Only users who configured the global lists are affected, but they must be able to tell why usage changed.

**Independent Test**: Load a configuration with `logDirectories` and `codexHomes` entries and check the load notes, that those directories are not read, and that the next save writes neither key.

**Acceptance Scenarios**:

1. **Given** a configuration with entries in `logDirectories` or `codexHomes`, **When** AgentTacho loads it, **Then** the entries are not read, and the load notes name each dropped entry and say to set it as an account's directory.
2. **Given** such a configuration, **When** Settings or AgentTacho saves the configuration, **Then** neither key is written.
3. **Given** an old entry equal to an account's directory, **When** AgentTacho loads it, **Then** the directory is still read through the account, and the note says it was already covered by that account.

---

### Edge Cases

- **Two accounts with the same directory**: the directory is read once; attribution decides per session as today.
- **A directory equal to the default** (`~/.claude`, `~/.codex`), entered or through an empty field: it is read once, like any other directory; the default is read only when at least one account resolves to it.
- **No account of an agent**: none of its sessions are read (no Claude subscription or Vertex account: no Claude Code sessions; no Codex subscription or OpenAI account: no Codex sessions).
- **A Vertex account used with OpenCode only**: its Claude Code directory stays empty; OpenCode usage comes from the global OpenCode directories as today.
- **An account directory that does not exist or has no sessions**: nothing is read from it and nothing fails; the field shows no error (as the credential directory does today).
- **Equivalent spellings** (`~/x`, `/Users/name/x`, trailing slash): treated as one directory, as the credential directory is today.
- **Removing an account**: its directory is no longer read from the next refresh on.
- **Switching a token-based account's provider** (Vertex to OpenAI or back): the directory field clears and its old directory is no longer read (FR-007).
- **An empty subscription directory**: the default applies for sessions and login (FR-006a), and the default is read once.
- **A hand-edited configuration** that sets a token-based account's directory: it is read like one set in Settings.
- **Demo build**: shows the new Settings layout; its scenario needs no directory change.

## Requirements *(mandatory)*

### Functional Requirements

**General sidebar**

- **FR-001**: The General tab MUST show a sidebar with six entries, in this order, each with a monochrome icon (the sidebar tint the HIG offers next to the accent color; the row highlight marks the selected page): Refresh, Appearance, Weekly window, Notifications, Sources, Startup. Selecting an entry MUST show its page next to the sidebar.
- **FR-002**: The pages MUST hold exactly these options, with today's labels, captions, validation and behavior:
  - Refresh: refresh interval (with the minimum hint), Adapt refresh;
  - Appearance: Show usage as, Dropdown theme;
  - Weekly window: Align with subscription account, Fallback weekday, Fallback hour, and one caption saying what the week counts for and that monthly budgets run by calendar month (walkthrough 2026-10-22);
  - Notifications: Notify when a sign-in stops working, Notify before a free limit reset expires;
  - Sources: OpenCode data directories;
  - Startup: Start at login, Check for updates automatically.
- **FR-003**: The selected page MUST be remembered across closing Settings, switching tabs and relaunching, like the selected tab. The first time, Refresh is selected.
- **FR-004**: Apply, undo, redo and the "Not applied" problem line MUST behave as today for every option.
- **FR-005**: The other tabs (Menu Bar, Accounts, Groups, Prices, Log, About) and the Settings window size MUST stay as they are.

**Per-account directories**

- **FR-006**: Claude subscription accounts MUST label their directory field "Claude Code directory" (the configuration key stays `credentialDirectory`). Its caption MUST say that the account's sessions and its login come from this directory, with an invented profile example. The caption of a Codex subscription account's "Codex home" MUST say that the account's sessions are read from it and, with live limits on, its sign-in; today's "It only matters when you have more than one Codex subscription account" no longer holds and MUST go.
- **FR-006a**: An empty or whitespace-only directory field of a subscription account MUST mean the default (`~/.claude` for a Claude subscription, `~/.codex` for a Codex subscription), for its sessions, its login and the tie-breaker of FR-009. Today an empty value is used as an empty path.
- **FR-007**: Vertex accounts MUST have an optional "Claude Code directory" (configuration key `claudeCodeDirectory`) and OpenAI accounts an optional "Codex home" (configuration key `codexHome`), stored on the account, empty by default, omitted from the configuration while empty or whitespace-only. The field sits in its own "Usage source" section directly below the "Token-based" section (provider and budget choice) and above an own budget's "Budget" section. Switching the account's provider MUST clear the field, since a Claude Code directory is no Codex home. A hand-edited key that does not fit the account's provider (for example `codexHome` on a Vertex account) MUST be ignored with a load note and is not written back.
- **FR-008**: AgentTacho MUST read Claude Code sessions from exactly the Claude Code directories of the Claude subscription and Vertex accounts, and Codex sessions from exactly the Codex homes of the Codex subscription and OpenAI accounts, each distinct directory once (compared by canonical path, as spec 015 FR-006 does today). An account whose field is empty or whitespace-only uses the default (`~/.claude` for Claude subscription and Vertex accounts, `~/.codex` for Codex subscription and OpenAI accounts), so the default is read only when at least one account resolves to it; with no account of an agent, none of its sessions are read. The OpenCode data directories are not affected (the default plus the global list). From a token-based account's directory AgentTacho MUST read only session files (the `projects` folder of a Claude Code directory, the `sessions` folder of a Codex home): never a login, keychain item or `auth.json`, and it makes no network request for it (constitution III).
- **FR-009**: Which account a session counts for MUST follow the existing rules (request ids, provider hints, custom markers, and the directory as tie-breaker between subscription accounts of the same kind); a token-based account's directory adds sessions to read and does not change those rules.
- **FR-010**: Settings MUST NOT offer "Additional Claude Code directories" or "Additional Codex homes".

**Upgrade**

- **FR-011**: On load, entries of `logDirectories` and `codexHomes` MUST NOT be read. Each entry MUST add a load note naming the entry and telling the user to set it as an account's directory; when it equals an account's directory (compared by canonical path) the note says it is already covered by that account; an entry equal to the default (`~/.claude`, `~/.codex`) is covered by an account that resolves to the default (also through an empty field) and otherwise gets the note on where to set it. The configuration stays valid whatever the keys hold: a value that is not a list of strings adds one load note for the key and is otherwise ignored.
- **FR-012**: Saving the configuration MUST NOT write `logDirectories` or `codexHomes`.

**Examples, docs and privacy**

- **FR-013**: Prompts, captions, documentation and tests MUST use invented profile paths (for example `~/.claude-personal`, `~/profiles/acme/claude`, `~/.codex-lab`, `~/.local/share/opencode-lab`); no real local tool path such as a `cc-deck` profile path may remain.
- **FR-014**: README (data sources and the "Agent session data" row of "Security and privacy") and the documentation that names the global lists (`docs/configuration.md`, `docs/development.md`) MUST describe the per-account directories, including that a token-based account's directory is read for sessions only. The General description in `docs/configuration.md` MUST follow the six pages of FR-001. The website's privacy copy MUST be checked for the same wording and changed with the README (constitution III).
- **FR-015**: The plan MUST confirm which screenshots, if any, show the changed tabs; a shot that does MUST be recaptured.

### Key Entities

- **General page**: one of six groups of General options, with a name, an icon and its options.
- **Account directory**: the agent directory of an account: the Claude Code directory of a Claude subscription or Vertex account, the Codex home of a Codex subscription or OpenAI account. Optional for token-based accounts; an empty field means the default directory of the agent.
- **Dropped global entry**: a `logDirectories` or `codexHomes` entry of an older configuration, reported once per load and no longer read.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every option of the old General tab is reachable in at most two clicks from the General tab (a sidebar entry, then the option), and none is lost, verified by a checklist of the old options against the pages.
- **SC-002**: No directory can be entered twice through Settings for the same agent: the only place to add a Claude Code directory or Codex home is an account.
- **SC-003**: Sessions in a Vertex or OpenAI account's directory count for that account with the same totals as when the directory was in the old global list, verified by tests with fixture sessions.
- **SC-004**: After an upgrade with old global entries, 100% of them are named in the load notes.
- **SC-005**: No real local tool path appears in the app's user-visible text, documentation or tests: a search for `cc-deck` in `Sources`, `Tests`, `docs` and `README.md` finds nothing.

## Assumptions

- The sidebar lives inside the General tab (the brainstorm chose this over a sidebar for the whole window).
- No screenshot shows the General or Accounts tab today (the Settings strips are `menubar-settings` and `prices` in `scripts/screenshots/capture.sh`, spec 031 FR-011a; both select their tab by name), so no recapture is expected; FR-015 confirms it in the plan.
- The OpenCode data directories stay a global list (one database holds all providers).
- The demo scenario needs no change; its Settings are reachable but not captured.
