# Contract: Settings > Accounts, "Which sessions count"

**Feature**: 038-match-rule-operators (reworked 2026-10-28)

## Token-based account section "Which sessions count"

Rows, in order (FR-012):

| Harness and kind | Rows |
|---|---|
| Claude Code, Directory only | Sessions `[Directory only ▾]` |
| Claude Code, Vertex or Other provider | Sessions `[Vertex ▾]`; `[ ] Only when`; when ticked: Condition `[Model ▾] [starts with ▾] [text]` |
| Codex | text row "Counts Codex sessions signed in with an API key."; `[ ] Only when`; when ticked: Condition row |
| OpenCode, Vertex or OpenAI | Sessions `[Vertex ▾]`; `[ ] Only when`; when ticked: Condition row |
| OpenCode, Other provider | Sessions `[Other provider ▾]`; Condition row (always, no checkbox) |

- Sessions pop-up items: Claude Code "Directory only", "Vertex", "Other provider"; OpenCode "Vertex", "OpenAI", "Anthropic", "Other provider". The pop-up keeps the width of its widest item (`StableWidthPicker`, reused).
- "Only when" is a checkbox (`Toggle` with `.toggleStyle(.checkbox)`).
- Condition row (reused from the first version): one visible label "Condition"; field pop-up (Model, Request id, Message id, Anywhere for Claude Code; Model, Anywhere otherwise), operator pop-up ("starts with", "contains", "matches regex"; Anywhere offers the last two), text field with the invented prompt below; accessibility labels "Field", "Operator", "Text". The text field moves to a second line inside the row when less than about 12 characters remain.

| Field | starts with | contains | matches regex |
|---|---|---|---|
| Model, Request id, Message id | `intranet/` | `glm` | `^intranet/` |
| Anywhere | (not offered) | `proj-alpha` | `proj-(alpha\|beta)` |

Behavior (FR-014, FR-019, edge cases):

- Ticking "Only when" shows the account's last condition, or Model, starts with, empty text the first time. Unticking hides the row and keeps the condition for the next tick (not written to the file).
- Choosing OpenCode Other provider turns the condition on the same way; choosing another kind afterwards leaves it on.
- Choosing Directory only hides the checkbox and the row and keeps the condition; the next kind that shows it brings it back as it was.
- A harness change sets the kind to the harness's default and keeps the condition (its field becomes Model when the harness does not offer it).
- Switching the field to Anywhere while "starts with" is chosen changes the operator to "contains".
- The window saves about 0.6 s after an edit; undo and redo cover kind, checkbox, field, operator and text.

## Notes (inside the group, below the rows)

Caption size, secondary color, leading aligned; in this order, each only when it applies (FR-013, research R13):

| # | When | Text |
|---|---|---|
| 1 | Claude Code Directory only | Counts only sessions that ran from this account's Claude Code directory, nothing else. |
| 1 | Claude Code Vertex | Also counts Claude Code requests billed through Vertex (the request id starts with req_vrtx_) from sessions no account's Claude Code directory claims. |
| 1 | Claude Code Other provider | Also counts Claude Code requests without an Anthropic request id, such as those through a company gateway, from sessions no account's Claude Code directory claims. |
| 1 | OpenCode Vertex | Counts OpenCode messages whose provider is google-vertex or google-vertex-anthropic. |
| 1 | OpenCode OpenAI | Counts OpenCode messages whose provider is openai. |
| 1 | OpenCode Other provider | Counts OpenCode messages of any provider other than Vertex and OpenAI. The condition says which. |
| 2 | condition shown with field Anywhere | Anywhere searches the whole record line, including tool inputs and outputs, so a session that only mentions the text matches too. |
| 3 | Claude Code Vertex or Other provider | Sessions that ran from <directory field, or ~/.claude (the default, since the Claude Code directory is empty)> always count for this account. The choices above decide for sessions that no account's Claude Code directory claims, such as those from Claude Code before version 2.1.300. (Shared directory: see the last decision below.) |
| 4 | condition shown with a blank text | The condition needs a text. |
| 4 | regex that does not compile | This regular expression is not valid. |
| 5 | overlap, Claude Code (not for Directory only) | ⚠ Records that match both this account and "X" stay Unassigned. Give one of them its own Claude Code directory, another choice under Sessions or another condition. |
| 5 | overlap, OpenCode | ⚠ Records that match both this account and "X" stay Unassigned. Give one of them another choice under Sessions or another condition. |
| 5 | overlap, Codex | ⚠ Records that match both this account and "X" stay Unassigned. Give one of them another condition. |
| 6 | Directory only with a shared main directory | ⚠ "X" uses the same Claude Code directory, so its sessions count for "X", not for this account. Give this account its own Claude Code directory. |

Codex has no note 1 (its sentence is the row). Notes 5 and 6 use the warning symbol (`exclamationmark.triangle`), as the first version's overlap warning does. "X" lists every other account (`"A"`, `"A" and "B"`, `"A", "B" and "C"`).

## Account list subtitle

The kind's name with the budget, for example `Other provider · $200 / month` (existing format): "Directory only", "Vertex", "Other provider", "API key", "OpenAI". The condition is not shown.

## New account sheet (token-based)

Harness pop-up, then the same Sessions pop-up (default: Claude Code Directory only, Codex none, OpenCode Vertex), "Only when" checkbox and Condition row; notes 1, 2 and 6 as captions below the controls. "Add" with a blank text or an invalid pattern shows the problem in the sheet's red validation message and adds nothing. Display name prompts:

| Kind | Prompt and default name |
|---|---|
| Claude Code Directory only | Claude Code account |
| Claude Code Vertex | Claude Code via Vertex |
| Claude Code Other provider | Claude Code via gateway |
| Codex API key | Codex API key |
| OpenCode Vertex | OpenCode via Vertex |
| OpenCode OpenAI | OpenCode via OpenAI |
| OpenCode Other provider | OpenCode account |

The default icon follows the kind: Google for Vertex, OpenAI for API key and OpenCode OpenAI, Claude for OpenCode Anthropic, the harness icon otherwise.

## Subscription account "Session matching (advanced)"

Row: Custom marker `[text field]` (no fixed width, reused). Notes inside the group (FR-018):

1. Leave this empty in most cases. Sessions that ran from this account's Claude Code directory count for it; other usage is assigned by its kind: direct Anthropic requests from Claude Code for a Claude subscription, ChatGPT-plan sessions for a Codex subscription.
2. Use a marker only to tell apart two subscriptions of the same kind. Enter text that appears only in this account's session records, such as a project path or a host name. When it is set, only this subscription's own kind of usage that contains the text counts for it; usage of a token-based account never does.

## Wording rule (FR-017)

No visible text of a token-based account says "profile", "Match rule", "Custom" or "preset". The token-based Claude Code directory prompt changes from `~/agent-profiles/work/claude` to `~/.claude-gateway`.

## Decisions at the plan review (2026-10-28)

- The new account sheet shows the "Claude Code directory" field for token-based Claude Code accounts (same field, prompt and caption as in Settings), so a Directory only account gets its own directory in one step; the Directory only warning (row 6) shows in the sheet from that field's value.
- No UI text uses "profile", for subscription accounts too: the Claude subscription's directory caption says "or enter another Claude Code directory such as ~/.claude-personal".
- The directory note (Claude Code) names the field's value: "Sessions that ran from ~/.claude-gateway always count for this account. ..."; an empty field reads "~/.claude (the default, since the Claude Code directory is empty)"; when other accounts use the same directory it reads "Sessions that ran from <dir> also belong to \"X\", so the choices above decide which of them count for this account, as they do for sessions that no account's Claude Code directory claims." (walkthrough feedback, 2026-10-28).
