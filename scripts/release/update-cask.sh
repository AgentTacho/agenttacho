#!/bin/bash
# Updates the agenttacho cask in the Homebrew tap for a published release
# (FR-021, FR-021a). Reads version, checksum and notarization from the
# release's release-info.json, checks the checksum against the release's DMG,
# renders the cask, and commits and pushes it in a fresh temporary clone of
# the tap. The first update also renames the old agentmeter cask (spec 023
# FR-016). Only the latest published release updates the cask; for an older
# one (for example `make release REPLACE=1` on an old tag) it prints
# `cask: vX.Y.Z is not the latest release, cask left unchanged` and exits 0.
#
# Usage: update-cask.sh <version>      (X.Y.Z, without the leading v)
# Environment: GH_REPO, TAP_REPO (defaults in lib.sh release_defaults; other
# values are meant for testing only).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
release_defaults

[ "$#" -eq 1 ] || die "usage: update-cask.sh <version>"
version="$1"
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
    die "version must look like X.Y.Z: $version"

work="$(mktemp -d "${TMPDIR:-/tmp}/agenttacho-cask.XXXXXX")"
trap 'rm -rf "$work"' EXIT
# stderr of the remote commands; its last line goes into the error message.
err="$work/stderr"

# A draft's download URL is not public, so a cask pointing at it would fail
# for every user.
is_draft="$(noninteractive gh release view "v$version" -R "$GH_REPO" --json isDraft -q .isDraft 2>"$err")" ||
    die "$(with_reason "cannot find release v$version in $GH_REPO" "$(cat "$err")")"
[ "$is_draft" = "false" ] ||
    die "release v$version in $GH_REPO is not published yet; publish it first: gh release edit v$version -R $GH_REPO --draft=false"

# The cask always points at the newest release; an older one never moves it
# back (versions compare numerically per component).
latest="$(noninteractive gh release list -R "$GH_REPO" --exclude-drafts --limit 1000 \
    --json tagName -q '.[].tagName' 2>"$err" | highest_release_tag)" ||
    die "$(with_reason "cannot list the releases of $GH_REPO" "$(cat "$err")")"
[ -n "$latest" ] || die "cannot find the latest release of $GH_REPO"
if [ "$latest" != "v$version" ]; then
    log cask "v$version is not the latest release, cask left unchanged"
    exit 0
fi

noninteractive gh release download "v$version" -R "$GH_REPO" -p release-info.json -D "$work/info" >/dev/null 2>"$err" ||
    die "$(with_reason "cannot download release-info.json of release v$version from $GH_REPO" "$(cat "$err")")"
info="$work/info/release-info.json"
[ -f "$info" ] || die "release v$version in $GH_REPO has no release-info.json"

info_version="$(jq -r '.version // empty' "$info")"
sha256="$(jq -r '.sha256 // empty' "$info")"
notarized="$(jq -r '.notarized' "$info")"
[ "$info_version" = "$version" ] ||
    die "release-info.json has version ${info_version:-none}, expected $version"
printf '%s\n' "$sha256" | grep -Eq '^[0-9a-f]{64}$' ||
    die "release-info.json has an invalid sha256: ${sha256:-none}"
case "$notarized" in
    true | false) ;;
    *) die "release-info.json has an invalid notarized value: $notarized" ;;
esac

# The checksum must be the one of the DMG users download (FINDING-29).
dmg_name="$(dmg_filename "$version")"
noninteractive gh release download "v$version" -R "$GH_REPO" -p "$dmg_name" -D "$work/dmg" >/dev/null 2>"$err" ||
    die "$(with_reason "cannot download $dmg_name of release v$version from $GH_REPO" "$(cat "$err")")"
[ -f "$work/dmg/$dmg_name" ] || die "release v$version in $GH_REPO has no $dmg_name"
dmg_sha256="$(shasum -a 256 "$work/dmg/$dmg_name" | awk '{print $1}')"
[ "$dmg_sha256" = "$sha256" ] ||
    die "$dmg_name of release v$version has sha256 $dmg_sha256, but release-info.json says $sha256"

noninteractive git clone -q --depth 1 -- "$TAP_REPO" "$work/tap" 2>"$err" ||
    die "$(with_reason "cannot clone tap repository: $TAP_REPO" "$(cat "$err")")"
mkdir -p "$work/tap/Casks"
render_cask "$version" "$sha256" "$notarized" >"$work/tap/Casks/agenttacho.rb"

cd "$work/tap"
git add Casks/agenttacho.rb
# AgentMeter's cask becomes AgentTacho's once: the old file goes and
# cask_renames.json maps the old token to the new one, keeping other entries,
# so `brew upgrade` moves existing installs (spec 023 FR-016).
renamed=false
if [ -e Casks/agentmeter.rb ]; then
    git rm -q Casks/agentmeter.rb
    renamed=true
fi
renames='{}'
[ ! -f cask_renames.json ] || renames="$(cat cask_renames.json)"
if [ "$(printf '%s' "$renames" | jq -r '.agentmeter // empty')" != "agenttacho" ]; then
    printf '%s' "$renames" | jq '. + {"agentmeter": "agenttacho"}' >cask_renames.json ||
        die "cannot update cask_renames.json in tap repository: $TAP_REPO"
    git add cask_renames.json
    renamed=true
fi
if git diff --cached --quiet; then
    log cask "already up to date (agenttacho $version)"
    exit 0
fi
message="agenttacho $version"
[ "$renamed" = "false" ] || message="$message (renamed from agentmeter)"
git commit -q -m "$message"
noninteractive git push -q origin HEAD 2>"$err" ||
    die "$(with_reason "cannot push to tap repository: $TAP_REPO" "$(cat "$err")")"
log cask "pushed agenttacho $version to $TAP_REPO"
