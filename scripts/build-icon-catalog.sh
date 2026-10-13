#!/usr/bin/env bash
# Bundles Font Awesome Free into the UsageCore resources: the three web fonts,
# the license, and a compact icon catalog (icons.json) for the settings icon
# picker. The output is committed; rerun this script only to change versions.
#
# Usage: scripts/build-icon-catalog.sh
#
# Requires: curl, openssl, tar, jq.
set -euo pipefail

VERSION="7.3.1"
TARBALL_URL="https://registry.npmjs.org/@fortawesome/fontawesome-free/-/fontawesome-free-${VERSION}.tgz"
# npm "dist.integrity" of the tarball above.
INTEGRITY="sha512-wmglKKPDIkgV3aWlZzWECCPoGIkYCulzBwxG9+w7rc5BGapZ6cPMpoPOT8k36J0Ni7PPX6c/rsoMWfS4d1MUMg=="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/../Sources/UsageCore/Resources/FontAwesome"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading Font Awesome Free ${VERSION}"
curl -fsSL "$TARBALL_URL" -o "$WORK/fa.tgz"

ACTUAL="sha512-$(openssl dgst -sha512 -binary "$WORK/fa.tgz" | openssl base64 -A)"
if [ "$ACTUAL" != "$INTEGRITY" ]; then
  echo "Integrity mismatch: expected $INTEGRITY, got $ACTUAL" >&2
  exit 1
fi

mkdir "$WORK/pkg"
tar -xzf "$WORK/fa.tgz" -C "$WORK/pkg"
PKG="$WORK/pkg/package"

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$PKG/webfonts/fa-solid-900.woff2" "$PKG/webfonts/fa-regular-400.woff2" "$PKG/webfonts/fa-brands-400.woff2" "$OUT/"
cp "$PKG/LICENSE.txt" "$OUT/LICENSE.txt"

# One entry per free icon and style, sorted by name then style:
# n = name, l = label, u = unicode code point (hex), s = style, t = search terms.
jq -c --arg version "$VERSION" '
  {
    version: $version,
    icons: [
      to_entries[]
      | .key as $name
      | .value as $icon
      | ($icon.familyStylesByLicense.free // [])[]
      | select(.family == "classic")
      | {n: $name, l: ($icon.label // $name), u: $icon.unicode, s: .style,
         t: (($icon.search.terms // []) | map(tostring))}
    ] | sort_by(.n, .s)
  }' "$PKG/metadata/icon-families.json" > "$OUT/icons.json"

COUNT="$(jq '.icons | length' "$OUT/icons.json")"
echo "Wrote $COUNT icon entries and 3 fonts to $OUT"
