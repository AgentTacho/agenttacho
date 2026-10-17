# Brainstorm: Multi-Harness Usage (Codex and OpenCode)

**Date:** 2026-10-14
**Status:** active

## Problem Framing

AgentTacho only reads Claude Code session logs. The `harness` field stored on accounts is never read, and the scanner, parser, and attributor all assume Claude Code's directory layout and record format (idea-inbox item `harness-adapter-seam`).

Two more harnesses are in use on the same machine:

- **Codex** writes one JSONL file per session under `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. Each turn has a `token_count` event with input, cached input, output and reasoning tokens. The session metadata and turn context carry the model, the working directory and the model provider. Each `token_count` also carries a `rate_limits` snapshot (used percent, window length, reset time, `plan_type`) for ChatGPT-plan logins.
- **OpenCode** keeps its data in a SQLite database at `~/.local/share/opencode/opencode.db`. Every assistant message records `providerID` (for example `google-vertex`, `litellm`), `modelID`, tokens (input, output, reasoning, cache read and write), timestamps, and OpenCode's own cost estimate. Sessions record their directory.

Usage from these harnesses is invisible today, even when it draws from the same budget. For example, OpenCode on `google-vertex` most likely bills the same GCP project as Claude Code on Vertex, but it never counts toward the Vertex budget.

This brainstorm covers **part A**: counting Codex and OpenCode token usage. **Part B**, live Codex/ChatGPT plan limits, is a follow-up. It could come from the log snapshots and/or an OpenAI usage endpoint using the Codex credentials.

## Approaches Considered

### A: Harness adapter seam with shared attribution
Each harness gets an adapter that discovers its data (JSONL directories or a SQLite database) and reads it incrementally. Every adapter emits the same usage record: harness, provider hint, model, tokens, timestamp, project, and session. One attribution step maps provider hints to accounts.
- Pros: a new harness is just a new adapter. Budgets, breakdowns, notifications, and the price table work unchanged.
- Cons: the largest refactor, because today's scanner, parser, and attributor are Claude-Code-shaped.

### B: Separate pipelines per harness
Each harness reads and attributes on its own, then hands finished per-account records to the aggregator.
- Pros: no shared refactor.
- Cons: attribution rules and incremental-read logic are duplicated per harness, and every new harness repeats them.

### C: OpenCode session totals only
Read OpenCode `session` totals, and leave Codex for later.
- Pros: quick.
- Cons: no per-day or per-model precision, and no Codex.

## Decision

Approach A.

**Accounts.** An account represents a billing source, not a harness. One Vertex account collects usage from every harness that uses Vertex (Claude Code and OpenCode on `google-vertex`).

**Codex.** Codex usage is attributed by auth mode:
- API-key usage goes to a new OpenAI token-based provider, priced from the price table.
- ChatGPT-login usage goes to a Codex subscription account. It shows tokens only until part B adds plan limits.

**Pricing.** All cost comes from AgentTacho's own price table (built-in, overrides, LiteLLM import). OpenCode's recorded cost is ignored, so a shared budget is priced consistently.

## Key Requirements

Harness adapters:
- Supported harnesses are Claude Code (existing), Codex, and OpenCode.
- Each harness is discovered in its default location. Additional locations can be configured, as Claude Code log directories can today.
- Reading stays incremental. Only changed session files are re-read, and only new or changed database rows are read. A partially written last record is tolerated, and a database that is locked or mid-write must not fail the refresh.
- Every adapter produces the same usage record. The token categories are input, output, cache write, cache read, and reasoning. Reasoning is reported where the harness provides it, and its pricing follows the price table's rules for that model.
- Codex and OpenCode sessions resolve to git projects through their working directory, like Claude Code sessions. This feeds the existing per-project breakdown.

Attribution:
- An account is a billing source. Usage from any harness is attributed to the account whose provider matches the record's provider hint. Matching uses Claude Code markers, OpenCode `providerID`, and the Codex auth mode with its model provider.
- The breakdown shows the split by harness in addition to models and projects.
- Usage that matches no account goes to Unassigned, as today (for example OpenCode via `litellm`).

Codex:
- Usage from an API-key login is attributed to a token-based account with a new OpenAI provider and priced from the price table. OpenAI model prices come through the existing LiteLLM import or overrides.
- Usage from a ChatGPT-plan login is attributed to a Codex subscription account. In part A that account shows token counts and the per-model and per-day breakdown, but no percent, no bar entry, and no thresholds.

OpenCode:
- Each assistant message is one usage record, with `providerID` as the provider hint.
- OpenCode's own cost field is not used.

Out of scope (part A):
- Live Codex/ChatGPT plan utilization and its reset times, whether from the log `rate_limits` snapshots or an OpenAI endpoint (part B).
- Harnesses beyond Codex and OpenCode.
- Using OpenCode's cost values.

## Open Questions

- How can a Codex session's auth mode (ChatGPT login or API key) be told apart reliably from the log alone? `plan_type` in `rate_limits` versus null `rate_limits` is one candidate, and `session_meta` fields are another.
- Which `providerID` values map to which AgentTacho providers (`google-vertex` to Vertex, `anthropic` to a Claude subscription or the Anthropic API, `openai`), and what happens with custom providers?
- How do Codex `cached_input_tokens` and `reasoning_output_tokens` map onto AgentTacho's token categories? Is reasoning priced as output?
- Which is the safest way to read OpenCode's SQLite database while OpenCode writes to it? Options include read-only mode, WAL, and copying the file.
- Does the account model still need a per-account `harness` field, or does it become a list or go away? This touches spec 001 FR-017.
- For part B: is the Codex usage endpoint stable enough to call, and how do the log snapshots and the endpoint combine when both are available?
