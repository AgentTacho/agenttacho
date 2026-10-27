# Contract: Settings > Accounts (token-based accounts)

All labels, captions and prompts live in `MatchRuleText` and `AccountDirectoryText` (UsageCore) so tests check them; examples are invented (FR-018). macOS controls per the HIG: pop-up buttons for choices, a text field for the custom text, a caption with a warning symbol for the overlap.

## Account editor

1. **Token-based** section
   - Harness: pop-up "Claude Code" / "Codex" / "OpenCode".
   - Budget: as today.
2. **Usage source** section (Claude Code and Codex only)
   - "Claude Code directory" or "Codex home" field, caption and prompt keyed by harness (today's texts, invented prompt `~/agent-profiles/work/claude` for Claude Code).
   - OpenCode instead shows one caption: "OpenCode data directories are set for all accounts in General > Sources."
3. **Additional session directories** (Claude Code and Codex only), as spec 035.
4. **Session matching** section
   - Match rule: pop-up with the presets of the harness, then "Custom", then "None (profile only)" for Claude Code. A Codex or OpenCode account whose rule was dropped while loading (FR-015) shows "None" as the current item while it is selected, so the pop-up never shows an empty value; once the user picks another item, "None" leaves the list.
   - Preset chosen: caption with what it checks, for example "Request id starts with req_vrtx_".
   - Custom chosen: "Field" pop-up (Model, Request id, Message id for Claude Code; Model for Codex and OpenCode; then "Anywhere in the record line"), and a text field with the prompt `intranet/` (or `proj-alpha` for "Anywhere"). Caption for "Anywhere": "Also searches tool inputs and outputs, so a session that only mentions the text matches too."
   - Claude Code caption (always): "Sessions that ran from this account's Claude Code directory count for it whatever the rule says. The rule decides for sessions without that information, such as older ones."
   - "None (profile only)" caption: "Only sessions that ran from this account's Claude Code directory count."
   - Overlap (FR-013): caption with `exclamationmark.triangle`: "Records that match both this account and \"Other\" stay Unassigned. Give one of them another rule or, for Claude Code, another directory."

## Subscription accounts

"Session matching (advanced)" with "Custom marker" stays; the first caption no longer says that Vertex counts OpenCode usage: "Leave this empty in most cases. Sessions that ran from this account's Claude Code directory count for it; other usage is assigned by its kind: direct Anthropic requests from Claude Code for a Claude subscription, ChatGPT-plan sessions for a Codex subscription."

## New account sheet (token-based)

Display name, Icon, Harness pop-up, Match rule pop-up (with the custom field and text when "Custom"), Budget as today. The display name prompt follows harness and preset: "Claude Code via Vertex", "Codex API key", "OpenCode via Vertex", "OpenCode via OpenAI", or "Claude Code account" / "Codex account" / "OpenCode account" for custom and none. The icon follows the preset's default until the user picks one.

## Behavior

- Changing the harness clears the directory fields and the additional directories and resets the rule to the harness default (data model).
- Apply, undo, redo and "Not applied" work as for the other fields; a blank custom text shows "Not applied: Account \"X\": the match rule needs a text".
- No change here sends a plan-limit request.
