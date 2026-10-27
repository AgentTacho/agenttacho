# Quickstart: validating spec 037

## Automated

```bash
make test           # UsageCoreTests and DemoModeTests
make test-release   # shell tests, including the screenshot stems
```

Key suites (new or extended):

- `SessionProfileTests`: detection of a shape line naming one, none or two configured directories; `~` and symlinked configuration directories; a shape line whose marker text must not leak (SC-004).
- `AttributionTests` / new `ProfileAttributionTests`: three profiles sharing one `projects` folder (SC-001, US1 scenarios 1 to 7); harness filtering; custom before presets; `none`; restriction to claimants of a shared directory.
- `LogIndexTests`: profile carried to appended lines; first shape line arriving later re-reads the file; candidate key change evicts only files that can change; unchanged files read zero times (SC-005).
- `MatchRuleTests`, `MatchRuleTextTests`: presets and fields per harness, defaults, case sensitivity, invented examples only.
- `ConfigurationTests`: new form round trip; legacy Vertex, OpenAI and marker migration; lenient reading; validation of blank custom text (SC-003).
- `MatchOverlapTests`: the pair table of SC-006.
- `DefaultScenarioTests`: every usage entry's harness equals its account's harness; the company group keeps all three harnesses.

## Manual (walkthrough)

1. Build a test home with three profile folders whose `projects` link to one shared folder, with fixture session files whose shape lines name each profile (`~/agent-profiles/personal/claude`, `.../work/claude`, `.../lab/claude`).
2. Configure a Claude subscription, a Vertex account and a custom-rule account (`Model` starts with `intranet/`) with those directories; refresh.
3. Expect each account to show only its profile's usage, Unassigned empty, and the diagnostic log line `profile named 3, none 0`.
4. Give two Vertex accounts the same directory: both show the overlap warning; change one directory: the warning disappears.
5. Load a configuration from before this feature: accounts migrate, the log names each once, and the next save writes `harness` and `matchRule`.

## Screenshots

After the maintainer's go: `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho`; review `budget` and `harnesses` in both appearances (the company group shows the extra member line).
