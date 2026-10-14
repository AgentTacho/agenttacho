#!/bin/bash
# Notarizes and staples a Developer ID signed DMG (FR-014, research.md R6).
#
# Usage: notarize.sh <dmg>
# Environment: NOTARY_PROFILE (default agentmeter-notary), RELEASE_ROOT
# (default: the repository root; Apple's log goes to build/release/ below it).
# A rejection or a timeout stops with the log saved to
# build/release/notary-log.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
release_defaults
cd "${RELEASE_ROOT:-$SCRIPT_DIR/../..}"

[ "$#" -eq 1 ] || die "usage: notarize.sh <dmg>"
dmg="$1"
[ -f "$dmg" ] || die "DMG not found: $dmg"
profile="$NOTARY_PROFILE"
notary_log="$OUT_DIR/notary-log.json"

log notary "submitting $dmg (profile $profile), this can take several minutes"
result="$(xcrun notarytool submit "$dmg" --wait --timeout 1h \
    --keychain-profile "$profile" --output-format json </dev/null)" || true
submission_id="$(printf '%s' "$result" | jq -r '.id // empty' 2>/dev/null || true)"
status="$(printf '%s' "$result" | jq -r '.status // empty' 2>/dev/null || true)"

if [ "$status" != "Accepted" ]; then
    if [ -n "$submission_id" ]; then
        mkdir -p "$(dirname "$notary_log")"
        rm -f "$notary_log"
        xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$notary_log" </dev/null >/dev/null 2>&1 || true
        if [ -f "$notary_log" ]; then
            die "notarization not accepted (status: ${status:-unknown}, submission $submission_id); Apple's log: $notary_log"
        fi
        die "notarization not accepted (status: ${status:-unknown}, submission $submission_id); no log yet, fetch it later with: xcrun notarytool log $submission_id --keychain-profile $profile"
    fi
    die "notarization submission failed: ${result:-no response from notarytool}"
fi

log notary "accepted (submission $submission_id)"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
log notary "stapled $dmg"
