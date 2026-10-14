# Idea Inbox

Ideas captured from code reviews for future brainstorming.

### diagnostic-log-size-bound

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: Log rotation keeps the live file plus one older generation, so the on-disk total is 10 MB while FR-036 names 5 MB.

> Whether the cap applies to the live file or the total is a spec ambiguity worth settling.

### threshold-baseline-after-reset

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: After a window reset the tracker records a baseline instead of treating the previous value as 0, so a window that starts above a threshold never notifies.

> FR-028 mandates the baseline only for the first refresh after launch; the stricter reading would notify. A spec note would remove the ambiguity.

### scan-credential-directories

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: A subscription account's credential directory is not scanned unless also listed under log directories, so the directory tie-breaker needs the path in two settings.

> Unioning the credential directories into the scan set would remove the duplication.

### log-config-reloads

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: A successful reload of a hand-edited configuration leaves no trace in the diagnostic log.

> US3 scenario 4 promises pickup; the log cannot confirm it happened.

### credential-error-allow-list

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: The credential-read error path falls back to String(describing:); the no-token guarantee holds by Foundation's error formatting rather than by construction.

> An allow-list mapping plus a sentinel test would make FR-011a hold by design.

### keychain-presence-check

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: The first-launch presence check reads the full secret item to answer yes or no.

> A kSecReturnAttributes query answers presence without materializing the token.

### parse-off-cooperative-pool

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: The directory scan and the parallel parse run synchronously inside an actor on the cooperative thread pool.

> No deadlock today; a dedicated serial queue bridged with a continuation would keep the pool free when more sources arrive.

### testable-bar-label

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: BarLabelBuilder implements FR-002, FR-003 and FR-005 as pure functions but lives in the untested app target.

> Moving it (minus the attributed-string rendering) into UsageCore would let the threshold-glyph and ordering rules be unit tested.

### single-window-reset-mechanism

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: The log index restarts itself on an earlier window start, and the coordinator's resetForEarlierWindow path does the same thing a second way; only the coordinator path logs it.

> One mechanism should remain, and the index should report the restart so the diagnostic log explains the full re-read.

### imported-prices-in-refresh-context

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 002-price-import
- **Summary**: Imported prices reach SessionLogSource through an injected ImportedPriceStore instead of RefreshContext, so overrides and imports for one refresh are read at different moments from different owners.

> Carrying ImportedPrices in RefreshContext, filled by the coordinator, would match how configuration and overrides flow and let tests inject imports without a file.

### reprice-for-override-edits

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 002-price-import
- **Summary**: Manual override edits still trigger a full refresh that calls the usage endpoint, while imports use the new reprice path.

> Detecting price-only configuration changes in saveConfiguration and calling requestReprice would keep rapid override edits off the rate-limited endpoint.

### price-import-service-in-core

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 002-price-import
- **Summary**: Apply, remove and export orchestration (re-stamping importedAt, save failure handling, log lines, reprice trigger) lives in the untested app target.

> A small UsageCore service called by AppModel would make FR-021, FR-026, FR-033 and FR-023a testable end to end.

### imported-price-sanity-ceiling

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 002-price-import
- **Summary**: LiteLLM prices are bounded below (non-negative) but not above; the preview is the only guard against an upstream mistake.

> Flagging values above a plausible ceiling (for example 1000 USD per million tokens) in the preview would make such mistakes stand out.

### decimal-precision-on-reload

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 002-price-import
- **Summary**: PriceEntry decodes prices through Double, so a CSV value with more than about 15 significant digits is applied with one value now and a slightly different one after a relaunch.

> Rounding CSV values to 6 decimals like provider prices (FR-008), or decoding Decimal from the JSON text, would keep stored and in-memory values identical.

### single-window-resolver-source

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 003-monthly-budget-period
- **Summary**: The coordinator resolves the weekly and collection windows with its injected WindowResolver, while the aggregator creates its own resolver for the monthly window.

> Passing the monthly window into `aggregate` would keep one source of truth if the resolver ever becomes configurable.

### window-kind-mapping-layer

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 003-monthly-budget-period
- **Summary**: `BudgetPeriod.windowKind` makes the configuration model depend on the notification tracker's `WindowKind`.

> An extension in ThresholdTracker.swift would keep the config layer free of one consumer's keying scheme.

### stale-entry-period-mismatch

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 003-monthly-budget-period
- **Summary**: While the record source keeps failing, carried-over group entries keep their old period, so a group just switched to monthly shows weekly wording until the source recovers.

> Dropping or relabelling carried-over entries whose period differs from the configuration would keep the display consistent with FR-014.

### injectable-calendar-provider

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 003-monthly-budget-period
- **Summary**: The time zone path depends on the default `Calendar.autoupdatingCurrent` stored as a `let`, so no test can change the zone between two refreshes.

> A calendar provider read on each refresh would make a time zone move testable end to end in the coordinator.

### log-writes-through-diagnosticlog

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 004-icon-labels-standalone-budgets
- **Summary**: The refresh log now writes full user-chosen names; DiagnosticLog.append escapes control characters, which is what keeps log forging out.

> Keep every log write going through DiagnosticLog.append so the mitigation is not lost.

### cache-picker-icon-images

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 004-icon-labels-standalone-budgets
- **Summary**: pickerText builds a fresh NSImage per picker item on every settings re-render.

> A small main-actor cache keyed by icon and size would avoid repeated drawing and menu rebuilds.

### budget-group-stores-budgetsettings

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 004-icon-labels-standalone-budgets
- **Summary**: BudgetGroup mirrors BudgetSettings field by field through a computed bridge.

> Storing BudgetSettings directly (flat JSON keys kept in the coder) would stop new budget fields from being silently dropped for groups.

### move-ui-defaults-into-usagecore

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 004-icon-labels-standalone-budgets
- **Summary**: The budget summary string and the FR-013 creation defaults live in the untested app target.

> Moving them into UsageCore helpers would make the US2 text and FR-013 defaults testable.

### explicit-group-management

- **Source**: walkthrough
- **Date**: 2026-10-14
- **Reference**: 004-icon-labels-standalone-budgets
- **Summary**: Groups are created only inside the new-account sheet and deleted implicitly when their last member leaves, so after moving the only member to an own budget no group is left to attach accounts to.

> Manage groups explicitly in settings with Add and Remove buttons, allow empty groups (shown without a percent or hidden from the bar), and stop the implicit creation and deletion in FR-014 and spec 001 FR-019. Removing a group with members would ask where the members go (own budget or another group).

### sqlite-defensive-open

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 006-multi-harness-usage
- **Summary**: The OpenCode database is opened without SQLITE_DBCONFIG_DEFENSIVE or trusted_schema=OFF.

> Defence in depth against a crafted opencode.db in a user-configured directory, whose views could run unusual SQL inside the app.

### unified-rederive-policy

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 006-multi-harness-usage
- **Summary**: LogIndex, OpenCodeSource and CodexSessionSource each handle "rules or prices changed" differently, and SourceOutput has overlapping .records and .recordBatch cases.

> One policy (store raw records, re-derive on fingerprint or price change) and one output case would avoid three implementations of every future fix.

### raw-line-retention

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 006-multi-harness-usage
- **Summary**: Codex and OpenCode keep raw JSON per record only for custom markers, and OpenCode runs a live-id query on every refresh.

> Keeping raw text only when a custom marker exists, and a cheap deletion check first, would make memory and per-refresh work scale with changes rather than history.

### opencode-completion-dependency

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 006-multi-harness-usage
- **Summary**: Counting a completed OpenCode message relies on OpenCode bumping time_updated on completion.

> Re-selecting ids seen incomplete on each refresh would pick up completion whatever time_updated does.

### codex-fork-structural-signal

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 006-multi-harness-usage
- **Summary**: The copied parent burst in forked Codex files is detected by time (1 s after the fork).

> A structural end marker, such as the child's own task_started, would remove the assumption that the child's first turn takes longer than a second.

### opencode-update-invariant

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 006-multi-harness-usage
- **Summary**: The OpenCode first-read bound assumes time_updated is never earlier than time.completed, mitigated by a one-hour margin.

> Stating the invariant in contracts/harness-formats.md (or verifying it against OpenCode's source) would make the margin a documented choice.

### codex-fork-structural-marker

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 006-multi-harness-usage
- **Summary**: Forked Codex subagent files start with a copy of the parent's token events; AgentMeter treats events stamped within about 1 s of the fork as copied history. This holds on all 38 observed forks (copies 1 to 2 ms after the fork, fastest real child turn 3.8 s), but it is a timing heuristic.

> If a Codex release writes a structural marker for the end of the copied history (or a fork offset in session_meta), switch the detection to it and drop the time gap.
