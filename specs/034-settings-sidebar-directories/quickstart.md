# Quickstart: Settings Sidebar and Per-Account Directories

## Automated

```bash
make test           # UsageCore and DemoMode tests, including the page, directory, load note and source tests
make test-release   # release script tests (no stem changes expected)
rg cc-deck Sources Tests docs README.md   # SC-005: no output
```

Expected: all green; `rg` prints nothing.

## Demo build (no real accounts)

```bash
make app-demo
```

1. Open Settings > General. A sidebar lists Refresh, Appearance, Weekly window, Notifications, Sources, Startup with icons; Refresh is selected the first time.
2. Click each entry and compare with `contracts/settings-layout.md`: every option of the old General tab is on exactly one page (SC-001).
3. Select Startup, close Settings, reopen it: Startup is still selected. Switch to Accounts and back: still Startup. Quit and relaunch the demo: still Startup (FR-003).
4. On Appearance, switch "Show usage as" to Remaining, then press Command-Z: it goes back to Used (FR-004). Enter `30` as refresh interval on Refresh: "Not applied: ..." appears at the bottom; enter `300`: it disappears.
5. Sources shows only the OpenCode list (prompt `~/.local/share/opencode-lab`) and the caption pointing to Accounts. "Additional Claude Code directories" and "Additional Codex homes" appear nowhere (FR-010).
6. Accounts: a Claude subscription shows "Claude Code directory" with the new caption; a Codex subscription's "Codex home" caption no longer says "It only matters when ..."; a Vertex account has a "Usage source" section with an empty "Claude Code directory" (prompt `~/profiles/acme/claude`); an OpenAI account the same with "Codex home" (prompt `~/.codex-lab`).
7. Type `~/profiles/acme/claude` into the Vertex field, then switch Provider to OpenAI: the field is empty and labeled "Codex home". Undo restores the Vertex directory.
8. The window stays 720 by 560 points; no field or button is clipped on any page, in light and dark appearance.

## Upgrade with old global entries

Automated in `LegacyDirectoryNotesTests` and `ConfigurationTests` (temp homes, invented paths). For a manual look with `make app`, add to `~/.config/agenttacho/config.json` the keys `"logDirectories": ["~/profiles/acme/claude", "~/.claude"]` and `"codexHomes": ["~/.codex-lab"]`, with a Vertex account whose `claudeCodeDirectory` is `~/profiles/acme/claude`. After the next refresh, Settings > Log shows (`contracts/configuration.md`):

- `logDirectories entry "~/profiles/acme/claude" is no longer read; it is already covered by account "<name>"`
- `logDirectories entry "~/.claude" is no longer read; set it as the Claude Code directory of an account in Settings > Accounts` (or `it is already covered by account "<name>"` when an account's directory, or an empty field, resolves to `~/.claude`)
- `codexHomes entry "~/.codex-lab" is no longer read; set it as the Codex home of an account in Settings > Accounts`

After any Settings change, the file contains neither `logDirectories` nor `codexHomes` (FR-012).

## Real accounts (maintainer, manual)

1. `make app`. In Accounts, give a Vertex account the Claude Code directory you run Vertex sessions from; after the next refresh its spend matches what it showed with the old global list (SC-003).
2. Give an OpenAI account a Codex home with API-key sessions; its spend includes them after the next refresh.
3. Settings > Log shows no keychain or `auth.json` line for either token-based account.

## Screenshots

None to recapture: no shot shows General or Accounts (plan, "Screenshots and website").
