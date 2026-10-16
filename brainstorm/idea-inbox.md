# Idea Inbox

Ideas from code reviews, research and use, for future brainstorming.

## Priorities

Rated on 2026-10-15 by usefulness for users that fits AgentMeter's minimal setup (few dependencies, small trust surface, little new UI). Five stars means do next.

Feature ideas:

| Rating | Entries |
|---|---|
| 5 | - |
| 4 | reset-and-credential-notifications (credential part first), colored-bar-levels |
| 3 | auto-update, adaptive-refresh, activity-history (one calm tab only), more-providers-without-cookies |
| 2 | status-page-badges, cli-json-output, models-dev-price-import, universal-build, usage-history-chart, admin-api-org-spend |
| 1 | widget, threshold-hooks, settings-redo-support |
| with the next provider | provider-descriptor-abstraction |

Review findings worth fixing soon (small, user-relevant): threshold-baseline-after-reset, release-signing-tier-guard, replace-published-as-draft, scan-credential-directories, sqlite-defensive-open, stale-entry-period-mismatch, claude-client-resource-timeout. All other review findings: clean up only when touching that code.

Suggested next five: colored-bar-levels, credential notifications (explicit-group-management moved to brainstorm 08, keep-last-good-values to brainstorm 09, pace-forecast to brainstorm 10).

### threshold-baseline-after-reset

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-agentmeter
- **Summary**: After a window reset the tracker records a baseline instead of treating the previous value as 0, so a window that starts above a threshold never notifies.

> FR-028 mandates the baseline only for the first refresh after launch; the stricter reading would notify. A spec note would remove the ambiguity.

### scan-credential-directories

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-agentmeter
- **Summary**: A subscription account's credential directory is not scanned unless also listed under log directories, so the directory tie-breaker needs the path in two settings.

> Unioning the credential directories into the scan set would remove the duplication.

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

### dmg-layout-single-source

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 005-macos-distribution
- **Summary**: The DMG window size and icon positions are defined in both dmg-settings.py and render-dmg-backgrounds.swift.

> Changing the icon positions without re-rendering the committed backgrounds misaligns the drag arrow; a shared source or a back-reference comment would prevent it.

### release-signing-tier-guard

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 005-macos-distribution
- **Summary**: The release identity is chosen by certificate name only, so an expired Developer ID silently falls back to self-signed.

> A tier change alters the designated requirement for every user; an optional REQUIRE_TIER or expected certificate or team ID check in preflight would stop an unintended downgrade.

### replace-published-as-draft

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 005-macos-distribution
- **Summary**: REPLACE=1 on a published release clobbers the live DMG, so a failed upload can leave a public release without a DMG.

> Switching the release back to a draft before clobbering would extend the spec's "stays a draft" guarantee to replacements.

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

### claude-client-resource-timeout

- **Source**: deep-review
- **Date**: 2026-10-14
- **Reference**: 007-codex-plan-limits
- **Summary**: The Claude usage client has no resource timeout; the Codex client sets one (45 s). Redirects are refused by both clients since the About tab work.

> The same token-leak reasoning (spec 001 FR-011a) applies to the Claude OAuth token.

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

### auto-update

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Auto-update for DMG installs (Sparkle with an EdDSA-signed appcast), turned off for Homebrew installs, which keep updating through `brew upgrade`.

> CodexBar uses Sparkle 2 with stable and beta channels and detects Homebrew installs to avoid fighting the cask (it offers a one-click `brew upgrade` instead). Without auto-update, DMG users stay on old builds. First third-party dependency for AgentMeter, plus an appcast URL to host (GitHub releases) and a new outbound request to document in the security statement. High impact, medium effort.

### reset-and-credential-notifications

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Optional notifications when a window resets, and when a credential stops working (Codex sign-in expired, Claude Code login missing or rejected).

> Turns silent failures (rows showing `--`) into a prompt to act. CodexBar has reset notifications (off by default) and credential-expiry and credential-change notifications. Medium impact, low effort.

### adaptive-refresh

- **Source**: codexbar-comparison
- **Date**: 2026-10-15
- **Reference**: https://github.com/steipete/CodexBar
- **Summary**: Adapt the refresh interval: slower in Low Power Mode, under thermal pressure or when the dropdown has not been opened for a while, faster right after it was opened.

> CodexBar's default refresh mode ranges from 2 to 30 minutes based on these signals. Fewer requests to the undocumented usage endpoints and less battery use. Medium impact, low effort.

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

### colored-bar-levels

- **Source**: user
- **Date**: 2026-10-15
- **Summary**: Show warning and over-limit levels in the menu bar with color (for example orange at the warning threshold, red at 100% and above) instead of the `⚠` and `‼` glyphs, keeping the bar compact.

> The bar is drawn as one template image today (BarLabelBuilder), which macOS tints monochrome for light and dark menu bars; that is why the glyphs carry the level (spec 001 FR-003). Colored values need a non-template image that follows the menu bar's appearance itself (effective appearance of the status item, light and dark, and the tinted or reduced-transparency variants). Color alone fails for color-blind users and in grayscale, so keep the glyphs as a setting ("Mark levels with: color / symbols / both"), with color as the default if it reads well.

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

### accounts-list-budget-subtitle

- **Source**: walkthrough
- **Date**: 2026-10-15
- **Reference**: 009-explicit-group-management
- **Summary**: The Accounts list subtitle of a token-based account says only "token-based (Vertex)", the provider; it should also say which budget the account uses, for example "Vertex · group Vertex" or "OpenAI · own budget".

> Found while trying explicit group management: with groups now able to stay empty and accounts moving between groups, the list does not show where an account's spend counts. Small text change in AccountSettingsView's subtitle.

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
