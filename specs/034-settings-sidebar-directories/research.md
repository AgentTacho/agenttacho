# Research: Settings Sidebar and Per-Account Directories

All findings come from this repository at commit `06a8b50` and from the site checkout of 2026-10-21. The Technical Context has no open questions; each section records a design choice.

## R1: Sidebar inside the General tab

- **Decision**: `GeneralSettingsTab` becomes `HStack(spacing: 0) { List(selection:) ... .listStyle(.sidebar).frame(width: 170); Divider(); page }`. Each entry is a `Label(title, systemImage:)`; no counts, no descriptions (clarification 3).
- **Rationale**: The Accounts and Groups tabs already pair a `List(selection:)` with a detail form, so the look fits. A plain `List` keeps the window's toolbar tabs untouched (FR-005): `NavigationSplitView` inside a `TabView` tab adds a sidebar toggle and its own toolbar items to the Settings window and lets the user collapse the sidebar, which the spec does not ask for.
- **Alternatives**: `NavigationSplitView` (rejected, above); a sidebar for the whole window (rejected by the brainstorm, spec Assumptions); a segmented picker on top of the form (rejected: six segments do not fit, and it is not a sidebar).

## R2: Remembering the page

- **Decision**: `@AppStorage("generalSettingsPage")` stores `GeneralSettingsPage.rawValue`; `GeneralSettingsPage(stored:)` maps nil or an unknown value to `.refresh` (FR-003). The list's optional selection binding ignores nil, so a click on empty list space keeps the page.
- **Rationale**: Same mechanism as the selected tab (`@AppStorage("settingsPane")`), so it survives closing Settings, switching tabs and relaunching. The mapping is in UsageCore so the fallback is tested.
- **Alternatives**: `@SceneStorage` (rejected: lost on relaunch).

## R3: Empty subscription directory means the default (FR-006a)

- **Decision**: `SubscriptionSettings` stores `enteredCredentialDirectory`; `credentialDirectory` becomes computed: blank entry (empty after trimming whitespace and newlines) returns `Paths.defaultClaudeDirectory`, any other entry is returned as typed; the setter stores the entry. `CodexSubscriptionSettings` does the same with `enteredCodexHome` and `codexHome`. The settings editors bind the entered value. `Account` encodes the entered value under the existing keys; decoding fills the entered value. The structs' own synthesized `Codable` gets explicit `CodingKeys` (`enteredCredentialDirectory = "credentialDirectory"`, `enteredCodexHome = "codexHome"`) so nothing that encodes them directly changes shape.
- **Rationale**: About 25 call sites read `credentialDirectory` or `codexHome` (`SessionLogSource`, `Attributor`, `SubscriptionSource`, `KeychainServiceName`, `CodexLimitsSource`, `CredentialAlertTracker`, `ThresholdTracker`, `ResetTicketExpiryTracker`, `RefreshCoordinator`, `validate`, `subscriptionFingerprint`, `DropdownView` section notes). With the effective value behind the old name, all of them get FR-006a, including the keychain service name (`KeychainServiceName.for(configDirectory: "")` hashes the empty string today) and the FR-009 tie-breaker, without touching them. The entered value keeps the field empty while the user types: normalizing the draft would write `~/.claude` into the field 600 ms after it was cleared, in the middle of typing.
- **Alternatives**: normalize on decode and in `settingsCandidate` (rejected: fights the user while typing, above); a new `effective...` accessor at each call site (rejected: 25 edits, easy to miss one).

## R4: The directory of a token-based account (FR-007)

- **Decision**: One optional field on `TokenBasedSettings`, `enteredSessionDirectory: String?`, with computed `sessionDirectory` (nil when nil or blank). Its meaning and its configuration key follow the provider: Vertex `claudeCodeDirectory` (a Claude Code directory, harness `claudeCode`), OpenAI `codexHome` (a Codex home, harness `codex`). `provider` has a `didSet` that clears the entry when the provider changes. `didSet` does not run in initializers, so decoding is unaffected.
- **Rationale**: One field per account matches "the agent directory of an account" (spec Key Entities) and makes the provider switch a single rule in UsageCore, tested there; the editor keeps binding `$settings.provider`. The account's `harness` field is not used: the spec ties the field to the provider, and a Vertex account used with OpenCode simply leaves it empty (edge case).
- **Alternatives**: two optional fields (rejected: allows both at once, which the spec forbids); clearing in the view's binding (rejected: logic in the app target, constitution II).

## R5: Decoding the new keys

- **Decision**: For a token-based account, the provider's key is decoded as `String` with `try?`; a value that is not a string is ignored with the note `<key> of account "<name>" is not readable, ignored`. The other provider's key, when present, is ignored with `<key> of account "<name>" does not belong to a <Provider> account, ignored`. Neither ever makes the configuration invalid. Subscription accounts keep today's strict decoding of `credentialDirectory` and `codexHome` (a wrong type stays a decoding error, as it is now). Names are clipped with `Configuration.clipped` (32 characters).
- **Rationale**: Same lenient pattern as `headlineWindow`, `timeFormat` and `dropdownTheme` (spec 027, 025, 032): a hand edit never breaks loading. Encoding writes only the provider's key from the effective value, so the ignored key and a blank value disappear on the next save (FR-007).

## R6: Dropped global lists (FR-011, FR-012)

- **Decision**: `Configuration` loses `logDirectories` and `codexHomes` as properties and `CodingKeys` cases; `init(from:)` reads them through a private `LegacyCodingKeys` container, after `accounts` is decoded, so the notes can name covering accounts. `LegacyDirectoryNotes.notes` checks each non-blank entry in order: equal to an account's effective directory (an empty field meaning the default, `~/.claude` or `~/.codex`) of the same agent (Claude subscription or Vertex for `logDirectories`; Codex subscription or OpenAI for `codexHomes`; canonical, first account in list order) gives the covered note with that account's name; otherwise the generic note. A key whose value is not a list of strings (including `null`) gives one note for the key. Entries are clipped to 160 characters, names to 32. Exact texts: `contracts/configuration.md`.
- **Canonical comparison**: `Attributor.canonical(paths.expand(entry))`, the comparison spec 015 FR-006 uses. It resolves symlinks, so it touches the file system; it runs only when a legacy key has entries, which a fresh or demo configuration never has (spec 024 SC-002 keeps the demo away from `~/.claude`).
- **Once per load**: notes go through `ConfigurationLoadNotes`, which `ConfigStore` hands out once per successful file read and `RefreshCoordinator` writes to the diagnostic log; Settings > Log shows them (clarification 2). Because the next save omits both keys, the notes stop after the first save, which is the upgrade path the spec describes.
- **Rationale**: removing the `CodingKeys` cases is what makes FR-012 hold by construction: the synthesized encoder writes only `CodingKeys`.
- **Alternatives**: keep the properties and skip them in a hand-written `encode(to:)` (rejected: every future key would need a manual encode line); migrate entries onto accounts automatically (rejected by the spec: an entry cannot be assigned to an account safely).

## R7: Directory sets of the session sources (FR-008, FR-009)

- **Decision**: `SessionLogSource.directories(for:)` is `accountClaudeCodeDirectories` (effective subscription directories and Vertex directories, an empty field meaning `~/.claude`, accounts order), expanded, deduplicated by canonical path, first spelling kept. `CodexSessionSource.homes(for:)` is `accountCodexHomes` (an empty field meaning `~/.codex`), deduplicated by canonical path (today by expanded path, with a canonical recheck in `collect` that stays as a guard). Neither adds the default on its own: it is read only when an account resolves to it, and without an account of an agent nothing is read (walkthrough 2026-10-22; the first draft added both defaults unconditionally).
- **Read-only boundary**: `LogDirectoryScanner` enumerates only `<dir>/projects/**/*.jsonl`; `CodexSessionSource` only `<home>/sessions/**/rollout-*.jsonl` and never opens `auth.json`. Credentials are read only by `SubscriptionSource` (iterates `subscriptionAccounts`) and `CodexLimitsSource` (iterates `codexSubscriptionAccounts`), so a token-based directory never reaches a keychain item, `auth.json` or the network (FR-008, constitution III). A test asserts that a Vertex-only configuration makes no keychain read through a stub reader.
- **Attribution**: `Attributor` is unchanged: token-based candidates have no directory, and the tie-breaker still separates only subscription accounts of the same kind (FR-009). The scanner records the configured directory per file, so a session found through a Vertex directory is attributed by its request id as before.
- **Two accounts, one directory**: read once by the canonical dedupe; attribution decides per session (edge case).

## R8: An account directory that does not exist

- **Decision**: Claude side unchanged: the scanner already logs `log directory not found` without a source error unless no directory at all could be scanned. Codex side: a missing non-default home is logged as `<path>: skipped, home not found` and no longer adds a record batch issue. An unreadable home and file errors stay issues.
- **Rationale**: Spec edge case: "nothing is read from it and nothing fails; the field shows no error". Before this spec the only non-default Codex homes were global entries and subscription homes; a missing subscription home already shows in the account's plan-limit section (live limits read `auth.json` from it), so a second, source-level issue adds nothing. This aligns Codex with Claude.
- **Tests**: `missingConfiguredHomeIsAnIssueAndOthersStillCount` and `logNamesEveryLocation` move to account homes and expect a log line instead of an issue.

## R9: Refresh after a directory edit

- **Decision**: A token-based directory is data relevant (`needsRefresh` is true) but not part of `subscriptionFingerprint`, so Settings triggers a local refresh (`.local`), which runs the session sources and reuses the network results. `dataRelevant()` compares effective values, so whitespace or clearing a subscription field to its default does not refresh.
- **Rationale**: Scenario 4 and 5 say "from the next refresh on"; a local refresh rescans at once without a request to Anthropic or ChatGPT.

## R10: Width inside the unchanged window

- **Decision**: Sidebar 170 points plus a divider leaves about 549 points for the page in the 720-point window. Fixed-width controls of today fit (refresh field 80, segmented pickers, steppers). The OpenCode "Add directory" field changes from a fixed 320 points to `frame(minWidth: 200, maxWidth: 320)` so the field and its Add button never clip. The account editors are unchanged in width.
- **Rationale**: FR-005 keeps 720 by 560 points; clarification 3 fixes the sidebar width.

## R11: Adding a token-based account

- **Decision**: `NewAccountSheet` gets no directory field for token-based accounts; the field is set in the account's "Usage source" section after adding. The Claude subscription field in the sheet is relabeled "Claude Code directory".
- **Rationale**: The field is optional and empty by default (FR-007); the sheet stays short. FR-006 asks for the label wherever a Claude subscription's directory is entered.

## R12: Invented paths (FR-013, SC-005)

- **Decision**: Examples are `~/.claude-personal`, `~/profiles/acme/claude`, `~/.codex-lab`, `~/.local/share/opencode-lab`; test homes use `/Users/tester`. Keychain service names in `CredentialReaderTests` and `SecurityToolCredentialReaderTests` are recomputed (SHA-256 of the expanded path, first 8 hex digits, verified against today's `bf7c1594`):

  | Expanded path | Service name |
  |---|---|
  | `/Users/tester/.claude-personal` | `Claude Code-credentials-de0a6064` |
  | `/Users/tester/profiles/acme/claude` | `Claude Code-credentials-f15f9b72` |

- **Test home**: `CredentialReaderTests` and `SecurityToolCredentialReaderTests` use `Paths(home: "/Users/rhuss")` today; they move to `/Users/tester`, so the `~` spellings expand to the paths above and hash to these names.
- **Files with a `cc-deck` path today**: `Sources/AgentTacho/AccountSettingsView.swift:205`, `Sources/AgentTacho/SettingsView.swift:278`, `Tests/UsageCoreTests/ConfigurationTests.swift:9,80`, `AttributionTests.swift:65-68`, `CredentialReaderTests.swift:16-19`, `SecurityToolCredentialReaderTests.swift:23`. `docs` and `README.md` have none.

## R13: Screenshots and website (FR-015, constitution III and V)

- **Screenshots**: `scripts/screenshots/capture.sh` captures `menubar budget harnesses prices menubar-settings glance same-provider`. Its Settings steps press the "Menu Bar" tab and crop between `agenttacho.menubarPreview` and `agenttacho.menubarRunOutToggle`, then press "Prices" and crop the import sheet. No shot shows General or Accounts, so none is recaptured. The steps press elements by name; none of the six sidebar titles equals a pressed name, so the capture keeps working when Settings opens on General.
- **Website**: `src/components/agenttacho/Privacy.astro` says token counts "come from the files your agents write on this Mac" and names no directory; `src/data/features.ts` names no directory setting. Both stay true, so no site pull request. The README's "Agent session data" row and "How it works" bullets change in the app pull request (FR-014).
