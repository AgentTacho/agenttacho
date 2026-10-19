# Quickstart: Section Bands

1. `make test`: `SectionBandsTests` (stripe sequence, Unassigned on and off, zero and one section, strength order in both contrast modes) and `DefaultScenarioTests` (stripes plain, tinted, plain, tinted for the `default` scenario) pass.
2. `make app-demo`, open the dropdown: no divider lines; the Codex and Side sections sit on a faint full-width band; the footer has a slightly stronger band down to the bottom edge.
3. Hover a non-headline row of the Codex section (tinted): the hover highlight and `○` are visible.
4. Expand a few Details until the sections scroll: the footer band stays pinned, section bands scroll above it.
5. System Settings > Accessibility > Display > Increase contrast: the bands get stronger while the dropdown is open; turn it off again.
6. Screenshots: ask the maintainer, then `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho` (AGENTS.md steps 4 to 8).
