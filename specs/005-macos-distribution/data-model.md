# Data Model: macOS Distribution (005)

No persistent application data changes. The entities below are values computed and passed between release scripts, plus the files they produce.

## VersionInfo

Computed by `lib.sh: version_info` from git state.

| Field | Type | Rule |
|---|---|---|
| `mode` | `release` \| `dev` | `release` only when HEAD is exactly at a tag matching `^v[0-9]+\.[0-9]+\.[0-9]+$` and the working tree is clean |
| `short_version` | `X.Y.Z` (numbers only) | release: the tag without `v`; dev: nearest matching tag without `v`, or `0.0.0` |
| `display_version` | string | release: `short_version`; dev: `short_version` + `-dev` |
| `build_number` | positive integer | `git rev-list --count HEAD` |
| `tag` | `vX.Y.Z` or empty | set in release mode only |

Written into the bundle's `Info.plist` as `CFBundleShortVersionString`, `CFBundleVersion`, `AgentTachoVersionDisplay`.

## SigningTier

Selected by `lib.sh: select_identity` from `security find-identity -p codesigning` output and overrides.

| Tier | Selected when | Identity passed to codesign | codesign flags | Notarizable | Permissions persist |
|---|---|---|---|---|---|
| `developer-id` | an identity named `Developer ID Application: …` exists | its SHA-1 | `--options runtime --timestamp` | yes, if a notary profile exists | yes |
| `self-signed` | an identity named `$SIGN_IDENTITY_NAME` (default `AgentTacho Signing`) exists | its SHA-1 | `--timestamp=none` | no | yes |
| `ad-hoc` | neither exists, or `SIGN_IDENTITY=-` | `-` | `--timestamp=none` | no | no |

An explicit `SIGN_IDENTITY` (name or SHA-1) skips selection; its tier is derived from the matching identity's name (`Developer ID Application:` prefix gives `developer-id`, `-` gives `ad-hoc`, anything else `self-signed`).

`self-signed` therefore means "any certificate that is not a Developer ID Application certificate", including certificates that are not self-signed, such as an "Apple Development" certificate passed through `SIGN_IDENTITY`. The tier only decides what depends on it (stable designated requirement, not notarizable, DMG background and caveats with first-launch steps), and that is the same for all of them; there is no separate tier for other certificates (decided after the code review, FINDING-26).

**Validation**: for `developer-id` and `self-signed`, `codesign -d -r-` on the built app MUST NOT contain `cdhash`.

## NotarizationStatus

| Value | When |
|---|---|
| `notarized` | tier is `developer-id`, profile `$NOTARY_PROFILE` (default `agenttacho-notary`) exists, submission accepted, staple validated |
| `not-notarized` | any other tier, or Developer ID without a profile (warning printed) |

Rejection or timeout is not a status: the release stops.

Determines the DMG background variant, the release-notes first-launch section, the cask caveats.

## ReleaseInfo (`release-info.json`, uploaded with each release)

| Field | Type | Example |
|---|---|---|
| `version` | string `X.Y.Z` | `"0.2.0"` |
| `dmg` | string | `"AgentTacho-0.2.0.dmg"` |
| `sha256` | 64 lowercase hex chars | `"9f2c…"` |
| `tier` | `developer-id` \| `self-signed` \| `ad-hoc` | `"self-signed"` |
| `notarized` | boolean | `false` |

Schema and examples: [contracts/release-info.md](contracts/release-info.md). Read back by the cask-only command.

## CaskInputs

Rendered into `Casks/agenttacho.rb` from `packaging/homebrew/agenttacho.rb.tmpl`.

| Input | Source |
|---|---|
| `version` | `ReleaseInfo.version` |
| `sha256` | `ReleaseInfo.sha256` |
| `caveats` | present only when `notarized` is false: first-launch steps for macOS 14 and 15+, the `xattr` command; in every release, "Homebrew quits AgentTacho before an upgrade and opens it again afterwards" |

Contract: [contracts/cask.md](contracts/cask.md).

## Release lifecycle (state transitions)

```text
preflight ──fail──> stopped (nothing created)
    │ ok
build ─> dmg ─> notarize? ──reject──> stopped (nothing published; notary log saved)
    │
draft release created ──upload fail──> draft remains (invisible; delete command printed)
    │ uploads ok
published ──cask fail──> published, cask stale (make cask VERSION=… printed)
    │
cask updated ──> done
```
