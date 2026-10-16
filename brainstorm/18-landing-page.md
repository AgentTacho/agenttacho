# Brainstorm: Landing Page

**Date:** 2026-10-16
**Status:** approved

## Intent

AgentMeter gets a landing page in the style of the sandcast and antwort sites. It is for developers who pay for AI coding agents in more than one way (a Claude or ChatGPT subscription with rate limits, plus pay-per-token spend on Vertex AI or the OpenAI API) and want to see their limits and budgets before something runs out.

What sets AgentMeter apart, and what the page has to carry above everything else, is that it is simple and intuitive: one clean line in the menu bar, a dropdown that stays readable, settings you understand without a manual. The budget feature (own budgets and shared budget groups, such as a company-imposed monthly limit that no provider enforces for you) and the privacy model are the two strong supporting points. The page should feel uncluttered and should itself demonstrate the simplicity it claims.

## Goals

- A single, uncluttered landing page at `https://agentmeter-dev.github.io/`.
- A prominent direct download of the latest release DMG, with the version number on the button.
- Feature cards that each show one feature with a real screenshot crop.
- An honest comparison with CodexBar and other trackers that highlights simplicity, budgets and privacy.
- Links to the GitHub repository and to GitHub Sponsors.
- Light and dark mode, like the other two sites.

## Non-goals

- No documentation site. The README stays the manual; the page links to it.
- No blog, RSS, newsletter or analytics.
- No demo video at launch (a short loop is a possible later addition).
- No custom domain at launch (ro14nd.de stays the personal blog).

## Anti-goals

- A busy page. If it looks like a dashboard of features, it fails even if every fact is right.
- The phrases "one calm glance" and "no dashboard" (or "without a dashboard"). The user rejected both framings.
- Leading with the company budget story. It is a strong argument, but simplicity leads; budgets come second.
- Claims we cannot back: "the only private tracker" (ccusage and Usage4Claude also have no telemetry), or anything that understates CodexBar's breadth.
- Real usage data, real account names or the Red Hat name and logo in screenshots.

## Three pieces of work, in order

1. **Move the repository** from `rhuss/agentmeter` to the new `agentmeter-dev` org.
2. **Demo mode** in the app for screenshots with made-up data (a spec in this repo, through the normal SDD flow).
3. **The site** in `agentmeter-dev/agentmeter-dev.github.io`. Building it can start in parallel with step 2, using neutral placeholder tiles (never crops of the current screenshot, which shows real data and German number formats), but it does not go public until the demo screenshots replace them. The org is on GitHub's free plan, where Pages needs a public repository, so the repository is public from the start and its deploy job runs only once the repository variable `SITE_LIVE` is `true`. *(My call.)* There is one launch, not two.

Process: steps 1 and 2 change this repository and follow its SDD flow (specs in `specs/`). The site repository gets a lighter process: an implementation plan from this document, no spec. *(My call; the site repo is not bound by this repo's AGENTS.md.)*

Prerequisites checked on 2026-10-16: the GitHub Sponsors listing for `rhuss` exists and is public; the user administers `agentmeter-dev`; the active `gh` token has `repo` and `admin:org` scopes, enough to create the site repository and run its workflows.

## 1. Repository move

- The user transfers `rhuss/agentmeter` to `agentmeter-dev` in the GitHub UI (or approves `gh api` doing it).
- About 15 files name `rhuss/agentmeter`: `Sources/UsageCore/Update/UpdateSource.swift` (`UpdateSource.official`), `Sources/UsageCore/AppLinks.swift` (repository and security statement URLs; the sponsor link `github.com/sponsors/rhuss` stays), `Sources/AgentMeter/InstallEnvironment.swift`, `packaging/homebrew/agentmeter.rb.tmpl`, `scripts/release/lib.sh`, the README, and the tests and fixtures that assert those values. Historical specs and brainstorms keep the old name.
- Installed copies of 0.4.0 check `api.github.com/repos/rhuss/agentmeter/releases/latest`. GitHub redirects transferred repositories, and the update host policy checks hosts, not owner paths, so the check should keep working. Verify with curl right after the transfer (the API redirect and the release asset download), before any release from the new location.
- The Homebrew tap stays at `rhuss/homebrew-tap` (`brew install --cask rhuss/tap/agentmeter`); only the cask's download URL changes. *(My call: moving the tap is not needed for the site and would break existing `brew upgrade` paths.)*
- Following AGENTS.md, the reference update is its own small spec. *(My call; it could also ride along with the next release spec.)*
- Release 0.4.1 is already planned as the first end-to-end test of the one-click update (brainstorm 17). The move happens **before** 0.4.1, so that release also tests updating a 0.4.0 install across the redirect, and the site reads the new API path from day one. *(My call.)*
- Open the repository settings after the move: set the homepage URL to the site, keep the FUNDING.yml (`github: rhuss`).

## 2. Demo mode (new spec, likely 019)

Purpose: realistic, made-up screenshots that show the current features (colored levels, pace meter, `↗` and `↑` markers, budgets, groups, alerts), driven end to end by the agent on the user's Mac.

Decided:

- **Dev build only.** Like the existing update-test build (`AGENTMETER_UPDATE_TEST`, `make app-update-test`), a `make app-demo` target builds a separate app with a compile-time flag. Release builds never contain demo code paths, so the README's "Security and privacy" section stays true without changes.
- **Separate identity.** Its own bundle identifier and name (for example "AgentMeter Demo") so its notification permission, defaults and config never touch the installed app. The capture script quits the real AgentMeter first so only one item is in the bar.
- **No secrets, no network.** The demo build registers one demo source in place of the five real sources (`SubscriptionSource`, `SessionLogSource`, `OpenCodeSource`, `CodexSessionSource`, `CodexLimitsSource`, registered in `AppModel.init` in `Sources/AgentMeter/App.swift`). No keychain read, no usage endpoints, no update check. `UsageSource` is public and `RefreshCoordinator` already takes sources, so this is the seam.
- **Separate config.** The demo build uses its own home for `config.json`, `last-good.json` and the log (`Sources/UsageCore/Config/Paths.swift` currently has no override), so Settings shows the demo accounts and groups.
- **Scenario files.** JSON files in the repo (for example `Resources/demo/*.json`) describe what the demo source returns: subscriptions with plan windows and reset times relative to "now", token accounts, groups, budgets, and a short observation history so the pace meter and the burn-rate markers have something to compute from. A scenario can hold timed frames, so a threshold crossing happens a few seconds after launch and a real notification fires (`ThresholdTracker` treats the first observation as the baseline).
- **English locale.** The capture launches the demo app with `-AppleLanguages (en) -AppleLocale en_US`, so numbers and dates read "1,578" and "Oct 16", not the German format of the current screenshot.

Demo story (decided): a Claude Max subscription, a ChatGPT Plus subscription for Codex, and a shared monthly **"Company budget"** group with a neutral building icon (Font Awesome, already bundled) holding a Vertex account and an OpenAI API account. No Red Hat name or logo. Exact numbers are the builder's call, but together the scenarios must show: green, orange and red levels in the bar; a pace meter that is on pace, one behind, one ahead; one entry with `↗` and one with `↑`; a budget over or near its limit; the details table with plausible model names.

Capture script (in this repo, for example `scripts/screenshots/`):

- Builds and launches the demo app per scenario, opens the dropdown, hovers the pace meter for its tooltip, opens the Settings tabs (Accounts, Groups, Menu Bar), and waits for the notification.
- Captures windows with `screencapture -l <window id>` and the menu bar item by region, in light and dark appearance, then crops the feature tiles. Switching appearance changes the system setting temporarily; the script restores it.
- Needs Accessibility permission for the terminal once (to click the menu bar item and Settings). The user grants it when the script asks.
- Writes into the site repo's image folder, as WebP at 2x.

Shot list:

| Shot | Used for |
|---|---|
| Menu bar item, mixed levels, light and dark | Strip under the hero |
| Claude plan section with pace meters | "Plan limits" card |
| Pace meter tooltip | "Pace" card |
| Budget row over or near its limit | "Budgets you set" card |
| Settings > Groups with "Company budget" | "Shared budgets" card |
| Details table (models) with the per-day trend | "Details on demand" card |
| Notification banner | "Alerts" card |
| Settings > Menu Bar (pills, colors, symbols) | Optional, simplicity section |
| Full dropdown | Social card or a later section |

## 3. The site

### Location and stack

- Repository `agentmeter-dev/agentmeter-dev.github.io`, served at `https://agentmeter-dev.github.io/`.
- Astro with the AstroWind template, starting from the sandcast site (`sandcast-dev/sandcast-dev.github.io`: Astro 7, Tailwind 4, a deploy workflow in `.github/workflows/actions.yaml`). Strip blog, docs, RSS and unused widgets. The sandcast repo also has a `Comparison` widget to reuse.
- GitHub Pages deploy through Actions on push to `main`, plus `workflow_dispatch` and a daily schedule.

### Latest version and download link

- At build time the site reads `https://api.github.com/repos/agentmeter-dev/agentmeter/releases/latest` and the release's `release-info.json` (version and DMG name, the same files the in-app update check uses), and renders the button as "Download AgentMeter v0.4.0" linking straight to the DMG asset.
- The release script (`scripts/release/`) triggers the site deploy at the end of a release with `gh workflow run` on the site repository, so the button updates within minutes. The daily schedule is the safety net. *(My call.)*
- If the API call fails during a build, the build uses the last known version committed in the repo rather than failing or showing no version.

### Page structure (from the approved mockup v5)

1. **Header:** icon and "AgentMeter", links Features, Privacy, Compare, then GitHub and Sponsor (heart) buttons, theme toggle.
2. **Hero, two columns:** left an eyebrow "Menu bar app for macOS", a two-line headline (second line in the accent color), the subtitle, the Download button with version and a "View on GitHub" button, and a small line "Free and open source · macOS 14+ · signed and notarized · or Homebrew" (the Homebrew command on hover or click). Right: the 3D clay mascot, facing the headline.
3. **Menu bar strip:** a wide, short panel that looks like the top of a macOS desktop, with the AgentMeter menu bar item large and crisp, and a short caption ("One number per plan or budget." plus one sentence about orange near the limit, red past it, click for the rest). This replaces the tall dropdown screenshot, which made the layout feel disordered.
4. **Features:** a strict 3×2 grid of equal cards. Each card has a fixed-height screenshot crop on top and a title plus one or two sentences below. Cards: Plan limits, Pace, Budgets you set, Shared budgets, Details on demand, Alerts. The user called the uneven layout of mockup v3 "quite unordered"; equal sizes and alignment are a requirement, not a polish item.
5. **Privacy:** short and concrete, from the README's "Security and privacy" section: it reads the agents' own sign-in tokens without changing them and sends them only to each provider's usage endpoint; it never touches the browser or its cookies; no telemetry; the only other request is the update check (which can be turned off); everything else is read from local files. Link to the README section for the full table.
6. **Compare:** a table, dated, against CodexBar, Claude Usage Tracker, ClaudeBar and ccusage (rows: form, agents covered, own weekly or monthly dollar budgets, shared budgets across accounts, browser cookies, telemetry, menu bar presentation). Fair in both directions: say that CodexBar covers about 105 providers and has widgets and a CLI. The facts come from the research of 2026-10-16 (sources listed below) and must be rechecked when the table is written.
7. **Closing call to action:** Download again, GitHub, and a sponsor line.
8. **Footer:** license (Apache 2.0), GitHub, Sponsors, releases, a credit line like the other two sites.

### Copy

- Tone like sandcast: short declarative sentences, no superlatives, no marketing filler. Plain English for a developer.
- Subtitle (accepted with mockup v4): "Plan limits and budgets for Claude Code, Codex and OpenCode, in one line of your menu bar."
- Headline (decided): **"Usage at a glance. Nothing more."**, the second sentence in the accent color. It states the simplicity that sets AgentMeter apart; "Every agent, every plan, one menu bar" stays the README tagline, since promising breadth invites a losing comparison with CodexBar.
- Feature card texts from mockup v4 are drafts; keep them to one or two sentences.
- No em dash or en dash anywhere (AGENTS.md).

### Visual identity

- Colors from the app icon: deep teal `#055653`, cyan `#2BDED4`, amber `#FDBC3B`, cream `#FCF7EB`. Light mode on a near-white background with teal text and a darker teal accent (`#0A8F87`); dark mode on deep teal-black (`#071A1A`) with cyan as accent. Amber for eyebrows and small highlights.
- Font: the one the sandcast site uses, or Inter as in the mockup. *(Builder's call.)*
- Mascot: the clay render facing left with the amber gauge segment on the right and a transparent background, currently at `~/Downloads/Left-facing clay mascot with floating gauge.png`. Keep the master in `Resources/icons/masters/` of this repo and a trimmed WebP in the site; add the soft shadow with CSS `drop-shadow`.
- Favicon and logo from `Resources/icons/masters/agentmeter-web-master.png`.
- Social preview card (1200×630): icon, headline, a menu bar crop. Built from existing assets.

### Mockups

The visual companion mockups (v1 to v5) live in the session's scratch directory and are throwaway; the approved state is v5: layout A, menu bar strip, 3×2 grid, mirrored mascot.

## Decided by the user

- Separate `agentmeter-dev` org (created) and moving the app repo there.
- Astro, same framework as the other two sites.
- Real menu bar screenshot in the hero area, 3D mascot on the side (layout A), mascot facing the text.
- Simplicity leads; budgets and privacy support it; the company budget is not the lead.
- New screenshots with made-up data, driven by the agent on the user's Mac, showing the trend indicators and coloring.
- Neutral company icon and name for the shared budget, no Red Hat branding.
- No "calm glance", no "no dashboard".
- Headline "Usage at a glance. Nothing more."

## My calls (check these)

- Demo mode as a dev-only build flag, not a hidden launch argument in release builds.
- Homebrew tap stays at `rhuss/homebrew-tap`.
- The repo reference update as its own small spec.
- Release script triggers the site deploy; daily schedule as fallback; last known version as build fallback.
- Feature grid of six cards with the titles above.
- Comparison against four tools, not all nine researched.
- Repository move before release 0.4.1.
- No public launch until the demo screenshots exist; the site repo is public (free plan) but deploys only once `SITE_LIVE` is set.
- SDD specs for the repo move and demo mode; a plain implementation plan for the site repo.

## Open questions

- None.

## Research notes (2026-10-16)

- CodexBar ([github.com/steipete/CodexBar](https://github.com/steipete/CodexBar), [codexbar.app](https://codexbar.app)): about 105 providers, one menu bar item per provider by default or a merged icon with a switcher, dense dropdown (plan, windows, pace, credits with a buy button, cost, top model, charts). Uses OAuth tokens, API keys, CLI probing and opt-in browser cookie import (Keychain "Safe Storage" access, Full Disk Access for Safari). No user-set dollar budgets, only budgets a provider exposes. MIT, about 22.6k stars, releases every few days.
- Claude Usage Tracker ([github.com/hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker)): menu bar, Claude and Codex, claude.ai session cookie, anonymous daily heartbeat, percentage alerts only.
- ClaudeBar ([github.com/tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar)): menu bar, about 28 providers, daily budget for Bedrock only.
- ccusage ([github.com/ryoppippi/ccusage](https://github.com/ryoppippi/ccusage)): CLI reports from local logs, no budgets, no menu bar.
- Also seen: Claude Code Usage Monitor (terminal, Claude only, one custom cost limit), TokenEater, Usage4Claude (minimal, Claude and Codex, no telemetry), VibeMeter (dormant).
- No competitor has user-set weekly or monthly dollar budgets or budgets shared across accounts.
