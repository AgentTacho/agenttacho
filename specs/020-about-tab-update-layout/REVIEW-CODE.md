# Code Review: About Tab Update Layout

**Spec:** specs/020-about-tab-update-layout/spec.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 12/12 (100%)
- Edge Cases: 6/6 (100%)
- Acceptance Scenarios: 12/12 (100%) by code inspection. They concern SwiftUI layout and the existing update logic, so they are walkthrough items; the update states and `checksForUpdates` are covered by existing UsageCore tests.
- Success Criteria: SC-001 and SC-003 hold by code inspection, SC-002 is a walkthrough check, SC-004: `make test` passes (1369 tests in 133 suites) and the configuration format is unchanged.

## Detailed Review

### Functional Requirements

| FR | Implementation | Status |
|----|----------------|--------|
| FR-001 no "Updates" heading in About | `AboutSettingsTab.updates`: the `Text("Updates")` heading is gone | Compliant |
| FR-002 no signing tier in About; stamp kept and used for the install action | `releaseGrid` has no Signing row; `AppVersionInfo.signing` still parsed and passed through `InstallEnvironment` to `UpdatePolicy` (`signing == .developerID(notarized: true)`) | Compliant |
| FR-003 centered button below release data, status directly below, centered, wrapping | `body` order header, updates; `updates` is a `VStack` (center alignment) with the button first, then the status `HStack`; `.multilineTextAlignment(.center)`, `UpdateStatusText(truncates: false)` uses `fixedSize(horizontal: false, vertical: true)` | Compliant |
| FR-004 body-size secondary text, links keep link style, same wording and actions | `.foregroundStyle(.secondary)` on `UpdateStatusText` only (body font unchanged); `UpdateButtons` keep `.buttonStyle(.link)`; `settingsText` and `UpdateButtons` unchanged | Compliant |
| FR-005 known update as a second status line with actions | `display.settingsKnownUpdate` rendered below the first line with `UpdateButtons` | Compliant |
| FR-006 button disabled while an install runs; result in Settings only | `.disabled(state.isInstallRunning)`; `checkNow(from: .settings)` | Compliant |
| FR-007 no toggle in About | toggle and `draft` binding removed from `AboutSettingsTab`; `SettingsView` passes only `updater` | Compliant |
| FR-008 "Updates" section directly after "Launch" in General | `GeneralSettingsTab`: `Section("Updates")` between `Section("Launch")` and `Section("Notifications")` | Compliant |
| FR-009 same stored setting through the Settings draft | `Toggle(..., isOn: $draft.checksForUpdates)`; the draft is applied by `SettingsView.scheduleApply/applyNow` like every General setting | Compliant |
| FR-010 dropdown line, gear menu and update logic unchanged | no changes to `UpdateViews.swift`, `DropdownView`, `Updater` or `Sources/UsageCore/Update/*` | Compliant |
| FR-011 spec 013 updated | spec 013 US4 narrative, scenario 1, FR-002, FR-011; `contracts/update-ui.md` Settings > About and new Settings > General section; RUNBOOK steps | Compliant |
| FR-012 README updated in every passage | usage paragraph, `checksForUpdates` reference, About and General tab overview, Security and privacy update bullet, release data paragraph (signing read by the updater, not shown) | Compliant |

### Edge Cases

| Edge case | Status |
|-----------|--------|
| Development build shows button and status as before | Compliant (`settingsText` unchanged) |
| Build without stamped data shows only rows it has; no Signing row | Compliant |
| Long error wraps under the button, centered, not truncated | Compliant (`truncates: false`, center alignment, `frame(maxWidth: 520)`) |
| Automatic checks off: status keeps today's wording | Compliant (no change to `settingsText`) |
| Smallest window: fits or scrolls | Compliant (content only removed; `ScrollView` kept) |
| Hand edit vs. draft while Settings is open | Compliant (existing `onChange(of: model.configuration)` reload rule) |

### Extra Features (Not in Spec)

None. The `AppVersionInfo` change is a doc comment update.

### Spec-Declared Constants

The spec has no `## Constants` section; check skipped.

## Code Quality Notes

The change removes more than it adds. Doc comments cite spec 020 FRs as AGENTS.md requires. No em or en dash characters in the changed code or docs.

## Deep Review Report

**Gate: PASS** (no fix round needed). Details: [review-findings.md](review-findings.md).

| Agent                   | Found | Fixed | Remaining | Status |
|-------------------------|-------|-------|-----------|--------|
| Correctness             | 0 | 0 | 0 | completed |
| Architecture & Idioms   | 2 | 0 | 2 (1 Minor, 1 Notable) | completed |
| Security                | 0 | 0 | 0 | completed |
| Production Readiness    | 0 | 0 | 0 | completed |
| Test Quality            | 0 | 0 | 0 | completed |
| Goal Alignment          | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external)   | 0 | 0 | 0 | completed |
| Copilot (external)      | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external)        | 0 | 0 | 0 | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed (1369 tests) |
| **Total**               | **2** | **0** | **2** | |

MVP: Architecture & Idioms (2 findings)

Remaining findings (none Critical or Important):
- FINDING-1 (Minor): the two status lines in `AboutSettingsTab.updates` duplicate the same `HStack`; a shared helper would keep FR-004 styling in one place.
- NOTABLE-1: `AppVersionInfo.Signing.text` now only feeds the update log summary; captured to `brainstorm/idea-inbox.md`.

Post-fix spec coverage: 12/12 requirements verified (no fix loop ran).

## Conclusion

The implementation matches spec 020 in every functional requirement and edge case. Tests and the app build pass. Ready for the walkthrough and the final gate.
