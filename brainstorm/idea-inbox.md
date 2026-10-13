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

### harness-adapter-seam

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: The stored harness value is never read; scanner, parser and attributor have no seam keyed by harness.

> FR-017 holds at the data-model level; a second harness will need a HarnessAdapter (directory layout, record parser, built-in rules).

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

### stable-signing-identity

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 001-llm-usage-menubar
- **Summary**: The ad-hoc signature changes every build, so "Always Allow" on the keychain item stops working after each rebuild.

> A stable signing identity (SIGN_IDENTITY ?= -) makes one consent persist and stops each click from editing the harness's keychain item ACL.

> Walkthrough step 10 (2026-10-13) adds a second symptom. After a rebuild, macOS rejects notification authorization with "Notifications are not allowed for this application" and shows no prompt, so threshold banners never appear although crossings are detected. A banner was delivered once before the first rebuild. Raises the priority of this item: without it, US4 cannot be observed on a development machine.

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
