# Tasks: About Tab Update Layout

**Input**: Design documents from `specs/020-about-tab-update-layout/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/settings-ui.md, quickstart.md

**Tests**: No new behavior in `UsageCore` and no `UsageCore` code change (research R2: `Signing.text` stays for the diagnostic log). The existing suite must stay green; the layout is checked by hand (quickstart.md). SC-003 holds by construction: the status line reuses `UpdateStatusText`, `UpdateButtons` and the `UpdateState` texts unchanged.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

No setup: no new files, targets or dependencies.

## Phase 2: Foundational

- [X] T001 Reword the `AppVersionInfo` doc comment in Sources/UsageCore/AppVersionInfo.swift: build-app.sh stamps the release data shown on the About tab (commit, build date, release tag), and the signing tier and notarization, which the update policy and the diagnostic log read (spec 020 FR-002). Do not change `Signing` or `Signing.text` (used by `InstallContext.logSummary` in Sources/UsageCore/Update/UpdatePolicy.swift).

## Phase 3: User Story 1, a quieter About tab (P1)

**Goal**: About shows Version, Commit, Built; a centered "Check for Updates…" button with the status line(s) below it; no heading, no toggle, no Signing row.

**Independent Test**: quickstart.md steps 2 and 3.

- [X] T002 [US1] In Sources/AgentTacho/AboutSettingsTab.swift remove the `if let signing = info.signing { row("Signing") ... }` row from `releaseGrid` (FR-002).
- [X] T003 [US1] In Sources/AgentTacho/AboutSettingsTab.swift rewrite `updates`: a `VStack(spacing: 6)` with `Button("Check for Updates\u{2026}") { updater.checkNow(from: .settings) }.disabled(state.isInstallRunning)` first (keep its comment about FR-003), then the status `HStack` (`UpdateStatusText` with `settingsText`, `truncates: false`, plus `UpdateButtons`), then the optional `display.settingsKnownUpdate` `HStack`, as today. Put `.foregroundStyle(.secondary)` on each `UpdateStatusText` (not on the `HStack`, so `UpdateButtons` keeps its link color); body font size. Keep `.multilineTextAlignment(.center)` and `.frame(maxWidth: 520)`. No `Text("Updates")` heading and no toggle. Update the doc comment to cite spec 020 FR-003 to FR-007 alongside spec 013 FR-003, FR-007a, FR-011.
- [X] T004 [US1] In Sources/AgentTacho/AboutSettingsTab.swift remove the `@Binding var draft: Configuration` property and its doc comment, and update the type's doc comment (release data without signing, the update check without its setting). In Sources/AgentTacho/SettingsView.swift change the call site to `AboutSettingsTab(updater: model.updater)` and its comment ("Last: release data, links and the update check.").

**Checkpoint**: `make test` passes; `make app` shows the new About tab.

## Phase 4: User Story 2, the automatic check in General (P1)

**Goal**: "Updates" section with the toggle after "Launch" in General.

**Independent Test**: quickstart.md step 4.

- [X] T005 [US2] In Sources/AgentTacho/SettingsView.swift, `GeneralSettingsTab.body`, add directly after `Section("Launch") { ... }` a section with a short comment citing spec 020 FR-008, FR-009: `Section("Updates") { Toggle("Check for updates automatically", isOn: $draft.checksForUpdates) }`.

**Checkpoint**: `make test` passes; the toggle round-trips through apply and relaunch.

## Phase 5: Polish & documentation

- [X] T006 [P] Update specs/013-auto-update/spec.md and specs/013-auto-update/RUNBOOK.md (spec 020 FR-011): FR-002 (spec line 163) says "in Settings > General"; FR-011 (line 176) ends "together with the "Check for Updates…" button; the toggle is in Settings > General (spec 020)"; User Story 4 narrative (line 101) says "in Settings > General"; acceptance scenario 1 (line 109) says "opens Settings > General"; RUNBOOK line 122 reads "Open Settings > About and look at the status under "Check for Updates…"", line 124 drops "and the toggle "Check for updates automatically"", and the step "Do" item 1 (line 266) says "Settings > General: turn off ...". Leave spec 013 research.md and tasks.md as historical records.
- [X] T007 [P] Update specs/013-auto-update/contracts/update-ui.md: the "Settings > About" section (no "Updates" heading, `Check for Updates…` button above the status, status in secondary text, no toggle) and a new "Settings > General (spec 020)" section with the toggle "Check for updates automatically" (default on), saved to `checksForUpdates`.
- [X] T008 [P] Update README.md (FR-012): line 55, "Turn off "Check for updates automatically" in Settings > General"; line 108, "like the toggle in Settings > General"; line 116 (General bullet), insert "the automatic update check" after "start at login"; line 122 (About bullet), "version and build number, the commit it was built from and build date" without signing, and "the update status with "Check for Updates…"" without the toggle; line 190, "Turn the automatic check off in Settings > General"; line 254, say `AgentTachoSigning` and `AgentTachoNotarized` are read by the updater, the other stamps are the release data for the About tab.
- [X] T009 Run `make test` and `make app`; run `rg -n "Settings > About" README.md specs/013-auto-update/spec.md specs/013-auto-update/contracts/update-ui.md specs/013-auto-update/RUNBOOK.md` and confirm no passage places the toggle or the signing tier in About; confirm `git diff main | rg "[\x{2013}\x{2014}]"` prints nothing.

## Dependencies & Execution Order

- T001 is independent of the views.
- T002, T003, T004 edit the same file: in that order. T005 shares SettingsView.swift with T004: after it.
- T006, T007, T008 are independent documents [P], after the code tasks so the docs describe what was built.
- T009 last.

## Parallel Example

```text
T006, T007 and T008 can run together: different documents.
```

## Implementation Strategy

Both stories are P1 and ship together: moving the toggle out of About (US1) without adding it to General (US2) would leave the automatic check without a switch. Do Phases 2 to 4, check with `make test`, then the documents.
