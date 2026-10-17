# Idea Inbox

Ideas from code reviews, research and use, for future brainstorming.

## Priorities

Rated on 2026-10-15 by usefulness for users that fits AgentMeter's minimal setup (few dependencies, small trust surface, little new UI). Five stars means do next.

Feature ideas:

| Rating | Entries |
|---|---|
| 5 | - |
| 4 | - |
| 3 | reset-notifications, activity-history (one calm tab only), more-providers-without-cookies |
| 2 | status-page-badges, cli-json-output, models-dev-price-import, universal-build, usage-history-chart, admin-api-org-spend |
| 1 | widget, threshold-hooks, settings-redo-support |
| with the next provider | provider-descriptor-abstraction |

Review findings worth fixing soon: the seven rated on 2026-10-15 moved to brainstorm 14 (fix-soon-batch). All other review findings: clean up only when touching that code.

Suggested next five: pick from the 3-star entries (explicit-group-management moved to brainstorm 08, keep-last-good-values to brainstorm 09, pace-forecast to brainstorm 10, credential notifications to brainstorm 11, colored-bar-levels to brainstorm 12, auto-update to brainstorm 13, adaptive-refresh to brainstorm 15).

### log-config-reloads

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-agentmeter
- **Summary**: A successful reload of a hand-edited configuration leaves no trace in the diagnostic log.

> US3 scenario 4 promises pickup; the log cannot confirm it happened.

### credential-error-allow-list

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-agentmeter
- **Summary**: The credential-read error path falls back to String(describing:); the no-token guarantee holds by Foundation's error formatting rather than by construction.

> An allow-list mapping plus a sentinel test would make FR-011a hold by design.

### keychain-presence-check

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-agentmeter
- **Summary**: The first-launch presence check reads the full secret item to answer yes or no.

> A kSecReturnAttributes query answers presence without materializing the token.

### parse-off-cooperative-pool

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-agentmeter
- **Summary**: The directory scan and the parallel parse run synchronously inside an actor on the cooperative thread pool.

> No deadlock today; a dedicated serial queue bridged with a continuation would keep the pool free when more sources arrive.

### testable-bar-label

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-agentmeter
- **Summary**: BarLabelBuilder implements FR-002, FR-003 and FR-005 as pure functions but lives in the untested app target.

> Moving it (minus the attributed-string rendering) into UsageCore would let the threshold-glyph and ordering rules be unit tested.

### single-window-reset-mechanism

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-agentmeter
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

### dmg-layout-single-source

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 005-macos-distribution
- **Summary**: The DMG window size and icon positions are defined in both dmg-settings.py and render-dmg-backgrounds.swift.

> Changing the icon positions without re-rendering the committed backgrounds misaligns the drag arrow; a shared source or a back-reference comment would prevent it.

### codex-limits-actor-reentrancy

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 007-codex-plan-limits
- **Summary**: CodexLimitsSource reads its gate state before awaiting the fetches and writes it after, so overlapping collect calls would interleave.

> Safe today because RefreshCoordinator serializes refreshes; a second caller would silently break it.

### shared-codex-rollout-scan

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 007-codex-plan-limits
- **Summary**: CodexSessionSource and CodexLimitsSource both enumerate and parse the same rollout files on every refresh.

> Extracting the limit snapshot during the existing token parse would halve the I/O for long active sessions.

### drag-during-structural-debounce

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 008-menu-bar-arrangement
- **Summary**: A drag in the Menu Bar tab that lands in the same 600 ms debounce as a structural edit to the same account is overridden by the FR-006/FR-007 placement.

> Unlikely through the UI, but the drop is lost silently; flushing the pending apply before a reorder would avoid it.

### arrangement-row-layering

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 008-menu-bar-arrangement
- **Summary**: The Config layer depends on `ArrangementRow`, a settings-row type that lives under `Bar/` next to the bar layout.

> Inverted layering; moving `ArrangementRow` next to `EntryRef` or the show-in-bar accessors into `ArrangementEditor` would restore it.

### resolved-arrangement-property

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 008-menu-bar-arrangement
- **Summary**: `x.asArrangement(x.arrangedEntries)` appears five times and `asArrangement` never uses `self`.

> A `resolvedArrangement` property would shrink the public API.

### menu-bar-tab-render-cost

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 008-menu-bar-arrangement
- **Summary**: One body evaluation of the Menu Bar tab resolves `arrangedEntries` about five times, and every snapshot invalidates the whole list.

> Negligible at realistic sizes, but quadratic; computing the arrangement once per body and splitting the preview into its own view would fix it.

### bounded-stored-arrangement

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 008-menu-bar-arrangement
- **Summary**: A hand-edited arrangement with many junk references is kept and walked on every render until the next structural edit.

> Only self-inflicted, since only the local user writes the file; truncating or deduplicating on decode would bound it.

### dropdown-order-unit-test

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 008-menu-bar-arrangement
- **Summary**: Dropdown section order, Unassigned last (FR-003) and SC-001 are view-level only and have no unit test of their own.

> A UsageCore-level section list shared by the dropdown would make SC-001 testable.

### settings-redo-support

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 008-menu-bar-arrangement
- **Summary**: Redo is never available in Settings because the undo closure registers no inverse step.

> Pre-existing; users may expect Cmd-Shift-Z after Cmd-Z.

### reset-notifications

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Optional notifications when a window resets.

> CodexBar has reset notifications (off by default). The credential part of this idea moved to brainstorm 11 (credential-notifications).

### status-page-badges

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Opt-in polling of the public Statuspage.io feeds of Anthropic and OpenAI, with a small overlay or note when an incident is open.

> Answers "is it me or them?" when a row turns stale. Public, unauthenticated endpoints, but new outbound requests: needs an opt-in and an update of the security statement. Medium impact, low effort.

### cli-json-output

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: A small command line tool (`agentmeter usage --json`) that prints the current snapshot, for tmux, SketchyBar or scripts.

> CodexBar's ecosystem (KDE, GNOME, waybar, Stream Deck front ends) grew from its CLI and `serve` HTTP API. A CLI needs no network listener; a later HTTP API would need a loopback-only bind and a token. Medium impact, medium effort.

### models-dev-price-import

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Offer models.dev as another provider price import next to LiteLLM, through the existing explicit import with diff preview.

> CodexBar prices from models.dev (cached 24 h) plus a bundled fallback and a custom overlay. models.dev covers more vendors (Gemini, Kimi, ...). Keep AgentMeter's explicit import UX rather than silent auto-refresh. Medium impact, low effort.

### usage-history-chart

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Record subscription window percentages over time and show a burndown chart per window, next to the existing per-day trend.

> CodexBar records quota snapshots for a burndown with an even-use guide and a utilization history. Needs a small local history store with documented retention. Medium impact, medium effort.

### more-providers-without-cookies

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Add the next agents whose limits can be read without browser cookies: Gemini CLI (`~/.gemini/oauth_creds.json` against Google's internal code-assist quota endpoint) and GitHub Copilot (device-flow login against the Copilot usage API).

> The most requested next agents. Both use files or a device flow, so they fit AgentMeter's security stance; Gemini's endpoint is undocumented like the Claude and Codex ones. Browser-cookie providers (Cursor, claude.ai web and most of CodexBar's 104) stay out: they need Full Disk Access or the browser's Safe Storage secret. Medium impact, medium effort.

### admin-api-org-spend

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Optional account source for authoritative organization spend: Anthropic Admin API (cost and usage reports) and OpenAI Admin API costs, instead of estimating from local logs.

> Useful for company accounts where local logs only cover one machine. Admin keys must live in the Keychain (or a 0600 file) and be documented in the security statement. Medium impact, medium effort.

### provider-descriptor-abstraction

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Before adding a fourth provider type, introduce a provider descriptor with an ordered list of fetch strategies and per-provider credential adapters, plus a test that keeps provider-specific code out of shared code.

> CodexBar adds providers quickly through `ProviderDescriptor` and `ProviderFetchStrategy` and guards the boundary with `ProviderArchitectureGatekeeperTests`. Low impact now, medium effort; pays off with Gemini and Copilot.

### universal-build

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Build a universal binary (Apple Silicon and Intel) if nothing in the code is arm64 specific.

> CodexBar ships universal builds. Cheap reach increase; the cask's `depends_on arch: :arm64` and the README would change. Low impact, low effort.

### widget

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: A WidgetKit widget with the current percentages and budgets.

> Visible without opening the menu. Needs a widget extension target, an app group and a shared snapshot, which the SwiftPM build does not support well. Medium impact, high effort.

### threshold-hooks

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Run a user-chosen local executable on events such as threshold crossed, limit reached, window reset or source unavailable.

> CodexBar runs hooks without a shell and never passes provider secrets to them; that is the design to copy. Power-user automation. Low impact, low effort.

### activity-history

- **Source**: user
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar (Usage & Spend page)
- **Summary**: Keep an overall track record of usage and show it in two calm graphics, outside the dropdown: a "Token activity" heatmap (one cell per day or week, toggles Daily / Weekly / Cumulative, total for the last year) and an "Estimated spend" bar chart (last 30 days, stacked per harness or account, click a bar for that day's breakdown per model).

> Don't overwhelm: the dropdown stays as it is; the history lives in its own Settings tab (or an "Activity" window from the gear menu), with one headline number per chart and details only on click. Needs AgentMeter's own store of daily aggregates (tokens and estimated cost per day, harness, account and model), because Claude Code deletes its session logs after 30 days by default (`cleanupPeriodDays`) and the logs can't serve a year view. Aggregates only, no prompts or project contents; document location and retention in the security statement. Related: usage-history-chart (burndown of subscription windows), which could share the same store.

### shared-arrangement-resolution

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 009-explicit-group-management
- **Summary**: `reconcilingArrangement` resolves `previous.arrangedEntries` three times per apply; compute it once and derive base, positions and order from it.

> Cheap at realistic sizes (tens of entries), but the function runs on the MainActor apply path and the work is easy to share.

### empty-group-notify-test-strength

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 009-explicit-group-management
- **Summary**: The "empty group never notifies" assertion cannot fail at 0% because thresholds at or below 0 are normalized away; only the re-baseline half is a real test.

> Informational: a stronger check would need a group whose computed spend could be non-zero without members, which the aggregator never produces.

### lenient-run-out-marker-key

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 011-pace-forecast
- **Summary**: A hand-edited non-boolean `showsRunOutMarker` rejects the whole configuration, while `arrangement` is read leniently; the README configuration section does not mention the key.

> Decoding it with `try?` like `arrangement` and documenting it would keep a typo from disabling the app's settings.

### run-out-text-in-core

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 011-pace-forecast
- **Summary**: The run-out time formatting (time only today, otherwise weekday, day, month and time, also at midnight, spec 011 FR-009) lives in the untested app target and uses the wall clock for "today".

> A UsageCore formatter taking a calendar and the snapshot time would make the midnight rule testable and keep "today" consistent with the pace.

### pace-for-old-observations

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 011-pace-forecast
- **Summary**: Local-only Codex values can be hours old but are not marked stale, so their pace line and bar marker describe the observation time, not the present.

> Spec 011 now drops run-outs already in the past (FR-005); a maximum observation age, or a note with the observation time, could make old values clearer.

### coalesce-last-good-writes

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 010-keep-last-good-values
- **Summary**: last-good.json is rewritten after every successful refresh, and twice when both Claude and Codex fetched in the same refresh.

> Within FR-013 and cheap today; a single combined replace per refresh (or a short debounce in LastGoodStore) would halve the writes.

### dropdown-note-view-model

- **Source**: deep-review
- **Date**: 2026-10-15
- **Reference**: 010-keep-last-good-values
- **Summary**: The dropdown builds the grace, stale and rejected-sign-in notes and their colors in SwiftUI; only the note strings are tested.

> A small note view-model in UsageCore (text plus neutral, stale or attention style per state) would make the dropdown parts of US1-1, US2-1 and US2-4 testable.

### single-source-pill-state

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 012-colored-bar-levels
- **Summary**: `BarEntryPresentation` stores the pill level three times (`iconTone`, `textTone`, `pill`), so states like a red pill with orange-pill text are representable.

> An `EntryStyle` enum (plain with a text tone, or pill with a level) would make invalid combinations impossible and simplify `usesColor`.

### diagnostic-log-line-cap

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 012-colored-bar-levels
- **Summary**: `DiagnosticLog.append` sanitizes control characters but never caps the length of one line, so the 5 MB promise depends on every caller bounding its input.

> A length cap inside `append` would cover all callers; spec 012 clips its own note for now.

### increased-contrast-pill-check

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 012-colored-bar-levels
- **Summary**: The increased-contrast cells of SC-004 cannot be resolved in tests without changing the system setting, and on this OS the accessibility appearance names resolve to the normal colors.

> The walkthrough should check pill legibility with "Increase contrast" turned on, in light and dark.

### replayed-results-as-health

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 014-credential-notifications
- **Summary**: Credential health is derived from entry state, so results replayed without a request (reprice, quick-retry kept entries, Codex not-due) count as working or failing, not as "unchanged" (spec 014 FR-001).

> Harmless in steady state, but after a baseline reset (Codex live limits off and on quickly) a replay can become the baseline. Document it, or carry a "request sent" marker on entries.

### expiry-notice-without-reread

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 014-credential-notifications
- **Summary**: An expired episode can notify on a snapshot that did not read the credential again, up to one refresh interval after the agent renewed the token.

> Allowed by FR-001 and FR-005; a "credential read this refresh" marker would tighten it.

### own-status-item

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 014-credential-notifications
- **Summary**: Opening the dropdown from a notification click relies on SwiftUI internals (status button in the window tree, a window class name containing MenuBarExtra).

> A SwiftUI update could break it silently; owning an NSStatusItem would remove the dependency.

### log-silent-tracker-transitions

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 014-credential-notifications
- **Summary**: Silent credential tracker decisions (failing baseline, episode inside the expiry delay, result ignored after a directory change) leave no log line.

> "I never got a notification" is the likely support question; one log line per transition (not per refresh) would answer it.

### runbook-app-layer-notifications

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 014-credential-notifications
- **Summary**: Notification Center removal, leftover removal at launch, queue dropping and the click behavior are verified only up to the UsageCore event.

> The walkthrough runbook should cover them by hand.

### verification-progress-in-core

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 013-auto-update
- **Summary**: The R4 verification order of a one-click install is driven by the app, which re-invokes the six-argument `UpdateVerification.verdict` after each step.

> A small `VerificationProgress` value in UsageCore that records each step and returns the first failure would make the order a tested decision.

### update-cleanup-on-quit

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 013-auto-update
- **Summary**: Quitting during an update download leaves the hidden mount, the partial disk image and a running tool until the next launch.

> A willTerminate handler that cancels, force-detaches and removes the update folder would clean up right away; next-launch cleanup stays as the fallback.

### bounded-relaunch-helper

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 013-auto-update
- **Summary**: The relaunch helper polls for the old process without a time limit, and nothing handles a deferred termination.

> Nothing defers termination today; a bounded wait and a fallback state would keep the line from staying at "Installing" if that changes.

### notarized-code-requirement

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 013-auto-update
- **Summary**: The update's designated requirement could include `and notarized`, so notarization is checked by the Security framework, also for the staged copy.

> This removes the dependence on parsing spctl text; like spctl it needs a stapled ticket or a network connection.

### transient-flag-equality

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 016-adaptive-refresh
- **Summary**: `TransientFlag` is public with an `==` that is always true, used to keep per-refresh facts (`reachedService`, `attempted`) out of entry equality; every carry-over path must reset them.

> Per-refresh transport facts belong on the source result, not on the entry.

### unified-endpoint-pace-gating

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 016-adaptive-refresh
- **Summary**: Claude is paced by switching the run to reprice mode, Codex by a `codexPaceDue` flag on `RefreshContext`, with different reuse log lines.

> A per-endpoint decision set on the context would unify both and make a third paced endpoint cheap.

### scheduled-call-spacing-invariant

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 016-adaptive-refresh
- **Summary**: `.scheduled` has no minimum spacing of its own; the bound on endpoint calls comes from the pace arithmetic and the app timer re-arm.

> A core invariant (no scheduled call within about a minute of the last attempt) would turn a future re-arm regression into a no-op instead of a request per second.

### undocumented-lock-notifications

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 016-adaptive-refresh
- **Summary**: Idle detection uses the undocumented `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` notifications.

> If they stop firing in a future macOS, idle falls back to the 10-minute input threshold, which is still safe.

### timer-rearm-ordering

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 016-adaptive-refresh
- **Summary**: Every snapshot cancels and re-creates the app timer task with several actor hops; scheduling correctness depends on how unstructured tasks interleave with the coordinator.

> Publishing the next scheduled time and the pace line with the snapshot would remove the ordering sensitivity.

### idle-poll-tolerance

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 016-adaptive-refresh
- **Summary**: The idle poll wakes the process every 60 s without a sleep tolerance.

> `Task.sleep(for:tolerance:)` with a slightly shorter interval would let the system coalesce the wakeup and still meet FR-011.

### activity-tolerance-boundary-test

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 016-adaptive-refresh
- **Summary**: The 5 s tick tolerance on the activity branch of `shouldCall` has no boundary test.

> Pair it with the FR-006 clarification that the tolerance applies to both conditions.

### homebrew-auto-updates

- **Source**: user
- **Date**: 2026-10-16
- **Reference**: 013-auto-update
- **Summary**: Declare `auto_updates true` in the `agentmeter` cask and let Homebrew installs use the one-click Install too, instead of copying `brew upgrade --cask agentmeter`.

> With `auto_updates true`, Homebrew leaves the app's updates to the app (`brew upgrade` skips it unless `--greedy`), as for Sparkle apps. Spec 013 would treat a cask-managed install like a DMG install (FR-012, FR-013) and the release script would add the stanza to the cask. Trade-off: `brew list` and `brew outdated` keep the installed cask version until `brew upgrade --greedy`, and `--greedy` reinstalls over an already updated app. README Installation and the cask caveats would need to explain it.

### budget-discard-on-config-edits

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 017-burn-rate-escalation
- **Summary**: Budget observations are discarded on amount, period, member and price changes, but not when a new log directory, Codex home, OpenCode directory or attribution change makes a budget's spend jump without new usage; that jump can show a false "↑" for up to an hour.

> The spec's own reason for discarding ("the percent of a budget can jump without any new usage") applies to these edits too; folding them into the fingerprint or the reprice flag would close the gap.

### single-pace-and-burn-value

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 017-burn-rate-escalation
- **Summary**: Dropdown rows resolve the pace from the row's value and the burn rate again from a window key, so the pair handed to the pace meter agrees only because the key mapping matches.

> Letting BurnRate carry its Pace (it already has it in BurnInputs) would give the meter one value and remove the double resolution and the per-row key building in the app layer.

### opencode-resource-limits

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 015-fix-soon-batch
- **Summary**: The hardened OpenCode connection sets no `SQLITE_LIMIT_LENGTH` and no progress handler, so a crafted `opencode.db` can still exhaust memory or stall a refresh with huge values or expensive innocuous expressions.

> SQLite's guidance for untrusted databases recommends a lower length limit and a wall-clock progress handler; both fail as an ordinary source error.

### release-exit-phase-naming

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 015-fix-soon-batch
- **Summary**: In release.sh the `published` exit phase now only covers a failed draft switch, and the later `phase="published"` assignment is dead.

> A dedicated phase name and message would keep the exit trap's meaning explicit for the next change.

### shared-canonical-path

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 015-fix-soon-batch
- **Summary**: LogDirectoryScanner keeps its own copy of the canonical path function that SessionLogSource dedup and Attributor use.

> Spec 015 FR-006 attribution depends on the copies staying identical; one shared `Paths.canonical` would remove the risk.

### settings-caption-credential-dirs

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 015-fix-soon-batch
- **Summary**: The Settings caption for extra Claude Code directories does not say that each subscription account's credential directory is scanned automatically.

> The caption still invites the double entry that spec 015 FR-006 makes unnecessary.

### older-window-suppression-log

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 015-fix-soon-batch
- **Summary**: Threshold observations with an earlier window end are ignored without limit and without a log line. A changed credential directory or Codex home re-baselines (fixed in spec 015 verification), but signing in to another account in the same directory can still silence that account for up to a window.

> A diagnostic line, or a re-baseline after repeated older ends, would make this visible and bounded.

### immutable-release-retry-advice

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 015-fix-soon-batch
- **Summary**: With GitHub's immutable releases enabled, the draft switch of `REPLACE=1` always fails and the retry advice loops.

> The failure message could name immutable releases and suggest a new patch version.

### downgrade-in-final-line

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 015-fix-soon-batch
- **Summary**: The "deliberate tier downgrade" statement of `ALLOW_TIER_DOWNGRADE=1` only appears in preflight, not in the final `done:` line of a release.

> Repeating it at the end keeps it visible after a long build and notarization log.

### threshold-source-stamped-entries

- **Source**: verify
- **Date**: 2026-10-16
- **Reference**: 015-fix-soon-batch
- **Summary**: The threshold tracker re-baselines when a credential directory or Codex home changes (spec 015 FR-002), but reads the directory from the current configuration; a refresh in flight during the change, or Codex entries carried over after a failed limits read, can make the new baseline record the old login's window.

> Stamping the directory or home on `SubscriptionEntry` and `CodexLimitsEntry` and skipping mismatched entries, as the tracker already does for period, members and live limits, would close it.

### budget-formatting-in-core

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 018-account-budget-subtitle
- **Summary**: `BudgetAmountFormatter` and `GroupListSubtitle` live in a file named after `AccountBudgetDescription`, while the dropdown's currency formatting (`UsageFormat`, including the near-duplicate `UsageFormat.budget`) stays in the view layer.

> Moving `UsageFormat`'s pure functions into UsageCore next to the new formatter would give amount formatting one home and bring it under the testable-logic rule.

### literal-sc004-amount-test

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 018-account-budget-subtitle
- **Summary**: `bothListsShowTheSameAmountText` derives its expected value from the formatter both lists call, so it only catches a list that stops calling it.

> Asserting the literal "$400 / month" on both outputs would make the SC-004 test independent of the formatter's implementation.

### pace-line-plan-list-wording

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 019-pace-line-names-plan
- **Summary**: The pace line joins slowed plan names with " and " and reuses the generic "no agent activity" reason, which fits exactly two `PacedEndpoint` cases.

> A third paced endpoint would read "A and B and C"; switching to `ListFormatter` or an explicit two-or-more rule with a test would keep the line natural.

### twelve-hour-test-icu-space

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 019-pace-line-names-plan
- **Summary**: `bothPlansTwelveHour` hard-codes U+202F before "AM", which depends on the toolchain's ICU data.

> Normalizing the narrow no-break space before comparing would keep the test stable across macOS and toolchain versions.

### pace-line-ui-manual-checks

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 019-pace-line-names-plan
- **Summary**: Spec 019 FR-005 (accessibility text equals the line) and FR-007 (wrapping, no truncation) live in the SwiftUI layer and have no automated test.

> The walkthrough should check the longest line (both plans, 12 hour time, another day) and VoiceOver by hand.

### signing-text-in-log-line

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 020-about-tab-update-layout
- **Summary**: `AppVersionInfo.Signing.text` returns display strings made for the removed About Signing row, and its only production caller is now the space-separated `key=value` update log summary.

> Logging the raw tier names (`developer-id`, `self-signed`, `ad-hoc`, `notarized=true|false`) would keep the log line machine-readable and let the display formatter go.

### no-answer-flag-after-precheck

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 021-recover-stuck-offline
- **Summary**: A failure before a request (expired or missing sign-in) leaves the spec 021 no-answer flag set, so each "Refresh now" within 60 s re-reads the credential (a keychain read for Claude) and logs, without sending a request.

> Decide whether the flag should follow the last request or the last attempt; clearing it on a pre-request failure would remove the extra reads.

### shared-endpoint-gate-type

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 021-recover-stuck-offline
- **Summary**: The "Refresh now" bypass lives twice in different shapes: a per-home Bool in the Codex fetch gate, and a per-account Set plus a policy flag for Claude.

> One per-target gate type (spacing, block, no-answer flag) used by both sources would keep the two rule sets in sync.

### bypass-click-floor

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 021-recover-stuck-offline
- **Summary**: There is no minimum gap between spec 021 bypass requests; each click after a finished run sends one request per no-answer account or Codex home.

> A short floor (5 to 10 s) would cap token-carrying requests during a fast-failing outage; the spec currently relies on the user's clicks only.

### partial-run-backoff-reset

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 021-recover-stuck-offline
- **Summary**: A successful partial run (no-answer-only or quick retry) resets the global rate-limit backoff and last outcome, also for accounts that were not asked.

> A partial `record` variant that only updates the last attempt and sets a block on 429 would keep the backoff history intact.

### richer-network-failure-detail

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 021-recover-stuck-offline
- **Summary**: The no-answer log detail lacks the stream error domain and the elapsed time of the failed request.

> Both are privacy-safe integers; with them the next stuck-offline incident could tell an in-process path problem from blackholed packets.

### double-click-two-requests

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 021-recover-stuck-offline
- **Summary**: A double click during a fast-failing bypass run sends two requests per service back to back (the run plus its follow-up), which FR-006 allows.

> Skipping the follow-up's bypass when the running run was itself a bypass started a few seconds earlier would keep one gesture to one request.

### single-app-identity

- **Source**: deep-review
- **Date**: 2026-10-17
- **Reference**: 023-rebrand-agenttacho
- **Summary**: The bundle identifier and the repository slug are spelled out in several places (Info.plist, build-app.sh, UpdateOutcome, AppLinks, UpdateSource, RunningInstance, lib.sh).

> A small `AppIdentity` in UsageCore that `UpdateOutcome.folderName`, `AppLinks`, `UpdateSource.official` and `RunningInstance` derive from would leave one Swift place to change on the next rename.

### watch-for-a-late-agentmeter

- **Source**: deep-review
- **Date**: 2026-10-17
- **Reference**: 023-rebrand-agenttacho
- **Summary**: The running-copy check runs only at AgentTacho's launch, so an AgentMeter started later by its leftover login item runs alongside unnoticed.

> Watching `NSWorkspace.didLaunchApplicationNotification` for the legacy identifier while AgentTacho runs would show the same alert; until then the README's "delete AgentMeter.app" step is the fix.

### allowlist-stale-alternatives

- **Source**: deep-review
- **Date**: 2026-10-17
- **Reference**: 023-rebrand-agenttacho
- **Summary**: The name check marks a whole allowlist line as used when any one of its `|` alternatives matches, so dead alternatives accumulate unnoticed.

> One phrase per allowlist line, or per-alternative usage tracking, would keep the list as tight as the stale check intends.

### startup-order-test

- **Source**: deep-review
- **Date**: 2026-10-17
- **Reference**: 023-rebrand-agenttacho
- **Summary**: That the move runs before any store creates its folder, and after the single-instance check, lives untested in `AppModel.init`.

> A small `Startup.prepare(paths:log:)` in UsageCore, called first by `AppModel.init`, would make the order and the "move" log lines testable.
