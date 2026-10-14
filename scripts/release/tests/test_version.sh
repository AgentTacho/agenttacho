# Tests for version_info (data-model.md, VersionInfo).

. "$RELEASE_DIR/lib.sh"

commit_in() {
    local repo="$1" msg="$2"
    echo "$msg" >>"$repo/README"
    git -C "$repo" commit -q -am "$msg"
}

# Prints the first three fields (mode short display) of version_info.
version_fields() {
    version_info | awk '{print $1, $2, $3}'
}

test_no_tags_is_dev_0_0_0() {
    local repo
    repo="$(make_git_repo)"
    cd "$repo"
    assert_eq "dev 0.0.0 0.0.0-dev" "$(version_fields)"
    assert_eq "" "$(version_info | awk '{print $5}')" "tag is empty in dev mode"
}

test_head_at_release_tag_with_clean_tree_is_release() {
    local repo
    repo="$(make_git_repo)"
    cd "$repo"
    git tag v0.2.0
    assert_eq "release 0.2.0 0.2.0" "$(version_fields)"
    assert_eq "v0.2.0" "$(version_info | awk '{print $5}')"
}

test_annotated_release_tag_is_release() {
    local repo
    repo="$(make_git_repo)"
    cd "$repo"
    git tag -a v0.3.1 -m "release 0.3.1"
    assert_eq "release 0.3.1 0.3.1" "$(version_fields)"
}

test_uncommitted_change_at_tag_is_dev() {
    local repo
    repo="$(make_git_repo)"
    cd "$repo"
    git tag v0.2.0
    echo "change" >>README
    assert_eq "dev 0.2.0 0.2.0-dev" "$(version_fields)"
    assert_eq "" "$(version_info | awk '{print $5}')"
}

test_commits_after_tag_are_dev_with_nearest_version() {
    local repo
    repo="$(make_git_repo)"
    cd "$repo"
    git tag v0.2.0
    commit_in "$repo" one
    commit_in "$repo" two
    assert_eq "dev 0.2.0 0.2.0-dev" "$(version_fields)"
}

test_tags_not_matching_vXYZ_are_ignored() {
    local repo
    repo="$(make_git_repo)"
    cd "$repo"
    git tag v0.1.0
    commit_in "$repo" one
    git tag v1.2
    git tag release-1
    git tag v1.2.3-rc1
    assert_eq "dev 0.1.0 0.1.0-dev" "$(version_fields)"
}

test_only_non_matching_tags_gives_0_0_0() {
    local repo
    repo="$(make_git_repo)"
    cd "$repo"
    git tag v1.2
    git tag v1.2.3-rc1
    assert_eq "dev 0.0.0 0.0.0-dev" "$(version_fields)"
}

test_highest_of_several_tags_on_head_wins() {
    local repo
    repo="$(make_git_repo)"
    cd "$repo"
    git tag v0.10.0
    git tag v0.2.0
    git tag v0.9.0
    assert_eq "release 0.10.0 0.10.0" "$(version_fields)"
    assert_eq "v0.10.0" "$(version_info | awk '{print $5}')"
}

test_build_number_is_commit_count() {
    local repo
    repo="$(make_git_repo)"
    cd "$repo"
    commit_in "$repo" one
    commit_in "$repo" two
    assert_eq "3" "$(git rev-list --count HEAD)"
    assert_eq "3" "$(version_info | awk '{print $4}')"
}

test_shallow_clone_warns_but_succeeds() {
    local repo clone out
    repo="$(make_git_repo)"
    commit_in "$repo" one
    commit_in "$repo" two
    clone="$TEST_TMP/shallow"
    git clone -q --depth 1 "file://$repo" "$clone"
    cd "$clone"
    assert_status 0 version_info
    assert_contains "$(cat "$LAST_ERR")" "warning: shallow clone, build number may be wrong"
    out="$(cat "$LAST_OUT")"
    assert_eq "dev 0.0.0 0.0.0-dev" "$(echo "$out" | awk '{print $1, $2, $3}')"
}

test_outside_a_git_repository_fails() {
    mkdir -p "$TEST_TMP/plain"
    cd "$TEST_TMP/plain"
    # Called as in build-app.sh: inside a command substitution, where Bash 3.2
    # does not apply `set -e`.
    GIT_CEILING_DIRECTORIES="$TEST_TMP" assert_status 1 \
        bash -c 'set -euo pipefail; . "$RELEASE_DIR/lib.sh"; v="$(version_info)"; echo "$v"'
    assert_contains "$(cat "$LAST_ERR")" "error: cannot read the git status"
    assert_eq "" "$(cat "$LAST_OUT")"
}

test_non_numeric_build_number_fails() {
    local repo real_git
    repo="$(make_git_repo)"
    cd "$repo"
    real_git="$(command -v git)"
    make_stub git "
case \"\$*\" in
    'rev-list --count HEAD') echo 'abc' ;;
    *) exec \"$real_git\" \"\$@\" ;;
esac"
    assert_status 1 bash -c 'set -euo pipefail; . "$RELEASE_DIR/lib.sh"; v="$(version_info)"; echo "$v"'
    assert_contains "$(cat "$LAST_ERR")" "error: invalid build number: abc"
    assert_eq "" "$(cat "$LAST_OUT")"
}

test_full_clone_does_not_warn() {
    local repo
    repo="$(make_git_repo)"
    cd "$repo"
    assert_status 0 version_info
    assert_eq "" "$(cat "$LAST_ERR")"
}
