# Data Model: Account Matching by Profile and Match Rules

## MatchPreset (new, UsageCore/Config/MatchRule.swift)

| Case | Harness | Stored value | Display name | Checks (caption) | Detection |
|---|---|---|---|---|---|
| `claudeCodeVertex` | Claude Code | `vertex` | Vertex | Request id starts with `req_vrtx_` | `requestIdPrefix("req_vrtx_")` |
| `codexAPIKey` | Codex | `apiKey` | API key | The session signs in with an API key | `providerHint(["apikey"])` |
| `openCodeVertex` | OpenCode | `vertex` | Vertex | Provider is `google-vertex` or `google-vertex-anthropic` | `providerHint([...])` |
| `openCodeOpenAI` | OpenCode | `openai` | OpenAI | Provider is `openai` | `providerHint(["openai"])` |

The stored value is unique per harness, not globally; decoding reads it together with the account's harness. `presets(for: Harness)` lists them in this order; the first is the default (spec 037 clarification).

## MatchField (new)

| Case | Stored | Label | Harnesses | Matches when |
|---|---|---|---|---|
| `model` | `model` | Model | all | `record.model` starts with the text |
| `requestId` | `requestId` | Request id | Claude Code | `record.requestId` starts with the text |
| `messageId` | `messageId` | Message id | Claude Code | `record.messageId` starts with the text |
| `anywhere` | `anywhere` | Anywhere in the record line | all, offered last | the raw line contains the text |

Comparison is case-sensitive (clarification). `fields(for: Harness)` lists them in this order.

## MatchRule (new)

```text
enum MatchRule { preset(MatchPreset), custom(field: MatchField, text: String), none }
```

- `default(for: Harness)` = `.preset(presets(for:).first!)`.
- `isOffered(for: Harness)`: a preset of that harness, a custom field of that harness, `.none` for Claude Code (for Codex and OpenCode `.none` exists only after a dropped rule, FR-015).
- `needsRawLine` is true for `custom(.anywhere, _)`.
- Validation: `custom` with blank text (after trimming) is refused (FR-011).

## TokenBasedSettings (changed)

| Field | Before | After |
|---|---|---|
| `provider: Provider` | decides harness, directory key, icon, rule | removed |
| `harness: Harness` | (only on `Account`, unused) | the account's one harness; changing it clears `enteredSessionDirectory` and `additionalSessionDirectories` and resets `matchRule` to the harness default |
| `matchRule: MatchRule` | (implicit through `provider`, plus `Account.customMarker`) | the account's rule |
| `enteredSessionDirectory` | Claude Code directory (Vertex) or Codex home (OpenAI) | Claude Code directory (harness Claude Code), Codex home (Codex), always nil for OpenCode |
| `additionalSessionDirectories` | as spec 035 | as spec 035, empty for OpenCode |

## Account (changed)

- `harness` becomes computed: `.claudeCode` for a Claude subscription, `.codex` for a Codex subscription, `settings.harness` for token-based. The `harness:` init parameter is removed.
- `customMarker` stays for subscription accounts; for token-based accounts it is always nil (migrated into `matchRule`).
- `agentDirectory(for:)` uses `settings.harness` and `Paths.defaultClaudeDirectory` / `defaultCodexHome`; nil for OpenCode.
- `AccountKind.sessionHarness` returns `settings.harness` for token-based.

## SessionProfile (new, UsageCore/Logs/SessionProfile.swift)

```text
struct Candidates { searchStrings: [(bytes, canonical)]; key: String }
enum Detection { notShape, named(String), none, ambiguous }
```

- Built per refresh from the main and additional Claude Code directories (literal and wildcard matches), each as `~`-expanded standardized path and symlink-resolved path, followed by `/projects/`.
- `SessionProfile.detect(line:candidates:) -> Detection` returns only the canonical directory, never other text (FR-004).

## FileIndexEntry (changed, LogIndex.swift)

| Field | Meaning |
|---|---|
| `profile: String?` | canonical directory in effect at the end of the last read; carried to appended lines |
| `sawShapeLine: Bool` | any shape line seen (named, none or ambiguous) |

The index stores `profileCandidatesKey: String` (each canonical directory with its claimant account ids and rank, sorted). Re-read rules: see plan "Re-read rules in LogIndex".

`LogIndexStats` gains `filesWithProfile: Int` and `filesWithoutProfile: Int` (files read in this refresh whose profile at the end of the read is named, or nil), for the FR-012 log line.

## Attributor (changed)

- `Candidate` gains `harness` (token-based) and `rule: MatchRule?` (token-based) next to `customMarker` (subscription), and `profileDirectory` (canonical main directory of Claude subscriptions and token-based Claude Code accounts).
- `accountId(for:rawLine:fileConfigDirectory:profileDirectory:)`: profile step for Claude Code records, then the rule step (FR-003).
- `fingerprint` includes harness and rule; `needsRawLine` replaces `usesCustomMarkers`.

## MatchOverlap (new, UsageCore/Config/MatchOverlap.swift)

```text
struct MatchOverlap { accountId: String; otherNames: [String] }
func Configuration.matchOverlaps(paths:) -> [MatchOverlap]
```

Groups token-based accounts by (harness, rule, canonical main directory for Claude Code); one entry per member of a group of two or more, in account order.

## State transitions

- **Harness change** (Settings): directory and additional directories clear, rule resets to the default preset, icon follows the preset unless the user chose one (new account sheet only).
- **Rule change**: no directory change; attribution fingerprint changes, the index re-attributes from the next refresh.
- **Load of a legacy token account**: `provider` (default `vertex`) and `customMarker` become harness and rule; one diagnostic log line per migrated account.
