# Research: Minimal Dropdown

All unknowns of the Technical Context are resolved; each decision below names the requirements it serves.

## R1: One value for pace and burn rate (FR-030, inbox single-pace-and-burn-value)

- **Decision**: add `public struct PaceReading { pace: Pace; burn: BurnRate? }` and `UsageSnapshot.paceReading(for: BurnWindowKey) -> PaceReading?`, built from the existing `burnInputs(for:)` so the pace and the burn rate come from the same `PaceInputs`. `burnRate(for:)` stays as a thin wrapper (`paceReading(for:)?.burn`) for the bar code that uses it today. The dropdown rows use only `paceReading(for:)` and stop calling `status.fiveHourPace(now:)`, `limits.pace(of:now:)` and `entry.pace(now:)` next to `burnRate(for:)`.
- **Rationale**: `burnInputs` already resolves the pace with its inputs; returning both removes the double resolution in the app layer and the per-row key building that only agreed by convention.
- **Alternatives**: a `pace` property on `BurnRate` (the inbox wording) fails when `BurnRate.compute` returns nil for a window with a pace (an observation at the reset), so the row would lose its tick; rejected.

## R2: Row bar decisions in core (FR-001 to FR-004, FR-007, FR-009, FR-032)

- **Decision**: `RowBar.make(usedPercent: Double, limitReached: Bool, reading: PaceReading?) -> RowBar` with `fill` (used percent / 100 clamped to 0...1), `tick` (`pace.expectedPercent / 100`, nil without a pace), `tone` (`.overLimit` when the rounded percent is 100 or more or `limitReached`, else `.attention` when `pace.usesAttentionColor(burn:)`, else `.neutral`) and `note: PaceNote?` (set exactly when the tone is `.attention`). `PaceNote` keeps the pace and the fast run-out and renders with `pace.summary(runOutText:fastRunOut:)`, so the words stay those of spec 011 and spec 017. `RowBar.accessibilitySummary(times:)` returns the pace summary also when no note shows (FR-006).
- **Rationale**: one tested function decides geometry, color and note, so they cannot disagree; the existing summary text is reused.
- **Alternatives**: computing tone in the view (today's approach) leaves FR-003 and FR-004 untested.

## R3: Time formats (FR-016 to FR-020, FR-031)

- **Decision**: `TimeText(format: TimeFormat, now: Date, calendar: Calendar, locale: Locale)` with `reset(_ date:) -> String` ("resets in 2h 26m" or "resets 17:20"), `runOut(_ date:)` (the part after "runs out "), `resetTooltip(_:)`, `runOutTooltip(_:)` and the static `relative(from:to:)`. Relative: whole minutes rounded down; "in <1m" below a minute; days+hours from one day, hours+minutes from one hour, minutes below; a zero second unit omitted; "now" at or before `now`. Absolute: calendar day difference from `calendar.startOfDay(for: now)`; same day the time, 1 to 6 days weekday+time, otherwise weekday, day, month, time; a reset at local midnight not on the same day weekday, day and month only; a run-out keeps its time at midnight. Formats use `Date.FormatStyle` with the given `locale`, `calendar` and its `timeZone`, so tests are deterministic. The app passes the dropdown's reference time as `now`, updated every 30 s while the panel is open (R8).
- **Rationale**: one formatter with explicit inputs replaces `UsageFormat.resetText` and `runOutText` in the untested app target (inbox run-out-text-in-core).
- **Alternatives**: `RelativeDateTimeFormatter` produces "in 4 days" without the second unit and with locale-dependent words; rejected for the compact two-unit form the spec asks for. `DateComponentsFormatter` with `.abbreviated` style gives "4d 16h" but rounds and localizes unit letters unpredictably; the units are built by hand instead.

## R4: The `timeFormat` configuration key (FR-021, edge case unknown value)

- **Decision**: `public enum TimeFormat: String, Codable, CaseIterable { case relative, absolute }`; `Account.timeFormat` and `BudgetGroup.timeFormat`, JSON key `timeFormat`, default `.relative`. Decoding: absent means relative; an unreadable or unknown value means relative plus a `ConfigurationLoadNotes` entry ("timeFormat \"x\" is not known, using relative"), the way `levelColor` is decoded (spec 012). Encoding always writes the key, like `shownInBar`. `Configuration.timeFormat(for: ArrangedEntry)` returns the account's value for an account section and the group's for a group section.
- **Rationale**: an account-level key keeps the value when a token-based account moves into a group and back (FR-021); the notes mechanism already reaches the diagnostic log without a problem notice.
- **Alternatives**: one global setting (simpler, but the user asked for per account and group); storing it inside each kind's settings struct (three places instead of one).

## R5: Section notes (FR-015, FR-029, inbox dropdown-note-view-model)

- **Decision**: `public struct SectionNote { text: String; style: NoteStyle }` with `NoteStyle` `.neutral`, `.warning`, `.alert`, and builders: `SectionNote.claude(state: SubscriptionState?, credentialDirectory:, isPreliminary:, nextRetryAt:, endpointBlockedUntil:, dates: NoteDates) -> [SectionNote]`, `SectionNote.codex(limits: CodexLimitsEntry, dates:) -> SectionNote?`, `SectionNote.budgetIncomplete(unpricedModels:)`, `SectionNote.budgetStale(since:dates:)`, `SectionNote.emptyGroup`, `SectionNote.staleMarker`, `SectionNote.noData(isPreliminary:)`. `NoteDates(locale:timeZone:)` formats "abbreviated date, shortened time" and "shortened time" as today. Texts are copied verbatim from `DropdownView.swift`, so tests pin today's wording.
- **Rationale**: the view keeps only a `switch` on `NoteStyle` for the color.
- **Alternatives**: a single enum of all states with a `text` property; it would duplicate the snapshot state enums.

## R6: Footer and Details texts (FR-014, FR-023 to FR-026)

- **Decision**: `FooterText.lastRefreshed(at: Date?, hasSnapshot: Bool, isPreliminary: Bool, now:, calendar:, locale:) -> String` ("Last refreshed 16:54", "Last refreshed Oct 17, 16:54", "Refreshing…", "No successful refresh yet"); the tooltip is `RefreshPaceStatus.text(now:calendar:)` when a pace is slowed, else none. `DetailsTotal.weekly(tokens: Int, locale:) -> String` ("This week: 45.1M tokens", compact number style as `UsageFormat.tokens`). The update line keeps `model.updater.display.lineState`; the dropdown no longer calls `checkNow(from: .dropdown)`, so the transient result never reaches the line, while the failed-install case set at launch still does (FR-026).
- **Rationale**: keeps the footer wording testable and leaves the spec 013 state machine as it is.
- **Alternatives**: removing `CheckOrigin.dropdown` from `UsageCore`; it is a spec 013 change with its own tests and not needed for this feature. First recorded as an idea inbox item, it was removed in the code review fix round together with its spec 013 tests, and spec 013 FR-003 was amended (deep review FINDING-9).

## R7: Rendering in SwiftUI (FR-001, FR-005, FR-011, FR-027, FR-028)

- **Decision**: a `RowBarView` draws a 4 pt capsule track in `Color.secondary.opacity(0.25)`, the fill capsule in the tone's color (neutral `Color.secondary`, attention `.orange`, over limit `.red`) and, with a tick, a 1.5 x 10 pt rectangle in `Color.primary`, full width via `GeometryReader` in a fixed-height frame. Dividers are emitted before every section except the first. The icon row uses three borderless buttons with SF Symbols `arrow.clockwise`, `gearshape`, `power`, `.help` and `.accessibilityLabel`, with `.keyboardShortcut(",")` and `.keyboardShortcut("q")` on the Settings and Quit buttons (no hidden duplicates needed without a `Menu`). The Settings button carries the identifier `agenttacho.settingsButton` for the capture.
- **Rationale**: matches the existing drawing style of `PaceMeter`; buttons replace the menu and its hidden shortcut workaround.

## R8: Live time updates (FR-020)

- **Decision**: the dropdown keeps its reference time `now` as view state and passes it into `TimeText`. Opening the panel (its first `onAppear`, then every time it becomes key) sets `now` and marks it open; a task keyed on the open state sets `now` every 30 s and is cancelled when the panel resigns key. The pace and the snapshot are not recomputed; only texts change.
- **Rationale**: the MenuBarExtra keeps its content alive while the panel is hidden, and a standalone panel probe showed that a `TimelineView(.periodic(from:by:))` keeps ticking after `orderOut` (deep review FINDING-10). Tying the updates to the key state stops them while the panel is closed, keeps the views' state (an expanded Details section) and makes times current the moment the panel opens; 30 s keeps minute values at most half a minute late while it is open.

## R9: Codex plan type and token lines (FR-013, FR-014)

- **Decision**: the Codex plan line and the header tooltip are both gone (the header names the plan; walkthrough step 5 showed Claude had no such tooltip); `planDisplayName` is removed; the plan line and the "Tokens this week" line go. `BreakdownView` gains `totalLine: String?`, shown above the view picker; subscription sections pass `DetailsTotal.weekly(...)`, budgets pass nil.

## R10: Single-member groups (FR-010)

- **Decision**: `BudgetSection` shows member lines only when `members.count >= 2`. Today a single member already shares the group's Details, so only the line goes.

## R11: Demo scenarios and coverage (FR-035)

- **Decision**: `CoverageReport` gains `attentionRows: [BurnWindowKey]` (keys of `UsageSnapshot.paceKeys`, made public from today's internal `burnWindowKeys`, whose `paceReading(for:)?.callsForAttention` is true), `singleMemberGroups: [String]` and `absoluteTimeOwners: [String]`. The `default` scenario must have `attentionRows >= 1` and a group with two or more members and keeps every `timeFormat` at the default. New `Resources/demo/variants.json`, a copy of the default story trimmed to the Claude account with `"timeFormat": "absolute"` and a group with one Vertex member, is checked by its own coverage test; `DefaultScenarioTests` already loads every JSON file in `Resources/demo`.
- **Alternatives**: one scenario for both published shots and variants; rejected in clarification (images show the default).

## R12: Capture script (FR-035)

- **Decision**: the `pace` stem crops the first row with a note, identified as `agenttacho.paceRow` (set on the row container whose `RowBar.note` is non-nil for the shot entry), instead of hovering the meter and compositing the tooltip; the tooltip helpers that only served this step are removed. Settings opens with `"$UIHELPER" press "$pid" agenttacho.settingsButton`. `scripts/release/tests/test_screenshots.sh` follows the new steps.
- **Rationale**: no hover means a faster and steadier capture.

## R13: Earlier specs (FR-033)

- **Decision**: rewrite each affected requirement in place to the new behavior and cite spec 025 in it, the way spec 020 amended spec 013 FR-002 and FR-011 ("... in Settings > General (spec 020)"): spec 004 FR-018a, spec 007 FR-011 and FR-013, spec 011 FR-008 to FR-010, spec 013 FR-003 and FR-009 (plus its `contracts/update-ui.md` dropdown section), spec 016 FR-016, spec 019 (line placement), spec 017 FR-012, spec 020 FR-010, spec 024 FR-014 and FR-019.
- **Rationale**: readers of an earlier spec see today's behavior and where it changed.

## R14: README (FR-034)

- **Decision**: update the hero image alt text, the Updates paragraph and the "Check for Updates…" sentence (no gear menu; the check lives in Settings > About), the configuration paragraph ("the settings window (the Settings icon in the dropdown, or ⌘,)"), the About tab bullet, the subscription and Codex paragraphs (bars, the orange note, Codex plan type on hover, token total in Details), and the configuration reference (`timeFormat` on accounts and groups).
