# Quickstart: Free Reset Tickets

## Automated

```bash
make test           # UsageCore and DemoMode tests, including the new ticket, tracker, text and coverage tests
make test-release   # release script tests (no new stem expected)
```

Expected: all green; `defaultScenarioShowsResetTickets` and `defaultScenarioFiresOneAlert` pass.

## Demo build (no real accounts)

```bash
make app-demo
```

1. Open the dropdown. The first Claude Max section header shows two dimmed gift glyphs after the account name, in light and dark appearance.
2. Hover the first glyph: "Free limit reset, expires in 2d 4h (<abs>)" and "Click to open the usage page". Hover the second: "no expiry".
3. Click a glyph: the default browser opens `https://claude.ai/settings/usage` and the dropdown closes.
4. Settings > General > Notifications shows "Notify before a free limit reset expires", on.
5. No expiry notification appears in the demo (only the scenario's one threshold alert).

## Real accounts (maintainer, manual)

1. Run `make app` with a Claude Pro or Max account. If Claude Settings > Usage offers "Reset for free", the dropdown shows the matching glyphs; otherwise none, and the usage figures look as before.
2. With a Codex subscription account and live limits on, compare the glyphs with the reset credits the ChatGPT usage page shows. A click opens `https://chatgpt.com/settings/usage?tab=overview`.
3. Check the diagnostic log (`~/Library/Logs/agenttacho/`) for `free reset` lines: no token, no identifier.
4. Contract details: `contracts/external-sources.md`; texts: `contracts/texts.md`.

## Screenshots (ask the maintainer first)

`scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho` writes all 14 files; check `glance` and `same-provider` show the two glyphs in both appearances.
