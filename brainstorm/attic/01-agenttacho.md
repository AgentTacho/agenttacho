# Brainstorm: AgentTacho

**Date:** 2026-10-13
**Status:** active

## Problem Framing

Agent harnesses (Claude Code today, others later) run against several accounts with different pricing models. A subscription account has fixed limits set by the provider (Anthropic's 5-hour and 7-day windows). A token-based account (Claude Code via Google Vertex) bills per token, and the only limit is the one the user sets for themselves. Soon the same Vertex account will carry more models, including OpenAI models, so several harness/model combinations will draw from one shared budget.

There is no single place to see "how much of each limit have I used this week". The user wants a macOS menu bar item that shows a compact percent per account in the bar, with details in the dropdown, refreshed every 5 minutes by default.

Current accounts (2), expected to grow to 5 to 10:

- Claude Code on a Claude Max subscription
- Claude Code via Google Vertex (token-based, more models coming)

## Approaches Considered

### A: Single menu bar app with pluggable usage sources (chosen)
One native app scans session logs, calls the Anthropic usage API, computes budgets, and renders bar and dropdown. Each account type is an internal "usage source" (subscription-API source, token-log source). New harnesses are added as new sources.
- Pros: one thing to install and run, no moving parts, settings and display stay in sync, simplest for the current 2 accounts.
- Cons: harness-specific parsing lives inside a GUI app, so reusing the numbers elsewhere (statusline, scripts) needs an export feature later.

### B: Usage engine plus thin menu bar display
A separate CLI or daemon reads logs, calls APIs, applies budgets, and writes a usage snapshot file. The menu bar app only reads and displays the snapshot and edits the config.
- Pros: numbers reusable from terminal, statusline, or scripts. Engine testable without UI. Parsers evolve independently.
- Cons: two components to build, version, and keep running. More moving parts than a personal tool with 2 accounts needs.

### C: Wrap an existing usage tool
Lean on a tool like ccusage for log parsing and pricing, and build only the menu bar, budget groups, and subscription API fetch on top.
- Pros: fastest start, price table maintained upstream.
- Cons: upstream owns the data model and harness coverage. Vertex detection, budget groups, and multi-harness support are exactly where the tool would need to be fought. Adds a runtime dependency to a menu bar app.

## Decision

Approach A. Design the usage-source abstraction cleanly enough that B's engine could be split out later if the numbers are ever needed outside the app.

Decisions made during the session:

- **Subscription percent** means Anthropic's real limit. The app fetches it from Anthropic's usage API using the OAuth credentials Claude Code already stores locally. This relaxes the original "local files only" constraint for subscription accounts.
- **Token-based cost** is computed from local session logs with a built-in per-model price table (input, output, cache tokens), overridable and extendable in settings. Budget and display in USD, since that is how Vertex bills.
- **Account attribution** is auto-detected from markers in the session log content, not from which directory a log lives in.
- **Week window** for self-set budgets aligns with the subscription account's 7-day reset timestamp, so all accounts reset together.
- **Menu bar text** shows a short user-defined label (1 to 3 characters) plus percent for each account or budget group the user chooses to display. Others appear only in the dropdown.
- **Budget groups** are modeled from the start: every budget belongs to a group, a group has 1..n accounts. Version one only lets the user assign accounts to a group in settings.

## Key Requirements

Menu bar and display:
- Bar item shows label + percent for user-selected accounts or groups. Color or marker by threshold.
- Dropdown per account or group: used vs budget with reset time (subscription: 5-hour and 7-day utilization with reset times), per-model breakdown (tokens and cost), daily trend for the current week.
- Refresh interval default 5 minutes, configurable in settings.
- macOS notifications at configurable percent thresholds (e.g. 80%, 100%), fired once per window.

Accounts and sources:
- Two source types in version one: subscription (Anthropic usage API) and token-log (local session logs).
- Harness coverage in version one: Claude Code only. The account model must allow adding Codex CLI and other harnesses as further sources without a data-model change.
- Vertex usage for non-Claude models counts once those harnesses write local logs the app can parse.
- Account detection from log content. Unknown or ambiguous sessions must be surfaced, not silently dropped.
- Built-in price table, overridable per model in settings. Unknown models flagged as unpriced.

Budgets and windows:
- Self-set weekly USD budget per group. Subscription accounts carry no self-set budget.
- Week boundary follows the subscription's 7-day reset. If no subscription account exists or the API is unreachable, fall back to a configurable weekday.
- Scale: 5 to 10 accounts.

Configuration:
- Config lives in a plain local file, editable through a settings window inside the app.

Out of scope for version one:
- Harnesses other than Claude Code.
- Per-account sub-budgets inside a group.
- History beyond the current week.
- Export, statusline integration, or any API for other tools.

## Open Questions

- Which markers in Claude Code session logs reliably distinguish Vertex traffic from direct Anthropic traffic? Model id format (`@` versioning on Vertex) is one candidate. The spec phase must verify against real logs, and define behavior when no marker matches.
- Which Anthropic endpoint exposes 5-hour and 7-day utilization for a subscription, how is it authenticated with the locally stored Claude Code OAuth credentials, and how often may it be polled?
- Where do session logs live when several Claude Code config directories exist (default `~/.claude` plus cc-deck profile directories)? Should discovery be automatic, configured, or both?
- How is the budget group reset handled when the aligned subscription has not yet reported a reset timestamp (first launch, offline)?
- Which cache-token categories does Vertex bill differently from direct Anthropic, and does the built-in price table need a per-provider variant per model?
- Should the bar percent for a subscription be the 7-day window, the 5-hour window, or the higher of both?
- Notification semantics: once per threshold per window, or re-notify after a configurable quiet period?
