#!/bin/bash
# Builds build/AgentMeter.app: compiles the release binary, assembles the
# bundle with icon and resources, stamps the version from git and signs it with
# the best available identity (plan.md, "Build and signing flow").
#
# Environment: SIGN_IDENTITY, SIGN_IDENTITY_NAME, APP_ICON (default
# Resources/icons/macos/AgentMeter.icns), RELEASE_ROOT (repository to build,
# default the one containing this script), DISTRIBUTION (1 for builds that
# leave this Mac, set by release.sh), NOTARIZE (true when release.sh will
# notarize the build, stamped for the About tab), UPDATE_TEST and UPDATE_SOURCE
# (UPDATE_TEST=1 makes an update-test build that reads its releases from the
# owner/repo in UPDATE_SOURCE, spec 013 FR-025; only `make app-update-test`
# sets it). Run it through `make app`, which selects the SDK the Swift build
# needs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
release_defaults

# Update-test build (spec 013 FR-025, contracts/make-targets.md): checked
# before anything else, so an invalid source never starts a build.
update_test=false
if [ "${UPDATE_TEST:-}" = "1" ]; then
    [ -n "${UPDATE_SOURCE:-}" ] ||
        die "UPDATE_SOURCE is required for an update-test build, for example: make app-update-test UPDATE_SOURCE=owner/repo"
    [[ "$UPDATE_SOURCE" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] ||
        die "UPDATE_SOURCE must look like owner/repo: $UPDATE_SOURCE"
    update_test=true
fi

cd "${RELEASE_ROOT:-$SCRIPT_DIR/../..}"

BUNDLE_ID="dev.rhuss.agentmeter"
EXECUTABLE="AgentMeter"
RELEASE_BUILD=".build/release"
# SwiftPM names the resource bundle <package>_<target>.bundle; Bundle.module
# looks for it in the app's Contents/Resources.
RESOURCE_BUNDLE="$RELEASE_BUILD/agentmeter_UsageCore.bundle"
# Template-image variant of the icon for the About tab; optional, the tab
# falls back to the app icon without it.
MONO_ICON="Resources/icons/mono/AgentMeter-mono.png"

[ -f "$APP_ICON" ] || die "missing app icon: $APP_ICON"

version="$(version_info)"
read -r mode short_version display_version build_number tag <<<"$version"
commit="$(git rev-parse HEAD)" || die "cannot read the commit of HEAD"
build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
identity="$(select_identity)"
tier="${identity%% *}"
identity="${identity#* }"
sign_hash="${identity%% *}"
sign_name="${identity#* }"

if [ "$update_test" = "true" ]; then
    swift build -c release -Xswiftc -DAGENTMETER_UPDATE_TEST
else
    swift build -c release
fi

# The resource accessor of SwiftPM's native build system looks for the
# resource bundle only next to the .app and then at an absolute path on this
# machine, so a distributed app would crash on another Mac. The accessor of
# the swiftbuild backend looks in Contents/Resources, where it is copied below.
# Local builds still work through the absolute path, so only builds for
# distribution (DISTRIBUTION=1, set by release.sh) stop.
if grep -qa "could not load resource bundle" "$RELEASE_BUILD/$EXECUTABLE"; then
    if [ "${DISTRIBUTION:-}" = "1" ]; then
        die "$RELEASE_BUILD/$EXECUTABLE uses SwiftPM's native resource accessor, which cannot find resources in Contents/Resources on another Mac; build with a toolchain whose default build system is swiftbuild"
    fi
    warn "SwiftPM's native resource accessor: this app finds its resources only on this Mac, do not distribute it"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$RELEASE_BUILD/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$APP_ICON" "$APP/Contents/Resources/AgentMeter.icns"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
if [ -f "$MONO_ICON" ]; then
    cp "$MONO_ICON" "$APP/Contents/Resources/AgentMeter-mono.png"
fi
# The feat, fix and perf commits since the previous release (About tab).
release_changes "$mode" >"$APP/Contents/Resources/changes.json"

plist="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $short_version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"
/usr/libexec/PlistBuddy -c "Delete :AgentMeterVersionDisplay" "$plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :AgentMeterVersionDisplay string $display_version" "$plist"
# Release data for the About tab. The signature seals the plist, so whether
# the build gets notarized is decided by release.sh before it builds.
for key in AgentMeterCommit AgentMeterBuildDate AgentMeterReleaseTag AgentMeterSigning AgentMeterNotarized AgentMeterUpdateSource; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" >/dev/null 2>&1 || true
done
/usr/libexec/PlistBuddy -c "Add :AgentMeterCommit string $commit" "$plist"
/usr/libexec/PlistBuddy -c "Add :AgentMeterBuildDate string $build_date" "$plist"
if [ "$mode" = "release" ] && [ -n "$tag" ]; then
    /usr/libexec/PlistBuddy -c "Add :AgentMeterReleaseTag string $tag" "$plist"
fi
/usr/libexec/PlistBuddy -c "Add :AgentMeterSigning string $tier" "$plist"
if [ "$(effective_notarized "$tier" "${NOTARIZE:-false}")" = "true" ]; then
    /usr/libexec/PlistBuddy -c "Add :AgentMeterNotarized bool true" "$plist"
fi

# The release source of an update-test build; a build without the flag never
# reads this key (spec 013 FR-025).
if [ "$update_test" = "true" ]; then
    /usr/libexec/PlistBuddy -c "Add :AgentMeterUpdateSource string $UPDATE_SOURCE" "$plist"
fi

log version "$display_version (build $build_number)"
if [ "$update_test" = "true" ]; then
    log build "update-test build, release source $UPDATE_SOURCE"
fi
log signing "$tier ($sign_name)"

# shellcheck disable=SC2046
codesign --force --sign "$sign_hash" --identifier "$BUNDLE_ID" $(codesign_flags "$tier") "$APP"
codesign --verify --strict "$APP"

if [ "$tier" = "ad-hoc" ]; then
    warn "ad-hoc signature, notification permission and start at login will not persist across rebuilds"
else
    requirement="$(codesign -d -r- "$APP" 2>&1 | grep 'designated' || true)"
    requirement_is_certificate_based "$requirement" ||
        die "designated requirement is not certificate based: ${requirement:-none}"
fi

echo "Built $APP"
