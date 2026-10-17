# Contract: The name check

Spec FR-026, SC-003. Run by `make test-release` as `scripts/release/tests/test_names.sh`, so a leftover "AgentMeter" fails the build's tests.

## What it searches

`rg -i -n 'agentmeter|agent meter'` over the tracked files (`git ls-files`), excluding `specs/`, `brainstorm/` and `docs/superpowers/`.

## Allowed matches

Each allowed match is listed in `scripts/release/tests/names-allowlist.txt` as `path:pattern`, one per line, with a comment (`  # FR-0xx`) saying which requirement needs it. The pattern is an extended regular expression, case-sensitive. For each matching line, every entry for that file is removed from the line, and what is left must not name the old name, so an allowed phrase cannot hide another use on the same line. Expected entries:

| Path | Why |
|---|---|
| `Sources/UsageCore/Config/Paths.swift` | legacy folder paths (FR-008) |
| `Sources/UsageCore/RunningInstance.swift` | legacy bundle identifier and its app name (FR-012) |
| `Sources/AgentTacho/SingleInstance.swift` | legacy bundle identifier query (FR-012) |
| `Sources/UsageCore/Config/LegacyDataMove.swift`, `Sources/AgentTacho/App.swift` | the move's log lines and doc comments (FR-008, FR-011, FR-012) |
| `Tests/UsageCoreTests/PathsTests.swift` | legacy folder fixtures (FR-008) |
| `Tests/UsageCoreTests/LegacyDataMoveTests.swift`, `Tests/UsageCoreTests/RunningInstanceTests.swift` | fixtures for the above |
| `scripts/release/update-cask.sh`, `scripts/release/tests/test_cask.sh` | old cask file and rename entry (FR-016) |
| `README.md` | "formerly AgentMeter", moving instructions, the redirect warning (FR-022, FR-023) |
| `scripts/release/tests/test_names.sh`, `scripts/release/tests/names-allowlist.txt` | the check itself |

## Result

- Every match is allowed: `names: ok (<n> allowed matches)`, exit 0.
- Any other match: one line per match (`path:line: text`), then `names: <n> leftover(s) of the old name`, exit 1.
- An allowlist entry that matches nothing: `names: stale allowlist entry <entry>`, exit 1 (keeps the list honest).
