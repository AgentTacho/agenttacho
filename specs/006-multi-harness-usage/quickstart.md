# Quickstart: Multi-Harness Usage

## Automated validation

```bash
make test
```

| Suite | Proves |
|-------|--------|
| `CodexSessionParserTests` (new) | The running-total delta rules: duplicate, null and zero events add nothing. The input is split into input, cache read and cache write. Reasoning stays inside output. The plan marker is detected. Subagent parent ids are read. A truncated last line is tolerated. (FR-008, FR-008a, FR-014) |
| `CodexSessionSourceTests` (new) | Default and extra homes are scanned, and a file reachable twice is counted once. Unchanged files are not re-parsed. A late plan marker re-attributes the session. A subagent inherits its parent's mode. An unreadable extra home becomes an issue without failing the read. (FR-002 to FR-006, FR-014) |
| `OpenCodeSourceTests` (new) | Run against a temporary SQLite fixture. Only completed assistant messages count. An updated message replaces its record. The watermark limits rows to new ones. Reasoning is added to output. A locked database returns the previous records flagged stale. A missing database is skipped silently. (FR-004, FR-005, FR-008b, FR-009) |
| `AttributionTests` | OpenCode `google-vertex` goes to Vertex. Codex `apikey` and OpenCode `openai` go to OpenAI. Codex `chatgpt` goes to the Codex subscription account, with the Codex-home tie-breaker. Custom markers work across harnesses. Unknown providers go to Unassigned. (FR-011 to FR-015) |
| `PriceTableTests` | `claude-opus-4-6@default` prices like `claude-opus-4-6`. (FR-020a) |
| `AggregatorTests` | `perHarness` split. `planAccounts` cover the weekly window with tokens only. Entries are marked stale for stale harnesses. (FR-017, FR-021, research R7) |
| `ConfigurationTests` | `codexSubscription` and `openai` decode and round-trip. Old files load unchanged. A duplicate Codex home is invalid. (FR-016 to FR-018) |
| `RefreshCoordinatorTests` | A `recordBatch` issue becomes a source error, and a stale harness does not mark other harnesses' entries stale. (FR-005, FR-006, SC-004) |

## Manual validation

1. `make run`, then open the dropdown. Expected: if OpenCode on `google-vertex` was used this week or month, the Vertex budget includes it. Details, then Harnesses, lists Claude Code and OpenCode.
2. In Settings, choose Add → Subscription account with Platform "ChatGPT (Codex)". Expected: after a refresh it lists Codex tokens for the week. It has no percent and no bar entry.
3. Open the diagnostic log (`~/Library/Logs/agenttacho/usage.log`). Expected: `codex` and `opencode` lines per refresh with record counts.
4. Optional: start an OpenCode session while refreshing repeatedly. Expected: no refresh errors for Claude Code entries. At worst a stale OpenCode source error, which clears on the next refresh.
