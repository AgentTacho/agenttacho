# Data Model: Settings Sidebar and Per-Account Directories

## GeneralSettingsPage (UsageCore, enum)

| Case (raw value) | `title` | `systemImage` | Options (FR-002) |
|---|---|---|---|
| `refresh` | Refresh | `arrow.clockwise` | Refresh interval with minimum hint, Adapt refresh |
| `appearance` | Appearance | `paintbrush` | Show usage as, Dropdown theme |
| `weeklyWindow` | Weekly window | `calendar` | Align with subscription account, Fallback weekday, Fallback hour, two captions |
| `notifications` | Notifications | `bell` | Notify when a sign-in stops working, Notify before a free limit reset expires |
| `sources` | Sources | `folder` | Additional OpenCode data directories, per-account caption |
| `startup` | Startup | `power` | Start at login, Check for updates automatically |

- `allCases` is the sidebar order (FR-001).
- `init(stored: String?)`: the case with that raw value, otherwise `.refresh` (FR-003).
- Persisted in the defaults under `generalSettingsPage`, never in `config.json`.

## Account directory (UsageCore, part of each account kind)

| Account kind | Stored (entered) | Effective | Config key | Default when blank | Read for |
|---|---|---|---|---|---|
| Claude subscription | `SubscriptionSettings.enteredCredentialDirectory: String` | `credentialDirectory: String` | `credentialDirectory` | `~/.claude` | sessions (`projects`), login (keychain item), tie-breaker |
| Codex subscription | `CodexSubscriptionSettings.enteredCodexHome: String` | `codexHome: String` | `codexHome` | `~/.codex` | sessions (`sessions`), sign-in (`auth.json`, live limits on), tie-breaker |
| Vertex (token-based) | `TokenBasedSettings.enteredSessionDirectory: String?` | `sessionDirectory: String?` | `claudeCodeDirectory` | nil, read as `~/.claude` | sessions (`projects`) only |
| OpenAI (token-based) | `TokenBasedSettings.enteredSessionDirectory: String?` | `sessionDirectory: String?` | `codexHome` | nil, read as `~/.codex` | sessions (`sessions`) only |

Rules:

- **Blank** means empty after trimming whitespace and newlines (FR-006a, FR-007).
- The effective value is what every reader uses; the entered value is what the editor binds and what is encoded for subscription accounts (research R3).
- A token-based account encodes its key only when `sessionDirectory` is non-nil; the key name follows `provider` (FR-007).
- **Provider switch**: setting `TokenBasedSettings.provider` to a different value sets `enteredSessionDirectory = nil` (FR-007). Initializers do not trigger it.
- `Configuration.validate()` keeps its rules: duplicate checks apply to subscription accounts (effective values, so a blank entry and `~/.claude` collide); a token-based directory may equal any other directory. Only the Claude duplicate message changes, to `Claude Code directory "<dir>" is used by more than one Claude subscription account.`
- `dataRelevant()` replaces each entered value with its effective value before comparing.

## Configuration lookups (UsageCore)

- `Account.agentDirectory(for:)`: the effective `credentialDirectory` of a Claude subscription, the effective `codexHome` of a Codex subscription, or the `sessionDirectory` of a Vertex or OpenAI account, `Provider.defaultSessionDirectory` (`~/.claude` or `~/.codex`) when blank; nil for an account of the other agent.
- `accountClaudeCodeDirectories: [String]`: `agentDirectory(for: .claudeCode)` of each account in list order. Unexpanded.
- `accountCodexHomes: [String]`: `agentDirectory(for: .codex)` of each account in list order.

Consumers expand and deduplicate by canonical path: `SessionLogSource.directories(for:)` and `CodexSessionSource.homes(for:)` read exactly these directories, so `~/.claude` and `~/.codex` are read only when an account resolves to them, and an agent without an account has nothing read (FR-008, walkthrough 2026-10-22).

## Dropped global entry (UsageCore, load time only)

| Key | Agent | Covering accounts | Default |
|---|---|---|---|
| `logDirectories` | Claude Code | Claude subscription, Vertex | `~/.claude` |
| `codexHomes` | Codex | Codex subscription, OpenAI | `~/.codex` |

- Not a property of `Configuration`; decoded only through `LegacyCodingKeys` in `Configuration.init(from:)` and never encoded (FR-011, FR-012).
- Per non-blank entry exactly one note, chosen in this order: covered by the first matching account (canonical path, `agentDirectory(for:)`, so an account with an empty field covers the default), generic. A non-list value gives one note for the key. Texts in `contracts/configuration.md`.
- No state is kept: the notes are produced on each successful file read and handed out once by `ConfigStore.takeLoadNotes()`.

## Load note flow (existing)

```text
config.json read (ConfigStore.loadLocked)
  -> JSONDecoder.userInfo[ConfigurationLoadNotes.userInfoKey]
  -> Account.init(from:) appends key notes (R5)
  -> Configuration.init(from:) appends legacy notes after accounts (R6)
  -> validate() ok -> pendingLoadNotes
  -> RefreshCoordinator.performRefresh: log.append(source: "config", note)
```

A file that fails to decode or validate keeps no notes (spec 012 FR-003), as today.
