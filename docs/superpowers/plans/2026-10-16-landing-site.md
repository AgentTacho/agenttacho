# AgentMeter Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish an uncluttered AgentMeter landing page at `https://agentmeter-dev.github.io/` with a direct DMG download, six feature cards with real screenshots, a privacy section and an honest comparison.

**Architecture:** Three streams. Streams A (repository move) and B (demo mode for screenshots) change the app repository and go through its SDD flow; this plan only hands them a brief and defines what they must deliver. Stream C (the site) is planned task by task here: an AstroWind site copied from the sandcast site, one page, the release version read at build time from GitHub, deployed by GitHub Actions.

**Tech Stack:** Astro 7, Tailwind CSS 4, TypeScript, AstroWind (from `sandcast-dev/sandcast-dev.github.io`), Node 22 (`node --test` for unit and page tests), GitHub Pages via Actions, ImageMagick for image prep.

**Spec:** `brainstorm/18-landing-page.md` (approved 2026-10-16). Read it first; this plan argues from it.

## Global Constraints

- Headline "Usage at a glance. Nothing more." with "Nothing more." in the accent color.
- Subtitle "Plan limits and budgets for Claude Code, Codex and OpenCode, in one line of your menu bar."
- Never use the phrases "calm glance", "no dashboard" or "without a dashboard". Never use "the only" about privacy.
- No em dash (U+2014) or en dash (U+2013) anywhere in the site source or output.
- No real usage data, real account names, Red Hat name or logo in any image. The shared budget is called "Company budget" with a neutral building icon.
- Colors: deep teal `#055653`, cyan `#2BDED4`, amber `#FDBC3B`, cream `#FCF7EB`; light accent `#0A8F87`; dark page `#071A1A`.
- Links: repository `https://github.com/agentmeter-dev/agentmeter`, sponsor `https://github.com/sponsors/rhuss`, README privacy section `https://github.com/agentmeter-dev/agentmeter#security-and-privacy`.
- Requirements line: "Free and open source · macOS 14+ · signed and notarized", Homebrew command `brew install --cask rhuss/tap/agentmeter`.
- License of the site: Apache 2.0 (as sandcast). Node >= 22.22.3 (`.nvmrc` 22).
- The org `agentmeter-dev` is on the free plan, so Pages needs a public repository. The repository is public from the start, but the deploy job runs only when the repository variable `SITE_LIVE` is `true`, and no image showing real data is ever committed.

## Review Focus

1. GitHub API unavailable or rate limited during a build: the page must still build and show the last known version and a working DMG link (Task 3 test `falls back when the API fails`).
2. Latest release without `release-info.json`, or with a `dmg` name that is not among the assets: use the fallback, never render a broken link (Task 3 tests `falls back when release-info is missing` and `falls back when the dmg is not an asset`).
3. Phone width (390 px): hero stacks with the mascot below the text, the grid becomes one column, no horizontal scroll (Task 6 Playwright check).
4. Dark mode: every screenshot has a dark variant, so no light screenshot sits on the dark page (Task 6 page test `every feature image has a dark variant`).
5. Equal card sizes: all six cards share one height and image height, the user's main complaint about mockup v3 (Task 6 Playwright check of bounding boxes).

---

## Stream A: Repository move (SDD, app repository)

Run in a fresh session in `/Users/rhuss/Work/projects/agentmeter`: `/speckit-specify` with the brief below, then clarify, plan, tasks, implement, as AGENTS.md describes.

Brief for `/speckit-specify`:

> Move the repository from `rhuss/agentmeter` to `agentmeter-dev/agentmeter` (brainstorm 18, section "1. Repository move"). Update every current reference (`UpdateSource.official`, `AppLinks.repository`, `AppLinks.securityStatement`, `InstallEnvironment.swift`, the cask template, `scripts/release/lib.sh`, README, tests and fixtures); keep the sponsor link `github.com/sponsors/rhuss` and the tap `rhuss/homebrew-tap`; historical specs keep the old name. Verify that a 0.4.0 install still finds updates through GitHub's redirect (curl of the old API path and the old asset URL) before releasing. At the end of `make release`, trigger the site deploy with `gh workflow run deploy.yml -R agentmeter-dev/agentmeter-dev.github.io` (a failure only warns). Ship as 0.4.1 together with brainstorm 17.

Delivers to stream C: the release API path `https://api.github.com/repos/agentmeter-dev/agentmeter/releases/latest`, and a release that triggers the site workflow named `deploy.yml`.

The transfer itself is done by the user in the GitHub UI (Settings > Transfer), or by the agent with `gh api -X POST repos/rhuss/agentmeter/transfer -f new_owner=agentmeter-dev` after explicit approval.

## Stream B: Demo mode and screenshots (SDD, app repository)

Run in a fresh session after stream A merged: `/speckit-specify` with this brief:

> A dev-only demo build for marketing screenshots (brainstorm 18, section "2. Demo mode"). `make app-demo` builds "AgentMeter Demo" with its own bundle identifier and a compile-time flag; the demo build registers one demo `UsageSource` instead of the five real sources in `AppModel.init`, reads JSON scenario files with timed frames and an observation history, uses its own home for config, last-good values and log, and makes no keychain read and no network request. Scenarios cover the shot list in the brainstorm (mixed green/orange/red levels, pace on/behind/ahead, `↗` and `↑`, a budget near or over its limit, "Company budget" group with a building icon, a threshold crossing that fires a notification). A capture script in `scripts/screenshots/` quits the real AgentMeter, launches the demo app with `-AppleLanguages (en) -AppleLocale en_US`, opens the dropdown, the pace tooltip and the Settings tabs, waits for the notification, and captures light and dark WebP at 2x into a target directory, restoring the system appearance afterwards.

Delivers to stream C, into a directory passed to the capture script, these files (each in `-light.webp` and `-dark.webp`):

| File stem | Content |
|---|---|
| `menubar` | Menu bar item only, mixed levels, transparent or menu bar background |
| `plan-limits` | Claude plan section with pace meters |
| `pace` | Pace meter with its tooltip |
| `budget` | Budget row near or over its limit |
| `groups` | Settings > Groups with "Company budget" |
| `details` | Details table (models) with the per-day trend |
| `alert` | Notification banner |
| `dropdown` | Full dropdown (social card) |

Stream C uses exactly these stems; until they exist it uses placeholders with the same names (Task 2).

## Stream C: The site (this plan)

### File structure (repository `agentmeter-dev/agentmeter-dev.github.io`)

| Path | Responsibility |
|---|---|
| `src/config.yaml` | Site name, URL `https://agentmeter-dev.github.io`, metadata, blog off |
| `src/navigation.ts` | Header links (Features, Privacy, Compare), header actions (GitHub, Sponsor), footer |
| `src/components/CustomStyles.astro` | Color and font tokens, light and dark |
| `src/utils/release.ts` | Fetch latest release and resolve version and DMG URL, with fallback |
| `src/data/release-fallback.json` | Last known `{ "version", "dmg" }` |
| `src/data/features.ts` | The six feature cards: title, body, shot stem |
| `src/data/comparison.ts` | Comparison columns and rows, with the date checked |
| `src/components/agentmeter/*.astro` | Page sections: `Hero`, `MenuBarStrip`, `FeatureGrid`, `Privacy`, `Compare`, `ClosingCta` |
| `src/components/agentmeter/Shot.astro` | One screenshot with light and dark variant |
| `src/pages/index.astro` | Composes the sections |
| `src/assets/agentmeter/` | Mascot, icon, screenshots (`<stem>-light.webp`, `<stem>-dark.webp`) |
| `public/og.png` | Social card 1200×630 |
| `tests/release.test.ts` | Unit tests for `release.ts` |
| `tests/page.test.ts` | Page contract tests against `dist/index.html` |
| `scripts/make-placeholders.sh`, `scripts/make-og.sh` | Image prep with ImageMagick |
| `.github/workflows/deploy.yml` | Check, test, build, deploy (deploy only with `SITE_LIVE`) |

### Task 1: Scaffold the repository from the sandcast site

**Files:**
- Create: the whole repository from a copy of `sandcast-dev/sandcast-dev.github.io` (without its `.git`)
- Modify: `src/config.yaml`, `src/navigation.ts`, `package.json` (`name`, add `"test": "node --test tests/*.test.ts"`), `README.md`, `LICENSE.md`
- Create: `.github/workflows/deploy.yml` (from sandcast's `actions.yaml`)
- Delete: blog, docs (Antora/decap), demo, RSS, sandcast-specific components and assets, `netlify.toml`, `vercel.json`, `wrangler.jsonc`, `Dockerfile`, `nginx/`, `docker-compose.yml`

**Interfaces:**
- Produces: `npm run check`, `npm run build`, `npm test` all usable; `src/pages/index.astro` renders a stub page; workflow `deploy.yml` with jobs `check`, `build`, `deploy`.

- [ ] **Step 1:** `gh repo create agentmeter-dev/agentmeter-dev.github.io --public --description "AgentMeter website: menu bar app for your coding agents' limits and budgets"`, clone it to `~/Work/projects/agentmeter-site`, copy the sandcast tree in without `.git`.
- [ ] **Step 2:** Strip the listed files and every import of them; set `config.yaml` (`name: AgentMeter`, `site: 'https://agentmeter-dev.github.io'`, title default "AgentMeter: usage at a glance", description = the subtitle) and navigation (links `#features`, `#privacy`, `#compare`; actions GitHub and Sponsor).
- [ ] **Step 3:** In `deploy.yml` keep sandcast's jobs, add `npm test` after `npm run build` in the build job, add triggers `schedule: - cron: '17 5 * * *'` and `workflow_dispatch`, and gate the deploy job with `if: github.event_name != 'pull_request' && github.ref == 'refs/heads/main' && vars.SITE_LIVE == 'true'`. Pass `GITHUB_TOKEN` to the build step as env `GITHUB_TOKEN` (used by Task 3).
- [ ] **Step 4:** Run `npm ci && npm run check && npm run build`. Expected: both succeed, `dist/index.html` exists.
- [ ] **Step 5:** Run `rg -n "sandcast|\x{2014}|\x{2013}" src public`. Expected: no output.
- [ ] **Step 6:** Commit `chore: scaffold AgentMeter site from the sandcast template` and push. Settings > Pages > Source: GitHub Actions.

### Task 2: Brand theme, fonts and assets

**Files:**
- Modify: `src/components/CustomStyles.astro`, `src/components/Logo.astro`, `src/components/Favicons.astro`, `public/favicon.ico`
- Create: `src/assets/agentmeter/mascot.webp`, `src/assets/agentmeter/icon.png`, `scripts/make-placeholders.sh`, placeholder screenshots `src/assets/agentmeter/<stem>-{light,dark}.webp` for all stems of stream B

**Interfaces:**
- Produces: tokens `--aw-color-primary`, `--aw-color-accent`, `--aw-color-bg-page`, `--aw-color-text-*` set from Global Constraints; asset paths above.

- [ ] **Step 1:** Set light tokens (primary `#055653`, accent `#0A8F87`, eyebrow amber `#C98A12`, page `#F7F8F7`, heading text `#0E3B3A`, muted `#4B5F5E`) and dark tokens (primary and accent `#2BDED4`, eyebrow `#FDBC3B`, page `#071A1A`, text `#EAF4F3`, muted `#9DB5B3`). Keep sandcast's fonts, Sora for headings and Source Sans 3 for body. *(Builder's call per the spec; sandcast's fonts keep the two sites visibly related.)*
- [ ] **Step 2:** Mascot: `magick "$HOME/Downloads/Left-facing clay mascot with floating gauge.png" -trim +repage -resize 900x900 -quality 90 src/assets/agentmeter/mascot.webp`. Also copy the source PNG to the app repository as `Resources/icons/masters/agentmeter-clay-mascot.png` (separate commit there, `chore(icons): add clay mascot master`). Icon and favicons from `Resources/icons/masters/agentmeter-web-master.png`.
- [ ] **Step 3:** `scripts/make-placeholders.sh` writes one neutral tile per stem and variant (teal-tinted, the stem name in the middle, sizes: `menubar` 900×124, others 1660×400 except `groups` 1600×1000 and `dropdown` 1023×1538). Run it. These are placeholders only; never commit crops of the current real screenshot.
- [ ] **Step 4:** Run `npm run check && npm run build`; open `npm run preview` and look at both themes. Expected: teal palette, AgentMeter logo and favicon.
- [ ] **Step 5:** Commit `feat: AgentMeter colors, fonts, logo, mascot and placeholder shots`.

### Task 3: Latest release at build time

**Files:**
- Create: `src/utils/release.ts`, `src/data/release-fallback.json` (`{ "version": "0.4.0", "dmg": "AgentMeter-0.4.0.dmg" }`), `tests/release.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export interface Release { version: string; dmgUrl: string; pageUrl: string; fromFallback: boolean }
  export async function getLatestRelease(fetchImpl?: typeof fetch, token?: string): Promise<Release>
  ```
  `dmgUrl` is `https://github.com/agentmeter-dev/agentmeter/releases/download/v<version>/<dmg>`; `pageUrl` is `https://github.com/agentmeter-dev/agentmeter/releases/latest`.

- [ ] **Step 1: Write the failing tests** in `tests/release.test.ts` with a stub `fetchImpl` serving fixtures shaped like the app's `Tests/UsageCoreTests/Fixtures/update/releases-latest.json` and `release-info.json`:
  - `resolves version and dmg from the latest release`: tag `v0.4.1`, release-info `{ "version": "0.4.1", "dmg": "AgentMeter-0.4.1.dmg" }`, asset listed → `version === '0.4.1'`, `dmgUrl` ends with `/releases/download/v0.4.1/AgentMeter-0.4.1.dmg`, `fromFallback === false`.
  - `falls back when the API fails`: API returns 403 → `version === '0.4.0'`, `fromFallback === true`.
  - `falls back when release-info is missing`: no `release-info.json` asset → fallback.
  - `falls back when the dmg is not an asset`: release-info names `AgentMeter-0.4.0.dmg` but assets list `AgentMeter-0.4.1.dmg` → fallback.
  - `sends the token when given`: the stub sees `Authorization: Bearer t`.
- [ ] **Step 2:** Run `npm test`. Expected: FAIL, module not found.
- [ ] **Step 3:** Implement `getLatestRelease` in `src/utils/release.ts`. The tests run under Node's built-in type stripping, so use erasable TypeScript only (no enums or parameter properties), import with explicit `.ts` extensions, and load the fallback with `import fallback from '../data/release-fallback.json' with { type: 'json' }`. A 10 second timeout per request; any error or inconsistency returns the fallback; log one line with the reason when it falls back.
- [ ] **Step 4:** Run `npm test`. Expected: 5 passing.
- [ ] **Step 5:** Commit `feat: read the latest release at build time`.

### Task 4: Page contract tests

**Files:**
- Create: `tests/page.test.ts`

**Interfaces:**
- Consumes: `dist/index.html` from `npm run build`.
- Produces: tests that Tasks 5 to 7 turn green one by one. `npm test` runs them after a build (CI already runs it after `npm run build`, Task 1).

- [ ] **Step 1: Write the tests** (read `dist/index.html` as text; skip with a clear message if it does not exist):
  - `has the headline and subtitle`: contains "Usage at a glance." and "Nothing more." and the subtitle from Global Constraints.
  - `has the download button with a version`: an `<a>` whose `href` matches `/releases\/download\/v\d+\.\d+\.\d+\/AgentMeter-\d+\.\d+\.\d+\.dmg$/` and whose text contains `v` plus the same version.
  - `links GitHub and Sponsors`: contains both URLs from Global Constraints.
  - `has the sections`: elements with `id="features"`, `id="privacy"`, `id="compare"`.
  - `has six feature cards`: six elements with `data-feature-card`.
  - `every feature image has a dark variant`: each `data-feature-card` holds one image marked `data-theme-variant="light"` and one `data-theme-variant="dark"`.
  - `avoids forbidden copy`: no "calm glance", no "no dashboard", no "without a dashboard", no "the only", no U+2014, no U+2013 (case-insensitive).
- [ ] **Step 2:** Run `npm run build && npm test`. Expected: the release tests pass, most page tests FAIL.
- [ ] **Step 3:** Commit `test: page contract for the landing page`.

### Task 5: Header, hero and menu bar strip

**Files:**
- Create: `src/components/agentmeter/Hero.astro`, `src/components/agentmeter/MenuBarStrip.astro`, `src/components/agentmeter/Shot.astro`
- Modify: `src/pages/index.astro`, header widget configuration in `src/navigation.ts`

**Interfaces:**
- Consumes: `getLatestRelease()` (Task 3), assets (Task 2).
- Produces: `<Shot stem="menubar" alt="..." class="..." />` renders two `<Image>`s, light with `data-theme-variant="light"` and class `dark:hidden`, dark with `data-theme-variant="dark"` and class `hidden dark:block`.

- [ ] **Step 1:** Hero, two columns on desktop (text about 60%, mascot about 40%), stacked on phones with the mascot below the text and at most 240 px wide: eyebrow "Menu bar app for macOS"; headline and subtitle from Global Constraints; primary button "Download AgentMeter" plus a small "v<version>" linking `dmgUrl`; secondary "View on GitHub"; the requirements line; "or Homebrew" reveals the Homebrew command in a copyable code element. Mascot with `drop-shadow` from CSS, `alt="AgentMeter mascot"`.
- [ ] **Step 2:** Header: logo and name, the three anchors, GitHub and Sponsor (heart icon `tabler:heart`) buttons, theme toggle.
- [ ] **Step 3:** Menu bar strip: a wide, short panel (radial teal and cream gradients, a translucent 44 px bar on top with the `menubar` shot right-aligned next to a static clock text "Fri Oct 16 10:42"), caption heading "One number per plan or budget." and text "Each entry shows how much is used. It turns orange near the limit and red past it. Click for the rest."
- [ ] **Step 4:** Run `npm run build && npm test`. Expected: headline, download, links tests PASS.
- [ ] **Step 5:** Commit `feat: hero with download button and menu bar strip`.

### Task 6: Feature grid

**Files:**
- Create: `src/data/features.ts`, `src/components/agentmeter/FeatureGrid.astro`
- Modify: `src/pages/index.astro`

**Interfaces:**
- Produces: `export const features: { title: string; body: string; stem: string; alt: string }[]` in this order and with this copy:
  1. "Plan limits", "Claude Max and ChatGPT Plus windows, 5-hour and weekly, with the reset time next to each.", `plan-limits`
  2. "Pace", "See whether you are on pace, behind, or about to run out before the reset.", `pace`
  3. "Budgets you set", "Pay-per-token spend on Vertex or the OpenAI API, against your own weekly or monthly budget.", `budget`
  4. "Shared budgets", "Several accounts under one budget, like a monthly limit your company sets.", `groups`
  5. "Details on demand", "Tokens per model, project and harness, with a per-day trend, folded away until you need them.", `details`
  6. "Alerts", "A notification when usage crosses your thresholds, 80% and 100% by default.", `alert`

- [ ] **Step 1:** Section `id="features"`, eyebrow "Features", heading "Everything in one menu.", a CSS grid `grid-cols-1 md:grid-cols-2 lg:grid-cols-3` with equal row heights; each card `data-feature-card`, a fixed-height image area (150 px, image `object-contain`, dark backdrop `#1E1E20` behind screenshots), title and body below.
- [ ] **Step 2:** Run `npm run build && npm test`. Expected: six cards and dark variant tests PASS.
- [ ] **Step 3:** Playwright check (MCP or a script) on `npm run preview`: at 1280 px all six cards have equal height (bounding boxes within 1 px) and equal image area height; at 390 px one column and `document.documentElement.scrollWidth === 390`. Expected: both hold.
- [ ] **Step 4:** Commit `feat: six feature cards in an even grid`.

### Task 7: Privacy and comparison

**Files:**
- Create: `src/components/agentmeter/Privacy.astro`, `src/data/comparison.ts`, `src/components/agentmeter/Compare.astro` (wraps sandcast's `Comparison` widget, `mode="versus"`)
- Modify: `src/pages/index.astro`

**Interfaces:**
- Produces: `export const comparison: { checked: string; columns: string[]; rows: { label: string; values: (boolean | string)[] }[] }` with `checked` the date the facts were verified.

- [ ] **Step 1:** Privacy section `id="privacy"`, heading "Your data stays on your Mac.", four short points taken from the app README's "Security and privacy" section as it reads on the day of writing: reads the agents' own sign-in tokens without changing them and sends them only to each provider's usage endpoint; never touches the browser or its cookies; no telemetry; the only other request is the update check, which you can turn off. A link "Read exactly what it reads" to the README section.
- [ ] **Step 2:** Re-verify the competitor facts in the spec's "Research notes" against each project's current README (CodexBar, Claude Usage Tracker, ClaudeBar, ccusage), then fill `comparison.ts`: columns AgentMeter, CodexBar, Claude Usage Tracker, ClaudeBar, ccusage; rows "Form", "Agents and providers", "Your own weekly or monthly dollar budgets", "One budget shared across accounts", "Reads browser cookies", "Telemetry", "Menu bar". State CodexBar's breadth plainly (about 105 providers, widgets, CLI). Show "As of <checked>" under the table.
- [ ] **Step 3:** Compare section `id="compare"`, heading "How it compares.", one sentence intro: "CodexBar covers far more providers. AgentMeter covers fewer, adds budgets you set, and keeps the menu bar to one line."
- [ ] **Step 4:** Run `npm run build && npm test`. Expected: all page tests PASS.
- [ ] **Step 5:** Commit `feat: privacy section and comparison table`.

### Task 8: Closing call to action, footer and social card

**Files:**
- Create: `src/components/agentmeter/ClosingCta.astro`, `scripts/make-og.sh`, `public/og.png`
- Modify: footer in `src/navigation.ts`, `src/config.yaml` (Open Graph image `og.png` 1200×630), `src/pages/index.astro`

- [ ] **Step 1:** Closing section: heading "Try it in your menu bar.", the Download button again (same `Release`), "View on GitHub", and a line "AgentMeter is free. If it saves you a surprise, consider sponsoring." linking Sponsors.
- [ ] **Step 2:** Footer: Apache 2.0, GitHub, Releases, Sponsors, and a credit line in the style of the other two sites ("Built with spec-driven development and Claude Code, by Roland Huß").
- [ ] **Step 3:** `scripts/make-og.sh` composes `public/og.png` with ImageMagick: dark teal `#071A1A` background, icon, the headline in two lines, the `menubar` dark shot. Run it.
- [ ] **Step 4:** Run `npm run check && npm run build && npm test`. Expected: all pass.
- [ ] **Step 5:** Commit `feat: closing call to action, footer and social card`.

### Task 9: Real screenshots and launch (after streams A and B)

**Files:**
- Modify: `src/assets/agentmeter/<stem>-{light,dark}.webp` (all stems), `public/og.png`, `src/data/release-fallback.json`

- [ ] **Step 1:** Run stream B's capture script with the target `~/Work/projects/agentmeter-site/src/assets/agentmeter/`. Look at every image in both themes; reject any that shows real names, German formats or clipped UI.
- [ ] **Step 2:** Regenerate `og.png` with `scripts/make-og.sh`; set `release-fallback.json` to the newest release.
- [ ] **Step 3:** Run `npm run check && npm run build && npm test` and the Task 6 Playwright check. Expected: all pass.
- [ ] **Step 4:** Commit `feat: real screenshots from the demo build` and push.
- [ ] **Step 5 (needs the user's go-ahead):** `gh variable set SITE_LIVE -b true -R agentmeter-dev/agentmeter-dev.github.io`, then `gh workflow run deploy.yml -R agentmeter-dev/agentmeter-dev.github.io`. Set the app repository's homepage: `gh repo edit agentmeter-dev/agentmeter --homepage https://agentmeter-dev.github.io`.
- [ ] **Step 6:** Verify live: `curl -sL https://agentmeter-dev.github.io/ | rg -o 'AgentMeter-[0-9.]+\.dmg' | head -1` names the latest release, and `curl -sIL <that dmgUrl>` ends in `200`. Open the page in both themes and at phone width.

## Order and dependencies

1. Stream C Tasks 1 to 8 can start now; they only use placeholders and the fallback version.
2. Stream A next (in its own session). After it merges and 0.4.1 is released, the site's build reads the new API path.
3. Stream B after A.
4. Task 9 last, then launch.
