# Contract: Configuration File (`config.json`)

Changes to `~/.config/agenttacho/config.json` for spec 034. Everything not listed keeps its spec 001 to 033 behavior.

## Account keys

### Claude subscription (`"type": "subscription"`)

| Key | Type | Rule |
|---|---|---|
| `credentialDirectory` | string | Unchanged key and decoding. Blank (empty or whitespace only) means `~/.claude` for sessions, login and tie-breaker (FR-006a). Written as entered. |

### Codex subscription (`"type": "codexSubscription"`)

| Key | Type | Rule |
|---|---|---|
| `codexHome` | string | Unchanged key and decoding. Blank means `~/.codex` (FR-006a). Written as entered. |

### Vertex (`"type": "tokenBased"`, `"provider": "vertex"` or no provider)

| Key | Type | Rule |
|---|---|---|
| `claudeCodeDirectory` | string, optional | New (FR-007). Its `projects` folder is read for sessions; nothing else in it. Absent, blank or not a string: no directory. Written only when not blank. |
| `codexHome` | any | Ignored with a load note, not written back. |

### OpenAI (`"type": "tokenBased"`, `"provider": "openai"`)

| Key | Type | Rule |
|---|---|---|
| `codexHome` | string, optional | New (FR-007). Its `sessions` folder is read for sessions; `auth.json` is never opened. Absent, blank or not a string: no directory. Written only when not blank. |
| `claudeCodeDirectory` | any | Ignored with a load note, not written back. |

Example:

```json
{ "id": "acc-acme", "type": "tokenBased", "icon": "brands:google",
  "displayName": "Acme Vertex", "provider": "vertex",
  "claudeCodeDirectory": "~/profiles/acme/claude",
  "budget": { "period": "monthly", "budgetUSD": 100, "shownInBar": true, "thresholds": [80, 100] } },
{ "id": "acc-lab", "type": "tokenBased", "icon": "brands:openai",
  "displayName": "OpenAI Lab", "provider": "openai",
  "codexHome": "~/.codex-lab", "groupId": "grp-lab", "shownInBar": false }
```

## Top-level keys

| Key | Before | Now |
|---|---|---|
| `logDirectories` | extra Claude Code directories, read | Never read for usage, never written (FR-011, FR-012). Entries produce load notes. |
| `codexHomes` | extra Codex homes, read | Same as `logDirectories`. |
| `openCodeDirectories` | extra OpenCode data directories | Unchanged. |

No value of `logDirectories` or `codexHomes` makes the configuration invalid.

## Directories read (FR-008)

```text
Claude Code: ~/.claude
             + effective credentialDirectory of every Claude subscription account
             + claudeCodeDirectory of every Vertex account that has one
Codex:       ~/.codex
             + effective codexHome of every Codex subscription account
             + codexHome of every OpenAI account that has one
OpenCode:    ~/.local/share/opencode + openCodeDirectories
```

Each list is expanded (`~`, trailing slash) and deduplicated by canonical path (symlinks resolved, `..` removed); the first spelling is kept. A missing directory reads nothing and adds no source error (research R8).

## Load notes

Written to the diagnostic log with source `config`, once per successful file read (FR-011, clarification 2). `<entry>` is the entry as written in the file, clipped to 160 characters; `<name>` is an account's display name, clipped to 32 characters (`...` appended when clipped).

### Dropped global entries

One note per non-blank entry, first matching row wins:

| Condition | `logDirectories` note | `codexHomes` note |
|---|---|---|
| canonical path equals an account's directory (first account in list order) | `logDirectories entry "<entry>" is no longer read; it is already covered by account "<name>"` | `codexHomes entry "<entry>" is no longer read; it is already covered by account "<name>"` |
| otherwise | `logDirectories entry "<entry>" is no longer read; set it as the Claude Code directory of an account in Settings > Accounts` | `codexHomes entry "<entry>" is no longer read; set it as the Codex home of an account in Settings > Accounts` |

Covering accounts: Claude subscription and Vertex for `logDirectories`; Codex subscription and OpenAI for `codexHomes`. An account's directory is its effective one: an empty field means the default (`~/.claude` or `~/.codex`), so an entry equal to the default is covered by the first account that resolves to it and otherwise gets the "set it as" note (spec 034 FR-008, walkthrough 2026-10-22). Blank entries produce no note.

A key whose value is not a list of strings (including `null`, a string, or a list holding a non-string):

- `logDirectories is not a list of directories, ignored`
- `codexHomes is not a list of directories, ignored`

### Account keys

| Condition | Note |
|---|---|
| Vertex account with a `codexHome` key | `codexHome of account "<name>" does not belong to a Vertex account, ignored` |
| OpenAI account with a `claudeCodeDirectory` key | `claudeCodeDirectory of account "<name>" does not belong to an OpenAI account, ignored` |
| provider's own key is not a string (including `null`) | `<key> of account "<name>" is not readable, ignored` |

A blank string for the provider's key produces no note.

### Blank subscription directory on the default

A file saved before spec 034 can hold a cleared `credentialDirectory` (or `codexHome`) next to an account that names `~/.claude` (or `~/.codex`). It stays valid: the duplicate check compares a blank entry as entered, so only two blank entries or two spellings of the same directory collide. Each blank entry that shares the default with another subscription account of the same agent gets one note:

- `Claude Code directory of account "<name>" is empty, so it reads ~/.claude like account "<other>"`
- `Codex home of account "<name>" is empty, so it reads ~/.codex like account "<other>"`

Settings does not let an edit create this state: clearing a subscription directory while another account of the same agent reads the default shows "Not applied: <label> of account "<name>" is empty, so it reads <default> like Claude (or Codex) subscription account "<other>". Enter the directory this account runs from." A configuration that already holds it stays editable.

Directories are read without surrounding whitespace; the file keeps every directory field as typed.

## Save

- `logDirectories` and `codexHomes` are never written (FR-012).
- A token-based account writes `claudeCodeDirectory` (Vertex) or `codexHome` (OpenAI) only when its value is not blank; the other provider's key is never written (FR-007).
- Switching a token-based account's provider in Settings clears its directory, so the saved file has no directory key for it until a new one is entered (FR-007).
