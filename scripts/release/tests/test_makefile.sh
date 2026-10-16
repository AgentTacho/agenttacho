# Tests for the release targets of the Makefile: variables reach the scripts
# through the environment, never as text pasted into the recipe (FINDING-30).

# The release variables a caller can set on the make command line.
RELEASE_VARS="SIGN_IDENTITY SIGN_IDENTITY_NAME NOTARY_PROFILE ALLOW_ADHOC ALLOW_TIER_DOWNGRADE REPLACE TAP_REPO GH_REPO VERSION UPDATE_SOURCE"

test_recipes_do_not_contain_variable_values() {
    local target var out
    for target in app app-update-test dmg release cask; do
        for var in $RELEASE_VARS; do
            out="$(make -s -n -C "$REPO_ROOT" "$target" "$var=MARKER-$var" 2>&1)" ||
                fail "make -n $target failed: $out"
            assert_not_contains "$out" "MARKER-$var"
        done
    done
}

test_cask_version_cannot_inject_commands() {
    # gh must never be reached: the version check of update-cask.sh fails first.
    make_stub gh 'echo "gh $*" >>"$CALL_LOG"; exit 1'
    assert_status 2 make -s -C "$REPO_ROOT" cask "VERSION=1; touch $TEST_TMP/pwned" \
        GH_REPO=invalid/invalid TAP_REPO=/nonexistent
    [ ! -e "$TEST_TMP/pwned" ] || fail "VERSION was run as a shell command"
    assert_contains "$(cat "$LAST_ERR")" "error: version must look like X.Y.Z: 1; touch $TEST_TMP/pwned"
    assert_eq "" "$(cat "$CALL_LOG")"
}

test_cask_requires_version() {
    make_stub gh 'echo "gh $*" >>"$CALL_LOG"; exit 1'
    assert_status 2 make -s -C "$REPO_ROOT" cask GH_REPO=invalid/invalid TAP_REPO=/nonexistent
    assert_contains "$(cat "$LAST_ERR")" "error: VERSION is required, for example: make cask VERSION=0.2.0"
    assert_eq "" "$(cat "$CALL_LOG")"
}

# spec 013 FR-025: only `make app-update-test` builds with the update-test flag.
test_app_never_passes_update_test_on() {
    local out
    out="$(UPDATE_TEST=1 UPDATE_SOURCE=rhuss/x make -s -n -C "$REPO_ROOT" app UPDATE_TEST=1 2>&1)"
    assert_contains "$out" "env -u UPDATE_TEST -u UPDATE_SOURCE bash scripts/release/build-app.sh"
}

test_app_update_test_sets_the_flag() {
    local out
    out="$(make -s -n -C "$REPO_ROOT" app-update-test UPDATE_SOURCE=rhuss/x 2>&1)"
    assert_contains "$out" "UPDATE_TEST=1 bash scripts/release/build-app.sh"
}

test_app_update_test_requires_a_source() {
    assert_status 2 make -s -C "$REPO_ROOT" app-update-test
    assert_contains "$(cat "$LAST_ERR")" "error: UPDATE_SOURCE is required for an update-test build"
}

test_app_update_test_rejects_an_invalid_source() {
    assert_status 2 make -s -C "$REPO_ROOT" app-update-test "UPDATE_SOURCE=x; touch $TEST_TMP/pwned"
    [ ! -e "$TEST_TMP/pwned" ] || fail "UPDATE_SOURCE was run as a shell command"
    assert_contains "$(cat "$LAST_ERR")" "error: UPDATE_SOURCE must look like owner/repo"
}
