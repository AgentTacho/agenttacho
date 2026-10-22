# Contract: Directory Resolution, Attribution and Log Lines

How the Claude Code, Codex and OpenCode sources turn the configuration into the directories one refresh reads (FR-004, FR-005, FR-008 to FR-013, FR-016).

## Wildcard expansion (`WildcardExpander`, FR-004, FR-005)

1. Expand `~`, standardize, split into components.
2. Base: the leading components without `*`. Then for each later component: with `*`, list every current candidate folder and keep the names that `WildcardPattern.matches(name:component:)` accepts and that `isDirectory` (symlinks followed); without `*`, append it as is. A bare `*` component never lists a candidate whose canonical path is the home folder or `/` (another spelling of `~/*` or `/*`, such as a different case, a firmlink or a symlink); the candidate is reported as not listed. Each level keeps at most `levelBudget` (1000) candidates in path order and marks the expansion truncated.
3. Keep only results that are folders.
4. Drop a result whose canonical path is the home folder or `/`.
5. Sort by full path (`String <`), count all (`matched`), keep the first 100 (`paths`).

`WildcardPattern`: `*` matches any run of characters within one name, including none, never `/`. A component that starts with `*` does not match a name that starts with `.`. Only `*` is special.

| Entry | Folders on disk | Matches |
|---|---|---|
| `~/agent-sessions/openshell/*/claude` | `alpha/claude`, `beta/claude`, `.cache/claude`, `team/alpha/claude`, `gamma/claude.txt` (a file) | `alpha/claude`, `beta/claude` |
| `~/.claude-*` | `~/.claude-lab`, `~/.claude-personal`, `~/.claude` | `~/.claude-lab`, `~/.claude-personal` |
| `~/agent-sessions/openshell/*/claude` | `link/claude` where `link` is a symlink to a folder | `link/claude` |
| `~/agent-sessions/none/*/claude` | `~/agent-sessions/none` missing | none, no error |
| `/Users/*` | the home folder is `/Users/tester` | every user folder except `/Users/tester` |

A parent that exists but cannot be listed adds to `listingErrors` with the reason; a missing parent, or one deleted between the check and the listing, adds nothing.

## Resolution order (`SessionDirectoryResolver.resolve`, FR-008, FR-012)

For harness `.claudeCode` (Claude subscription and Vertex accounts) or `.codex` (Codex subscription and OpenAI accounts):

```text
1. main directories   configuration.accountClaudeCodeDirectories / accountCodexHomes (spec 034, accounts order)
2. additional         for each account of that harness in accounts order,
                        for each entry in list order:
                          literal  -> expanded entry
                          wildcard -> expansion.paths (path order, at most 100)
```

Each directory is kept once, by `canonicalPath`, with the first spelling and origin. Skipped without a log line: the home folder and `/` for every Claude Code directory (as today) and every additional Codex directory. A Codex main home is not filtered (unchanged).

`additionalByAccount`: for every subscription account, the canonical paths of its literal entries and its wildcard matches, whether or not the directory was first reached another way.

`wildcards`: one `WildcardReport` per distinct entry text in first-seen order, even when several accounts list it.

### Example

Accounts: Claude Max (main blank, so `~/.claude`; entries `~/.claude-lab`, `~/agent-sessions/openshell/*/claude`), Vertex Acme (main `~/.claude-lab`). Folders: `~/.claude`, `~/.claude-lab`, `~/agent-sessions/openshell/alpha/claude`.

```text
directories: ~/.claude (main), ~/.claude-lab (main, Vertex), ~/agent-sessions/openshell/alpha/claude (wildcard)
additionalByAccount: Claude Max -> {~/.claude-lab, ~/agent-sessions/openshell/alpha/claude}  (canonical)
wildcards: "~/agent-sessions/openshell/*/claude": matched 1, read 1
```

## What is read from each directory (FR-009, FR-010)

| Source | From a main directory | From an additional directory |
|---|---|---|
| Claude Code | `projects/**/*.jsonl`; for a Claude subscription, `SubscriptionSource` also reads the login (unchanged) | `projects/**/*.jsonl` only |
| Codex | `sessions/**/rollout-*.jsonl`; for a Codex subscription, `CodexLimitsSource` reads sign-in and local snapshots (unchanged) | `sessions/**/rollout-*.jsonl` only; its rate-limit data decides the session's auth mode, never plan limits |
| OpenCode | `opencode.db` (default and literal entries, unchanged) | `opencode.db` of each matched folder that holds one; others skipped silently |

`SubscriptionSource`, `CodexLimitsSource`, `KeychainServiceName` and `CodexCredentialReader` never see an additional directory: they keep reading `credentialDirectory` and `codexHome` of subscription accounts only.

## Failure and issues (FR-008)

| Situation | Claude Code | Codex | OpenCode match |
|---|---|---|---|
| main directory missing | scanner error (unchanged) | `skipped, Codex not installed` / `skipped, home not found` (unchanged) | n/a |
| main directory unreadable | scanner error (unchanged) | issue plus log (unchanged) | n/a |
| additional literal missing | log `skipped, not found` | log `skipped, not found` | n/a |
| additional unreadable or a file under it unreadable | log line only | log line only, no issue | database read error: issue and stale, as a literal entry |
| no `projects` / `sessions` / `opencode.db` | nothing | nothing | nothing |

The Claude Code source throws only when `scannedDirectories == 0` and a main directory reported an error.

## Tie-breaker (FR-012)

Applies only when several subscription accounts of one kind match a record (spec 006 FR-015). With `dir` the canonical directory the file was found in:

```text
mains = matches where main directory == dir
if mains.count == 1                          -> that account
if mains.isEmpty:
    adds = matches where additional contains dir
    if adds.count == 1                       -> that account
otherwise                                    -> Unassigned
```

Because main directories are scanned first, a file reachable through a main and an additional directory is found in the main directory.

`Attributor.fingerprint` includes neither the entries nor the matches, so a new sandbox folder or an edited list never rereads the whole index (research R5). Instead each source keeps, per directory, `Attributor.claimKey(forDirectory:)`: the subscription accounts (of a kind with more than one account) that claim the directory as an additional directory. When the key of an indexed directory changes (a match appears, disappears or leaves the cap, or a list is edited), only that directory's files are attributed again: the Claude Code index rereads them, the Codex source rebuilds their records from the parsed sessions.

## Log lines (FR-005, FR-016)

Claude Code (`sessionLogs`), per refresh:

```text
<path>: skipped, not found                                      (additional literal, per refresh)
<path>: error: not readable                                     (additional, literal or match)
<path>: error: cannot read <file>: <error>                      (under an additional directory)
wildcard "<entry>": <n> folder(s) matched                       (one per entry)
directories read <d>, files seen <f>, re-read <r> (<b> bytes), records since collection start <c>, <s> s
```

Codex (`codex`), per refresh:

```text
<home>: <r> record(s) in window, <f> file(s) read               (main and literal homes, unchanged shape)
<home>: skipped, not found                                      (additional literal)
<home>: error: <message>                                        (additional, literal or match: unreadable, scan error)
wildcard "<entry>": <n> folder(s) matched, <r> record(s) in window, <f> file(s) read
<h> home(s) read, <s> session(s), <c> record(s) since collection start, <p> file(s) parsed, <t> s
```

OpenCode keeps its per-database lines; a matched folder without `opencode.db` gets none.

Cap line, all three sources, from `WildcardCapLog` (once after launch or after the configuration changes, then only when `<n>` changes):

```text
wildcard "<entry>": <n> folders matched, only the first 100 are read
```

Listing errors of an expansion: `wildcard "<entry>": cannot list <path>: <reason>`, per refresh.

Truncation line, all three sources, from `WildcardCapLog` with the same rule as the cap line:

```text
wildcard "<entry>": more than 1000 folders at one level, only the first 1000 are looked at
```

## Links inside an additional directory (FR-006, FR-009)

An additional directory or wildcard match is read only below itself: a `projects` (Claude Code), `sessions` (Codex) or `opencode.db` (OpenCode match) whose canonical path lies outside the directory is skipped with the log line `<dir>: skipped, <name> is a link outside the directory`. Main directories keep following their links.

## Unchanged OpenCode matches (FR-005)

A wildcard-matched `opencode.db` is opened again only when the size or modification date of the database or its `-wal` file changed; otherwise its records are kept and the log line reads `<db>: <n> record(s) in window, unchanged`.

SC-005: with unchanged matched files the Claude Code line reads `re-read 0` and the Codex line `0 file(s) parsed`.
