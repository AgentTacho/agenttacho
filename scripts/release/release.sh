#!/bin/bash
# Publishes an AgentTacho release (spec 005 FR-015 to FR-019,
# contracts/make-targets.md).
#
# Usage: release.sh [--dry-run]
#
# Steps: preflight, build, DMG, notarization (Developer ID with a notary
# profile), release notes and release-info.json, draft GitHub release, uploads,
# publish, site deploy (latest release of the official repository only),
# cask update. Replacing the assets of a published release
# (REPLACE=1) switches it back to a draft first and publishes it again only
# after every upload succeeded, so users never see a release with a missing
# or mismatched asset; every publish marks the release as latest exactly when
# its tag is the highest published release tag (spec 015 FR-016). --dry-run
# stops after the local files, never notarizes and never writes to GitHub or
# the tap; preflight problems are only warnings.
#
# Environment: SIGN_IDENTITY, SIGN_IDENTITY_NAME, NOTARY_PROFILE, ALLOW_ADHOC,
# ALLOW_TIER_DOWNGRADE (lets a release fall back from an expired or revoked
# Developer ID certificate to the next tier, spec 015 FR-013),
# ALLOW_UNNOTARIZED (lets a Developer ID release go out without a
# notarization profile, spec 023 FR-015), REPLACE,
# TAP_REPO, GH_REPO, SITE_REPO. For tests: RELEASE_ROOT (repository to release,
# default the one containing this script) and BUILD_APP_SH, MAKE_DMG_SH,
# NOTARIZE_SH, UPDATE_CASK_SH (helper scripts, default the sibling scripts).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
release_defaults
# Release builds never carry the update-test flag (spec 013 FR-025).
[ -z "${UPDATE_TEST:-}" ] || die "UPDATE_TEST is set; release builds never carry the update-test flag"
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
            # A missing profile never drops notarization unnoticed, for
            # example when it was never stored under its name (spec 023
            # FR-015); ALLOW_UNNOTARIZED=1 releases without it on purpose.
            if [ "${ALLOW_UNNOTARIZED:-}" = "1" ]; then
                warn "Developer ID certificate without notarization profile $NOTARY_PROFILE, releasing as Developer ID, not notarized (deliberate, ALLOW_UNNOTARIZED=1)"
            elif [ "$dry_run" = "true" ]; then
                warn "Developer ID certificate without notarization profile $NOTARY_PROFILE; a real release would stop unless ALLOW_UNNOTARIZED=1 is set"
            else
                die "notarization profile $NOTARY_PROFILE not found; store it with: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id <team-id>, or set ALLOW_UNNOTARIZED=1 to release without notarization"
            fi ;;
        *)
            if [ "$dry_run" = "true" ]; then
                warn "cannot check notarization profile $NOTARY_PROFILE (${notary_state#error }), the dry run continues without notarization"
            else
                die "cannot check notarization profile $NOTARY_PROFILE: ${notary_state#error }"
            fi ;;
    esac
fi

# The build uses exactly the identity selected here and stamps the
# notarization decision into its Info.plist, which the signature seals.
SIGN_IDENTITY="$sign_hash" DISTRIBUTION=1 NOTARIZE="$notarize" bash "$BUILD_APP_SH"

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
release_notes "$display_version" "$tier" "$notarized" "$(release_changes "$mode")" >"$notes"
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
was_published=false
on_exit() {
    local status=$?
    [ "$status" -ne 0 ] || return 0
    case "$phase" in
        draft)
            printf 'error: %s failed; draft release %s left in place, retry with: make release REPLACE=1, or delete with: gh release delete %s -R %s --yes\n' \
                "$step" "$tag" "$tag" "$GH_REPO" >&2
            if [ "$was_published" = "true" ]; then
                printf 'note: %s was published before; its downloads (also through the Homebrew cask) fail until a retry publishes it again\n' \
                    "$tag" >&2
            fi ;;
        published)
            printf 'error: %s failed; release %s is published, retry with: make release REPLACE=1\n' \
                "$step" "$tag" >&2 ;;
        cask)
            printf 'error: cask update failed; finish with: make cask VERSION=%s\n' "$short_version" >&2 ;;
    esac
}
trap on_exit EXIT

# Latest by version, not by what GitHub reports: the same answer before the
# draft switch and on a retry of a draft, and a retried older tag never
# becomes "Latest" (spec 015 FR-016, research R7). The cask update keeps its
# own version check (spec 005 FR-021).
published_tags="$(gh release list -R "$GH_REPO" --exclude-drafts --limit 1000 \
    --json tagName -q '.[].tagName' </dev/null)" || die "cannot list the releases of $GH_REPO"
latest_flag="--latest=false"
if [ "$(printf '%s\n%s\n' "$published_tags" "$tag" | highest_release_tag)" = "$tag" ]; then
    latest_flag="--latest"
fi

release_exists=false
if [ "${REPLACE:-}" = "1" ] && gh release view "$tag" -R "$GH_REPO" >/dev/null 2>&1 </dev/null; then
    release_exists=true
fi

if [ "$release_exists" = "true" ]; then
    if [ "$(gh release view "$tag" -R "$GH_REPO" --json isDraft -q .isDraft </dev/null)" = "true" ]; then
        phase="draft"
        log release "replacing assets of draft release $tag"
    else
        # A failed switch leaves the release published and unchanged.
        phase="published"
        step="switching the release to a draft"
        gh release edit "$tag" -R "$GH_REPO" --draft=true </dev/null >/dev/null
        phase="draft"
        was_published=true
        log release "switched release $tag to a draft to replace its assets"
    fi
else
    step="creating the draft release"
    gh release create "$tag" -R "$GH_REPO" --draft --verify-tag \
        --title "AgentTacho $short_version" --notes-file "$notes" </dev/null >/dev/null
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
gh release edit "$tag" -R "$GH_REPO" --draft=false --notes-file "$notes" "$latest_flag" </dev/null >/dev/null
phase="published"
log release "published $tag"

# The site shows the latest release, so a latest release of the official
# repository starts its deploy; a failure only warns and never fails the
# release (spec 023 FR-018, contracts/release-and-tap.md).
if [ "$latest_flag" = "--latest" ] && [ "$GH_REPO" = "$OFFICIAL_GH_REPO" ]; then
    if deploy_err="$(gh workflow run deploy.yml -R "$SITE_REPO" </dev/null 2>&1 >/dev/null)"; then
        log release "started site deploy in $SITE_REPO"
    else
        log release "warning: $(with_reason "could not start the site deploy" "$deploy_err"); start it with: gh workflow run deploy.yml -R $SITE_REPO"
    fi
fi

phase="cask"
bash "$UPDATE_CASK_SH" "$short_version" </dev/null
phase="done"
log release "done: AgentTacho $short_version"
