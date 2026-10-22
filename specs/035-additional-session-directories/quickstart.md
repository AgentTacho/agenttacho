# Quickstart: Additional Session Directories per Account

## Automated

```bash
make test           # UsageCore and DemoMode tests, including entry rules, wildcard expansion, resolution, sources and attribution
make test-release   # release script tests (no stem changes expected)
rg cc-deck Sources Tests docs README.md   # SC-006: no output
rg -n '[\x{2013}\x{2014}]' specs/035-additional-session-directories Sources Tests docs README.md   # no output
```

Expected: all green; both `rg` runs print nothing.

What the tests prove (details in `contracts/`):

| Proof | Test suite |
|---|---|
| SC-001 same totals from an additional directory, four account kinds | `LogIndexTests`, `CodexSessionSourceTests` |
| SC-002 folders appear and disappear between refreshes, no Settings change | `SessionDirectoryResolverTests`, `LogIndexTests` |
| SC-003 one directory as main, literal entry and wildcard match counts once | `SessionDirectoryResolverTests`, `LogIndexTests`, `CodexSessionSourceTests` |
| SC-004 no credential read or request for an additional directory (fixture holds `auth.json`, recording doubles) | `SubscriptionSourceTests`, `CodexLimitsSourceTests`, `CodexSessionSourceTests` |
| SC-005 `re-read 0` and `0 file(s) parsed` on an unchanged second refresh | `LogIndexTests`, `CodexSessionSourceTests` |
| FR-004 to FR-006 matching and refusals | `WildcardExpanderTests`, `SessionDirectoryEntryTests` |
| FR-013 OpenCode wildcard databases | `OpenCodeSourceTests` |
| FR-007 load notes, nothing written back | `ConfigurationTests` |
| FR-012 tie-breaker ranks | `AttributionTests` |

## Fixture walk-through with the real build (invented paths only)

Use a scratch user account or a copy of the config; never a real sandbox export.

```bash
mkdir -p ~/agent-sessions/openshell/alpha/claude/projects/demo
mkdir -p ~/agent-sessions/openshell/beta/claude/projects/demo
# copy one fixture session from Tests/UsageCoreTests/Fixtures into each projects/demo folder
make app
```

1. Settings > Accounts, select the Claude subscription: "Additional session directories" sits under "Subscription", caption names `~/agent-sessions/openshell/*/claude`, prompt `~/.claude-lab`.
2. Add `~/agent-sessions/openshell/*/claude`. Within a second the menu bar refreshes; Settings > Log shows `wildcard "~/agent-sessions/openshell/*/claude": 2 folder(s) matched` and a `directories read` count two higher than before. The `config` save line ends in `refresh local`, so no plan-limit request follows (FR-003).
3. Add `~/agent-sessions/openshell/*/claude` again (or with a trailing space): the list does not change.
4. Add `~/*/claude`: the bottom line reads `Not applied: Additional session directory "~/*/claude" of account "...": * may not stand for a whole folder directly under the home folder or /.` Press Command-Z: the line disappears.
5. `mkdir -p ~/agent-sessions/openshell/gamma/claude/projects/demo` with a fixture session, wait for the next refresh: the log says `3 folder(s) matched`. Delete `beta`: the next refresh says `2 folder(s) matched`, nothing fails.
6. Select a Vertex account, switch Provider to OpenAI: the list empties and the caption names `~/agent-sessions/openshell/*/codex`. Undo restores both.
7. General > Sources: the OpenCode caption mentions `*` with `~/agent-sessions/openshell/*/opencode`.

## Hand edit

Add to an account in `~/.config/agenttacho/config.json`:

```json
"additionalSessionDirectories": ["~/.claude-lab", "~/agent-sessions/**/claude", "agent-sessions/*/claude"]
```

After the reload, Settings > Log shows two notes (`... is refused (** is not supported, * covers one folder level), ignored` and `... is refused (it must start with ~/ or /), ignored`), Settings shows only `~/.claude-lab`, and the next save writes only that entry. Replace the value with `"~/.claude-lab"` (a string): one note `additionalSessionDirectories of account "..." is not readable, ignored`, the rest of the configuration loads.

## Demo build

```bash
make app-demo
```

Settings > Accounts shows the new section, empty, on every account; no shot covers it (plan "Screenshots and website").
