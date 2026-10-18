# Contract: scenario file

Location: `Resources/demo/<name>.json`, copied into `AgentTacho Demo.app/Contents/Resources/demo/` by `make app-demo` only. Selected with the launch argument `-demoScenario <name>` (default `default`).

```json
{
  "name": "default",
  "configuration": { "version": 1, "accounts": [], "groups": [] },
  "importedPrices": { "batches": [] },
  "claude": {
    "acc-max": {
      "plan": "max",
      "fiveHour": { "used": 58, "resetsIn": "2h" },
      "sevenDay": { "used": 70, "resetsIn": "3d12h" }
    }
  },
  "codex": {
    "acc-codex": {
      "plan": "plus",
      "windows": [
        { "lengthMinutes": 300, "used": 40, "resetsIn": "1h30m" },
        { "lengthMinutes": 10080, "used": 60, "resetsIn": "3d12h" }
      ]
    }
  },
  "usage": [
    { "at": "-2d3h", "account": "acc-vertex", "harness": "openCode",
      "model": "claude-sonnet-5", "project": "~/src/checkout-service",
      "input": 182000, "output": 21000, "cacheRead": 940000, "cacheWrite": 64000 }
  ],
  "frames": [
    { "at": "12s",
      "usage": [ { "at": "-1m", "account": "acc-openai-company", "harness": "codex",
                   "model": "gpt-5.5", "project": "~/src/billing",
                   "input": 900000, "output": 120000, "cacheRead": 0, "cacheWrite": 0 } ] }
  ]
}
```

Rules:

- `configuration` is exactly the format of `config.json` and is written to the demo's `config.json` at launch (FR-009). Its accounts set `thresholds` explicitly; `credentialDirectory` and `codexHome` are never read by the demo build.
- `importedPrices` is exactly the format of `imported-prices.json` and is written at launch.
- Durations: `[-]` followed by `Nd`, `Nh`, `Nm`, `Ns` in this order. `resetsIn` and frame `at` are positive; usage `at` is negative.
- Frame `claude` and `codex` entries change only the fields they name. Frame `usage` entries are added from that frame on; their `at` is relative to launch like all others.
- Names are invented. The loader test rejects "Red Hat" in any spelling and email-shaped strings anywhere in the file (FR-015).
- A file that fails to parse or validate is reported with its JSON path, for example `frames[0].claude.acc-max.sevenDay.used: expected a number from 0 to 100`.
