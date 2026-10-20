# Quickstart: Site Reframe Screenshots

## Automated checks

```bash
make test           # BarLayout shot accounts, demo coverage (two Claude Max accounts, calm second, bands)
make test-release   # capture order, fill_crop geometry and failures, 14 files, no notification setup
```

Expected: both pass.

## Demo build by hand

```bash
make app-demo
```

Open the dropdown: "Claude Max · Work" then "Claude Max · Personal" at the top, the second at 20% and 35% with no pace note; the bar shows five entries.

## Capture (maintainer's go-ahead required)

The run quits AgentTacho, switches the appearance twice and moves the mouse.

```bash
scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho
```

Expected: 14 lines `<stem>-<appearance>.webp WxH`, exit 0, no notification prompt needed. Open `glance-*` and `same-provider-*` in both appearances: equal margins, nothing cut, readable names and percentages ([contract](contracts/capture-stems.md)).
