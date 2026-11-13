# Brainstorm: Claude Code Auto-mode classifier usage in AgentTacho

**Date:** 2026-11-12  
**Status:** active

## Problem framing

AgentTacho's GLM and DeepSeek token totals can be lower than the EnMaaS backend's usage report. A scaling factor was considered, but the experiments found a concrete class of client-side calls that can be omitted from Claude Code's usual usage surfaces: Auto-mode tool-approval classifier requests.

The goal is to determine whether AgentTacho can account for those requests accurately, without applying a guessed multiplier or double-counting usage already present in Claude's session records.

## Findings

### What is established

- A small Claude Code 2.1.319 GLM Auto-mode probe made three main API requests and two successful `side_query` classifier requests. The debug log showed the two classifier calls, but the transcript, standard OTel API request events, and final cumulative OTel token metrics only contained the three main requests.
- In a subsequent small GLM Auto-mode probe, setting `AUTOMODE_DECISION_LOG=1` caused Claude Code to write `.automode_decisions.jsonl` in the run's working directory. The installed client is 2.1.319.
- That file reported usage for two successful classifier decisions. Main requests totaled 80,168 tokens. Classifier usage totaled 69,624 tokens: 969 input, 68,608 cache-read, and 47 output tokens. The combined client-reported total was 149,792 tokens across five requests.
- The classifier calls were for `rits/zai-org/glm-5-3[1m]`. Their usage was absent from the usual transcript and OTel totals. This probe's classifier share was about 46.5 percent of the combined count. It is a task-specific observation, not a correction factor.
- AgentTacho's GLM and DeepSeek group increased by exactly the main-request token total in the captured probes. It currently does not ingest `.automode_decisions.jsonl`, so it does not include the classifier usage.
- In a separate small Auto-mode probe without the native usage diagnostic, the Slack backend counters rose by five total requests and five free-model requests, matching three main requests plus two classifiers. This confirmed the request-count mechanism for that probe.
- For the latest native-diagnostic probe, the expected Slack counter reading is 4,756 total requests and 4,091 free-model requests, from a provisional baseline of 4,751 and 4,086. The after reading is still pending. Its 149,792 token increase may not change the bot's rounded `470M` display.
- A larger GLM Auto-mode run had 33 locally recorded main requests but the backend counters rose by 66. It had 19 classifier verdicts, which do not account for all 33 extra requests. No debug log was collected for that run, so its remaining excess is unresolved.

### Scope and caveats

- All controlled model experiments were run by the user. GLM was tested; DeepSeek and Codex were not.
- The Slack bot reports EnMaaS usage across models and rounds its token total. It exposes free-model request count separately, but not a free-model token subtotal. AgentTacho's GLM and DeepSeek group is a narrower scope. Exact monthly token equality cannot be inferred from the screenshots.
- The Slack billing period is shown in US Pacific time; AgentTacho's monthly usage uses Europe/Berlin boundaries. Comparisons need aligned time windows.
- The native decision log is an internal, undocumented, version-dependent diagnostic. There is no dedicated Claude Code settings key, though the environment variable can be placed in a Claude `settings.json` `env` block. Enabling it makes the file; it does not make AgentTacho read it.
- The diagnostic writes in the Claude session's working directory. The rows inspected do not provide an obvious stable session or provider request ID for correlating classifier usage with a specific Claude transcript. Attribution, duplicate handling, file discovery, privacy, and upgrades need design work.
- No single multiplier is supported by these observations. The classifier count and cached context vary by task, and the larger run remains unexplained.

### Current AgentTacho ingestion boundary

- `LogDirectoryScanner` enumerates JSONL files below configured Claude `projects/` directories and skips hidden files.
- `SessionRecordParser` accepts Claude `assistant` records with a `message.usage` object and a message ID or request ID.
- `.automode_decisions.jsonl` is hidden and has a different record schema. It is written to Claude's working directory, which may not be inside the configured Claude `projects/` tree. It is therefore outside both the current discovery and parsing paths.
- AgentTacho reads agent files and must not modify them. It must not silently set `AUTOMODE_DECISION_LOG` or edit Claude settings. Any enablement guidance should be explicit and user-controlled.

## Handoff for a future feature spec

The investigation is ready to hand off as a feature question: should AgentTacho optionally ingest Claude's existing Auto-mode decision log, and what is the safe way to discover and attribute it?

The spec should decide:

- Discovery scope: derive candidate working directories from already parsed Claude session records, support an explicit user-configured directory, or use another bounded approach. Do not scan the whole filesystem.
- Enablement: consume the file if present and explain how to enable it manually, or add an explicit AgentTacho option that only controls its own reader. AgentTacho must not edit Claude's settings or write into Claude's directories.
- Attribution: the inspected decision rows have timestamps and usage details but no obvious stable Claude session ID or provider request ID. Decide how records map to configured accounts and concurrent sessions sharing a working directory. If safe attribution is not possible, leave the data out rather than assigning it speculatively.
- Deduplication: the file is append-only in the observed client. Repeated scans, partial trailing lines, file truncation/rotation, duplicate rows, and multiple sessions sharing the file need defined behavior.
- Data semantics: map input, cache-read, cache-creation, and output counters into the existing usage model without double-counting main requests. Keep records with missing or zero usage from creating misleading model/account rows.
- Compatibility and privacy: treat the format as internal and version-dependent; do not collect full request or response bodies. Decide whether to warn when the client version or row shape is unknown.
- Validation: use sanitized captured fixtures and tests for parsing, attribution, duplicate scans, partial writes, missing counters, and mixed Claude session plus classifier records. No product tests have been added for this brainstorm.

### Codex comparison, source-based only

Current Codex source has an `auto_review` Guardian reviewer path that can create auxiliary model requests. AgentTacho's Codex source scans rollout JSONL files and parses cumulative `token_count` events, so a Guardian rollout could already be counted if it is present in a configured Codex home and contains those events. This was not tested in the user's Codex setup. Do not treat Codex support as confirmed by the Claude experiment or assume the reviewer used the same provider/account as the main model.

## Approaches to consider

### A. Read Claude's native Auto-mode decision log

Teach AgentTacho to discover and parse `.automode_decisions.jsonl`, then include usage-bearing classifier records in totals.

- Pros: uses counters emitted by Claude Code; avoids capturing full request bodies or routing traffic through a proxy.
- Questions: how to enable the diagnostic for normal sessions, discover working directories, correlate rows to sessions, avoid counting a shared or stale file twice, handle missing usage fields, and make behavior robust to Claude Code updates.
- Risk: an internal log format can change without notice. Missing or disabled logs would continue to omit usage.

### B. Continue external reconciliation only

Keep AgentTacho's current ingestion unchanged and use the native log as an experiment/audit source when investigating discrepancies.

- Pros: no product change and no new parsing dependency on an internal format.
- Cons: displayed totals will continue to exclude these calls; manual collection is not a durable accounting solution.

### C. Capture all provider requests through a local relay

Route requests through an instrumented local proxy that records response usage, including auxiliary calls.

- Pros: could expose usage for call types not represented in Claude's local logs.
- Cons: changes the network path and credentials handling, adds setup and failure modes, and may not see calls that bypass the relay. More invasive than the native diagnostic for the confirmed classifier case.

## Current direction

Use approach A as the leading implementation candidate, subject to a design that proves safe discovery and deduplication. Keep approach B as the fallback if stable attribution cannot be achieved. Do not add a global scaling factor. Do not begin implementation until the issue scope and requirements are accepted.

Before implementation, use a later controlled run with `AUTOMODE_DECISION_LOG=1` to confirm the backend refresh for the native-diagnostic probe. If more free-model usage is available, repeat the larger workload with the diagnostic enabled to determine how much of its 33-request excess is classifier traffic. No further model usage is needed to document the finding.

## Open questions

- Can AgentTacho reliably discover the working directory for each Claude session and read only the corresponding decision log?
- Can decision rows be attributed and deduplicated across concurrent sessions sharing a working directory, file rotation, or repeated scans?
- Should the diagnostic be enabled only by an explicit user option, or should AgentTacho detect an existing file and consume it without changing Claude settings?
- What should the UI or logs say when classifier usage is unavailable, partial, or emitted by a Claude version with a changed schema?
- Is internal-format support acceptable with a pinned parser, version checks, and tests based on captured fixtures?
- Does a repeated larger Auto-mode run explain the remaining request excess, or is another call source involved?
- Can the backend provide per-model, unrounded token data or request IDs to validate exact reconciliation?
- Does the latest Slack refresh show the expected five request increase for the native-diagnostic run? Its after reading remains blank in the capture notes as of this brainstorm update.

## Slack message draft for later

Do not send yet. Once the user has the latest backend refresh, review the values and share this in the relevant EnMaaS support thread, editing the wording to fit the audience:

> We investigated the GLM usage discrepancy with controlled Claude Code runs. In Auto mode, one small probe showed three main requests plus two successful classifier requests. Claude's usual transcript and OTel usage totals included the three main requests but omitted the classifier usage. A follow-up on Claude Code 2.1.319 enabled its internal `AUTOMODE_DECISION_LOG` diagnostic and captured counters for two classifier calls: 69,624 tokens combined (mostly cache reads), in addition to 80,168 tokens from the three main calls. In a separate small probe, the backend request counters increased by five, matching the three main calls plus two classifiers. The backend token display is rounded, so exact token reconciliation is still pending. A larger run had an additional request excess that these findings do not yet explain. We have not applied a scaling factor. We are checking the latest backend refresh and have tested GLM only so far.

Keep the message factual and update it with the pending backend reading before sharing. Do not share raw logs, credentials, project identifiers, or local paths.

## Experiment artifacts

Detailed local captures and machine-readable reconciliations are under:

`/Users/rhuss/Work/experiments/agenttacho-token-audit/`

In particular, the latest native diagnostic capture is `runs/20261112T173436Z-glm-65866604/`. These files contain local session material and should remain private; share only reviewed aggregate results.

---

## Revisit: 2026-11-13

### Updated Problem Framing

The feature is for all AgentTacho users, opt-in. Enabling and reading are split between two tools:

- **aprofile enables.** aprofile brainstorm 007 (Profile Features, `~/Development/ai/aprofile/brainstorm/007-profile-features.md`) adds an `automode-decision-log` feature: `aprofile features claude/<name>` places `AUTOMODE_DECISION_LOG=1` in the profile's `settings.json` env block on `sync`, `show` reports it, disabling removes it. It names AgentTacho as the consumer.
- **AgentTacho only reads.** It consumes the decision log when present and has no switch of its own. Without the file, nothing changes. AgentTacho never edits Claude settings (constitution III).
- Users without aprofile set the variable by hand (`settings.json` `env` or shell). The README documents both paths.

Success: with the log enabled, AgentTacho's totals for an account include the classifier usage of its sessions, with no scaling factor and no double counting, and with no measurable slowdown of a refresh.

Anti-goals: AgentTacho writing Claude settings or anything into working directories; a filesystem scan; assigning rows to an account by guess; a global multiplier.

Rows observed in the 2.1.319 log carry `ts` (epoch ms), `tool`, `decision`, `classifierModel`, `inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`, `costUSD`, `durationMs` and classifier routing fields (`stage`, `classifierSource`, `classifierSite`, ...). No session ID, no request ID. About 550 bytes per row.

### New Approaches Considered

The earlier B (manual reconciliation only) no longer fits a feature for all users; C (local relay) changes the network path and credential handling and stays dropped.

#### A: Classifier rows become ordinary usage records (chosen)
Each usage-bearing row becomes a usage record with its model, timestamp, four token counters, and the owning session's project and account. Totals, limits, groups, the project breakdown and pricing treat it like any other record. Only the diagnostic log distinguishes it (counts of classifier rows read, assigned, unassigned).
- Pros: smallest change, no new UI, reuses specs 037 and 039 machinery.
- Cons: a jump in totals after enabling the log is explained only by the diagnostic log.

#### B: A plus a visible classifier share
Same records, tagged, with a line such as "incl. 69.6K Auto-mode classifier" in the dropdown's account details.
- Pros: the difference against a backend report explains itself.
- Cons: new UI with shots, demo scenario and website copy (constitution V) for a feature few users enable; wording for absent or partial logs.

#### Attribution variants
- **Time-based (chosen):** a row goes to the session in the same working directory whose time span covers its `ts`; overlapping sessions on different accounts leave the row unassigned.
- **Directory-based:** all rows of a directory go to one account, only if a single account ever used that directory. Simpler, loses more (switching profiles in one repo).

### Updated Decision

Approach A with time-based attribution. Records are tagged as classifier usage internally from the start, so B's visible line can follow later without a data model change.

### Key Requirements

- **Discovery:** look only for `<cwd>/.automode_decisions.jsonl`, where `cwd` comes from Claude session records already parsed and the session falls inside the current usage window. No filesystem scan, no extra directory setting. *(My proposal: every classifier call happens inside a known session, so its log sits in a known working directory.)*
- **Incremental reading:** reuse `LogIndex`'s size/date check and byte offset; read only appended bytes; a file shorter than its parsed offset is read again from the start (the existing rule for replaced files); an incomplete trailing line waits for the next refresh.
- **Attribution:** time-based as above, through the session's resolved account (spec 037 profile and match rules). Account match rules that inspect record lines (request ID prefixes and similar) do not apply to classifier rows; the account comes from the session. Ambiguous rows stay unassigned and are counted in the diagnostic log.
- **Data semantics:** map `inputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`, `outputTokens` to the existing counters. Skip rows with missing counters or all zero. Main-request records are untouched, so nothing is counted twice.
- **Privacy:** read only the timestamp, model and counter fields; never keep `tool` input or other row content beyond what attribution needs. Update the README's "Security and privacy" section and the website privacy section to say AgentTacho reads this file in session working directories. *(My call: not strictly a credentials or network change, but it is a new file read outside the agents' config directories.)*
- **Performance:** one size/date check per working directory per refresh, done off the sequential merge phase so a slow or unmounted volume cannot stall a refresh. *(My call, from the performance discussion.)*
- **Compatibility:** treat the format as internal and version-dependent; parser tested against sanitized captured fixtures; an unknown row shape is skipped and noted in the diagnostic log, not shown as an error.
- **Docs:** README section on enabling the log (aprofile `features`, or `settings.json` `env` by hand) and on adding `.automode_decisions.jsonl` to a global gitignore (`core.excludesFile`), since the file lands untracked in every repository the profile works in. *(My call: documentation, no code in either tool.)*
- **Screenshots and website:** no visible UI change (approach A changes totals only); website privacy copy changes as above.
- **Out of scope:** enabling the log from AgentTacho, the visible classifier line (B), Codex Guardian usage, a relay, any scaling factor.

### Open Threads

- Session time span for attribution: first to last record, and how much grace margin around it (a classifier call could fall just outside the last recorded assistant message).
- Does `classifierModel` (`rits/zai-org/glm-5-3[1m]`) match the model string in the main-request records, so price lookup and per-model rows line up?
- Retention: when a working directory or worktree is deleted, do already ingested classifier records stay, as for deleted session files?
- Two identical rows in one file: each line counts as its own call (the file offset identifies a row) unless evidence shows the client writes duplicates.
- Experimental threads unchanged: the pending Slack "after" reading for the native-diagnostic probe, and the larger run's unexplained request excess (repeat with the log enabled).
