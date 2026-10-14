#!/bin/bash
# Publishes an AgentMeter release (FR-015 to FR-019, contracts/make-targets.md).
#
# Usage: release.sh [--dry-run]
#
# Steps: preflight, build, DMG, notarization (Developer ID with a notary
# profile), release notes and release-info.json, draft GitHub release, uploads,
# publish, cask update. --dry-run stops after the local files, never notarizes
# and never writes to GitHub or the tap; preflight problems are only warnings.
#
# Environment: SIGN_IDENTITY, SIGN_IDENTITY_NAME, NOTARY_PROFILE, ALLOW_ADHOC,
# REPLACE, TAP_REPO, GH_REPO. For tests: RELEASE_ROOT (repository to release,
# default the one containing this script) and BUILD_APP_SH, MAKE_DMG_SH,
# NOTARIZE_SH, UPDATE_CASK_SH (helper scripts, default the sibling scripts).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
release_defaults
cd "${RELEASE_ROOT:-$SCRIPT_DIR/../..}"

dry_run=false
case "${1:-}" in
    --dry-run) dry_run=true ;;
    "") ;;
    *) die "usage: release.sh [--dry-run]" ;;
esac

BUILD_APP_SH="${BUILD_APP_SH:-$SCRIPT_DIR/build-app.sh}"
MAKE_DMG_SH="${MAKE_DMG_SH:-$SCRIPT_DIR/make-dmg.sh}"
NOTARIZE_SH="${NOTARIZE_SH:-$SCRIPT_DIR/notarize.sh}"
UPDATE_CASK_SH="${UPDATE_CASK_SH:-$SCRIPT_DIR/update-cask.sh}"
export GH_PROMPT_DISABLED=1 GIT_TERMINAL_PROMPT=0

if [ "$dry_run" = "true" ]; then
    preflight dry-run
else
    preflight release
fi

identity="$(select_identity)"
tier="${identity%% *}"
identity="${identity#* }"
sign_hash="${identity%% *}"
version="$(version_info)"
read -r mode short_version display_version _build tag <<<"$version"
# Preflight already stops a release without a clean vX.Y.Z commit; this keeps
# a development version from ever being published.
if [ "$dry_run" = "false" ] && { [ "$mode" != "release" ] || [ -z "$tag" ]; }; then
    die "HEAD is not a clean commit with a vX.Y.Z tag"
fi

# notarize: the DMG will be submitted (selects the background); notarized:
# it was accepted and stapled (release notes and release-info.json).
notarize=false
notarized=false
if [ "$tier" = "developer-id" ]; then
    notary_state="$(notary_profile_state)"
    case "$notary_state" in
        available) notarize=true ;;
        missing)
            warn "Developer ID certificate without notarization profile $NOTARY_PROFILE, releasing as Developer ID, not notarized" ;;
        *)
            if [ "$dry_run" = "true" ]; then
                warn "cannot check notarization profile $NOTARY_PROFILE (${notary_state#error }), the dry run continues without notarization"
            else
                die "cannot check notarization profile $NOTARY_PROFILE: ${notary_state#error }"
            fi ;;
    esac
fi

# The build uses exactly the identity selected here.
SIGN_IDENTITY="$sign_hash" DISTRIBUTION=1 bash "$BUILD_APP_SH"

bash "$MAKE_DMG_SH" "$APP" "$display_version" "$tier" "$notarize" "$sign_hash"
dmg_name="$(dmg_filename "$display_version")"
dmg="$OUT_DIR/$dmg_name"

if [ "$notarize" = "true" ] && [ "$dry_run" = "false" ]; then
    bash "$NOTARIZE_SH" "$dmg"
    notarized=true
    # Stapling changes the DMG, so the checksum is taken again.
    (cd "$OUT_DIR" && shasum -a 256 "$dmg_name" >"$dmg_name.sha256")
fi

sha256="$(awk '{print $1; exit}' "$dmg.sha256")"
notes="$OUT_DIR/release-notes.md"
info="$OUT_DIR/release-info.json"
release_notes "$display_version" "$tier" "$notarized" >"$notes"
release_info_json "$display_version" "$sha256" "$tier" "$notarized" >"$info"

# The cask takes its checksum from release-info.json, so it must be the one
# of the final (stapled) DMG that gets uploaded.
dmg_sha256="$(shasum -a 256 "$dmg" | awk '{print $1}')"
info_sha256="$(jq -r '.sha256' "$info")"
[ "$info_sha256" = "$dmg_sha256" ] ||
    die "release-info.json has sha256 ${info_sha256:-none}, but $dmg has $dmg_sha256"

# The dry run ends with the `dmg:` line printed by make-dmg.sh.
[ "$dry_run" = "false" ] || exit 0

# From here on, a failure leaves state on GitHub; the exit trap names it.
phase="before-release"
step=""
on_exit() {
    local status=$?
    [ "$status" -ne 0 ] || return 0
    case "$phase" in
        draft)
            printf 'error: %s failed; draft release %s left in place, retry with: make release REPLACE=1, or delete with: gh release delete %s -R %s --yes\n' \
                "$step" "$tag" "$tag" "$GH_REPO" >&2 ;;
        published)
            printf 'error: %s failed; release %s is published, retry with: make release REPLACE=1\n' \
                "$step" "$tag" >&2 ;;
        cask)
            printf 'error: cask update failed; finish with: make cask VERSION=%s\n' "$short_version" >&2 ;;
    esac
}
trap on_exit EXIT

release_exists=false
if [ "${REPLACE:-}" = "1" ] && gh release view "$tag" -R "$GH_REPO" >/dev/null 2>&1 </dev/null; then
    release_exists=true
fi

if [ "$release_exists" = "true" ]; then
    if [ "$(gh release view "$tag" -R "$GH_REPO" --json isDraft -q .isDraft </dev/null)" = "true" ]; then
        phase="draft"
    else
        phase="published"
    fi
    log release "replacing assets of existing release $tag"
else
    step="creating the draft release"
    gh release create "$tag" -R "$GH_REPO" --draft --verify-tag \
        --title "AgentMeter $short_version" --notes-file "$notes" </dev/null >/dev/null
    phase="draft"
    log release "created draft release $tag"
fi

clobber=""
[ "${REPLACE:-}" = "1" ] && clobber="--clobber"
for asset in "$dmg" "$dmg.sha256" "$info"; do
    step="uploading $(basename "$asset")"
    # shellcheck disable=SC2086
    gh release upload "$tag" "$asset" -R "$GH_REPO" $clobber </dev/null
    log release "uploaded $(basename "$asset")"
done

step="publishing the release"
gh release edit "$tag" -R "$GH_REPO" --draft=false --notes-file "$notes" </dev/null >/dev/null
phase="published"
log release "published $tag"

phase="cask"
bash "$UPDATE_CASK_SH" "$short_version" </dev/null
phase="done"
log release "done: AgentMeter $short_version"
