# Brainstorm: Settings Sidebar and Per-Account Directories

**Date:** 2026-10-22
**Status:** spec-created (specs/034-settings-sidebar-directories)

## Problem Framing

The General tab of Settings is one long scrolling form with nine sections: Refresh, Display, Weekly window, Launch, Updates, Notifications, and three lists of additional directories (Claude Code, Codex, OpenCode). It keeps growing with every feature, and finding an option means scrolling.

The directory lists are also confusing. Each Claude subscription account already has a "Credential directory" and each Codex subscription account a "Codex home", and both are scanned for sessions automatically (`SessionLogSource.swift`, `CodexSessionSource.swift`, spec 015 FR-006). The global lists invite entering the same directory twice (idea inbox `settings-caption-credential-dirs`), while token-based accounts (Vertex, Anthropic API, OpenAI API) have no directory of their own and depend on the global list when their sessions live in a profile directory. Directory configuration belongs to the account it serves.

Finally, prompts, captions and tests show a real local path (`~/.local/share/cc-deck/profiles/...`). Examples should be invented profile paths.

## Approaches Considered

### A: Sidebar for the whole Settings window
- Pros: the standard macOS System Settings pattern; one navigation level; General's sections become first-class entries next to Accounts, Groups and Prices.
- Cons: a larger change to every tab and to the Settings screenshot strips (`menubar-settings`, `prices`).

### B: Sidebar inside the General tab
- Pros: smaller change; the other tabs and their screenshot strips stay as they are.
- Cons: two navigation levels (tab bar plus sidebar).

### Directories: three variants
- **Every account gets its agent directory, OpenCode stays global**: Claude accounts get a Claude Code directory, Codex accounts a Codex home; one OpenCode database holds all providers, so its directories stay a global list.
- **Subscriptions only, rename**: rename the field, keep the global lists for token-based accounts.
- **Every account, OpenCode too**: no global lists, but OpenCode directories could end up on several accounts.

## Decision

Approach B (sidebar inside General) with six pages, and every account gets its own agent directory while OpenCode keeps one global list. The maintainer chose B over the whole-window sidebar. Existing entries of the global Claude Code and Codex lists are dropped on load, with a load note per entry.

## Key Requirements

- **General sidebar**: the General tab shows a sidebar with six pages, each holding today's options unchanged in behavior:
  - **Refresh**: refresh interval, Adapt refresh.
  - **Appearance**: Show usage as, Dropdown theme.
  - **Weekly window**: align with subscription account, fallback weekday and hour.
  - **Notifications**: Notify when a sign-in stops working, Notify before a free limit reset expires.
  - **Sources**: OpenCode data directories (default always read, add and remove others).
  - **Startup**: Start at login, Check for updates automatically.
  The other tabs (Menu Bar, Accounts, Groups, Prices, Log, About) stay as they are. The selected page is remembered like the selected tab.
- **Per-account directory**: every Claude account (subscription, Vertex, Anthropic API) has a "Claude Code directory" field, replacing "Credential directory"; every Codex account (subscription, OpenAI API) has a "Codex home" field. Sessions in that directory are read for usage; subscription accounts take their login from it (as today). An empty field means the default (`~/.claude`, `~/.codex`), which is always read anyway.
- **Global lists removed**: "Additional Claude Code directories" and "Additional Codex homes" disappear from Settings. Entries already in the configuration (`logDirectories`, `codexHomes`) are no longer read; each dropped entry gets a load note in the diagnostic log naming it, so a user can move it to an account.
- **Attribution unchanged**: the rules that assign a session to an account stay as they are (request ids, provider hints, markers); the account directories add places to read and keep their role as the tie-breaker between subscription accounts of the same kind.
- **Invented example paths**: prompts, captions, README and tests use made-up profile paths such as `~/.claude-personal`, `~/profiles/acme/claude`, `~/.codex-lab`, `~/.local/share/opencode-lab`; no `cc-deck` path remains.
- **Docs**: README's "Security and privacy" table and any doc that names the global lists follow the change. The website privacy copy is checked for the same wording.
- **Screenshots**: no shot shows the General or Accounts tab today (the Settings strips are Menu Bar and Prices), so no recapture is expected; the plan confirms this.

## Open Questions

- Sidebar entry icons and whether the sidebar shows section counts or descriptions.
- Whether the token-based accounts' directory field sits in its own "Usage source" section or next to the provider settings.
- Whether two accounts may name the same directory (today two subscription accounts may), and what the field says when a directory is also the default.
- Exact load note text for dropped global entries, and whether the first launch after the update also shows it in Settings.
- Whether the field validates that the directory exists (and for Claude, that it has a `projects` folder).
- Window size: does the 720 by 560 Settings window still fit the sidebar plus the widest page?
