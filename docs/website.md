# The website

How `https://agenttacho.dev` is built, what feeds it, and how to keep it current. AGENTS.md has the rule and the order of work; this file is the reference you open when you work on the site.

## What it is

- Repository `AgentTacho/agenttacho.github.io`, public, served by GitHub Pages from GitHub Actions under the custom domain `agenttacho.dev`. One page, built with Astro and the AstroWind template, copied from the sandcast site.
- Clone it next to the app repository: `gh repo clone AgentTacho/agenttacho.github.io <site checkout>`. Use the Node version in `.nvmrc`, then `npm ci`.

## What feeds the page

| On the page | Source | Changed by |
|---|---|---|
| Seven screenshots, light and dark | `src/assets/agenttacho/<stem>-{light,dark}.webp` | `scripts/screenshots/capture.sh` in the app repository, with this directory as its target |
| Six feature cards and a one-line feature strip | `src/data/features.ts`; each card names its `stem` | by hand, with the feature |
| Comparison table | `src/data/comparison.ts`; `checked` is the date the facts were verified | by hand, after re-reading each competitor's README |
| Privacy section | `src/components/agenttacho/Privacy.astro` | by hand; it mirrors the README's "Security and privacy" section |
| Download button and version | `src/utils/release.ts` reads the latest release of `AgentTacho/agenttacho` at build time; `src/data/release-fallback.json` when the API fails | `make release` publishes the release; the fallback file by hand |
| Social card | `src/assets/images/og.png`, composed by `scripts/make-og.sh` from the icon, the headline and the `menubar-dark` shot | run the script after the menubar shot changed |

Stems (spec 031 FR-011): `menubar`, `budget`, `harnesses`, `prices`, `menubar-settings`, `glance`, `same-provider`. The capture writes only these 14 files and never deletes others in its target; images of dropped stems leave the site in its own pull request.

## Build and check

```bash
cd <site checkout>
npm ci
export GITHUB_TOKEN=$(gh auth token)   # the build reads the GitHub API; without a token it may hit the rate limit and fall back
npm run check                           # astro check, ESLint, Prettier
npm run build                           # writes dist/
npm test                                # release lookup and page contract tests; needs dist/ from the build
npm run dev                             # http://localhost:4321, look at both themes and at phone width
```

The page contract tests (`tests/page.test.ts`) fail when a card lacks its dark image, when the count of cards (six) changes or the one-line feature strip goes missing, when the download link carries no version, or when the copy contains an em dash, an en dash, "calm glance", "no dashboard" or "the only private/tracker/menu bar". Change a count and its test together, on purpose, never the test alone.

## Recapture the screenshots

1. Get the maintainer's go for the run: the capture quits AgentTacho, switches the appearance twice and moves the mouse.
2. In the app repository: `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho`. It builds the demo app itself, so run it from a clean `make test`. First time on a Mac: give the terminal Accessibility, Screen Recording and Automation (System Events) permission. No notification setup is needed; no shot shows a notification.
3. The script ends with the 14 files and their pixel sizes; size the card image areas from them. On a failure it names the stems it could not capture and the target keeps its old files.
4. `git status` in the site checkout lists the changed images. Look at each in both themes; `npm run dev` shows them in place.
5. When `menubar-dark.webp` changed: `scripts/make-og.sh`.
6. `npm run check && npm run build && npm test`, then a pull request.

Reading the result: a real 2x shot is tens to hundreds of kilobytes. The placeholders from `scripts/make-placeholders.sh` are 2 to 8 KB; a tiny file in `src/assets/agenttacho` means the real capture never landed there.

## Scope

When a feature touches the site, change only:

- `src/assets/agenttacho/<stem>-{light,dark}.webp` (through the capture script, never by hand)
- `src/data/features.ts` (cards and the feature strip), `src/data/comparison.ts` (set `checked` to today when the facts were re-verified), `src/components/agenttacho/Privacy.astro` (mirrors the README's "Security and privacy" section)
- `src/assets/images/og.png` through `scripts/make-og.sh`
- `src/data/release-fallback.json` after a release

Leave the AstroWind plumbing (`src/utils/`, `vendor/`, `src/components/` outside `agenttacho/`) and `.github/workflows/deploy.yml` alone unless the task is about the site itself. The page contract tests in `tests/` change only together with the count or copy they check, never alone. Never commit a screenshot of the real app.

## Deploy

- `deploy.yml` runs on every push to `main`, on pull requests (check and build only), daily at 05:17 UTC, and on `gh workflow run deploy.yml -R AgentTacho/agenttacho.github.io`.
- The Pages upload and the deploy job run only while the repository variable `SITE_LIVE` is `true`. Setting it is the maintainer's decision: `gh variable set SITE_LIVE -b true -R AgentTacho/agenttacho.github.io`. The site goes live only with real screenshots in place.
- `make release` in the app repository starts `deploy.yml` after it published the latest release (`SITE_REPO` in the Makefile), so the download button follows a release within minutes. The daily run is a safety net: GitHub disables scheduled workflows in a public repository after 60 days without a commit; re-enable it under Actions when it shows as disabled.
- After each release, set `src/data/release-fallback.json` to the new version and DMG name, so a build that cannot reach the API still names a file that exists.

## Domains

- `agenttacho.dev` is the site's address. `agenttacho.com` only redirects to it. Both are registered at Porkbun and use Cloudflare's nameservers; DNS changes happen in the Cloudflare dashboard, not at Porkbun.
- `agenttacho.dev`: four A and four AAAA records for GitHub Pages and `www` as a CNAME to `agenttacho.github.io`, all "DNS only" (grey cloud). GitHub Pages issues its own certificate and cannot do that behind Cloudflare's proxy.
- `agenttacho.com`: placeholder records `192.0.2.1` for the apex and `www`, proxied (orange cloud), and a Cloudflare redirect rule that sends every request to `https://agenttacho.dev` with the path and query string, status 301.
- The custom domain is a setting of the Pages site, not a `CNAME` file, because the site deploys from Actions: `gh api repos/AgentTacho/agenttacho.github.io/pages` shows it. `https://agenttacho.github.io` redirects to the custom domain.
- `site` in `src/config.yaml` must name `https://agenttacho.dev`; it feeds the canonical link, the sitemap and the social card URL.
- `.dev` is on the browsers' HSTS preload list, so the site works over HTTPS only. A missing or expired GitHub certificate takes the whole site down, not just the padlock.

## Pitfalls

- The real app and the demo app both have an executable named `AgentTacho`. Tell them apart by bundle id (`dev.rhuss.agenttacho`, `dev.rhuss.agenttacho.demo`) or by path, never by process name; `fs_usage` and `pgrep` by name see both.
- The capture refuses to start while the appearance is on Auto or without a 2x display, and says what to change. It restores the appearance and restarts AgentTacho even after Ctrl-C.
- zsh has a `log` builtin that hides `/usr/bin/log`; use the full path to read the unified log.
- "The timestamp service is not available" from code signing is a network hiccup; run `make app-demo` again.
- The feature cards show each shot in a 327 by 122 pixel box with `object-contain`, so a large shot shrinks until its text cannot be read. The Settings shots (`menubar-settings`, `prices`) are strips cut around identified views and must stay within 727 by 271 points (a card scale of 0.45); `capture.sh` fails a larger strip and names its size (spec 031 FR-011a, from spec 029 FR-008a). When a Settings change makes a strip too large, shorten the strip rather than raising the limit.
