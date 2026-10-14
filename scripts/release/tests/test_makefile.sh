# Tests for the release targets of the Makefile: variables reach the scripts
# through the environment, never as text pasted into the recipe (FINDING-30).

# The release variables a caller can set on the make command line.
RELEASE_VARS="SIGN_IDENTITY SIGN_IDENTITY_NAME NOTARY_PROFILE ALLOW_ADHOC REPLACE TAP_REPO GH_REPO VERSION"

test_recipes_do_not_contain_variable_values() {
    local target var out
    for target in app dmg release cask; do
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
