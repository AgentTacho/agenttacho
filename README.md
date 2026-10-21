<h1><img src="Resources/icons/macos/AgentTacho.png" alt="AgentTacho app icon" width="80" align="left">AgentTacho<br><sub><sup>Every agent, every plan, one menu bar</sup></sub></h1>

AgentTacho reads the usage your agents already record on this Mac and shows each account as an icon and a percentage in the menu bar. Click one for the detail: usage per model, project or tool, with a daily trend and a notification when you cross a threshold.

- **Claude Code on Pro or Max:** the real 5-hour and 7-day usage Anthropic reports, plus model limits such as Fable's.
- **Codex on a ChatGPT plan:** every plan window with its reset time, live from ChatGPT, so usage on other machines counts too.
- **Pay-per-token accounts** (Vertex AI, OpenAI API): spend in US dollars against a weekly or monthly budget you set, priced from your agents' local logs.
- **Shared budgets:** several accounts under one budget, for example a company's monthly spending limit.
- **Local first:** AgentTacho reads your agents' files on this Mac. Apart from the usage checks with Anthropic and ChatGPT, it makes no network calls on its own.

It works with Claude Code, Codex and OpenCode, on macOS 14 or newer with Apple Silicon. For the markers, the pace bars, the Settings tabs and everything else, see the [documentation](docs/README.md).

See it in action with screenshots at **[agenttacho.dev](https://agenttacho.dev)**.

## Status

A personal project, built for my own setup and shared as is. It runs on macOS 14 or newer with Apple Silicon and reads usage from three agent harnesses: Claude Code, Codex and OpenCode.

> [!TIP]
> AgentTacho is free and open source. If it saved you from a surprise rate limit, consider sponsoring it on GitHub. It keeps the lights on, and the notarization paid.

AgentTacho is not affiliated with Anthropic, OpenAI, Google or the OpenCode project. The subscription percentages come from an undocumented Anthropic endpoint that Claude Code itself uses (`/api/oauth/usage`). It can change or disappear without notice, and then the subscription rows show an error while token-based accounts keep working. The same goes for the ChatGPT usage service behind the Codex plan limits (`/backend-api/wham/usage`); when it changes, Codex subscription accounts fall back to the limits recorded in the local Codex sessions.

## Install

AgentTacho needs macOS 14 or newer on Apple Silicon.

```bash
brew install --cask agenttacho/tap/agenttacho
```

Or download `AgentTacho-X.Y.Z.dmg` from the [latest release](https://github.com/AgentTacho/agenttacho/releases/latest), open it and drag AgentTacho onto the Applications folder. The app updates itself from GitHub; the full detail, including Homebrew and the updater, is in [docs/installation.md](docs/installation.md).

## Build

Requirements: macOS 14 or newer on Apple Silicon, and the Xcode Command Line Tools with Swift 5.10 or newer. There are no third-party Swift packages.

```bash
make test     # unit tests for the UsageCore library
make app      # builds build/AgentTacho.app
make run      # builds and opens the app
```

Build only through the Makefile, never `swift build` or `xcodebuild` directly. The demo build, the project layout and the scripts are in [docs/development.md](docs/development.md).

## How it works

- **Claude Code.** AgentTacho reads Claude Code's session files under `~/.claude/projects`, the credential directory of every Claude subscription account, and any extra directories you configure. A directory named in more than one place is read once. After the first scan it only rereads files that changed. A request id starting with `req_vrtx_` marks a Vertex session; other `req_` ids are direct Anthropic sessions.
- **Codex.** AgentTacho reads the rollout files under `~/.codex/sessions` and any extra Codex homes. Usage is the change of each session's running token total, so repeated events never count twice. A session whose rate-limit snapshot names a ChatGPT plan counts for the Codex subscription account (a subagent follows its parent session); every other session is API-key usage and counts for the OpenAI account. The same rate-limit snapshots supply the fallback for the plan limits.
- **Codex plan limits.** With live limits on (the default), AgentTacho reads the access token from `auth.json` in the account's Codex home at each refresh and asks the ChatGPT usage service for the plan's current limits, as Codex itself does. It never refreshes that sign-in: only Codex renews it while it runs. If the token has expired, or the service has already rejected it (a manual refresh tries a rejected token once more), AgentTacho makes no request and shows the newest snapshot, with a note to run Codex. Redirects are refused, so the token only ever goes to that one address. With live limits off, AgentTacho neither reads the sign-in nor contacts the service, and shows only the newest snapshot.
- **OpenCode.** AgentTacho reads `~/.local/share/opencode/opencode.db` (and any extra data directories) read-only. Code stored in the database file cannot call functions that are unsafe for untrusted files (SQLite's `trusted_schema=OFF`), virtual table modules are switched off, and `message` and `session` must be ordinary tables, not views or virtual tables. After the first read, only messages that changed are read. A database that does not pass these checks is treated like an unreadable one. Each completed assistant message counts once. Its provider decides the account: `google-vertex` goes to Vertex, `openai` to OpenAI, anything else to Unassigned unless a custom marker claims it. OpenCode's own cost estimate is ignored. If the database is busy, the previous OpenCode values stay, marked stale.
- **Breakdowns.** Every account, group and Unassigned entry can show its usage per model, per project or per harness.
- **Prices.** The built-in table is in `Sources/UsageCore/Resources/prices.json`, and imported prices and your overrides are layered on top of it (see [docs/prices.md](docs/prices.md)). A model without a price is counted as unpriced, and the total of its budget (a group or an own budget) is marked incomplete until you add a price.
- **Subscription limits.** At each refresh, AgentTacho reads Claude Code's stored login from the macOS keychain through Apple's `/usr/bin/security` tool, and asks Anthropic's usage endpoint for the current utilization. Claude Code's keychain items already trust that tool, so no keychain dialog appears.

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
- Apart from the update check, no other server receives anything, and there is no telemetry. Besides the update check, AgentTacho downloads only two things, both without credentials and only when you ask: the update's disk image from GitHub, after you click Install (see [installation](docs/installation.md#what-the-update-check-sends-and-verifies) for what the update check sends and verifies), and LiteLLM's price list from `raw.githubusercontent.com`, when you choose it from the Import menu.

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

## Documentation

The full reference lives in [`docs/`](docs/README.md): [installation](docs/installation.md), [reading the bar](docs/usage.md), [accounts and budgets](docs/accounts-and-budgets.md), [configuration](docs/configuration.md), [prices](docs/prices.md) and [build and development](docs/development.md). It is interim material that a proper reference on [agenttacho.dev](https://agenttacho.dev) will supersede.

## Contributing

Contributions are welcome, through spec-driven development with [Spec Kit](https://github.com/github/spec-kit) and [cc-spex](https://github.com/rhuss/cc-spex). See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow, and [AGENTS.md](AGENTS.md) and the [constitution](.specify/memory/constitution.md) for the conventions.

Maintainers: the release procedure is in [HOWTO_RELEASE.md](HOWTO_RELEASE.md), and the website guide in [docs/website.md](docs/website.md).

## Credits

The icons are [Font Awesome Free](https://fontawesome.com) 7.3.1 by Fonticons, Inc. The icons are licensed under CC BY 4.0, the fonts under SIL OFL 1.1, and the code under MIT. See `Sources/UsageCore/Resources/FontAwesome/LICENSE.txt`.

## License

Apache License 2.0, see [LICENSE](LICENSE). The bundled Font Awesome files keep their own licenses, listed above.

---

Author: Roland Huß [AIA PAI Nc Hin R Claude Opus 5.5 v1.0](https://aiattribution.github.io/statements/AIA-PAI-Nc-Hin-R-?model=Claude%20Opus%205.5-v1.0)
