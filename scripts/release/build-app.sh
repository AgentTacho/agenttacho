#!/bin/bash
# Builds build/AgentTacho.app: compiles the release binary, assembles the
# bundle with icon and resources, stamps the version from git and signs it with
# the best available identity (plan.md, "Build and signing flow").
#
# Environment: SIGN_IDENTITY, SIGN_IDENTITY_NAME, APP_ICON (default
# Resources/icons/macos/AgentTacho.icns), RELEASE_ROOT (repository to build,
# default the one containing this script), DISTRIBUTION (1 for builds that
# leave this Mac, set by release.sh), NOTARIZE (true when release.sh will
# notarize the build, stamped for the About tab), UPDATE_TEST and UPDATE_SOURCE
# (UPDATE_TEST=1 makes an update-test build that reads its releases from the
# owner/repo in UPDATE_SOURCE, spec 013 FR-025; only `make app-update-test`
# sets it), DEMO (DEMO=1 builds "AgentTacho Demo.app" with its own bundle id,
# the AGENTTACHO_DEMO flag, its own scratch path and the scenario files,
# spec 024 FR-001; only `make app-demo` sets it). Run it through `make app`,
# which selects the SDK the Swift build needs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
release_defaults

# Demo build (spec 024 FR-001, FR-002): never together with the update-test
# flag and never for distribution, checked first.
demo=false
if [ "${DEMO:-}" = "1" ]; then
    [ "${UPDATE_TEST:-}" != "1" ] || die "DEMO and UPDATE_TEST cannot be combined"
    [ "${DISTRIBUTION:-}" != "1" ] || die "demo builds are never distributed"
    demo=true
fi

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

EXECUTABLE="AgentTacho"
RELEASE_BUILD=".build/release"
# The demo build compiles into its own scratch path, so its flagged objects
# never reach a later regular or release build (spec 024 research R1).
DEMO_SCRATCH=".build/demo"
if [ "$demo" = "true" ]; then
    RELEASE_BUILD="$DEMO_SCRATCH/release"
fi
# SwiftPM names the resource bundle <package>_<target>.bundle; Bundle.module
# looks for it in the app's Contents/Resources.
RESOURCE_BUNDLE="$RELEASE_BUILD/agenttacho_UsageCore.bundle"
# Template-image variant of the icon for the About tab; optional, the tab
# falls back to the app icon without it.
MONO_ICON="Resources/icons/mono/AgentTacho-mono.png"

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

if [ "$demo" = "true" ]; then
    # DEMO=1 in the environment makes Package.swift compile the app with
    # AGENTTACHO_DEMO and link DemoMode.
    swift build -c release --scratch-path "$DEMO_SCRATCH"
elif [ "$update_test" = "true" ]; then
    swift build -c release -Xswiftc -DAGENTTACHO_UPDATE_TEST
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
# A regular build must not contain demo code (spec 024 FR-003, SC-006): the
# executable depends on DemoMode only in a demo build.
if [ "$demo" = "false" ]; then
    symbols="$(nm -U "$APP/Contents/MacOS/$EXECUTABLE")" || die "cannot list the symbols of $APP/Contents/MacOS/$EXECUTABLE"
    if grep -q DemoMode <<<"$symbols"; then
        die "the app links DemoMode symbols"
    fi
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$APP_ICON" "$APP/Contents/Resources/AgentTacho.icns"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
if [ -f "$MONO_ICON" ]; then
    cp "$MONO_ICON" "$APP/Contents/Resources/AgentTacho-mono.png"
fi
# The scenarios and the made-up LiteLLM prices go into the demo app only
# (spec 024 FR-003).
if [ "$demo" = "true" ]; then
    cp -R Resources/demo "$APP/Contents/Resources/demo"
fi
# The feat, fix and perf commits since the previous release (About tab).
release_changes "$mode" >"$APP/Contents/Resources/changes.json"

plist="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $short_version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"
/usr/libexec/PlistBuddy -c "Delete :AgentTachoVersionDisplay" "$plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :AgentTachoVersionDisplay string $display_version" "$plist"
# Release data for the About tab. The signature seals the plist, so whether
# the build gets notarized is decided by release.sh before it builds.
for key in AgentTachoCommit AgentTachoBuildDate AgentTachoReleaseTag AgentTachoSigning AgentTachoNotarized AgentTachoUpdateSource; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" >/dev/null 2>&1 || true
done
/usr/libexec/PlistBuddy -c "Add :AgentTachoCommit string $commit" "$plist"
/usr/libexec/PlistBuddy -c "Add :AgentTachoBuildDate string $build_date" "$plist"
if [ "$mode" = "release" ] && [ -n "$tag" ]; then
    /usr/libexec/PlistBuddy -c "Add :AgentTachoReleaseTag string $tag" "$plist"
fi
/usr/libexec/PlistBuddy -c "Add :AgentTachoSigning string $tier" "$plist"
if [ "$(effective_notarized "$tier" "${NOTARIZE:-false}")" = "true" ]; then
    /usr/libexec/PlistBuddy -c "Add :AgentTachoNotarized bool true" "$plist"
fi

# The demo app's own identity, so notification permission, preferences and
# the running-instance check never meet the installed AgentTacho (spec 024
# FR-001).
if [ "$demo" = "true" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName AgentTacho Demo" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName AgentTacho Demo" "$plist"
fi

# The release source of an update-test build; a build without the flag never
# reads this key (spec 013 FR-025).
if [ "$update_test" = "true" ]; then
    /usr/libexec/PlistBuddy -c "Add :AgentTachoUpdateSource string $UPDATE_SOURCE" "$plist"
fi

log version "$display_version (build $build_number)"
if [ "$update_test" = "true" ]; then
    log build "update-test build, release source $UPDATE_SOURCE"
fi
if [ "$demo" = "true" ]; then
    log build "demo build, bundle id $BUNDLE_ID"
fi
log signing "$tier ($sign_name)"
# A development build keeps the fallback below an expired or revoked
# Developer ID, but names the certificate (spec 015 FR-014). release.sh
# always passes SIGN_IDENTITY, so a release does not print this again.
if [ -z "${SIGN_IDENTITY:-}" ] && [ "$tier" != "developer-id" ]; then
    unusable="$(unusable_developer_ids)"
    if [ -n "$unusable" ]; then
        warn "$(unusable_developer_ids_text "$unusable"), signing on the next tier ($tier)"
    fi
fi

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
