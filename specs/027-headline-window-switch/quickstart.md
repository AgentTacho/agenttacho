# Quickstart: Headline Window Switch

## Automated

```bash
make test          # UsageCore: HeadlineWindowTests, BarLayoutTests, BarPresentationTests, ConfigurationTests; DemoModeTests coverage
make test-release  # capture script stubs unchanged
```

Expected: all pass; `DefaultScenarioTests` reports tag "5h" for `acc-max` and the headline row `5-hour`.

## By hand (demo build)

```bash
make app-demo && open .build/AgentTacho-demo.app   # path as printed by make
```

1. Menu bar reads `✳ 5h 58%` for Claude Max; the dropdown's Claude section shows `●` on "5-hour" and the header `5h 58%`.
2. Hover "7-day": subtle highlight and `○`. Click it: `●` moves, header and bar read `70%` without tag.
3. Click "5-hour" on the ChatGPT Plus section: its header and bar entry read `5h 40%`; click "weekly" to return.
4. Persistence across a restart: the demo build rewrites its configuration from the scenario at every launch, so it is checked by the `ConfigStore` round trip test (T004) and, in a real build, by choosing a window, quitting and relaunching.
5. Settings, Menu Bar tab: the preview shows the same tags.
6. VoiceOver on a window row: action "Show in menu bar"; the headline row reads "shown in menu bar".
