# Contract: Harness Data Formats (read-only)

These are the formats AgentMeter reads, as observed on 2026-10-14 (Codex CLI 0.161.0 and the current OpenCode release). AgentMeter never writes to these files.

## Codex rollout files

Path: `<codexHome>/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl`. Each line is `{"timestamp": "<ISO-8601>", "type": "<type>", "payload": {...}}`.

| Line | Fields used |
|------|-------------|
| `type == "session_meta"` (first one only; forked files repeat the parent's) | `payload.id` (session id), `payload.cwd`, `payload.source.subagent.thread_spawn.parent_thread_id` or `payload.forked_from_id` (parent). `source.subagent` may also be a string such as `"review"`. |
| `type == "turn_context"` | `payload.model`, `payload.cwd` |
| `type == "event_msg"` and `payload.type == "token_count"` | `payload.info.total_token_usage.{input_tokens, cached_input_tokens, cache_write_input_tokens, output_tokens, reasoning_output_tokens, total_tokens}`, `payload.rate_limits.plan_type` |

Rules:
- Skip `token_count` lines whose `info` is null.
- Usage is the difference between consecutive `total_token_usage` values within a file. Lines whose total is unchanged add nothing, and an all-zero event keeps the previous total.
- Forked subagent files start with a copy of the parent's token events, stamped within about 1 s of the fork. These copies only set the starting total and add no usage (see the idea-inbox item `codex-fork-structural-marker`).
- `input_tokens` includes `cached_input_tokens` and `cache_write_input_tokens`.
- `output_tokens` includes `reasoning_output_tokens`.
- A session is a ChatGPT-plan session when any `rate_limits.plan_type` is a non-empty string.

## OpenCode database

Path: `<dataDir>/opencode.db` (SQLite in WAL mode). Open it read-only. When the database is in WAL mode and no `opencode.db-wal` file exists (OpenCode not running), open it with `immutable=1` so no side files are created. When a WAL file exists, open it plainly read-only, because the WAL holds writes not yet merged into the main file.

| Table | Columns used |
|-------|--------------|
| `message` | `id`, `session_id`, `time_updated` (ms since epoch), `data` (JSON) |
| `session` | `id`, `directory` |

Fields used from `message.data` JSON: `role`, `providerID`, `modelID`, `path.cwd`, `time.completed` (ms), `tokens.{input, output, reasoning, cache.read, cache.write}`. The session id comes from the `message.session_id` column.

Rules:
- Only assistant messages that have `time.completed` count.
- `tokens.reasoning` is separate from `tokens.output`.
- OpenCode's `cost` field is ignored.
