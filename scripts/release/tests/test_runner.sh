# Tests for the test runner itself (run.sh): test discovery, isolation from
# the caller's environment and the errexit semantics of assert_status.

# The test files for the nested runs are written with a leading `|` that sed
# strips, so this runner does not discover their test functions.

# copy_runner: a copy of run.sh in $TEST_TMP/suite/tests, so a nested run only
# sees the test files written there. Prints the tests directory.
copy_runner() {
    mkdir -p "$TEST_TMP/suite/tests"
    cp "$TESTS_DIR/run.sh" "$TEST_TMP/suite/tests/run.sh"
    printf '%s\n' "$TEST_TMP/suite/tests"
}

test_runner_discovers_one_line_test_functions() {
    local dir
    dir="$(copy_runner)"
    sed 's/^|//' >"$dir/test_sample.sh" <<'EOF'
|test_one_line() { :; }
|test_one_line_spaced () { true; }
|test_multi_line() {
|    :
|}
|not_a_test() { exit 1; }
EOF
    assert_status 0 bash "$dir/run.sh"
    local out
    out="$(cat "$LAST_OUT")"
    assert_contains "$out" "ok   test_sample::test_one_line"
    assert_contains "$out" "ok   test_sample::test_one_line_spaced"
    assert_contains "$out" "ok   test_sample::test_multi_line"
    assert_contains "$out" "3 passed, 0 failed"
}

test_runner_unsets_git_and_stub_variables() {
    local dir
    dir="$(copy_runner)"
    sed 's/^|//' >"$dir/test_env.sh" <<'EOF'
|test_environment_is_clean() {
|    local v
|    for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
|        GH_AUTH_STATUS GH_RELEASE_EXISTS GH_RELEASE_DRAFT GH_FAIL_ON \
|        GH_VIEW_STATUS GH_DOWNLOAD_STATUS GH_DOWNLOAD_NOTHING GH_RELEASE_TAGS \
|        GH_LIST_STATUS NOTARY_OK NOTARY_ERROR NOTARIZE_STATUS CASK_STATUS STALE_SHA \
|        GH_REPO TAP_REPO ALLOW_TIER_DOWNGRADE; do
|        if [ -n "${!v+set}" ]; then
|            echo "leaked: $v" >&2
|            exit 1
|        fi
|    done
|}
EOF
    GIT_DIR=/nonexistent GIT_WORK_TREE=/nonexistent GIT_INDEX_FILE=/nonexistent \
        GIT_OBJECT_DIRECTORY=/nonexistent GH_AUTH_STATUS=1 GH_RELEASE_EXISTS=1 \
        GH_RELEASE_DRAFT=true GH_FAIL_ON=release GH_VIEW_STATUS=1 \
        GH_DOWNLOAD_STATUS=1 GH_DOWNLOAD_NOTHING=1 GH_RELEASE_TAGS=v9.9.9 GH_LIST_STATUS=1 NOTARY_OK=1 \
        NOTARY_ERROR=x NOTARIZE_STATUS=1 CASK_STATUS=1 STALE_SHA=1 GH_REPO=a/b TAP_REPO=/x ALLOW_TIER_DOWNGRADE=1 \
        assert_status 0 bash "$dir/run.sh"
    assert_contains "$(cat "$LAST_OUT")" "1 passed, 0 failed"
}

# A function that relies on errexit to stop at a failing command.
stops_at_false() {
    false
    echo "after false"
}

test_assert_status_runs_the_command_with_errexit() {
    assert_status 1 stops_at_false
    assert_not_contains "$(cat "$LAST_OUT")" "after false"
}

test_assert_status_keeps_errexit_for_the_test() {
    assert_status 0 true
    case "$-" in
        *e*) ;;
        *) fail "errexit is off after assert_status" ;;
    esac
}
