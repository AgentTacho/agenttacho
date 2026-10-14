# Data Model: Multi-Harness Usage

Changes relative to the data models of specs 001, 003, and 004.

## Harness (changed)

`claudeCode` (existing), `codex`, `openCode`. Display names are "Claude Code", "Codex", and "OpenCode".

## Provider (changed)

| Case | Default icon | Built-in matches |
|------|--------------|------------------|
| vertex | `brands:google` | Claude Code `req_vrtx_` request ids. OpenCode `providerID` `google-vertex` or `google-vertex-anthropic`. |
| openai (**new**) | `brands:openai` | Codex sessions without a plan marker (API key). OpenCode `providerID` `openai`. |

## AccountKind (changed)

| Case | JSON `type` | Notes |
|------|-------------|-------|
| subscription | `subscription` | unchanged (Anthropic plans) |
| tokenBased | `tokenBased` | provider may now be `openai` |
| codexSubscription (**new**) | `codexSubscription` | `CodexSubscriptionSettings { codexHome: String = "~/.codex" }`. Token-only: no shown-in-bar setting, no thresholds, no budget. Default icon `brands:openai`. |

## Configuration (changed)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| codexHomes | [String] | [] | **new**, optional key. Extra Codex homes, read in addition to `~/.codex`. |
| openCodeDirectories | [String] | [] | **new**, optional key. Extra OpenCode data directories, read in addition to `~/.local/share/opencode`. |
| codexSubscriptionAccounts | computed | | accounts of kind `.codexSubscription` |

Validation (new): two Codex subscription accounts with the same Codex home make the configuration invalid.

## RawUsageRecord / UsageRecord (changed)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| harness | Harness | `.claudeCode` | **new** |
| providerHint | String? | nil | **new** (raw only). OpenCode `providerID`; Codex `"chatgpt"` or `"apikey"`. |
| reasoningTokens | Int | 0 | **new**. Informational; already included in `outputTokens`. |
| sessionId | String? | nil | **new** (raw only) |
| outputTokens | Int | | Always the priced output, including reasoning (FR-008, FR-008b). |
| cacheWrite5mTokens | Int | | Codex and OpenCode cache writes land here (FR-020b). |

Message id schemes: Claude Code is unchanged; Codex is `codex:<sessionId>:<running total_tokens>`; OpenCode is the message id.

## CodexSession (new, internal to the Codex source)

| Field | Type |
|-------|------|
| sessionId | String |
| parentSessionId | String? |
| cwd | String? |
| planMarker | Bool |
| metaLine | String (first `session_meta` line, for custom markers) |
| records | [CodexRecord] (`raw: RawUsageRecord`, `line: String`) |

Auth mode resolution, in order: the session's own `planMarker`; else the resolved mode of its parent, when the parent is known; else API key.

## RecordBatch / SourceOutput (changed)

`SourceOutput.recordBatch(RecordBatch)` is **new**. `RecordBatch { records: [UsageRecord], issues: [String], staleHarnesses: Set<Harness> }`.

## Snapshot (changed)

| Type | Field | Change |
|------|-------|--------|
| UsageSnapshot | planAccounts: [String: TokenAccountEntry] | **new**. One entry per Codex subscription account: weekly window, tokens only. |
| UsageBreakdown | perHarness: [HarnessUsage] | **new** |
| HarnessUsage | harness, totalTokens, costUSD?, priced | **new** |
| ModelUsage | reasoningTokens: Int | **new** |
| GroupEntry / TokenAccountEntry | stale | Also set when the entry contains records from a stale harness (research R7). |

## Pricing (changed)

`PriceTable.canonicalModel` now strips any trailing `@<suffix>`. Reasoning is never priced separately, because it is part of output.
