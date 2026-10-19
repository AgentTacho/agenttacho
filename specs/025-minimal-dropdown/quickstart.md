# Quickstart: checking the minimal dropdown

## Automated

```bash
make test           # UsageCore and DemoMode tests, including RowBar, TimeText, SectionNote, FooterText, config decoding, coverage
make test-release   # release script tests, including test_screenshots.sh for the changed capture steps
```

Expected: both pass; `TimeTextTests` cover every case of SC-006 with a fixed calendar (UTC), locale `en_US` and reference time.

## Demo build by hand

```bash
make app-demo
open -n "build/AgentTacho Demo.app" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario default
open -n "build/AgentTacho Demo.app" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario variants
```

Check in the default scenario:

1. Every window row has a text line and a bar; exactly the rows that are ahead with a run-out or burn fast show an orange note (SC-002).
2. No row has a pace tooltip; hovering a reset time shows the absolute date and time.
3. Dividers between sections; the Codex section has no plan line and no token line; hovering its name shows the plan.
4. "Company budget" keeps its two member lines; Details of the Claude section start with "This week: …".
5. Footer: "Last refreshed …" is the last text line; the three icons have tooltips; ⌘, opens Settings; ⌘Q quits.

Check in the `variants` scenario: the Claude section reads absolute times ("resets 17:20", "resets Fri 09:00"), hovering shows the relative form, and the one-member group has no member line.

## Settings

Open Settings > Accounts, select the Claude account, switch "Times" to Absolute: Settings applies it after a short pause and the dropdown follows; ⌘Z restores Relative; quit and relaunch: the choice is kept; `config.json` has `"timeFormat": "absolute"`.

## Screenshots (maintainer's go only)

```bash
scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho
```

Review the changed stems (plan-limits, pace, budget, details, harnesses, groups, dropdown) in both appearances, then replace `docs/images/agenttacho-dropdown.png` and open the site pull request (AGENTS.md steps 4 to 8).
