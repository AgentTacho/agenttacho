# Implementation Plan: Fix-Soon Review Batch

**Branch**: `015-fix-soon-batch` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/015-fix-soon-batch/spec.md`

## Summary

Seven small fixes in three groups. App correctness: `ThresholdTracker` compares the first value of a reset window against 0 (research R1); the refresh drops carried-over budget entries computed for another period, so the existing no-data presentation shows (R2); `SessionLogSource` scans Claude subscription credential directories (R3). Hardening: the OpenCode reader sets `trusted_schema=OFF` and refuses views in place of its tables (R4); the Claude usage session gets a 45 s resource timeout (R5). Release safety: preflight stops on an expired or revoked Developer ID unless `ALLOW_TIER_DOWNGRADE=1` (R6); `REPLACE=1` turns a published release into a draft before replacing assets and publishes it again afterwards (R7). The README's security and maintainer sections are updated.

## Technical Context

**Language/Version**: Swift 5.10 (swift-tools-version 5.10); Bash for the release scripts

**Primary Dependencies**: Foundation (`URLSession`), SQLite3 (system library, already used), `gh` and `security` in the release scripts; no new dependencies

**Storage**: none new (no configuration keys, no files)

**Testing**: Swift Testing via `make test` (`Tests/UsageCoreTests`); Bash release tests via `make test-release` (`scripts/release/tests`)

**Target Platform**: macOS 14 or newer, Apple Silicon

**Project Type**: desktop menu bar app (`UsageCore` library plus thin `AgentMeter` executable) and release scripts

**Performance Goals**: no change in refresh cost (one extra directory per Claude subscription account at most; two pragmas and one schema query per OpenCode read)

**Constraints**: logic in `UsageCore` with tests first; read-only on agent files; README "Security and privacy" kept true in the same pull request; no em or en dashes

**Scale/Scope**: 7 findings; about 6 Swift files and 4 script files touched, plus tests and README

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is still the unfilled template, so the project rules in `AGENTS.md` serve as the gate:

| Rule | Status |
|---|---|
| Build and test only through the Makefile | Pass: `make test`, `make test-release` |
| Logic in `UsageCore`, covered by tests, test first | Pass: tracker, snapshot filter, scan set, OpenCode reader and client configuration are in `UsageCore`; the app layer is not changed |
| Doc comments cite spec requirements | Pass: changed code cites `spec 015 FR-...` |
| No em or en dashes | Pass: checked in review |
| Read-only on agent files; Security and privacy section stays true | Pass: the OpenCode read stays read-only and gets stricter; README updated for the hardened read, both request time limits and the extra scanned directories (FR-011) |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/015-fix-soon-batch/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── release-command.md
├── checklists/requirements.md
└── spec.md
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Notifications/ThresholdTracker.swift     # R1: reset compares with 0
├── Snapshot/RefreshCoordinator.swift        # R2: call the period filter after carry-over
├── Snapshot/UsageSnapshot.swift             # R2: period filter helper
├── Logs/SessionLogSource.swift              # R3: credential directories, canonical dedup
├── Logs/OpenCodeSource.swift                # R4: trusted_schema=OFF, table check, test hook
└── Subscription/UsageEndpointClient.swift   # R5: 45 s resource timeout

Tests/UsageCoreTests/
├── ThresholdTrackerTests.swift
├── RefreshCoordinatorTests.swift (or a snapshot filter test file)
├── SessionLogSourceTests.swift
├── OpenCodeSourceTests.swift
└── UsageEndpointClientTests.swift

scripts/release/
├── lib.sh            # R6: unusable_developer_ids, preflight guard
├── build-app.sh      # R6: development build warning
├── release.sh        # R6 downgrade note, R7 draft-first replacement
└── tests/            # test_signing.sh, test_preflight.sh, test_release_flow.sh, test_makefile.sh

Makefile              # R6: export ALLOW_TIER_DOWNGRADE
README.md             # FR-011, FR-013 (maintainer section)
```

**Structure Decision**: Existing layout; no new targets. Each fix stays in the file that owns the behavior today.

## Implementation Notes

- **Order**: The three groups are independent. Within each group, write the failing test first. Suggested order: R1, R2, R3 (P1), then R4, R5, then R6, R7, then README.
- **R1 test matrix**: one test per window kind (Claude 5-hour, 7-day, Codex plan window, weekly group, monthly own budget) for "reset above threshold notifies", plus tests for the five re-baseline events and for reset plus member-set change in the same refresh (SC-001). Existing tests that assert "no notification after a window reset" change to the new rule; list them in the commit message.
- **R2**: filter `snapshot.groups` and `snapshot.accountBudgets` against `configuration.budgetOwners` after the carry-over block and before the log loop. The coordinator test drives a failing record source and a period switch.
- **R4 test**: see research R4 and T008: views in place of `message` or `session` fail the table check; a `VIRTUAL` generated `message.data` column calling a test-registered function fails with "unsafe use of" and the function never runs (SC-004); a control case on a plain connection with `trusted_schema` on shows the function would run; a normal database reads the same rows as before (FR-009).
- **R6 tests**: move `stub_identities` from `test_signing.sh` into `scripts/release/tests/helpers.sh` (T014) and reuse it; change `test_expired_developer_id_falls_through_to_self_signed` and `test_revoked_developer_id_falls_through_to_self_signed` so that `select_identity` still returns self-signed (selection is unchanged) and new preflight tests expect the stop, the dry-run warning, the opt-out warning, the forced `SIGN_IDENTITY` pass and the ad-hoc case.
- **R7 tests**: extend `test_release_flow.sh` with a published release and `REPLACE=1`: the recorded `gh` calls must show `--draft=true` before any upload, and on an upload failure no `--draft=false` call; every publish passes `--latest` or `--latest=false` by version (research R7), including a retry of an older draft.
- **R1 detail**: only a later known end counts as a reset for subscription and Codex windows, and an earlier known end is ignored as older data (research R1), so Codex live and snapshot values that disagree notify at most once.

## Complexity Tracking

No violations.
