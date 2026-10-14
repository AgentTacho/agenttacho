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
    echo "icon" >"$root/Resources/icons/macos/AgentMeter.icns"
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
mkdir -p .build/release/agentmeter_UsageCore.bundle
if [ \"\${NATIVE_ACCESSOR:-0}\" = 1 ]; then
    echo 'could not load resource bundle: from a or b' >.build/release/LLMUsageMenuBar
else
    echo 'unable to find bundle named agentmeter_UsageCore' >.build/release/LLMUsageMenuBar
fi
chmod +x .build/release/LLMUsageMenuBar"
}

# stub_codesign: records calls; `codesign -d -r-` prints CODESIGN_REQUIREMENT
# (default a certificate based requirement) on stderr, like codesign does.
stub_codesign() {
    make_stub codesign "
echo \"codesign \$*\" >>\"$CALL_LOG\"
case \"\$*\" in
    *-d*) echo \"designated => \${CODESIGN_REQUIREMENT:-identifier \\\"dev.rhuss.agentmeter\\\" and certificate leaf = H\\\"aaaa\\\"}\" >&2 ;;
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
    "$PLIST_BUDDY" -c "Print :$1" "$APP_ROOT/build/AgentMeter.app/Contents/Info.plist"
}

test_build_app_stamps_version_icon_and_signs_self_signed() {
    prepare_build self-signed
    assert_status 0 build_app
    local out log
    out="$(cat "$LAST_OUT")"
    log="$(cat "$CALL_LOG")"
    assert_contains "$out" "version: 0.2.0 (build 2)"
    assert_contains "$out" "signing: self-signed (AgentMeter Signing)"
    assert_contains "$out" "Built build/AgentMeter.app"
    assert_eq "0.2.0" "$(plist_value CFBundleShortVersionString)"
    assert_eq "2" "$(plist_value CFBundleVersion)"
    assert_eq "0.2.0" "$(plist_value AgentMeterVersionDisplay)"
    assert_eq "AgentMeter" "$(plist_value CFBundleIconFile)"
    [ -f "$APP_ROOT/build/AgentMeter.app/Contents/Resources/AgentMeter.icns" ] || fail "icon not copied"
    [ -d "$APP_ROOT/build/AgentMeter.app/Contents/Resources/agentmeter_UsageCore.bundle" ] || fail "resource bundle not copied"
    [ -x "$APP_ROOT/build/AgentMeter.app/Contents/MacOS/LLMUsageMenuBar" ] || fail "executable not copied"
    assert_contains "$log" "codesign --force --sign $SELF_SIGNED_HASH --identifier dev.rhuss.agentmeter --timestamp=none build/AgentMeter.app"
    assert_contains "$log" "codesign --verify --strict build/AgentMeter.app"
    assert_contains "$log" "codesign -d -r- build/AgentMeter.app"
    assert_eq "" "$(cat "$LAST_ERR")"
}

test_build_app_developer_id_uses_hardened_runtime_and_timestamp() {
    prepare_build developer-id
    assert_status 0 build_app
    assert_contains "$(cat "$LAST_OUT")" "signing: developer-id (Developer ID Application: Roland Huss (TEAM123456))"
    assert_contains "$(cat "$CALL_LOG")" "codesign --force --sign $DEVELOPER_ID_HASH --identifier dev.rhuss.agentmeter --options runtime --timestamp build/AgentMeter.app"
}

test_build_app_ad_hoc_warns_that_permissions_do_not_persist() {
    prepare_build ad-hoc
    assert_status 0 build_app
    assert_contains "$(cat "$LAST_OUT")" "signing: ad-hoc (no certificate)"
    assert_contains "$(cat "$LAST_ERR")" "warning: ad-hoc signature, notification permission and start at login will not persist across rebuilds"
    assert_contains "$(cat "$CALL_LOG")" "codesign --force --sign - --identifier dev.rhuss.agentmeter --timestamp=none build/AgentMeter.app"
    assert_not_contains "$(cat "$CALL_LOG")" "codesign -d"
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
    assert_eq "0.2.0-dev" "$(plist_value AgentMeterVersionDisplay)"
}

test_build_app_refuses_native_resource_accessor_for_distribution() {
    prepare_build self-signed
    NATIVE_ACCESSOR=1 DISTRIBUTION=1 assert_status 1 build_app
    assert_contains "$(cat "$LAST_ERR")" "uses SwiftPM's native resource accessor"
    assert_not_contains "$(cat "$CALL_LOG")" "codesign --"
    [ ! -d "$APP_ROOT/build/AgentMeter.app" ] || fail "app bundle assembled despite the native accessor"
}

test_build_app_native_resource_accessor_only_warns_for_local_builds() {
    prepare_build self-signed
    NATIVE_ACCESSOR=1 assert_status 0 build_app
    assert_contains "$(cat "$LAST_ERR")" "warning: SwiftPM's native resource accessor: this app finds its resources only on this Mac"
    assert_contains "$(cat "$LAST_OUT")" "Built build/AgentMeter.app"
}

# --- make-dmg.sh -------------------------------------------------------------

# dmg_fixture: an app bundle, the icon and both background variants.
dmg_fixture() {
    DMG_ROOT="$TEST_TMP/dmg"
    mkdir -p "$DMG_ROOT/build/AgentMeter.app/Contents" "$DMG_ROOT/Resources/icons/macos" "$DMG_ROOT/Resources/dmg"
    echo "icon" >"$DMG_ROOT/Resources/icons/macos/AgentMeter.icns"
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

test_make_dmg_self_signed_uses_instructions_background_and_signs() {
    dmg_fixture
    assert_status 0 make_dmg build/AgentMeter.app 0.2.0 self-signed false "$SELF_SIGNED_HASH"
    local log expected
    log="$(cat "$CALL_LOG")"
    assert_contains "$log" "uvx --from dmgbuild==1.6.7 --with ds_store==1.3.3 --with mac_alias==2.2.3 dmgbuild"
    assert_contains "$log" "-D app=build/AgentMeter.app -D background=Resources/dmg/background-unnotarized.png -D icon=Resources/icons/macos/AgentMeter.icns AgentMeter build/release/AgentMeter-0.2.0.dmg"
    assert_contains "$log" "codesign --force --sign $SELF_SIGNED_HASH --timestamp=none build/release/AgentMeter-0.2.0.dmg"
    assert_before_in_log "uvx " "codesign --force"
    expected="$(cd "$DMG_ROOT/build/release" && shasum -a 256 AgentMeter-0.2.0.dmg)"
    assert_eq "$expected" "$(cat "$DMG_ROOT/build/release/AgentMeter-0.2.0.dmg.sha256")"
    assert_contains "$(cat "$LAST_OUT")" "dmg: build/release/AgentMeter-0.2.0.dmg (self-signed, not notarized)"
}

test_make_dmg_notarized_developer_id_uses_plain_background() {
    dmg_fixture
    assert_status 0 make_dmg build/AgentMeter.app 0.2.0 developer-id true "$DEVELOPER_ID_HASH"
    assert_contains "$(cat "$CALL_LOG")" "-D background=Resources/dmg/background-notarized.png"
    assert_contains "$(cat "$CALL_LOG")" "codesign --force --sign $DEVELOPER_ID_HASH --options runtime --timestamp build/release/AgentMeter-0.2.0.dmg"
}

test_make_dmg_ad_hoc_is_not_signed() {
    dmg_fixture
    assert_status 0 make_dmg build/AgentMeter.app 0.2.0-dev ad-hoc false -
    assert_contains "$(cat "$CALL_LOG")" "-D background=Resources/dmg/background-unnotarized.png"
    assert_not_contains "$(cat "$CALL_LOG")" "codesign"
    [ -f "$DMG_ROOT/build/release/AgentMeter-0.2.0-dev.dmg.sha256" ] || fail "checksum file missing"
}

test_make_dmg_fails_without_background_or_icon() {
    dmg_fixture
    rm "$DMG_ROOT/Resources/dmg/background-unnotarized.png"
    assert_status 1 make_dmg build/AgentMeter.app 0.2.0 self-signed false "$SELF_SIGNED_HASH"
    assert_eq "error: missing DMG background: Resources/dmg/background-unnotarized.png" "$(cat "$LAST_ERR")"
    rm "$DMG_ROOT/Resources/icons/macos/AgentMeter.icns"
    assert_status 1 make_dmg build/AgentMeter.app 0.2.0 self-signed false "$SELF_SIGNED_HASH"
    assert_eq "error: missing app icon: Resources/icons/macos/AgentMeter.icns" "$(cat "$LAST_ERR")"
    assert_not_contains "$(cat "$CALL_LOG")" "uvx"
}

test_make_dmg_requires_five_arguments() {
    dmg_fixture
    assert_status 1 make_dmg build/AgentMeter.app 0.2.0
    assert_contains "$(cat "$LAST_ERR")" "error: usage: make-dmg.sh"
}

assert_before_in_log() {
    local first second
    first="$(line_of "$1")"
    second="$(line_of "$2")"
    [ "$first" -gt 0 ] && [ "$second" -gt 0 ] && [ "$first" -lt "$second" ] ||
        fail "[$1] not before [$2] in: $(cat "$CALL_LOG")"
}
