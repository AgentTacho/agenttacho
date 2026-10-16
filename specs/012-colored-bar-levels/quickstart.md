# Quickstart: Validate Colored Bar Levels

## Automated

```bash
make test
```

Covers: decision table of `contracts/bar-rendering.md` for all six setting combinations, three levels, fresh and stale (SC-003); pill contrast for the four appearance conditions (SC-004); configuration decoding with missing, known and unknown values, write-back on save, load notes (SC-005, FR-003); accessibility text (SC-006).

## Manual (walkthrough)

Prerequisites: `make app`, run the built app, at least one entry shown in the bar. To force levels, lower an account's or group's budget (or thresholds) in Settings so its percent passes the warning threshold and 100%.

1. Default settings, entry at a warning level: value orange, icon neutral, no `⚠`, entry width unchanged (SC-001).
2. Entry over 100%: value red.
3. No entry at a level: compare with the previous release side by side in light, dark, tinted menu bar, inactive secondary display, Reduce transparency, Increase contrast (SC-002).
4. Toggle System Settings > Appearance between Light and Dark with a level shown: the bar updates within a second (SC-007).
5. Open the dropdown: the highlighted bar entry stays readable (FR-015).
6. Menu Bar tab: switch Level color to Pill: rounded orange or red background, readable text; preview matches.
7. Check "Mark levels with ⚠ / ‼" with each Level color choice.
8. Level color Off, symbols off: the note appears; the bar shows no level; a threshold notification still arrives.
9. VoiceOver (Cmd-F5) on the bar item: entries at a level are read with "warning" or "over limit".
10. Put `"levelColor": "rainbow"` into `~/.config/agentmeter/config.json`: bar uses colored text, the log (`~/Library/Logs/agentmeter/usage.log`, or Settings > Log) has a `config` note, no problem notice appears.
