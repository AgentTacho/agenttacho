# Contract: Configuration File (`config.json`)

Changes to `~/.config/agenttacho/config.json` for spec 035. Everything not listed keeps its spec 001 to 034 behavior.

## Account key `additionalSessionDirectories`

Valid on every account type: `subscription` (Claude Code directories), `codexSubscription` (Codex homes), `tokenBased` with `provider` `vertex` (Claude Code directories) or `openai` (Codex homes).

| Value | Load | Save |
|---|---|---|
| absent | empty list, no note | not written |
| `[]` or only blank strings | empty list, no note | not written |
| list of strings | each entry trimmed; blank entries dropped silently; refused entries (below) dropped with one note each | trimmed, non-blank entries in order, key only when at least one |
| anything else (`null`, a string, a number, an object, a list holding a non-string) | empty list, one note | not written |

No value of this key makes the configuration invalid (FR-007). A `tokenBased` account whose provider changes in Settings loses its list (spec 034 FR-007 edge case); a hand-edited file keeps what it lists.

Example:

```json
{ "id": "acc-max", "type": "subscription", "icon": "brands:claude",
  "displayName": "Claude Max", "credentialDirectory": "",
  "additionalSessionDirectories": ["~/.claude-lab", "~/agent-sessions/openshell/*/claude"],
  "shownInBar": true, "thresholds": [] },
{ "id": "acc-plan", "type": "codexSubscription", "icon": "brands:openai",
  "displayName": "ChatGPT Plus", "codexHome": "~/.codex-lab",
  "additionalSessionDirectories": ["~/.codex"],
  "shownInBar": true, "thresholds": [], "liveLimits": true }
```

## Top-level key `openCodeDirectories`

The type check is unchanged: a value that is not a list of strings stays a decoding error, as today. After it, refused entries (below) are dropped with one note each and never written back. Literal relative entries are kept as today.

## Entry rules (FR-004, FR-006)

Checked on the trimmed entry, in this order, without any file system access. `~` and a leading `~/` expand to the home folder first; `.` and `..` are removed and a trailing slash dropped.

| Refusal | Applies to | Example | Reason text |
|---|---|---|---|
| `relative` | account lists always; OpenCode list only when the entry contains `*` | `agent-sessions/*/claude`, `~name/x` | `it must start with ~/ or /` |
| `doubleStar` | both | `~/agent-sessions/**/claude` | `** is not supported, * covers one folder level` |
| `homeOrRoot` | both | `~`, `~/`, `/`, the home folder's full path | `the home folder or / is not a session directory` |
| `bareStarAtTop` | both | `~/*/claude`, `/*`, `~/*` | `* may not stand for a whole folder directly under the home folder or /` |

Accepted examples: `~/.claude-lab`, `~/.claude-*`, `~/agent-sessions/openshell/*/claude`, `/Volumes/archive/*/codex`, `~/agent-sessions/openshell/sandbox-*/opencode`.

Only `*` is a wildcard; `?`, `[`, `]`, `{`, `}` are ordinary name characters. A `*` in a main directory field (`credentialDirectory`, `codexHome`, `claudeCodeDirectory`) stays an ordinary character.

## Load notes

Entries and names are clipped to 32 characters like other load notes (`Configuration.clipped`).

```text
additionalSessionDirectories of account "<name>" is not readable, ignored
additionalSessionDirectories entry "<entry>" of account "<name>" is refused (<reason>), ignored
openCodeDirectories entry "<entry>" is refused (<reason>), ignored
```

## Settings refusal (`Configuration.validate()`)

`ConfigurationError(kind: .sessionDirectoryEntry, message:)`, shown as "Not applied: <message>". The first refused entry in accounts order, then the OpenCode list, wins. The entry is not clipped.

```text
Additional session directory "<entry>" of account "<name>": <reason>.
OpenCode data directory "<entry>": <reason>.
```

## Refresh classification (FR-003)

| Change | `needsRefresh` | `needsNetworkRefresh` |
|---|---|---|
| add, remove or reorder an entry on any account | true | false |
| add or remove an OpenCode entry | true (unchanged) | false (unchanged) |
| change a Claude subscription's main directory | true | true (unchanged) |
