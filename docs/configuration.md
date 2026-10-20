# Configuration

Everything lives in one JSON file, `~/.config/agenttacho/config.json`. The settings window (the Settings icon at the bottom of the dropdown, or ⌘,) writes it, and you can edit it by hand. The app picks up changes at the next refresh. If the file is invalid, the dropdown says so and the last valid configuration stays active.

```json
{
  "version": 1,
  "refreshIntervalSeconds": 300,
  "adaptiveRefresh": true,
  "codexHomes": [],
  "openCodeDirectories": [],
  "accounts": [
    { "id": "acc-max", "type": "subscription", "icon": "brands:claude",
      "displayName": "Claude Max", "credentialDirectory": "~/.claude",
      "shownInBar": true, "thresholds": [80, 100], "headlineWindow": "fiveHour" },
    { "id": "acc-vertex", "type": "tokenBased", "icon": "brands:google",
      "displayName": "Claude Code via Vertex", "provider": "vertex",
      "groupId": "grp-vertex", "shownInBar": false },
    { "id": "acc-own", "type": "tokenBased", "icon": "brands:google",
      "displayName": "Personal Vertex", "provider": "vertex",
      "budget": { "period": "monthly", "budgetUSD": 100, "shownInBar": true, "thresholds": [80, 100] } },
    { "id": "acc-oai", "type": "tokenBased", "icon": "brands:openai",
      "displayName": "OpenAI API", "provider": "openai",
      "budget": { "period": "monthly", "budgetUSD": 50, "shownInBar": true, "thresholds": [80, 100] } },
    { "id": "acc-codex", "type": "codexSubscription", "icon": "brands:openai",
      "displayName": "ChatGPT Plus", "codexHome": "~/.codex",
      "shownInBar": true, "thresholds": [80, 95], "liveLimits": true }
  ],
  "groups": [
    { "id": "grp-vertex", "name": "Vertex", "icon": "solid:wallet",
      "period": "monthly", "budgetUSD": 400, "shownInBar": true, "thresholds": [80, 100] }
  ]
}
```

`checksForUpdates` (default `true`) turns the automatic update check on or off, like the toggle in Settings > General.

The optional `arrangement` key holds the order of the bar and the dropdown: `entries` lists the top-level entries as `{ "kind": "account" | "group", "id": "..." }`, and `members` maps each group id to its member account ids in order. The key is absent until you first change the order (or add, move or remove an account or group in a way that affects it); until then the bar shows accounts first, then groups. Unknown or misplaced ids are ignored and missing entries are added at the end, so a hand edit never makes the file invalid.

Every account and group takes an optional `timeFormat` for its section in the dropdown: `"relative"` (the default) reads reset and run-out times as "resets in 2h 26m" or "runs out in 2d 13h", `"absolute"` as "resets 17:20" today, "resets Fri 09:00" within the next six days, and with the date further out. Hovering a time shows the other form. It changes only the dropdown, not the bar or notifications. A token-based account in a group uses its group's format and keeps its own value for when it gets its own budget again. An unknown `timeFormat` value reads as `"relative"` and is noted in the log.

Claude and Codex subscription accounts take an optional `headlineWindow`: the window the bar and the account's section header follow, set by clicking a window row in the dropdown. For a Claude subscription it is `"fiveHour"`, `"sevenDay"` or `"model:<model name>"` (for example `"model:Fable"`, matched exactly, including case); for a Codex plan `"window:<name>"` with the window's name from the dropdown, such as `"window:5-hour"`, `"window:weekly"` or `"window:30-day"`. Without it the bar shows the 7-day window or the plan's longest window. A model limit or plan window the provider no longer reports falls back to that default until it is back. An unknown value, or one for the other account type, is ignored and noted in the log; the next save drops it.

The optional `levelColor` key sets how the bar shows levels: `"text"` (the default) colors the value orange at the first threshold and red at the second one or at a real limit, such as 100% or a reached Codex limit, `"pill"` draws the entry on an orange or red background, and `"off"` uses no color. `showLevelSymbols` (default `false`) adds the `⚠` and `‼` symbols. An unknown `levelColor` value falls back to `"text"` and is noted in the log.

The optional `displayDirection` key sets how limits and budgets read, like **Show usage as** in Settings > General: `"used"` (the default) counts up from 0% to 100%, `"remaining"` counts down from 100%. Thresholds are stored in used percent either way, so a first notification shown as "20% left" is stored as 80, and switching never changes when a notification fires. An unknown value reads as `"used"` and is noted in the log.

## Settings tabs

The settings window has seven tabs:

- **General**: refresh interval (default 5 minutes, minimum 1 minute), which subscription account sets the weekly window, the fallback weekday and hour (both apply to weekly budgets, of groups or of accounts with their own budget, and to Unassigned only), start at login, whether usage reads as used or remaining (**Show usage as**), the automatic update check, whether a sign-in that stops working is notified, and extra locations to read: Claude Code directories, Codex homes and OpenCode data directories. With **Adapt refresh** on (the default), opening the menu refreshes values that are more than a minute old, plan limits are checked less often while no agent writes new usage, and the whole refresh slows down while you are away, in Low Power Mode or when the Mac runs hot. Plan limits are still checked at least every 30 minutes (or at the refresh interval, if that is longer), and hovering "Last refreshed" in the dropdown says why and when the next check is due. Turn it off to go back to the fixed interval.
- **Menu Bar**: the order of the bar entries, which the dropdown sections follow too, with a live preview of the bar. Drag a row, or select it and use Move Up and Move Down (Option-Command-Up and Option-Command-Down Arrow). A group's members are listed under it and move with it; they can be reordered only within their group. Each row has a "Show in bar" checkbox, the same setting as the toggle in the account or group editor. "Level color" (Text, Pill or Off) and "Mark levels with ⚠ / ‼" set how warning and over-limit levels look; with Off and no symbols, levels no longer appear in the bar. "Show ↗ or ↑ when an entry will run out before it resets" turns both markers on or off; the dropdown's bars and notes stay.
- **Accounts**: display name, icon, the credential directory for subscription accounts, the Codex home, whether the account shows in the bar, notification thresholds (checked for every plan window) and live limits for Codex subscription accounts, an optional custom marker for telling apart two accounts of the same kind, and "Times" (Relative or Absolute) for how the account's section in the dropdown reads its reset and run-out times. A token-based account has a provider (Vertex or OpenAI) and a budget: either its own (period, amount, whether it shows in the bar, notification thresholds, Times) or a budget group. A group member can show its share of the group budget in the bar.
- **Groups**: name, icon, period (weekly or monthly) and budget, whether the group shows in the bar, notification thresholds, and Times (Relative or Absolute) for the group's section in the dropdown. Add creates a group called "Budget group" (weekly, 60 USD, shown in the bar, thresholds at 80% and 100%) that you then edit. Remove asks first; if the group still has accounts, you pick where they go: each to its own budget with the group's settings, or all into another group. Membership itself is set in each account's Budget picker.
- **Prices**: prices in USD per million tokens, with their source, your own overrides and extra models, and an Import menu (see [Prices](prices.md)).
- **Log**: the newest 500 lines of the diagnostic log, refreshed after every refresh, with buttons to reload it, show it in Finder or open it in Console. The log stays within 5 MB: at 2.5 MB it moves to `usage.log.1` and a new file starts.
- **About**: the running build (version and build number, the commit it was built from and build date), the update status with "Check for Updates…", what changed since the previous release with a link to the release notes, and links to the GitHub repository, the issue tracker and the [sponsor page](https://github.com/sponsors/rhuss). "Your credentials" opens a short summary of the credentials AgentTacho reads (details in [Security and privacy](../README.md#security-and-privacy)).

## Icons

Every account and group has one [Font Awesome Free](https://fontawesome.com) icon, chosen from a searchable picker. New entries start with a default: the Claude icon for subscriptions, the Google icon for Vertex accounts, the OpenAI icon for OpenAI and Codex subscription accounts, and a wallet for groups. Several entries may share an icon; the dropdown and settings show each icon next to its name. Older configuration files with text labels still load: the labels are ignored and entries without an icon get the default.
