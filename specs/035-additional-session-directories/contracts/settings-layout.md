# Contract: Settings Layout and Texts

All texts are constants or functions of `AccountDirectoryText` in UsageCore (FR-002, FR-013, FR-014), so `AccountDirectoryTextTests` checks them. The window stays 720 by 560 points; no other tab changes.

## Settings > Accounts

The new section sits directly below the section that holds the main directory:

| Account | Sections, top to bottom (new one marked) |
|---|---|
| Claude subscription | Account, Subscription, **Additional session directories**, Notifications, Session matching (advanced) |
| Codex subscription | Account, Codex subscription, **Additional session directories**, Notifications, Session matching (advanced) |
| Vertex | Account, Token-based, Usage source, **Additional session directories**, Budget and Notifications (own budget only), Session matching (advanced) |
| OpenAI | same as Vertex |

Section content (the shared `DirectoryListSection`, the same view the OpenCode list uses):

1. Caption (`.caption`, secondary)
2. A bordered list, about four rows high, one row per entry: the entry on one line, shortened in the middle, the full entry as tooltip. Rows can be selected (several at once). An empty list shows `emptyList` (`No directories`) in secondary text.
3. Below the list, the macOS add and remove buttons: a borderless plus button (accessibility label "Add") that opens a menu, and a borderless minus button (accessibility label "Remove") that removes the selected rows, disabled without a selection. The Delete key removes the selected rows too.
4. Editing in place: a double-click on a row, Return on a selected row, or `editItem` (`Edit`) in the row's context menu (which also has "Remove") turns the row into a text field with the entry. Return or leaving the field applies `SessionDirectoryEntry.replacing(at:with:in:)` (trimmed; blank text or another entry's text leaves the list unchanged); Escape cancels.

The add menu:

| Item | Text | Action |
|---|---|---|
| `chooseFolderItem` | `Choose Folder…` | An open panel for folders only, several at once, hidden folders shown, starting in the home folder, with the message `chooseFolderMessage(for:)`. Each chosen folder is added as `SessionDirectoryEntry.entry(forChosenFolder:paths:)`: the home folder written as `~`. |
| `enterPathItem` | `Enter Path…` | A sheet titled `enterPathTitle` (`Add Directory`) with a text field (the list's invented prompt), the caption `enterPathCaption` (`Start with ~/ or /. * stands for any folder name at one level.`), "Cancel" and a default "Add" button disabled while the field is blank. |

| Key | Claude Code | Codex | OpenCode |
|---|---|---|---|
| `chooseFolderMessage(for:)` | `Choose Claude Code directories whose sessions count for this account.` | `Choose Codex homes whose sessions count for this account.` | `Choose OpenCode data directories that hold an opencode.db.` |

| Key | Claude Code (Claude subscription, Vertex) | Codex (Codex subscription, OpenAI) |
|---|---|---|
| `additionalDirectoriesSection` | `Additional session directories` | same |
| `additionalDirectoriesPrompt(for:)` | `~/.claude-lab` | `~/.codex-lab` |
| `additionalDirectoriesCaption(for:)` | `Sessions in these directories are read for this account's usage, in addition to the Claude Code directory above. * stands for any folder name at one level, for example ~/agent-sessions/openshell/*/claude. Only session files are read, never a login.` | `Sessions in these directories are read for this account's usage, in addition to the Codex home above. * stands for any folder name at one level, for example ~/agent-sessions/openshell/*/codex. Only session files are read, never a login or auth.json.` |

The harness comes from `AccountKind.sessionHarness`, so an OpenAI account shows the Codex texts and a provider switch swaps them (and empties the list).

Add: `SessionDirectoryEntry.adding(_:to:)` for each chosen folder or the entered path; an entry already in the list after trimming leaves it unchanged. A refused entry is added to the draft, and the bottom line reads `Not applied: Additional session directory "<entry>" of account "<name>": <reason>.` until it is removed or undone.

The new account sheet shows no list.

## Settings > General > Sources

| Element | Text |
|---|---|
| OpenCode section title (`openCodeSection`) | `Additional OpenCode data directories` (unchanged) |
| OpenCode caption (`openCodeCaption`, moved from the view) | `~/.local/share/opencode is always read. Add other OpenCode data directories that hold an opencode.db. * stands for any folder name at one level, for example ~/agent-sessions/openshell/*/opencode.` |
| OpenCode prompt (`openCodePrompt`) | `~/.local/share/opencode-lab` (unchanged) |
| "Claude Code and Codex" caption (`sourcesAccountsCaption`) | `Claude Code directories and Codex homes are set per account in Accounts, together with any additional session directories. An account without one uses ~/.claude or ~/.codex.` |

The OpenCode list is the same `DirectoryListSection` (list, add menu, remove button) with the OpenCode texts.

A refused OpenCode entry shows `Not applied: OpenCode data directory "<entry>": <reason>.`

## Behavior

- Apply, undo and redo go through the existing draft in `SettingsView`; nothing new in the app target.
- A list change refreshes usage locally; no plan-limit request (contracts/configuration.md "Refresh classification").
- Settings never lists folders and shows no match count; the log does (contracts/directory-resolution.md).
