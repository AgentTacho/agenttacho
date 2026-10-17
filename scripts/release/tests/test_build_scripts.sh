# Tests for build-app.sh (FR-001 to FR-008) and make-dmg.sh (FR-009 to
# FR-013) against fixture repositories, with swift, codesign, security and
# uvx stubbed. PlistBuddy is the real one.

. "$RELEASE_DIR/lib.sh"
. "$TESTS_DIR/helpers.sh"

PLIST_BUDDY=/usr/libexec/PlistBuddy

# --- build-app.sh ------------------------------------------------------------

# app_fixture: a repository with the Info.plist and an icon, tagged v0.2.0 at
# its second commit. Prints its path.
app_fixture() {
    local root="$TEST_TMP/app"
    make_git_repo "$root" >/dev/null
    mkdir -p "$root/Resources/icons/macos"
    cp "$REPO_ROOT/Resources/Info.plist" "$root/Resources/Info.plist"
    echo "icon" >"$root/Resources/icons/macos/AgentTacho.icns"
    printf '.build/\nbuild/\n' >"$root/.gitignore"
    git -C "$root" add .
    git -C "$root" commit -q -m "app"
    git -C "$root" tag v0.2.0
    printf '%s\n' "$root"
}

# stub_swift: `swift build` writes a binary and the resource bundle; with
# NATIVE_ACCESSOR=1 the binary carries the native SwiftPM accessor message.
stub_swift() {
    make_stub swift "
echo \"swift \$*\" >>\"$CALL_LOG\"
mkdir -p .build/release/agenttacho_UsageCore.bundle
if [ \"\${NATIVE_ACCESSOR:-0}\" = 1 ]; then
    echo 'could not load resource bundle: from a or b' >.build/release/AgentTacho
else
    echo 'unable to find bundle named agenttacho_UsageCore' >.build/release/AgentTacho
fi
chmod +x .build/release/AgentTacho"
}

# stub_codesign: records calls; `codesign -d -r-` prints CODESIGN_REQUIREMENT
# (default a certificate based requirement) on stderr, like codesign does.
stub_codesign() {
    make_stub codesign "
echo \"codesign \$*\" >>\"$CALL_LOG\"
case \"\$*\" in
    *-d*) echo \"designated => \${CODESIGN_REQUIREMENT:-identifier \\\"dev.rhuss.agenttacho\\\" and certificate leaf = H\\\"aaaa\\\"}\" >&2 ;;
esac
exit 0"
}

prepare_build() {
    stub_security "${1:-self-signed}"
    stub_swift
    stub_codesign
    APP_ROOT="$(app_fixture)"
}

build_app() {
    RELEASE_ROOT="$APP_ROOT" bash "$RELEASE_DIR/build-app.sh" </dev/null
}

plist_value() {
    "$PLIST_BUDDY" -c "Print :$1" "$APP_ROOT/build/AgentTacho.app/Contents/Info.plist"
}

test_build_app_stamps_version_icon_and_signs_self_signed() {
    prepare_build self-signed
    assert_status 0 build_app
    local out log
    out="$(cat "$LAST_OUT")"
    log="$(cat "$CALL_LOG")"
    assert_contains "$out" "version: 0.2.0 (build 2)"
    assert_contains "$out" "signing: self-signed (AgentTacho Signing)"
    assert_contains "$out" "Built build/AgentTacho.app"
    assert_eq "0.2.0" "$(plist_value CFBundleShortVersionString)"
    assert_eq "2" "$(plist_value CFBundleVersion)"
    assert_eq "0.2.0" "$(plist_value AgentTachoVersionDisplay)"
    assert_eq "AgentTacho" "$(plist_value CFBundleIconFile)"
    [ -f "$APP_ROOT/build/AgentTacho.app/Contents/Resources/AgentTacho.icns" ] || fail "icon not copied"
    [ -d "$APP_ROOT/build/AgentTacho.app/Contents/Resources/agenttacho_UsageCore.bundle" ] || fail "resource bundle not copied"
    [ -x "$APP_ROOT/build/AgentTacho.app/Contents/MacOS/AgentTacho" ] || fail "executable not copied"
    assert_contains "$log" "codesign --force --sign $SELF_SIGNED_HASH --identifier dev.rhuss.agenttacho --timestamp=none build/AgentTacho.app"
    assert_contains "$log" "codesign --verify --strict build/AgentTacho.app"
    assert_contains "$log" "codesign -d -r- build/AgentTacho.app"
    assert_eq "" "$(cat "$LAST_ERR")"
}

test_build_app_developer_id_uses_hardened_runtime_and_timestamp() {
    prepare_build developer-id
    assert_status 0 build_app
    assert_contains "$(cat "$LAST_OUT")" "signing: developer-id (Developer ID Application: Roland Huss (TEAM123456))"
    assert_contains "$(cat "$CALL_LOG")" "codesign --force --sign $DEVELOPER_ID_HASH --identifier dev.rhuss.agenttacho --options runtime --timestamp build/AgentTacho.app"
}

test_build_app_ad_hoc_warns_that_permissions_do_not_persist() {
    prepare_build ad-hoc
    assert_status 0 build_app
    assert_contains "$(cat "$LAST_OUT")" "signing: ad-hoc (no certificate)"
    assert_contains "$(cat "$LAST_ERR")" "warning: ad-hoc signature, notification permission and start at login will not persist across rebuilds"
    assert_contains "$(cat "$CALL_LOG")" "codesign --force --sign - --identifier dev.rhuss.agenttacho --timestamp=none build/AgentTacho.app"
    assert_not_contains "$(cat "$CALL_LOG")" "codesign -d"
}

# spec 015 FR-014: a development build with an unusable Developer ID falls
# back as before and names the certificate; a forced identity does not warn.
test_build_app_warns_about_an_unusable_developer_id() {
    stub_identities \
        "$DEVELOPER_ID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_CERT_EXPIRED)" \
        "$SELF_SIGNED_HASH \"AgentTacho Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    stub_swift
    stub_codesign
    APP_ROOT="$(app_fixture)"
    assert_status 0 build_app
    assert_contains "$(cat "$LAST_OUT")" "signing: self-signed (AgentTacho Signing)"
    assert_eq "warning: Developer ID certificate \"Developer ID Application: Roland Huss (TEAM123456)\" is expired, signing on the next tier (self-signed)" \
        "$(cat "$LAST_ERR")"
    SIGN_IDENTITY="$SELF_SIGNED_HASH" assert_status 0 build_app
    assert_eq "" "$(cat "$LAST_ERR")"
}

test_build_app_rejects_hash_based_requirement() {
    prepare_build self-signed
    CODESIGN_REQUIREMENT='cdhash H"0123"' assert_status 1 build_app
    assert_contains "$(cat "$LAST_ERR")" "error: designated requirement is not certificate based"
}

test_build_app_dev_version_after_tag() {
    prepare_build self-signed
    echo "more" >>"$APP_ROOT/README"
    git -C "$APP_ROOT" commit -q -am "more"
    assert_status 0 build_app
    assert_contains "$(cat "$LAST_OUT")" "version: 0.2.0-dev (build 3)"
    assert_eq "0.2.0" "$(plist_value CFBundleShortVersionString)"
    assert_eq "3" "$(plist_value CFBundleVersion)"
    assert_eq "0.2.0-dev" "$(plist_value AgentTachoVersionDisplay)"
}

test_build_app_refuses_native_resource_accessor_for_distribution() {
    prepare_build self-signed
    NATIVE_ACCESSOR=1 DISTRIBUTION=1 assert_status 1 build_app
    assert_contains "$(cat "$LAST_ERR")" "uses SwiftPM's native resource accessor"
    assert_not_contains "$(cat "$CALL_LOG")" "codesign --"
    [ ! -d "$APP_ROOT/build/AgentTacho.app" ] || fail "app bundle assembled despite the native accessor"
}

test_build_app_native_resource_accessor_only_warns_for_local_builds() {
    prepare_build self-signed
    NATIVE_ACCESSOR=1 assert_status 0 build_app
    assert_contains "$(cat "$LAST_ERR")" "warning: SwiftPM's native resource accessor: this app finds its resources only on this Mac"
    assert_contains "$(cat "$LAST_OUT")" "Built build/AgentTacho.app"
}

# --- build-app.sh: release data for the About tab ----------------------------

app_file() {
    printf '%s\n' "$APP_ROOT/build/AgentTacho.app/Contents/Resources/$1"
}

test_build_app_stamps_commit_build_date_signing_and_release_tag() {
    prepare_build self-signed
    assert_status 0 build_app
    assert_eq "$(git -C "$APP_ROOT" rev-parse HEAD)" "$(plist_value AgentTachoCommit)"
    [[ "$(plist_value AgentTachoBuildDate)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] ||
        fail "build date is not ISO 8601 UTC: $(plist_value AgentTachoBuildDate)"
    assert_eq "v0.2.0" "$(plist_value AgentTachoReleaseTag)"
    assert_eq "self-signed" "$(plist_value AgentTachoSigning)"
    assert_status 1 plist_value AgentTachoNotarized
    # v0.2.0 is the first release: no previous tag, no changes.
    assert_eq "[]" "$(jq -c . "$(app_file changes.json)")"
}

test_build_app_dev_build_has_no_release_tag_and_bundles_changes() {
    prepare_build ad-hoc
    echo "feature" >>"$APP_ROOT/README"
    git -C "$APP_ROOT" commit -q -am "feat(bar): show a new thing"
    echo "chore" >>"$APP_ROOT/README"
    git -C "$APP_ROOT" commit -q -am "chore: tidy up"
    assert_status 0 build_app
    assert_status 1 plist_value AgentTachoReleaseTag
    assert_eq "ad-hoc" "$(plist_value AgentTachoSigning)"
    assert_eq '[{"type":"feat","scope":"bar","subject":"show a new thing"}]' \
        "$(jq -c 'map({type, scope, subject})' "$(app_file changes.json)")"
}

test_build_app_marks_notarized_developer_id_builds() {
    prepare_build developer-id
    NOTARIZE=true assert_status 0 build_app
    assert_eq "developer-id" "$(plist_value AgentTachoSigning)"
    assert_eq "true" "$(plist_value AgentTachoNotarized)"
}

test_build_app_notarized_flag_only_for_developer_id() {
    prepare_build self-signed
    NOTARIZE=true assert_status 0 build_app
    assert_status 1 plist_value AgentTachoNotarized
    stub_security developer-id
    NOTARIZE=false assert_status 0 build_app
    assert_status 1 plist_value AgentTachoNotarized
}

test_build_app_copies_mono_icon_only_when_present() {
    prepare_build self-signed
    assert_status 0 build_app
    [ ! -e "$(app_file AgentTacho-mono.png)" ] || fail "mono icon copied although the repository has none"
    mkdir -p "$APP_ROOT/Resources/icons/mono"
    echo "mono" >"$APP_ROOT/Resources/icons/mono/AgentTacho-mono.png"
    assert_status 0 build_app
    assert_eq "mono" "$(cat "$(app_file AgentTacho-mono.png)")"
}

# --- build-app.sh: update-test build (spec 013 FR-025) ----------------------

test_build_app_update_test_compiles_the_flag_and_stamps_the_source() {
    prepare_build developer-id
    UPDATE_TEST=1 UPDATE_SOURCE=rhuss/agenttacho-update-test assert_status 0 build_app
    assert_contains "$(cat "$CALL_LOG")" "swift build -c release -Xswiftc -DAGENTTACHO_UPDATE_TEST"
    assert_eq "rhuss/agenttacho-update-test" "$(plist_value AgentTachoUpdateSource)"
    assert_contains "$(cat "$LAST_OUT")" "update-test build, release source rhuss/agenttacho-update-test"
}

test_build_app_without_update_test_has_neither_flag_nor_source() {
    prepare_build developer-id
    UPDATE_SOURCE=rhuss/agenttacho-update-test assert_status 0 build_app
    assert_not_contains "$(cat "$CALL_LOG")" "AGENTTACHO_UPDATE_TEST"
    assert_status 1 plist_value AgentTachoUpdateSource
    assert_not_contains "$(cat "$LAST_OUT")" "update-test"
}

test_build_app_update_test_requires_a_valid_source() {
    prepare_build developer-id
    UPDATE_TEST=1 assert_status 1 build_app
    assert_contains "$(cat "$LAST_ERR")" "error: UPDATE_SOURCE is required for an update-test build"
    local bad
    for bad in "rhuss" "AgentTacho/agenttacho/extra" "rhuss/agent tacho" 'rhuss/$(touch x)' "/agenttacho" "rhuss/"; do
        UPDATE_TEST=1 UPDATE_SOURCE="$bad" assert_status 1 build_app
        assert_contains "$(cat "$LAST_ERR")" "error: UPDATE_SOURCE must look like owner/repo"
    done
    assert_not_contains "$(cat "$CALL_LOG")" "swift build"
}

test_release_refuses_update_test() {
    local mode
    for mode in "--dry-run" ""; do
        if [ -n "$mode" ]; then
            UPDATE_TEST=1 assert_status 1 bash "$RELEASE_DIR/release.sh" "$mode"
        else
            UPDATE_TEST=1 assert_status 1 bash "$RELEASE_DIR/release.sh"
        fi
        assert_contains "$(cat "$LAST_ERR")" "error: UPDATE_TEST is set; release builds never carry the update-test flag"
    done
}

# --- make-dmg.sh -------------------------------------------------------------

# dmg_fixture: an app bundle, the icon and both background variants.
dmg_fixture() {
    DMG_ROOT="$TEST_TMP/dmg"
    mkdir -p "$DMG_ROOT/build/AgentTacho.app/Contents" "$DMG_ROOT/Resources/icons/macos" "$DMG_ROOT/Resources/dmg"
    echo "icon" >"$DMG_ROOT/Resources/icons/macos/AgentTacho.icns"
    echo "plain" >"$DMG_ROOT/Resources/dmg/background-unnotarized.png"
    echo "plain" >"$DMG_ROOT/Resources/dmg/background-notarized.png"
    # uvx stub: records its arguments and writes the DMG (the last argument).
    make_stub uvx "
echo \"uvx \$*\" >>\"$CALL_LOG\"
for last in \"\$@\"; do :; done
echo \"dmg image\" >\"\$last\""
    stub_codesign
}

make_dmg() {
    RELEASE_ROOT="$DMG_ROOT" bash "$RELEASE_DIR/make-dmg.sh" "$@" </dev/null
}

# Gatekeeper refuses to mount a quarantined signed DMG that is not notarized
# and offers no "Open Anyway" for it, while an unsigned DMG mounts and the
# first-launch steps apply to the (signed) app inside.
test_make_dmg_self_signed_uses_instructions_background_and_does_not_sign() {
    dmg_fixture
    assert_status 0 make_dmg build/AgentTacho.app 0.2.0 self-signed false "$SELF_SIGNED_HASH"
    local log expected
    log="$(cat "$CALL_LOG")"
    assert_contains "$log" "uvx --from dmgbuild==1.6.7 --with ds_store==1.3.3 --with mac_alias==2.2.3 dmgbuild"
    assert_contains "$log" "-D app=build/AgentTacho.app -D background=Resources/dmg/background-unnotarized.png -D icon=Resources/icons/macos/AgentTacho.icns AgentTacho build/release/AgentTacho-0.2.0.dmg"
    assert_not_contains "$log" "codesign"
    expected="$(cd "$DMG_ROOT/build/release" && shasum -a 256 AgentTacho-0.2.0.dmg)"
    assert_eq "$expected" "$(cat "$DMG_ROOT/build/release/AgentTacho-0.2.0.dmg.sha256")"
    assert_contains "$(cat "$LAST_OUT")" "dmg: build/release/AgentTacho-0.2.0.dmg (self-signed, not notarized)"
}

test_make_dmg_notarized_developer_id_uses_plain_background() {
    dmg_fixture
    assert_status 0 make_dmg build/AgentTacho.app 0.2.0 developer-id true "$DEVELOPER_ID_HASH"
    assert_contains "$(cat "$CALL_LOG")" "-D background=Resources/dmg/background-notarized.png"
    assert_contains "$(cat "$CALL_LOG")" "codesign --force --sign $DEVELOPER_ID_HASH --options runtime --timestamp build/release/AgentTacho-0.2.0.dmg"
    assert_before_in_log "uvx " "codesign --force"
}

test_make_dmg_developer_id_without_notarization_is_not_signed() {
    dmg_fixture
    assert_status 0 make_dmg build/AgentTacho.app 0.2.0 developer-id false "$DEVELOPER_ID_HASH"
    assert_contains "$(cat "$CALL_LOG")" "-D background=Resources/dmg/background-unnotarized.png"
    assert_not_contains "$(cat "$CALL_LOG")" "codesign"
}

test_make_dmg_ad_hoc_is_not_signed() {
    dmg_fixture
    assert_status 0 make_dmg build/AgentTacho.app 0.2.0-dev ad-hoc false -
    assert_contains "$(cat "$CALL_LOG")" "-D background=Resources/dmg/background-unnotarized.png"
    assert_not_contains "$(cat "$CALL_LOG")" "codesign"
    [ -f "$DMG_ROOT/build/release/AgentTacho-0.2.0-dev.dmg.sha256" ] || fail "checksum file missing"
}

test_make_dmg_fails_without_background_or_icon() {
    dmg_fixture
    rm "$DMG_ROOT/Resources/dmg/background-unnotarized.png"
    assert_status 1 make_dmg build/AgentTacho.app 0.2.0 self-signed false "$SELF_SIGNED_HASH"
    assert_eq "error: missing DMG background: Resources/dmg/background-unnotarized.png" "$(cat "$LAST_ERR")"
    rm "$DMG_ROOT/Resources/icons/macos/AgentTacho.icns"
    assert_status 1 make_dmg build/AgentTacho.app 0.2.0 self-signed false "$SELF_SIGNED_HASH"
    assert_eq "error: missing app icon: Resources/icons/macos/AgentTacho.icns" "$(cat "$LAST_ERR")"
    assert_not_contains "$(cat "$CALL_LOG")" "uvx"
}

test_make_dmg_requires_five_arguments() {
    dmg_fixture
    assert_status 1 make_dmg build/AgentTacho.app 0.2.0
    assert_contains "$(cat "$LAST_ERR")" "error: usage: make-dmg.sh"
}

assert_before_in_log() {
    local first second
    first="$(line_of "$1")"
    second="$(line_of "$2")"
    [ "$first" -gt 0 ] && [ "$second" -gt 0 ] && [ "$first" -lt "$second" ] ||
        fail "[$1] not before [$2] in: $(cat "$CALL_LOG")"
}
