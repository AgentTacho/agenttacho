# Quickstart: Pace Forecast

## Automated

```bash
make test
```

Expected: the new `PaceTests` suite (computation, band, hold back, exclusions, summary text, spec examples) and the extended `BarLayoutTests` and `ConfigurationTests` pass with the rest of the suite.

## By hand

1. `make app` and launch the built app with at least one Claude subscription and one budget configured.
2. Open the dropdown. Each 5-hour, 7-day, model limit, Codex window and budget row with data ends in a pace meter: a tick alone for on pace, a bar left of the tick for behind, right of it for ahead; hovering shows "on pace", "N% ahead" or "N% behind".
3. For an entry clearly ahead (more than 5 points) and more than 10% into its window, the meter is orange and its tooltip ends with "· runs out <time>", and the bar shows `↗` after its value unless it is already at its warning threshold.
4. Open Settings, Menu Bar tab. The preview shows the same marker. Turn off "Mark entries projected to run out before reset": the marker disappears from the preview and, after applying, from the bar; the dropdown is unchanged. Undo restores it.
5. Check with VoiceOver (or Accessibility Inspector) that an entry with the marker reads "projected to run out before reset".
6. Confirm the diagnostic log shows no new requests and no new files were written.
