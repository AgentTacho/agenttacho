---

description: "Task list for free reset tickets"
---

# Tasks: Free Reset Tickets

**Input**: Design documents from `specs/033-free-reset-tickets/`

**Prerequisites**: plan.md (Interfaces block, Global constraints), spec.md, research.md, data-model.md, contracts/external-sources.md, contracts/texts.md, quickstart.md

**Tests**: Included. Constitution II requires tests first for logic in UsageCore (Swift Testing, run with `make test`).

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Conventions for every task

- Signatures follow the Interfaces block in plan.md.
- New and changed doc comments cite the requirements they implement (for example `spec 033 FR-008`).
- No em dash or en dash characters anywhere.
- Build and test only through the Makefile (`make test`, `make test-release`, `make app`, `make app-demo`).
- No service identifier (`id`, grant ids, `usable_now`) is decoded, stored or logged; no token reaches a log or a notification.

---

## Phase 1: Setup

**Purpose**: Confirm a green baseline.

- [X] T001 Run `make test` on the branch and confirm all existing tests pass before any change (no file changes)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The ticket model, decoders, list helpers, time texts, links and the configuration key that every story uses (data-model "ResetTicket", "ResetTicketRead", "ResetTicketList", "Configuration"; research R1, R3, R6, R8).

- [X] T002 [P] Add Tests/UsageCoreTests/ResetTicketsTests.swift: Claude decoding per contracts/external-sources.md (valid block with one expiring and one non-expiring grant gives two tickets; `resets_left: 2` gives two tickets with the grant's `ends_at`; paused, future `starts_at` and past `ends_at` grants give none; `eligible: false`, missing block and empty `grants` give `.tickets([])`; wrong types, negative `resets_left`, unparsable time, 201 grants and 51 usable tickets give `.clearingFailure`); Codex decoding (available with future or absent `expires_at` counts; redeemed, redeeming, expired status and past `expires_at` do not; missing `credits` gives `.tickets([])`; wrong types, bad time and 51 usable give `.clearingFailure`); list helpers `usable(at:)`, `sortedForDisplay` (soonest first, nil last), `glyphs(at:)` (three shown plus overflow, expired dropped), `groupedByExpiry(at:)`
- [X] T003 Implement Sources/UsageCore/Subscription/ResetTickets.swift: `ResetTicket`, `ResetTicketRead` with kind labels (`transport`, `http-<code>`, `malformed`, `implausible`, `flag-dropped`, `skipped`), `ResetTicketDecoding.claude(cedarEmber:now:)` and `ResetTicketDecoding.codex(data:now:)` with the caps of research R1 and R3, and the `[ResetTicket]` helpers (spec 033 FR-002, FR-003, FR-008); make T002 pass
- [X] T004 [P] Add tests in Tests/UsageCoreTests/TimeTextTests.swift (or the existing TimeText test file) for `TimeText.expiry(_:)` ("in 2d 3h (<abs>)" with the same absolute form the reset tooltips use, for today, tomorrow and later dates) and `TimeText.absolute(_:)`; implement both in Sources/UsageCore/Dropdown/TimeText.swift by exposing the existing private absolute form (research R8, spec 033 FR-010)
- [X] T005 [P] Add tests in Tests/UsageCoreTests/ConfigurationTests.swift: `notifyFreeResetExpiry` defaults to true, a file without the key reads true, false round-trips, the key is always encoded, and `dataRelevant()` normalizes it to true; implement the key in Sources/UsageCore/Config/Configuration.swift exactly like `notifySignInProblems` (spec 033 FR-017)
- [X] T006 [P] Add `AppLinks.claudeUsagePage` (`https://claude.ai/settings/usage`) and `AppLinks.codexUsagePage` (`https://chatgpt.com/settings/usage?tab=overview`) in Sources/UsageCore/AppLinks.swift with a test in the existing AppLinks test file or a new Tests/UsageCoreTests/AppLinksTests.swift (spec 033 FR-010a, research R6)
- [X] T007 Add `resetTickets: [ResetTicket]` (init parameter defaulting to `[]`) to `SubscriptionEntry` in Sources/UsageCore/Snapshot/UsageSnapshot.swift and to `CodexLimitsEntry` in Sources/UsageCore/Subscription/CodexLimits.swift; make `reused(now:)`, `endingGrace` and `markedStale(reason:)` copy it, with tests that each copy keeps the tickets (spec 033 FR-006). The "never persisted" check follows in T009 and T011, which drive the sources with a `LastGoodStore` and assert the written JSON has no ticket field

**Checkpoint**: `make test` green; tickets can be decoded, listed, timed and carried on entries.

---

## Phase 3: User Story 1 - See free reset tickets next to the account (Priority: P1) MVP

**Goal**: Claude and Codex accounts show up to three dimmed gift glyphs plus `+N` with expiry tooltips; a click opens the usage page and closes the dropdown.

**Independent Test**: In the demo build the first Claude Max header shows two glyphs with the tooltips of contracts/texts.md; source tests show tickets reaching entries for Claude and Codex under every case of contracts/external-sources.md (quickstart "Demo build" steps 1 to 3).

### Tests for User Story 1

- [X] T008 [P] [US1] Add tests in Tests/UsageCoreTests/UsageEndpointClientTests.swift: with `includeTickets: true` the request URL carries `cedar_ember=1` and otherwise unchanged headers; without it the URL has no query; a valid block next to valid windows returns both; a malformed block still returns the windows and a `.clearingFailure` read; the existing `fetch(token:)` behaves as before
- [X] T009 [P] [US1] Add tests in Tests/UsageCoreTests/SubscriptionSourceTests.swift for the `TicketFlag` table in data-model.md: 400 then plain 200 (one repeat, usage ok, tickets cleared, flag never sent again in later refreshes, one log line); 403 then plain 403 (usage classified `signInRejected` from the plain result, flag suspended, tickets kept, next refresh sends plain, the refresh after a plain success sends the flag again); 422 handled like 400; 401 and 429 never repeated; transport error keeps the last tickets minus expired; a malformed block clears; removed accounts drop flag and tickets; `notSignedIn` clears tickets, `credentialsExpired` and `credentialReadFailed` keep them; after a change of the account's credential directory followed by a transport failure no tickets are shown and the flag is `on` again; a failure kind is logged once per run per account with no token or identifier in the line; for a malformed block, a dropped flag and a transport failure the entry's state, fetch outcome and windows equal those of the same refresh without tickets (SC-004); the `LastGoodStore` file written after a refresh with tickets contains no ticket field (FR-006)
- [X] T010 [P] [US1] Add tests in Tests/UsageCoreTests/CodexUsageClientTests.swift for `fetchResetCredits`: URL from the `resetCreditsURL` init parameter (default `wham/rate-limit-reset-credits`), same headers as `wham/usage` (stub handler branches on `request.url` since both share the bearer token), a 10 s request and resource timeout, redirect and unexpected location give `.temporaryFailure`, HTTP 500 and transport errors give `.temporaryFailure`, a malformed body gives `.clearingFailure`, a valid body gives tickets
- [X] T011 [P] [US1] Add tests in Tests/UsageCoreTests/CodexLimitsSourceTests.swift: the credit request is sent only after a successful plan-limit fetch, never with live limits off and never after a failed or skipped plan-limit request (then tickets are kept as a temporary failure); two accounts on one Codex home both get the tickets from one request; entries carry `resetTickets`; a clearing failure empties them; a later refresh that sends no request (not due, blocked, no sign-in) keeps the tickets minus expired; the `LastGoodStore` file contains no ticket field; a credit request answered with 401, 429, 500 or a timeout leaves the entry's state, observation, credential problem, `rejectedTokens` and the per-home gate (`lastFetchAt`, `lastNoAnswer`, `blockedUntil`, next-fetch decision) equal to the same refresh without the credit request (SC-004)
- [X] T012 [P] [US1] Add Tests/UsageCoreTests/ResetTicketTextTests.swift for every dropdown row of contracts/texts.md: glyph tooltip with and without expiry (each ending with "Click to open the usage page"), overflow tooltip listing the hidden tickets in display order, VoiceOver labels for 1 and N tickets with and without expiry

### Implementation for User Story 1

- [X] T013 [US1] Extend Sources/UsageCore/Subscription/UsageEndpointClient.swift: `fetch(token:includeTickets:) -> (status: SubscriptionStatus, tickets: ResetTicketRead?)` adding the `cedar_ember=1` query item via `URLComponents`, decoding the block leniently next to `Body` and passing it to `ResetTicketDecoding.claude`; keep `fetch(token:)` as a wrapper (spec 033 FR-001, FR-003); make T008 pass
- [X] T014 [US1] Extend Sources/UsageCore/Subscription/SubscriptionSource.swift: per-account `TicketFlag` and `lastTickets` in the actor; `collect` passes each account's flag into the static `attempt`, which performs the FR-004 repeat (4xx except 401 and 429) and returns the ticket read and the flag transition with the attempt (plan Interfaces); `apply` commits the flag; the branch of `collect` that resets `lastGood` and episodes on a credential directory change also clears `lastTickets` and resets the flag to `on`; `apply` setting `SubscriptionEntry.resetTickets` per FR-003, a per-run log-once set with the messages of contracts/texts.md, and pruning with the other per-account state (spec 033 FR-003, FR-004, FR-019); make T009 pass
- [X] T015 [US1] Add `resetCreditsURL` (init parameter with default) and `fetchResetCredits(_ credential: CodexCredential) async -> ResetTicketRead` to Sources/UsageCore/Subscription/CodexUsageClient.swift per contracts/external-sources.md, using its own ephemeral session configuration with 10 s request and resource timeouts (spec 033 FR-001, FR-005); make T010 pass
- [X] T016 [US1] Extend Sources/UsageCore/Subscription/CodexLimitsSource.swift: `live` calls `fetchResetCredits` with the already read credential after `fetch` succeeded and returns the read with `.success`; failed or skipped plan-limit requests give `.temporaryFailure("skipped")`; `lastTickets` per canonical Codex home mapped to accounts through `plan.home` (live limits on only); entries get `resetTickets`, including those built without a request in `notDue`, `blocked`, `noRequest`, `fallback` and `graceEntry` (minus expired); log-once per account and kind; pruning (spec 033 FR-001, FR-003, FR-019); make T011 pass
- [X] T017 [US1] Implement Sources/UsageCore/Dropdown/ResetTicketText.swift (`glyphTooltip`, `overflowTooltip`, `accessibilityLabel`) using `TimeText.expiry` (spec 033 FR-010, FR-011); make T012 pass
- [X] T018 [US1] Add Sources/AgentTacho/ResetTicketGlyphs.swift: renders `labelText("solid:gift")` for each of `glyphs(at: times.now).shown` and `Text("+N")` for the overflow, all in `colors.secondary`, each with its `.help` text from `ResetTicketText`; each glyph and the marker is its own plain-style button (so each keeps its own `.help`) calling one `open()` that runs `NSWorkspace.shared.open(url)` then `onOpen()`; the group is combined into one accessibility element with the label from `ResetTicketText.accessibilityLabel` and an "Open usage page" action that calls the same `open()`; renders nothing for no usable tickets (spec 033 FR-008 to FR-012)
- [X] T019 [US1] Wire the glyphs in Sources/AgentTacho/DropdownView.swift: add `@Environment(\.dropdownColors)` to `SubscriptionSection`, place `ResetTicketGlyphs` right after `Text(account.displayName)` in the Claude header (`AppLinks.claudeUsagePage`) and in the `CodexPlanSection` header (`AppLinks.codexUsagePage`); give the name `.lineLimit(1)` with lower layout priority than the glyphs and the headline; pass a closure `{ panel?.close() }` from `DropdownView` down to both sections (spec 033 FR-008, FR-010a, FR-013, edge case "Long account name")
- [X] T020 [US1] Demo: add `ScenarioTicket { expiresIn: ScenarioDuration? }` and `ClaudeWindows.tickets` in Sources/DemoMode/Scenario.swift (validated like the other durations), fill `resetTickets` in `DemoSubscriptionSource` in Sources/DemoMode/DemoSources.swift relative to the scenario clock, give `acc-max` two tickets (`expiresIn: "2d4h"` and one without) in Resources/demo/default.json, add coverage fields `resetTicketsWithExpiry` and `resetTicketsWithoutExpiry` in Sources/DemoMode/ScenarioCoverage.swift and the test `defaultScenarioShowsResetTickets` in Tests/DemoModeTests/DefaultScenarioTests.swift; `demoFilesUseInventedNamesOnly` and `defaultScenarioFiresOneAlert` stay green (spec 033 FR-021)

**Checkpoint**: `make test` green; `make app-demo` shows two glyphs on the first Claude Max header with the contract tooltips, and a click opens Claude's usage page and closes the dropdown.

---

## Phase 4: User Story 2 - Be reminded before a ticket expires (Priority: P2)

**Goal**: Two notifications per account and expiry time (3 days, 24 hours), never repeated across relaunches, never in the demo build.

**Independent Test**: Tracker tests feed tickets across both steps and a simulated relaunch (new tracker over the same store) and see exactly the expected events (spec US2, SC-003).

### Tests for User Story 2

- [X] T021 [P] [US2] Add Tests/UsageCoreTests/ResetTicketNoticeStoreTests.swift: the in-memory store round-trips; the `UserDefaults` store (on a `UserDefaults(suiteName:)` removed after the test) round-trips keys as `"<accountId>|<epoch>|<step>"` strings under `freeResetNotices` and ignores unparsable entries
- [X] T022 [P] [US2] Add Tests/UsageCoreTests/ResetTicketExpiryTests.swift for every notification row and log row of contracts/texts.md (title and body for 1 and n tickets per step, body via a `TimeText` pinned to `en_US_POSIX` and a fixed time zone for today, within a week and later, identifier format, `logMessage` for delivered and suppressed), and a sentinel that no alert text contains a token-like or identifier input
- [X] T023 [P] [US2] Add Tests/UsageCoreTests/ResetTicketExpiryTrackerTests.swift: 5 days out nothing; crossing into 3 days delivers once; crossing into 24 hours delivers once; first seen at 30 hours delivers the 3-day step only, then 24-hour later; first seen at 10 hours delivers the 24-hour step only and never the 3-day one; no-expiry tickets never notify; two tickets with one expiry give one alert with count 2; a late ticket at a delivered step gives nothing; a new tracker over the same store delivers nothing already recorded (relaunch); keys prune after expiry and for removed accounts; a renamed account keeps its keys and uses the new name; preliminary snapshots are skipped; two accounts on one login each notify; Claude and Codex entries both feed it; a clock moved backwards (now earlier than the previous observation) neither repeats a recorded step nor treats a future expiry as passed
- [X] T024 [P] [US2] Extend Tests/UsageCoreTests/PendingNotificationQueueTests.swift: expiry alerts queue, drain in order, and do not disturb crossings and credential alerts

### Implementation for User Story 2

- [X] T025 [US2] Implement Sources/UsageCore/Notifications/ResetTicketNoticeStore.swift (`ResetTicketNoticeKey`, protocol, `UserDefaultsResetTicketNoticeStore(defaults:)`, `InMemoryResetTicketNoticeStore`) (spec 033 FR-016); make T021 pass
- [X] T026 [US2] Implement Sources/UsageCore/Notifications/ResetTicketExpiry.swift (`ResetTicketExpiryStep`, `ResetTicketExpiryAlert`, `ResetTicketExpiryEvent`) with the texts of contracts/texts.md (spec 033 FR-015, FR-019); make T022 pass
- [X] T027 [US2] Implement Sources/UsageCore/Notifications/ResetTicketExpiryTracker.swift per the data-model table (spec 033 FR-014, FR-016, FR-017); make T023 pass
- [X] T028 [US2] Add the expiry list to Sources/UsageCore/Notifications/PendingNotificationQueue.swift (`drain()` returns a third element); make T024 pass
- [X] T029 [US2] In Sources/AgentTacho/NotificationPresenter.swift update the `drain()` call site for the third element and add `handle(_ events: [ResetTicketExpiryEvent])`: post `.deliver` with the alert's identifier, title and body (body formatted with a `TimeText` from the system calendar and locale) (queue while authorization is pending, "not sent (no app bundle)" log without a bundle), log `.suppressed` and delivered events with `logMessage` under source `notifications` (spec 033 FR-018, FR-019)
- [X] T030 [US2] In Sources/AgentTacho/App.swift create `resetTicketTracker = ResetTicketExpiryTracker(store: UserDefaultsResetTicketNoticeStore(defaults: .standard))` next to `credentialTracker` and feed `apply(_:)` events to the presenter inside the existing `#if !AGENTTACHO_DEMO` branch (spec 033 FR-018)

**Checkpoint**: `make test` green; with a real account a ticket inside 3 days notifies once (quickstart "Real accounts").

---

## Phase 5: User Story 3 - Turn the reminders off (Priority: P3)

**Goal**: One switch in Settings > General stops expiry notifications without touching glyphs or other notifications.

**Independent Test**: Tracker test with the switch off yields `.suppressed` and records the step; Settings shows the switch on by default below the sign-in switch.

- [X] T031 [P] [US3] Add tests in Tests/UsageCoreTests/ResetTicketExpiryTrackerTests.swift: switch off gives `.suppressed` (recorded, never delivered later after turning it on for the same step); threshold and credential trackers are unaffected (their existing tests unchanged)
- [X] T032 [US3] Add `Toggle("Notify before a free limit reset expires", isOn: $draft.notifyFreeResetExpiry)` below the sign-in toggle in the Notifications section of Sources/AgentTacho/SettingsView.swift (spec 033 FR-017)

**Checkpoint**: `make test` green; Settings shows both switches.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T033 [P] Add a no-token sentinel test in Tests/UsageCoreTests/ResetTicketsTests.swift or a new Tests/UsageCoreTests/ResetTicketNoTokenTests.swift: a stubbed Claude and Codex refresh with sentinel token and sentinel grant or credit ids leaves no sentinel in entries, logs, alert texts or the notice store (spec 033 FR-006, FR-015, FR-019, SC-004)
- [X] T034 Update README.md "Security and privacy" per research R10 (Codex row, token destinations with the query flag and the credit request with its 10 s timeout, the notice record in macOS defaults, tickets in memory only and never in `last-good.json`, requests per refresh including the single Claude repeat, tickets never redeemed, the expiry notification switch) (spec 033 FR-020)
- [X] T035 Run `rg -n "[\x{2013}\x{2014}]"` over changed files (no en or em dash) and `make test` and `make test-release`; fix until green
- [x] T036 Site pull request in the site checkout (clone with `gh repo clone AgentTacho/agenttacho.github.io` if missing): mirror the README changes in src/components/agenttacho/Privacy.astro, update the free reset tickets entry in docs/card-candidates.md (spec 033, this app pull request, status stays `planned` until merge), run `npm run check`, `npm run build`, `npm test`; open the pull request and link it from the app pull request (spec 033 FR-020, FR-022)
- [x] T038 Before submitting, confirm that [AgentTacho/agenttacho#8](https://github.com/AgentTacho/agenttacho/pull/8) and [AgentTacho/agenttacho.github.io#17](https://github.com/AgentTacho/agenttacho.github.io/pull/17) are merged (`gh pr view`); if either was rejected, add a `free-resets` stem and a card per constitution 2.0.0 and spec FR-023; after this feature merges, set its card-candidates entry to `ready` in a site pull request (spec 033 FR-022, FR-023)
- [x] T037 Ask the maintainer before capturing; then run `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho`, review `glance` and `same-provider` in both appearances (two glyphs, invented names, US formats), and add the 14 files to the site pull request (spec 033 FR-022, SC-006)

---

## Dependencies & Execution Order

- Phase 1, then Phase 2 (T003 after T002; T007 after T003).
- US1 (Phase 3) depends on Phase 2. T013 before T014; T015 before T016; T017 before T018; T018 before T019. T020 depends on T007.
- US2 (Phase 4) depends on Phase 2 (entries with tickets, configuration key) and is independent of the US1 UI; T025, T026 before T027; T029 and T030 after T027 and T028.
- US3 (Phase 5) depends on T027 (tracker) and T005.
- Polish after the stories; T036 and T037 last (T037 needs the maintainer's go).

## Parallel Opportunities

- Phase 2: T002, T004, T005, T006 together.
- US1 tests T008 to T012 together; T013/T014 (Claude) and T015/T016 (Codex) and T017 can proceed in parallel tracks.
- US2 tests T021 to T024 together.

## Implementation Strategy

MVP is US1: tickets visible with tooltips and the usage link. US2 adds the reminders, US3 the switch. Each phase ends with `make test` green.
