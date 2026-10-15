#!/bin/bash
# Creates build/release/AgentMeter-<display_version>.dmg with the background
# variant for the signing tier and notarization, the volume icon and an
# Applications link; signs it only when it will be notarized and writes the .sha256 file
# (FR-009 to FR-013).
#
# Usage: make-dmg.sh <app> <display_version> <tier> <notarized> <identity-hash-or-dash>
#   notarized: true when the DMG will be notarized (selects the background
#   without first-launch instructions).
# Environment: APP_ICON, RELEASE_ROOT (repository the relative paths refer
# to, default the one containing this script).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
release_defaults
cd "${RELEASE_ROOT:-$SCRIPT_DIR/../..}"

[ "$#" -eq 5 ] || die "usage: make-dmg.sh <app> <display_version> <tier> <notarized> <identity-hash-or-dash>"
app="$1"
display_version="$2"
tier="$3"
notarized="$4"
identity="$5"

[ -d "$app" ] || die "app bundle not found: $app"
[ -f "$APP_ICON" ] || die "missing app icon: $APP_ICON"

background="$(dmg_background "$tier" "$notarized")"
[ -f "$background" ] || die "missing DMG background: $background"

dmg_name="$(dmg_filename "$display_version")"
dmg="$OUT_DIR/$dmg_name"
mkdir -p "$OUT_DIR"
rm -f "$dmg" "$dmg.sha256"

# dmgbuild and its dependencies are pinned, so the release step never picks
# up a new upstream version on the signing machine.
uvx --from dmgbuild==1.6.7 --with ds_store==1.3.3 --with mac_alias==2.2.3 dmgbuild \
    -s "$SCRIPT_DIR/dmg-settings.py" \
    -D "app=$app" \
    -D "background=$background" \
    -D "icon=$APP_ICON" \
    "AgentMeter" "$dmg"

# Only a DMG that gets notarized is signed: Gatekeeper refuses to mount a
# quarantined signed DMG without notarization and offers no "Open Anyway" for
# it, while an unsigned DMG mounts and only the signed app inside is checked.
if [ "$notarized" = "true" ]; then
    # shellcheck disable=SC2046
    codesign --force --sign "$identity" $(codesign_flags "$tier") "$dmg"
fi

(cd "$OUT_DIR" && shasum -a 256 "$dmg_name" >"$dmg_name.sha256")

if [ "$notarized" = "true" ]; then
    log dmg "$dmg ($tier, notarizable)"
else
    log dmg "$dmg ($tier, not notarized)"
fi
