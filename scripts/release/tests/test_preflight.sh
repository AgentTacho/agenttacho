# Tests for preflight (FR-016, FR-019, SC-005). Real local bare repositories
# act as origin and tap; gh and security are stubs.

. "$RELEASE_DIR/lib.sh"
. "$TESTS_DIR/helpers.sh"

ready_release() {
    stub_security self-signed
    stub_gh
    setup_release_repo
    tag_and_push v0.2.0
}

test_all_good_passes_without_output() {
    ready_release
    assert_status 0 preflight release
    assert_eq "" "$(cat "$LAST_ERR")"
    assert_not_contains "$(cat "$CALL_LOG")" "release create"
}

test_dirty_tree_stops() {
    ready_release
    echo "change" >>README
    assert_status 1 preflight release
    assert_contains "$(cat "$LAST_ERR")" "error: working tree has uncommitted changes"
}

test_untracked_file_counts_as_dirty() {
    ready_release
    echo "new" >notes.txt
    assert_status 1 preflight release
    assert_contains "$(cat "$LAST_ERR")" "uncommitted changes"
}

test_shallow_clone_stops_release_and_warns_in_dry_run() {
    ready_release
    # A `shallow` file is what makes git treat a repository as shallow.
    git rev-parse HEAD >"$(git rev-parse --git-dir)/shallow"
    assert_status 1 preflight release
    assert_contains "$(cat "$LAST_ERR")" "error: shallow clone, the build number would be wrong"
    assert_status 0 preflight dry-run
    assert_contains "$(cat "$LAST_ERR")" "warning: shallow clone, the build number would be wrong"
}

test_head_without_tag_stops() {
    stub_security self-signed
    stub_gh
    setup_release_repo
    assert_status 1 preflight release
    assert_contains "$(cat "$LAST_ERR")" "error: HEAD has no vX.Y.Z tag"
}

test_non_release_tag_stops() {
    stub_security self-signed
    stub_gh
    setup_release_repo
    tag_and_push v0.2.0-rc1
    assert_status 1 preflight release
    assert_contains "$(cat "$LAST_ERR")" "HEAD has no vX.Y.Z tag"
}

test_tag_missing_on_origin_stops() {
    stub_security self-signed
    stub_gh
    setup_release_repo
    git tag v0.2.0
    assert_status 1 preflight release
    assert_contains "$(cat "$LAST_ERR")" "error: tag v0.2.0 is not pushed to origin"
}

test_tag_on_origin_at_other_commit_stops() {
    stub_security self-signed
    stub_gh
    setup_release_repo
    tag_and_push v0.2.0
    git tag -d v0.2.0 >/dev/null
    echo "more" >>README
    git commit -q -am "more"
    git tag v0.2.0
    assert_status 1 preflight release
    assert_contains "$(cat "$LAST_ERR")" "error: tag v0.2.0 on origin points to a different commit"
}

test_annotated_tag_on_origin_passes() {
    stub_security self-signed
    stub_gh
    setup_release_repo
    tag_and_push v0.2.0 annotated
    assert_status 0 preflight release
    assert_eq "" "$(cat "$LAST_ERR")"
}

test_annotated_tag_on_origin_at_other_commit_stops() {
    local origin_commit
    stub_security self-signed
    stub_gh
    setup_release_repo
    tag_and_push v0.2.0 annotated
    origin_commit="$(git rev-parse HEAD)"
    git tag -d v0.2.0 >/dev/null
    echo "more" >>README
    git commit -q -am "more"
    git tag -a v0.2.0 -m "moved"
    assert_status 1 preflight release
    # The peeled commit of the annotated tag on origin, not the tag object.
    assert_eq "error: tag v0.2.0 on origin points to a different commit ($origin_commit, HEAD is $(git rev-parse HEAD))" "$(cat "$LAST_ERR")"
}

test_lightweight_tag_on_origin_passes() {
    stub_security self-signed
    stub_gh
    setup_release_repo
    tag_and_push v0.2.0
    assert_status 0 preflight release
}

test_gh_not_authenticated_stops() {
    ready_release
    GH_AUTH_STATUS=1 assert_status 1 preflight release
    assert_eq "error: gh is not authenticated (You are not logged into any GitHub hosts. To log in, run: gh auth login)" "$(cat "$LAST_ERR")"
}

test_missing_origin_remote_stops() {
    ready_release
    git remote remove origin
    assert_status 1 preflight release
    assert_eq "error: cannot read tags from origin (fatal: 'origin' does not appear to be a git repository)" "$(cat "$LAST_ERR")"
}

test_existing_release_stops() {
    ready_release
    GH_RELEASE_EXISTS=1 assert_status 1 preflight release
    assert_contains "$(cat "$LAST_ERR")" "error: release v0.2.0 already exists"
    assert_contains "$(cat "$LAST_ERR")" "REPLACE=1"
}

test_existing_release_passes_with_replace() {
    ready_release
    GH_RELEASE_EXISTS=1 REPLACE=1 assert_status 0 preflight release
}

test_release_view_uses_gh_repo() {
    ready_release
    preflight release
    assert_contains "$(cat "$CALL_LOG")" "gh release view v0.2.0 -R example/agentmeter"
}

test_ad_hoc_stops() {
    ready_release
    stub_security ad-hoc
    assert_status 1 preflight release
    assert_contains "$(cat "$LAST_ERR")" "error: no signing certificate"
    assert_contains "$(cat "$LAST_ERR")" "ALLOW_ADHOC=1"
}

test_ad_hoc_passes_when_allowed() {
    ready_release
    stub_security ad-hoc
    ALLOW_ADHOC=1 assert_status 0 preflight release
}

test_unreachable_tap_stops() {
    ready_release
    TAP_REPO="$TEST_TMP/missing-tap.git" assert_status 1 preflight release
    assert_eq "error: tap repository not reachable: $TEST_TMP/missing-tap.git (fatal: '$TEST_TMP/missing-tap.git' does not appear to be a git repository)" "$(cat "$LAST_ERR")"
}

test_release_mode_stops_at_first_problem() {
    stub_security ad-hoc
    stub_gh
    setup_release_repo
    echo "change" >>README
    assert_status 1 preflight release
    assert_eq "error: working tree has uncommitted changes" "$(cat "$LAST_ERR")"
}

test_dry_run_only_warns() {
    stub_security ad-hoc
    stub_gh
    setup_release_repo
    echo "change" >>README
    GH_AUTH_STATUS=1 TAP_REPO=/nonexistent assert_status 0 preflight dry-run
    local err
    err="$(cat "$LAST_ERR")"
    assert_contains "$err" "warning: working tree has uncommitted changes"
    assert_contains "$err" "warning: HEAD has no vX.Y.Z tag"
    assert_contains "$err" "warning: gh is not authenticated"
    assert_contains "$err" "warning: no signing certificate"
    assert_contains "$err" "warning: tap repository not reachable: /nonexistent"
    assert_not_contains "$err" "error:"
}

test_dry_run_on_clean_tagged_repo_is_silent() {
    ready_release
    assert_status 0 preflight dry-run
    assert_eq "" "$(cat "$LAST_ERR")"
}

test_unknown_mode_fails() {
    ready_release
    assert_status 1 preflight publish
}

test_tap_repo_is_never_read_as_a_git_option() {
    ready_release
    TAP_REPO="--upload-pack=touch $TEST_TMP/pwned" assert_status 0 preflight dry-run
    [ ! -e "$TEST_TMP/pwned" ] || fail "TAP_REPO was passed to git as an option"
    assert_contains "$(cat "$LAST_ERR")" "warning: tap repository not reachable: --upload-pack=touch $TEST_TMP/pwned"
}
