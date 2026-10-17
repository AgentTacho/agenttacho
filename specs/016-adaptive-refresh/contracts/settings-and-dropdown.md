# Contract: Setting, Dropdown and README

## Configuration file

```json
{
  "refreshIntervalSeconds": 300,
  "adaptiveRefresh": true
}
```

- Missing key: `true`.
- `"adaptiveRefresh": "yes"` (any non-boolean): `true`. The diagnostic log gets `config: adaptiveRefresh is not a boolean, using true` when the file loads, and the configuration stays valid.
- Changing only this key causes no network refresh. The app re-arms its timer.

## Settings, General tab

The toggle sits directly below the refresh interval field:

```text
Refresh every  [300] seconds
[x] Adapt refresh
    Refresh when the menu opens; check plan limits less often while no
    agent runs, while you are away or while the Mac saves power (at most
    every 30 minutes).
```

## Dropdown footer

```text
Last refreshed 16 Oct 2026 at 14:05                       stale?
Plan limits next checked at 14:35 (no agent activity)     <- only when a pace is slower than base
<source errors>
[Refresh now]                                   [gear]
```

- Caption font, secondary color, one line; it does not wrap. "Last refreshed" keeps its current meaning.
- Opening the dropdown asks for a refresh per FR-012. While it runs, nothing changes in the footer beyond today's behavior.

## README

- Configuration section: the example JSON gains `"adaptiveRefresh": true`. The General bullet describes the toggle and the behavior in one or two sentences, including the 30-minute bound.
- "Security and privacy": the sentence "AgentTacho uses each one for a single read-only request per refresh (every 5 minutes by default), plus at most one extra request 30 seconds after ..." changes to describe:
  - at most one request per account per refresh at the configured interval;
  - fewer requests while no agent is active, you are away or the Mac saves power (at least every 30 minutes);
  - a refresh when the menu opens or you return (at most one per minute);
  - the existing retries.
