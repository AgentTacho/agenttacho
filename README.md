<h1><img src="Resources/icons/macos/AgentTacho.png" alt="AgentTacho app icon" width="80" align="left">AgentTacho<br><sub><sup>Every agent, every plan, one menu bar</sup></sub></h1>

I use Claude Code on a Max plan, Codex on ChatGPT Plus and Claude through Vertex AI on a company budget. AgentTacho puts all of them in the menu bar: how much of each limit or budget is used, and when it resets. You see it before a rate limit stops a session or the Vertex spend runs past its budget, without opening a single dashboard.

<br clear="left">

<p align="center">
  <img src="docs/images/agenttacho-dropdown.png" alt="AgentTacho in the menu bar with its dropdown open: a Claude Max subscription at 65% of its 7-day limit with a per-model token breakdown and a per-day trend, a Codex account on a ChatGPT Plus plan at 5% of its weekly limit, and a Vertex budget at 526% of its monthly budget" width="420">
</p>

## What it does

- **Claude Code on Pro or Max:** the real 5-hour and 7-day usage Anthropic reports, plus model limits such as Fable's.
- **Codex on a ChatGPT plan:** every plan window with its reset time, live from ChatGPT, so usage on other machines counts too.
- **Pay-per-token accounts** (Vertex AI, OpenAI API): spend in US dollars against a weekly or monthly budget you set, priced from your agents' local logs.
- **Shared budgets:** several accounts under one budget, for example a company's monthly spending limit.
- **Details on click:** usage per model, project or agent tool, with a daily trend.
- **Alerts:** a notification when usage crosses your thresholds (80% and 100% by default). In the bar, a value turns orange when it is close to the limit and red when it is over it. In the Menu Bar tab of Settings you can show levels as a pill instead, add the `⚠` and `‼` symbols, or turn the colors off. `~` means the value may be out of date, and `↗` means the entry will run out before it resets if you keep this pace. `↑` takes its place when the entry burns at least twice as fast as the remaining time allows, either on average or over the last hour, so it will run out in half the time left or sooner. In the dropdown, a small meter at the end of every limit and budget row shows whether you are on pace (a tick), behind (a bar to the left) or ahead (a bar to the right, orange when it runs out before the reset or burns fast); hover over it for the numbers and the run-out time. For an entry that burns fast, the tooltip says "burning fast" and gives the run-out time at that rate.
- **Your layout:** pick which entries show in the bar and in which order.
- **Local first:** AgentTacho reads your agents' files on this Mac. Apart from the usage checks with Anthropic and ChatGPT, it makes no network calls on its own.

It works with Claude Code, Codex and OpenCode, on macOS 14 or newer with Apple Silicon.

> [!TIP]
> AgentTacho is free and open source. If it saved you from a surprise rate limit, consider [sponsoring it on GitHub](https://github.com/sponsors/rhuss). It keeps the lights on, and the notarization paid.

## Status

A personal project, built for my own setup and shared as is. It runs on macOS 14 or newer with Apple Silicon and reads usage from three agent harnesses: Claude Code, Codex and OpenCode.

AgentTacho is not affiliated with Anthropic, OpenAI, Google or the OpenCode project. The subscription percentages come from an undocumented Anthropic endpoint that Claude Code itself uses (`/api/oauth/usage`). It can change or disappear without notice, and then the subscription rows show an error while token-based accounts keep working. The same goes for the ChatGPT usage service behind the Codex plan limits (`/backend-api/wham/usage`); when it changes, Codex subscription accounts fall back to the limits recorded in the local Codex sessions.

## Installation

AgentTacho needs macOS 14 or newer on Apple Silicon.

**Download.** Get `AgentTacho-X.Y.Z.dmg` from the [latest release](https://github.com/AgentTacho/agenttacho/releases/latest), open it and drag AgentTacho onto the Applications folder.

**Homebrew.**

```bash
brew install --cask agenttacho/tap/agenttacho
brew upgrade --cask agenttacho              # install a newer release
brew uninstall --zap --cask agenttacho      # remove the app, its configuration and its logs
```

AgentTacho runs only once. If you start a second copy (for example a build of your own while the installed app runs), it shows the running one with its version, location and process ID, and offers to stop it and start in its place, or gives you the `kill` command to stop it yourself. `brew upgrade` quits a running AgentTacho before the upgrade and opens it again afterwards. Notification permission and start at login carry over to upgrades signed with the same certificate.

**Updates.** AgentTacho checks GitHub for a newer release 5 minutes after it starts and then once a day. When one exists, a quiet line at the bottom of the dropdown says "AgentTacho X.Y.Z available", with "Release notes" and one action:

- **Install** (DMG installs in a folder you can write to, such as Applications): downloads the new DMG, verifies it, replaces the app, moves the old version to the Trash and starts the new one. Notification permission, start at login and your configuration stay as they are. "Cancel" stops it while it downloads or verifies. When the download fails or Gatekeeper cannot be reached, the line offers "Try again" next to "Release notes".
- **Upgrade with Homebrew** (installs from the cask): copies `brew upgrade --cask agenttacho` to the clipboard for you to run in a terminal. AgentTacho never runs Homebrew or changes a Homebrew install itself. The tap can take a little longer than GitHub to offer a new release.
- **Download** (everything else, with the reason): opens the release page. This is what you get when AgentTacho runs straight from the opened DMG ("Move AgentTacho to Applications to install updates"), from a folder it cannot write to, or when the downloaded release cannot be verified.

"Check for Updates…" in the gear menu and in Settings > About checks right away and shows the result where you started it: on the dropdown's line until the dropdown closes, or in Settings. Turn off "Check for updates automatically" in Settings > General to stop the daily check; AgentTacho then contacts GitHub only when you ask. Development builds (made with `make app` from a checkout that is not exactly a release tag) never check. Releases up to 0.3.1 have no updater, so install the first release with this feature by hand.

## Build and run

Requirements: macOS 14 or newer on Apple Silicon, and the Xcode Command Line Tools with Swift 5.10 or newer. There are no third-party Swift packages.

```bash
make test     # unit tests for the UsageCore library (Swift Testing)
make app      # builds build/AgentTacho.app, signed with the best available identity
make app-demo # builds build/AgentTacho Demo.app, which plays a made-up scenario for screenshots
make run      # builds and opens the app
```

Run the app bundle rather than `swift run`, because notifications and start at login need an application bundle.

`make app-demo` builds a separate app, "AgentTacho Demo.app", for screenshots. It has its own bundle identifier (`dev.rhuss.agenttacho.demo`) and its own folders (`~/.config/agenttacho-demo`, `~/Library/Logs/agenttacho-demo`, `~/Library/Application Support/agenttacho-demo`), so it runs next to an installed AgentTacho without touching that app's settings, saved values or log. Instead of reading your agents' files, it plays a made-up scenario from `Resources/demo/`. It reads no keychain item and makes no network request. Settings > About shows "Build: Demo". `make app`, `make dmg` and `make release` never build it, and a release refuses to run while the `DEMO` environment variable is set.

`make app` signs with a Developer ID certificate if there is one, otherwise with the self-signed "AgentTacho Signing" certificate (see [Releasing](#releasing-maintainer)), otherwise ad-hoc. It prints the version and the signing tier it used. With an ad-hoc signature, macOS treats every rebuild as a new app, so notification permission and start at login are lost after each build. `make app SIGN_IDENTITY=-` forces an ad-hoc signature.

On first launch, AgentTacho creates a configuration with one subscription account if Claude Code is signed in with the default configuration directory `~/.claude`. If you run Claude Code with a different directory (for example through `CLAUDE_CONFIG_DIR`), set that directory as the account's credential directory in Settings. AgentTacho also reads the session logs in each subscription account's credential directory, so you do not need to list it again under the extra Claude Code directories.

## Configuration

Everything lives in one JSON file, `~/.config/agenttacho/config.json`. The settings window (the gear menu in the dropdown, "Settings…", or ⌘,) writes it, and you can edit it by hand. The app picks up changes at the next refresh. If the file is invalid, the dropdown says so and the last valid configuration stays active.

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
      "shownInBar": true, "thresholds": [80, 100] },
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

The optional `levelColor` key sets how the bar shows levels: `"text"` (the default) colors the value orange at the warning threshold and red at 100% or above, `"pill"` draws the entry on an orange or red background, and `"off"` uses no color. `showLevelSymbols` (default `false`) adds the `⚠` and `‼` symbols. An unknown `levelColor` value falls back to `"text"` and is noted in the log.

The settings window has seven tabs:

- **General**: refresh interval (default 5 minutes, minimum 1 minute), which subscription account sets the weekly window, the fallback weekday and hour (both apply to weekly budgets, of groups or of accounts with their own budget, and to Unassigned only), start at login, the automatic update check, whether a sign-in that stops working is notified, and extra locations to read: Claude Code directories, Codex homes and OpenCode data directories. With **Adapt refresh** on (the default), opening the menu refreshes values that are more than a minute old, plan limits are checked less often while no agent writes new usage, and the whole refresh slows down while you are away, in Low Power Mode or when the Mac runs hot. Plan limits are still checked at least every 30 minutes (or at the refresh interval, if that is longer), and a line in the dropdown says why and when the next check is due. Turn it off to go back to the fixed interval.
- **Menu Bar**: the order of the bar entries, which the dropdown sections follow too, with a live preview of the bar. Drag a row, or select it and use Move Up and Move Down (Option-Command-Up and Option-Command-Down Arrow). A group's members are listed under it and move with it; they can be reordered only within their group. Each row has a "Show in bar" checkbox, the same setting as the toggle in the account or group editor. "Level color" (Text, Pill or Off) and "Mark levels with ⚠ / ‼" set how warning and over-limit levels look; with Off and no symbols, levels no longer appear in the bar. "Show ↗ or ↑ when an entry will run out before it resets" turns both markers on or off; the dropdown meters stay.
- **Accounts**: display name, icon, the credential directory for subscription accounts, the Codex home, whether the account shows in the bar, notification thresholds (checked for every plan window) and live limits for Codex subscription accounts, and an optional custom marker for telling apart two accounts of the same kind. A token-based account has a provider (Vertex or OpenAI) and a budget: either its own (period, amount, whether it shows in the bar, notification thresholds) or a budget group. A group member can show its share of the group budget in the bar.
- **Groups**: name, icon, period (weekly or monthly) and budget, whether the group shows in the bar, and notification thresholds. Add creates a group called "Budget group" (weekly, 60 USD, shown in the bar, thresholds at 80% and 100%) that you then edit. Remove asks first; if the group still has accounts, you pick where they go: each to its own budget with the group's settings, or all into another group. Membership itself is set in each account's Budget picker.
- **Prices**: prices in USD per million tokens, with their source, your own overrides and extra models, and an Import menu (see [Prices](#prices)).
- **Log**: the newest 500 lines of the diagnostic log, refreshed after every refresh, with buttons to reload it, show it in Finder or open it in Console. The log stays within 5 MB: at 2.5 MB it moves to `usage.log.1` and a new file starts.
- **About** (also "About AgentTacho" in the dropdown's gear menu): the running build (version and build number, the commit it was built from and build date), the update status with "Check for Updates…", what changed since the previous release with a link to the release notes, and links to the GitHub repository, the issue tracker and the [sponsor page](https://github.com/sponsors/rhuss). "Your credentials" opens a short summary of the credentials AgentTacho reads (details in [Security and privacy](#security-and-privacy)).

Every account and group has one [Font Awesome Free](https://fontawesome.com) icon, chosen from a searchable picker. New entries start with a default: the Claude icon for subscriptions, the Google icon for Vertex accounts, the OpenAI icon for OpenAI and Codex subscription accounts, and a wallet for groups. Several entries may share an icon; the dropdown and settings show each icon next to its name. Older configuration files with text labels still load: the labels are ignored and entries without an icon get the default.

## Accounts and budgets

Each entry in the bar is an icon and a percentage. Click it for the details.

- **Subscription accounts** (Claude Code on a Claude Pro or Max plan) show the real 5-hour and 7-day utilization that Anthropic reports, plus model-specific weekly limits such as the one for Fable. The bar shows the 7-day window. If a refresh cannot reach Anthropic, for example right after waking from sleep, the values stay as they are and AgentTacho tries once more 30 seconds later; only when that fails too are they marked stale (`~`), with the time of the last good values. If Anthropic rejects the sign-in, the values are marked stale and the dropdown says in red to run `claude` to sign in again. The last good values are saved, so after a relaunch they are back right away, even without a network, marked stale until the next successful refresh.
- **Token-based accounts** (Google Vertex AI or the OpenAI API) show spend in USD, computed from the local usage data of Claude Code, Codex and OpenCode with a built-in price table you can override, measured against a weekly or monthly budget you set. An account either has its own budget or belongs to a budget group. An account stands for who pays, not for a harness: a Vertex account collects Vertex usage from Claude Code and from OpenCode.
- **Codex subscription accounts** (Codex on a ChatGPT plan) show the plan's limits: every window of the plan (for example 5-hour and weekly on Plus, 30-day on Free) with its percent and reset time. The bar shows the longest window. The limits come live from the ChatGPT usage service, so usage on other machines and in the cloud counts too. When the service cannot be reached, AgentTacho tries once more 30 seconds later before marking anything stale. If that fails too, or the Codex sign-in has expired, the newer of the last live limits and the last limits Codex recorded on this Mac is shown, marked stale. The last live limits are saved, so they survive a relaunch. A rejected sign-in is noted in red. The dropdown also lists the tokens used through the plan this week, with the same breakdown.
- **Budget groups** put token-based accounts under one shared budget, either weekly or monthly. A weekly budget lines up with your subscription's 7-day reset, or with a weekday and hour you choose. A monthly budget runs from midnight on the 1st to the end of the calendar month in local time, which suits a company spending limit granted per month. You add and remove groups in the Groups tab. A group can be empty: it stays when its last account moves elsewhere or is removed, shows 0%, and keeps its settings and its place in the bar until an account joins it again.
- **Member shares.** A group member can also appear in the bar on its own, showing its spend as a percent of the group budget. It sits right after its group, or in the group's place when the group itself is hidden.


## How it works

- **Claude Code.** AgentTacho reads Claude Code's session files under `~/.claude/projects`, the credential directory of every Claude subscription account, and any extra directories you configure. A directory named in more than one place is read once. After the first scan it only rereads files that changed. A request id starting with `req_vrtx_` marks a Vertex session; other `req_` ids are direct Anthropic sessions.
- **Codex.** AgentTacho reads the rollout files under `~/.codex/sessions` and any extra Codex homes. Usage is the change of each session's running token total, so repeated events never count twice. A session whose rate-limit snapshot names a ChatGPT plan counts for the Codex subscription account (a subagent follows its parent session); every other session is API-key usage and counts for the OpenAI account. The same rate-limit snapshots supply the fallback for the plan limits.
- **Codex plan limits.** With live limits on (the default), AgentTacho reads the access token from `auth.json` in the account's Codex home at each refresh and asks the ChatGPT usage service for the plan's current limits, as Codex itself does. It never refreshes that sign-in: only Codex renews it while it runs. If the token has expired, or the service has already rejected it (a manual refresh tries a rejected token once more), AgentTacho makes no request and shows the newest snapshot, with a note to run Codex. Redirects are refused, so the token only ever goes to that one address. With live limits off, AgentTacho neither reads the sign-in nor contacts the service, and shows only the newest snapshot.
- **OpenCode.** AgentTacho reads `~/.local/share/opencode/opencode.db` (and any extra data directories) read-only. Code stored in the database file cannot call functions that are unsafe for untrusted files (SQLite's `trusted_schema=OFF`), virtual table modules are switched off, and `message` and `session` must be ordinary tables, not views or virtual tables. After the first read, only messages that changed are read. A database that does not pass these checks is treated like an unreadable one. Each completed assistant message counts once. Its provider decides the account: `google-vertex` goes to Vertex, `openai` to OpenAI, anything else to Unassigned unless a custom marker claims it. OpenCode's own cost estimate is ignored. If the database is busy, the previous OpenCode values stay, marked stale.
- **Breakdowns.** Every account, group and Unassigned entry can show its usage per model, per project or per harness.
- **Prices.** The built-in table is in `Sources/UsageCore/Resources/prices.json`, and imported prices and your overrides are layered on top of it (see [Prices](#prices)). A model without a price is counted as unpriced, and the total of its budget (a group or an own budget) is marked incomplete until you add a price.
- **Subscription limits.** At each refresh, AgentTacho reads Claude Code's stored login from the macOS keychain through Apple's `/usr/bin/security` tool, and asks Anthropic's usage endpoint for the current utilization. Claude Code's keychain items already trust that tool, so no keychain dialog appears.

## Prices

Spend is computed from token counts and a price table in USD per million tokens. Each model's price comes from the first of these layers that has it:

1. **Manual**: prices you enter or override on the Prices tab (stored in `config.json`).
2. **CSV**: the prices of the last CSV file you imported.
3. **Provider imports**: Anthropic, OpenAI or Google Gemini prices from LiteLLM. When two of them price the same model, the more recent import wins.
4. **Built-in**: the table shipped with the app.

The **Import** menu on the Prices tab offers:

- **Anthropic prices (LiteLLM)**, **OpenAI prices (LiteLLM, direct and Vertex)** and **Google Gemini prices (LiteLLM)**. These download LiteLLM's public price list ([`model_prices_and_context_window.json`](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json)) once, when you choose the item. Nothing is fetched in the background.
- **From CSV file…** reads a CSV file with a header row. `model`, `input` and `output` are required; `cache_write_5m`, `cache_write_1h` and `cache_read` are optional and default to 1.25, 2 and 0.1 times the input price. Commas or semicolons work as separators, and with semicolons a decimal comma (`2,50`) is accepted too. Files larger than 5 MB are rejected. A new CSV import replaces the previous one. The full format is in [`specs/002-price-import/contracts/price-csv.md`](specs/002-price-import/contracts/price-csv.md).
- **Export current prices as CSV…** writes the effective table in the same format, so you can edit it in a spreadsheet and import it again.
- **Remove … prices** for each stored import, after a confirmation that says how many models fall back to another price.

Every import shows a preview first: new, changed, removed and shadowed models (a shadowed model keeps a higher-ranked price, such as your override), plus skipped CSV rows with their line numbers. Nothing changes until you choose Apply. Applying or removing an import re-prices the session logs right away without asking Anthropic's usage endpoint again.

The table shows each row's source and, by default, only the models used in the current window plus your overrides; switch the filter to **All** to see every model. Imported prices are stored in `~/.config/agenttacho/imported-prices.json`, one batch per import kind.

## Security and privacy

To show your plan limits, AgentTacho reads the sign-in tokens of Claude Code and Codex and uses them to ask Anthropic and OpenAI for your usage. That makes it a program with access to secrets, so this section spells out what it reads, what for, and what that means for you.

### What it reads, and why

| What | Where | What for | What it keeps |
|---|---|---|---|
| Claude Code login | The macOS keychain item `Claude Code-credentials` (one per Claude Code directory), read with Apple's `/usr/bin/security` tool | Asking Anthropic for your 5-hour, 7-day and model limits | The access token and its expiry, in memory for one request. The item also holds Claude Code's refresh token, which AgentTacho discards. |
| Codex sign-in | `auth.json` in the Codex home, only for Codex subscription accounts with live limits on | Asking ChatGPT for your plan limits | The access token and account ID, in memory for one request. The refresh token and ID token are never decoded. |
| Agent session data | `~/.claude/projects` and the `projects` folder of each Claude subscription account's Claude Code directory, `~/.codex/sessions`, OpenCode's `opencode.db` (read-only, without functions that are unsafe for untrusted files, and only from ordinary tables) | Counting tokens per model, project and day | Token counts, model and project names. OpenCode's credential files are never opened. |
| System state (with Adapt refresh on) | Seconds since the last keyboard or mouse input, screen lock and display sleep, Low Power Mode and thermal state, from macOS without any permission | Slowing the refresh while you are away or the Mac saves power | Only whether you are idle, in Low Power Mode or under thermal pressure. No keystrokes or input events are read. |
| Homebrew's record of the `agenttacho` cask | The links in `/opt/homebrew/Caskroom/agenttacho` and `/usr/local/Caskroom/agenttacho` | Telling a Homebrew install apart, so updates go through Homebrew | Whether the cask's link points at the running app |

### Where the tokens go

- The Claude access token goes only to `https://api.anthropic.com/api/oauth/usage`, and the Codex token and account ID only to `https://chatgpt.com/backend-api/wham/usage`. Both requests are read-only, refuse redirects, keep no cache or cookies, and give up after 45 seconds in total, so a slow server cannot keep a token in an open request.
- With live limits turned off, AgentTacho neither reads the Codex sign-in nor contacts ChatGPT.
- Tokens are never written to the configuration, the log, notifications or any other file. AgentTacho never refreshes or changes a login and never writes to your agents' files.
- Apart from the update check below, no other server receives anything, and there is no telemetry. Besides the update check, AgentTacho downloads only two things, both without credentials and only when you ask: the update's disk image from GitHub, after you click Install (see [Updates](#updates)), and LiteLLM's price list from `raw.githubusercontent.com`, when you choose it from the Import menu.

### Updates

- **The check.** AgentTacho asks `https://api.github.com/repos/AgentTacho/agenttacho/releases/latest` for the latest published release and then downloads that release's `release-info.json` (version, DMG name, SHA-256, signing). That is two small requests 5 minutes after launch, once a day while it runs, and whenever you choose "Check for Updates…". Development builds (made with `make app` from a checkout that is not exactly a release tag) never check. Turn the automatic check off in Settings > General ("Check for updates automatically") or with `"checksForUpdates": false` in the configuration.
- **What the requests carry.** No credentials, cookies, account names, usage data or anything that identifies you or your Mac. The only identifying header is the user agent `AgentTacho/X.Y.Z`. They use HTTPS, keep no cache or cookies on disk, and follow redirects only to `api.github.com`, `github.com`, `objects.githubusercontent.com` and `release-assets.githubusercontent.com`; any other redirect stops the request.
- **Install.** Only when you click Install does AgentTacho download the DMG (at most 100 MB, from the same hosts). Before anything is replaced, it checks that the DMG matches the SHA-256 in `release-info.json`, that Gatekeeper reports the DMG as notarized, that the DMG holds exactly one app with AgentTacho's bundle identifier and the release's version, that the app's signature is valid and comes from a Developer ID certificate of the same team as the running app, and that Gatekeeper reports the app as notarized. The copy it puts in place is checked once more. If any step fails, nothing is replaced and the line offers the release page with the reason. The signature check is the real safeguard: a compromised GitHub account or release could change the checksum, but not sign with the maintainer's Developer ID.
- **What it writes.** For an update, AgentTacho writes only its own app bundle, a temporary folder (`$TMPDIR/dev.rhuss.agenttacho-update/` and a staging folder in the system's `TemporaryItems` folder on the app's volume, both removed afterwards) and the Trash, where the previous version goes. A Homebrew install is never changed: the line only copies the `brew upgrade` command.

### What it writes

AgentTacho writes only its own files: the configuration in `~/.config/agenttacho/`, the diagnostic log in `~/Library/Logs/agenttacho/`, `~/Library/Application Support/agenttacho/last-good.json`, its UI preferences (such as the last Settings tab) in the macOS defaults, and a price CSV export where you choose to save it. `last-good.json` holds, per subscription account, the last plan-limit percentages and reset times, the names of model-specific limits, the Codex window lengths and limit-reached flags, the time they were fetched, the Claude Code directory or Codex home they came from, and the Codex plan type. It never holds a token, a ChatGPT account ID or an email address; accounts are keyed by the IDs from your AgentTacho configuration. It is readable only by you (mode 0600, in a 0700 directory) and is replaced as a whole on every write. Deleting it is safe: AgentTacho writes a new one after the next successful refresh.

### What you should know

- **No keychain dialog does not mean special trust.** Claude Code's keychain item lets `/usr/bin/security` read it without asking, so any program running under your account can read that token the same way. AgentTacho does not weaken this protection, and it does not add any either.
- **The tokens are powerful.** Claude Code's access token can do what Claude Code can do with your subscription, and the Codex token can act on your ChatGPT account. AgentTacho uses each one for at most one read-only request per account and refresh, at the refresh interval (every 5 minutes by default). With Adapt refresh on, these requests come less often while no agent is active, you are away or the Mac saves power, but at least every 30 minutes (or at the refresh interval, if that is longer); opening the menu or coming back to the Mac adds a refresh, at most one request per minute. On top of that come at most one extra request 30 seconds after a refresh that could not reach the service or got a server error (HTTP 5xx), one retry when a rate limit ends, and, each time you click "Refresh now" within a minute of a request that could not reach the service, one request for each account that got no answer (a rate-limit wait still holds these back).
- **AgentTacho is not sandboxed.** The macOS App Sandbox would block reading other apps' files and keychain items, which is the whole job. It runs with your user account's access, so what it reads is limited by its code, not by macOS.
- **The usage endpoints are undocumented.** Claude Code and Codex call them themselves, and AgentTacho sends the same kind of request. Neither Anthropic nor OpenAI documents or endorses this use, and either can change it at any time.
- **A failing sign-in is notified once.** When a sign-in that worked is rejected or removed, or has been expired for a day, AgentTacho sends one notification naming the account and the command to run, never a token, and removes it once the sign-in works again. "Notify when a sign-in stops working" in Settings > General turns this off.
- **Usage data is stored in plain text.** The configuration, the saved limits in `last-good.json` and the diagnostic log at `~/Library/Logs/agenttacho/usage.log` (at most 5 MB together with its one older file `usage.log.1`, a few lines per refresh) contain account names, project names, plan limits and spend, but no credentials. The log also notes when you went idle or came back and when Low Power Mode or thermal pressure changed. Any program running as you can read them. Settings > Log shows the newest lines.
- **You trust the build.** Releases are signed with a Developer ID certificate and notarized by Apple. That proves who signed the app and that Apple's malware scan passed, not that the binary matches this source code. Releases are built on the maintainer's Mac and are not reproducible yet. To be sure, read the code and build it yourself with `make app`.

## Development

- `Sources/UsageCore`: all logic (configuration, log parsing, pricing, attribution, weekly windows, aggregation, thresholds, icon catalog), with no UI code.
- `Sources/AgentTacho`: the SwiftUI menu bar app.
- `Tests/UsageCoreTests`: Swift Testing suites with small synthetic session-log fixtures.
- `scripts/sum-vertex.sh <start> <end> [dir...]`: recomputes Vertex spend for a window with `jq`, as an independent check of the app.
- `scripts/build-icon-catalog.sh`: regenerates the bundled Font Awesome files from a pinned release, with an integrity check.
- `Sources/DemoMode` and `Resources/demo/`: the demo build. A scenario such as `default.json` holds a configuration, plan windows, usage records and timed frames, with every time relative to launch. `make test` checks that the default scenario produces each level, marker and pace state the screenshots show, plus exactly one alert. Launch the demo app with `-demoScenario <name>` to play another file.
- `scripts/screenshots/capture.sh <dir>`: writes the eleven landing page screenshots from the demo build, each in light and dark (22 WebP files). It quits a running AgentTacho, switches the system appearance for the dark pass, and puts both back when it ends, even after a failure or Ctrl-C. It needs `brew install webp imagemagick`. Before the first capture, give your terminal Accessibility, Screen Recording and Automation (System Events) permission, then run `scripts/screenshots/capture.sh --first-run <dir>` once and allow notifications for AgentTacho Demo with the Banners style. A run takes a few minutes and moves the mouse, so leave the Mac alone until it finishes.
- `scripts/release/`: the build, DMG, release and cask scripts behind `make app`, `make dmg`, `make release` and `make cask`. `make test-release` runs their tests, which use stubs and local repositories and publish nothing.
- `specs/001-agenttacho` and `docs/superpowers/specs`: the specification, plan and design notes the app was built from.

## Releasing (maintainer)

### Signing certificate (once)

Releases and local builds are signed with a self-signed code-signing certificate named "AgentTacho Signing", so macOS recognizes each new build as the same app. Create it once in Keychain Access:

1. Choose Keychain Access > Certificate Assistant > Create a Certificate.
2. Enter the name `AgentTacho Signing` exactly (no space; the build matches the name exactly and otherwise falls back to ad-hoc signing), choose Identity Type "Self Signed Root" and Certificate Type "Code Signing", and select "Let me override defaults".
3. Set the validity period to 3650 days (10 years). Keep the key pair at RSA, 2048 bits. Under Key Usage, check only "Signature"; under Extended Key Usage, keep "Code Signing". Leave Basic Constraints unchecked, uncheck Subject Alternative Name (checked by default, but code signing does not use it), and store the certificate in the login keychain.
4. Open the new certificate in the login keychain, expand Trust and set "Code Signing" to "Always Trust".

`make app` then prints `signing: self-signed (AgentTacho Signing)`. To look up a certificate with another name, pass `SIGN_IDENTITY_NAME="Other name"`. The tier `self-signed` stands for any certificate that is not a Developer ID Application certificate, so a build signed with, for example, an "Apple Development" certificate through `SIGN_IDENTITY` is also reported, released and described in the notes as `self-signed`.

To sign on a second Mac or a CI runner, export the certificate together with its private key as a `.p12` file (select both in Keychain Access, then File > Export Items, and set an export password) and import it there. Both commands ask for their password, so no password ends up on the command line or in the shell history:

```bash
security import AgentTacho-Signing.p12 -k ~/Library/Keychains/login.keychain-db \
  -T /usr/bin/codesign                  # asks for the .p12 export password in a dialog
security set-key-partition-list -S apple-tool:,apple: -s \
  ~/Library/Keychains/login.keychain-db # asks for the login keychain password in the terminal
rm AgentTacho-Signing.p12               # the private key is in the keychain now
```

The second command lets `codesign` use the key without a keychain prompt, which a release without a terminal needs. Delete the `.p12` file after the import (or keep it only in a password manager or vault): anyone with the file and its password can sign builds that macOS treats as AgentTacho. A CI runner has to pass both passwords non-interactively (`-P` and `-k`); take them from the runner's secret store, never from a value typed into a command.

### Notarization profile (once)

Releases with a Developer ID certificate are notarized with the `notarytool` keychain profile `agenttacho-notary`. Store it once. The command asks for an app-specific password for your Apple ID:

```bash
xcrun notarytool store-credentials agenttacho-notary --apple-id <apple-id> --team-id EC5BHUKA6K
```

Without the profile, `make release` stops before building and says how to store it; `ALLOW_UNNOTARIZED=1` releases without notarization on purpose. `make dmg` only warns.

### Publishing a release

```bash
make dmg                                     # dry run, works on any commit
git tag vX.Y.Z && git push origin vX.Y.Z
make release
```

`make dmg` builds `build/release/AgentTacho-<version>.dmg` and its checksum without publishing anything. Untagged or uncommitted builds get a development version such as `0.2.0-dev`, and preflight problems only print warnings.

Every build stamps its release data into `Info.plist`. `AgentTachoVersionDisplay`, `AgentTachoCommit` (full hash), `AgentTachoBuildDate` (ISO 8601, UTC) and `AgentTachoReleaseTag` (release builds only) are the release data for the About tab. `AgentTachoSigning` (`developer-id`, `self-signed` or `ad-hoc`) and `AgentTachoNotarized` (only when `make release` or `make dmg` builds with Developer ID and a working notarization profile; a dry run stamps it too but never submits) are read by the updater to choose how an update is installed, not shown on the About tab. It also bundles `Contents/Resources/changes.json`: the `feat`, `fix` and `perf` commit subjects since the previous `vX.Y.Z` tag (merges and other commit types are left out). The release notes get the same list as their "Changes" section, grouped into Features, Fixes and Performance, so write those subjects for users.

`make release` checks first and stops before building when the working tree has uncommitted changes, the repository is a shallow clone, HEAD has no `vX.Y.Z` tag, the tag is not on `origin` at the same commit, `gh` is not logged in, the GitHub release already exists, only an ad-hoc signature is available, a Developer ID certificate in the keychain is expired or revoked while no usable one exists (so the release would quietly drop to a lower signing tier), or the tap repository cannot be reached. To release on the lower tier anyway, set `ALLOW_TIER_DOWNGRADE=1`; the output then says that the downgrade was deliberate. `make app` and `make dmg` only warn about such a certificate. It then builds and signs the app, creates the DMG, notarizes it when possible, creates a draft GitHub release, uploads the DMG, its `.sha256` file and `release-info.json`, publishes the release, starts the website deploy (`deploy.yml` in `AgentTacho/agenttacho.github.io`) and updates the `agenttacho` cask in `AgentTacho/homebrew-tap`. It starts the deploy only for the latest release of `AgentTacho/agenttacho`. If starting it fails, `make release` prints a warning with the command to run by hand and carries on. Before the upload it checks that the checksum in `release-info.json` matches the final DMG. The cask moves only to the latest published release: replacing the assets of an older tag with `REPLACE=1` leaves it alone, and the GitHub release is marked as latest only when its tag is the highest one. Replacing the assets of a published release turns it back into a draft first and publishes it again once every upload succeeded, so users never see a release with a missing or mismatched DMG; while it is a draft, its downloads are unavailable. If an upload fails, the release stays a draft and the output shows how to retry (`make release REPLACE=1`) or delete it. If the cask update fails after publishing, finish it with the command below, which refuses releases that are still drafts:

```bash
make cask VERSION=X.Y.Z
```

`make cask` downloads the release's DMG and stops when its checksum differs from `release-info.json`.

The release targets read these variables:

| Variable | Default | Meaning |
|---|---|---|
| `SIGN_IDENTITY` | automatic | Identity name or SHA-1 to sign with; `-` forces ad-hoc |
| `SIGN_IDENTITY_NAME` | `AgentTacho Signing` | Name of the self-signed certificate |
| `NOTARY_PROFILE` | `agenttacho-notary` | `notarytool` keychain profile |
| `ALLOW_ADHOC` | unset | `1` allows publishing an ad-hoc signed release |
| `ALLOW_TIER_DOWNGRADE` | unset | `1` allows releasing on a lower tier when the Developer ID certificate is expired or revoked (ad-hoc still needs `ALLOW_ADHOC=1`) |
| `ALLOW_UNNOTARIZED` | unset | `1` allows a Developer ID release without the notarization profile |
| `REPLACE` | unset | `1` replaces the assets of an existing release |
| `TAP_REPO` | `git@github.com:AgentTacho/homebrew-tap.git` | Tap repository; override for testing only |
| `GH_REPO` | `AgentTacho/agenttacho` | GitHub repository of the app; override for testing only |
| `SITE_REPO` | `AgentTacho/agenttacho.github.io` | Website repository whose `deploy.yml` a latest release starts; override for testing only |
| `VERSION` | required for `make cask` | Version of an already published release |

`TAP_REPO`, `GH_REPO` and `SITE_REPO` exist so tests and trial runs can point at a scratch tap or repository. With another `GH_REPO`, `make release` does not start the website deploy.

To try one-click install end to end before a release contains it, `make app-update-test UPDATE_SOURCE=owner/repo` builds `build/AgentTacho.app` with an update-test flag that reads releases from that repository instead of `AgentTacho/agenttacho` (and checks although it is not a tagged release build). `make app` never sets the flag, and `make release` and `make dmg` refuse to run when `UPDATE_TEST` is set. The procedure is in `specs/013-auto-update/quickstart.md`. The cask's download URL and the `brew install` command in the release notes always name `AgentTacho/agenttacho` and `agenttacho/tap`, whatever these variables say.

The DMG backgrounds live in `Resources/dmg/` and are generated by `make backgrounds`: the notarized one (used by every Developer ID release) draws its title on the committed artwork `background-notarized-base.png`, and the unnotarized one, with the first-launch steps, is drawn entirely from code. The window size and icon positions for each are in `scripts/release/dmg-settings.py`.

## Contributing

Contributions are welcome, through spec-driven development with [Spec Kit](https://github.com/github/spec-kit) and [cc-spex](https://github.com/rhuss/cc-spex). [AGENTS.md](AGENTS.md) describes the setup, the workflow and the project conventions.

## Credits

The icons are [Font Awesome Free](https://fontawesome.com) 7.3.1 by Fonticons, Inc. The icons are licensed under CC BY 4.0, the fonts under SIL OFL 1.1, and the code under MIT. See `Sources/UsageCore/Resources/FontAwesome/LICENSE.txt`.

## License

Apache License 2.0, see [LICENSE](LICENSE). The bundled Font Awesome files keep their own licenses, listed above.

---

Author: Roland Huß [AIA PAI Nc Hin R Claude Opus 5.5 v1.0](https://aiattribution.github.io/statements/AIA-PAI-Nc-Hin-R-?model=Claude%20Opus%205.5-v1.0)
