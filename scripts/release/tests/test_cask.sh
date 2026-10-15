# Tests for render_cask (contracts/cask.md) and update-cask.sh (FR-021,
# FR-021a) against a local bare tap repository.

. "$RELEASE_DIR/lib.sh"
. "$TESTS_DIR/helpers.sh"

SHA="3b1f0c9e4a8d2b7f6e5c4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d"
CASK_CONTRACT="$REPO_ROOT/specs/005-macos-distribution/contracts/cask.md"

# The not-notarized example from the contract with the checksum filled in.
contract_cask() {
    sed -n '/^```ruby$/,/^```$/p' "$CASK_CONTRACT" | sed '1d;$d' |
        sed "s/<sha256 from release-info.json>/$1/"
}

test_rendered_cask_matches_contract() {
    [ -f "$CASK_CONTRACT" ] || fail "missing $CASK_CONTRACT"
    assert_eq "$(contract_cask "$SHA")" "$(render_cask 0.2.0 "$SHA" false)"
}

# caveats_of <cask>: the caveats heredoc of a rendered cask.
caveats_of() {
    printf '%s\n' "$1" | sed -n '/caveats <<~EOS/,/^  EOS$/p'
}

# Homebrew reopens apps that `uninstall quit:` closed during `brew upgrade`
# (Cask::Upgrade.reopen_apps_after_upgrade), so the caveats say so (FR-024).
REOPEN_CAVEAT="Homebrew quits AgentMeter before an upgrade and opens it
    again afterwards."

test_notarized_caveats_only_mention_reopen() {
    local cask caveats
    cask="$(render_cask 0.3.0 "$SHA" true)"
    caveats="$(caveats_of "$cask")"
    assert_eq "  caveats <<~EOS
    $REOPEN_CAVEAT
  EOS" "$caveats"
    assert_not_contains "$caveats" "not notarized"
    assert_not_contains "$caveats" "xattr"
    assert_not_contains "$caveats" "macOS 14"
    assert_contains "$cask" 'version "0.3.0"'
}

test_unnotarized_caveats_name_first_launch_and_reopen() {
    local caveats
    caveats="$(caveats_of "$(render_cask 0.2.0 "$SHA" false)")"
    assert_contains "$caveats" "AgentMeter is not notarized by Apple. After each install or upgrade,"
    assert_contains "$caveats" "Or run: xattr -dr com.apple.quarantine /Applications/AgentMeter.app"
    assert_contains "$caveats" "$REOPEN_CAVEAT"
    assert_not_contains "$caveats" "not restarted"
}

test_unnotarized_caveats_align_step_text() {
    local caveats
    caveats="$(caveats_of "$(render_cask 0.2.0 "$SHA" false)")"
    assert_contains "$caveats" "      macOS 14:          Control-click AgentMeter in Applications and choose Open."
    assert_contains "$caveats" "      macOS 15 or later: open AgentMeter, then choose \"Open Anyway\" in
                         System Settings > Privacy & Security."
}

test_rendered_casks_are_valid_ruby() {
    render_cask 0.2.0 "$SHA" false >unnotarized.rb
    render_cask 0.2.0 "$SHA" true >notarized.rb
    ruby -c unnotarized.rb >/dev/null || fail "unnotarized cask is not valid Ruby"
    ruby -c notarized.rb >/dev/null || fail "notarized cask is not valid Ruby"
}

test_cask_has_zap_paths_and_quit() {
    local cask
    cask="$(render_cask 0.2.0 "$SHA" false)"
    assert_contains "$cask" '"~/.config/agentmeter",'
    assert_contains "$cask" '"~/Library/Logs/agentmeter",'
    assert_contains "$cask" '"~/Library/Preferences/dev.rhuss.agentmeter.plist",'
    assert_contains "$cask" 'uninstall quit: "dev.rhuss.agentmeter"'
    assert_contains "$cask" 'depends_on arch: :arm64'
    assert_contains "$cask" 'depends_on macos: ">= :sonoma"'
}

# --- update-cask.sh --------------------------------------------------------

# write_fixture <version> <sha256|-> [notarized]: the release served by the gh
# stub: AgentMeter-<version>.dmg, its release-info.json and the tag in the
# release list. "-" puts the DMG's real checksum (FIXTURE_SHA) into
# release-info.json.
write_fixture() {
    local dir="$TEST_TMP/fixture" sha="$2"
    mkdir -p "$dir"
    printf 'dmg %s\n' "$1" >"$dir/AgentMeter-$1.dmg"
    FIXTURE_SHA="$(shasum -a 256 "$dir/AgentMeter-$1.dmg" | awk '{print $1}')"
    [ "$sha" != "-" ] || sha="$FIXTURE_SHA"
    printf '{"version":"%s","dmg":"AgentMeter-%s.dmg","sha256":"%s","tier":"self-signed","notarized":%s}\n' \
        "$1" "$1" "$sha" "${3:-false}" >"$dir/release-info.json"
    echo "v$1" >>"$dir/tags"
}

# gh stub for update-cask.sh:
#   release view <tag> ... --json isDraft  prints GH_RELEASE_DRAFT (default
#       false); GH_VIEW_STATUS=1 simulates a missing release
#   release list ...                       prints GH_RELEASE_TAGS when set,
#       else the fixture tags; GH_LIST_STATUS=1 simulates an API error
#   release download <tag> -R <repo> -p <name> -D <dir>  copies the fixture
#       file <name>; GH_DOWNLOAD_STATUS=1 fails every download,
#       GH_DOWNLOAD_NOTHING=1 succeeds without writing a file
stub_gh_download() {
    make_stub gh "
echo \"gh \$*\" >>\"$CALL_LOG\"
case \"\$1 \$2\" in
    'release view')
        [ \"\${GH_VIEW_STATUS:-0}\" = 0 ] || { echo 'release not found' >&2; exit 1; }
        echo \"\${GH_RELEASE_DRAFT:-false}\"
        exit 0 ;;
    'release list')
        [ \"\${GH_LIST_STATUS:-0}\" = 0 ] || { echo 'HTTP 502: Bad Gateway' >&2; exit 1; }
        if [ -n \"\${GH_RELEASE_TAGS+set}\" ]; then
            printf '%s\n' \$GH_RELEASE_TAGS
        else
            cat \"$TEST_TMP/fixture/tags\"
        fi
        exit 0 ;;
esac
[ \"\${GH_DOWNLOAD_STATUS:-0}\" = 0 ] || { echo 'no assets match the file pattern' >&2; exit 1; }
[ \"\${GH_DOWNLOAD_NOTHING:-0}\" = 0 ] || exit 0
dir=. pattern=
while [ \$# -gt 0 ]; do
    case \"\$1\" in
        -D) dir=\"\$2\"; shift ;;
        -p) pattern=\"\$2\"; shift ;;
    esac
    shift
done
[ -f \"$TEST_TMP/fixture/\$pattern\" ] || { echo 'no assets match the file pattern' >&2; exit 1; }
mkdir -p \"\$dir\"
cp \"$TEST_TMP/fixture/\$pattern\" \"\$dir/\""
}

setup_tap() {
    git init -q --bare "$TEST_TMP/tap.git"
    TAP_REPO="$TEST_TMP/tap.git"
    GH_REPO="example/agentmeter"
    export TAP_REPO GH_REPO
}

tap_log() {
    git --git-dir="$TEST_TMP/tap.git" log --format=%s 2>/dev/null || true
}

tap_cask() {
    git --git-dir="$TEST_TMP/tap.git" show main:Casks/agentmeter.rb
}

update_cask() {
    bash "$RELEASE_DIR/update-cask.sh" "$@"
}

test_update_cask_commits_and_pushes() {
    setup_tap
    write_fixture 0.2.0 -
    stub_gh_download
    assert_status 0 update_cask 0.2.0
    assert_eq "agentmeter 0.2.0" "$(tap_log)"
    assert_eq "$(render_cask 0.2.0 "$FIXTURE_SHA" false)" "$(tap_cask)"
    local log
    log="$(cat "$CALL_LOG")"
    assert_contains "$log" "gh release list -R example/agentmeter --exclude-drafts"
    assert_contains "$log" "gh release download v0.2.0 -R example/agentmeter -p release-info.json"
    assert_contains "$log" "gh release download v0.2.0 -R example/agentmeter -p AgentMeter-0.2.0.dmg"
    assert_eq "cask: pushed agentmeter 0.2.0 to $TAP_REPO" "$(cat "$LAST_OUT")"
}

test_update_cask_second_run_is_up_to_date() {
    setup_tap
    write_fixture 0.2.0 -
    stub_gh_download
    update_cask 0.2.0 >/dev/null
    assert_status 0 update_cask 0.2.0
    assert_eq "cask: already up to date (agentmeter 0.2.0)" "$(cat "$LAST_OUT")"
    assert_eq "1" "$(tap_log | wc -l | tr -d ' ')"
}

test_update_cask_keeps_existing_tap_content() {
    local seed="$TEST_TMP/seed"
    setup_tap
    make_git_repo "$seed" >/dev/null
    mkdir -p "$seed/Casks"
    echo 'cask "other" do end' >"$seed/Casks/other.rb"
    git -C "$seed" add Casks
    git -C "$seed" commit -q -m "other"
    git -C "$seed" push -q "$TAP_REPO" main
    write_fixture 0.2.1 - true
    stub_gh_download
    assert_status 0 update_cask 0.2.1
    assert_eq "agentmeter 0.2.1" "$(tap_log | head -n 1)"
    git --git-dir="$TEST_TMP/tap.git" show main:Casks/other.rb >/dev/null || fail "other cask lost"
    assert_eq "$(render_cask 0.2.1 "$FIXTURE_SHA" true)" "$(tap_cask)"
}

test_update_cask_fails_without_release_info() {
    setup_tap
    write_fixture 0.2.0 -
    stub_gh_download
    GH_DOWNLOAD_STATUS=1 assert_status 1 update_cask 0.2.0
    assert_eq "error: cannot download release-info.json of release v0.2.0 from example/agentmeter (no assets match the file pattern)" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}

test_update_cask_fails_when_download_writes_no_release_info() {
    setup_tap
    write_fixture 0.2.0 -
    stub_gh_download
    GH_DOWNLOAD_NOTHING=1 assert_status 1 update_cask 0.2.0
    assert_eq "error: release v0.2.0 in example/agentmeter has no release-info.json" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}

test_update_cask_fails_for_missing_release() {
    setup_tap
    write_fixture 0.2.0 -
    stub_gh_download
    GH_VIEW_STATUS=1 assert_status 1 update_cask 0.2.0
    assert_eq "error: cannot find release v0.2.0 in example/agentmeter (release not found)" "$(cat "$LAST_ERR")"
    assert_not_contains "$(cat "$CALL_LOG")" "release download"
    assert_eq "" "$(tap_log)"
}

test_update_cask_rejects_version_mismatch() {
    setup_tap
    write_fixture 0.2.1 -
    stub_gh_download
    GH_RELEASE_TAGS="v0.2.0" assert_status 1 update_cask 0.2.0
    assert_eq "error: release-info.json has version 0.2.1, expected 0.2.0" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}

test_update_cask_rejects_short_sha256() {
    setup_tap
    write_fixture 0.2.0 "3b1f0c9e"
    stub_gh_download
    assert_status 1 update_cask 0.2.0
    assert_eq "error: release-info.json has an invalid sha256: 3b1f0c9e" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}

test_update_cask_rejects_uppercase_sha256() {
    local upper
    upper="$(printf '%s' "$SHA" | tr 'a-f' 'A-F')"
    setup_tap
    write_fixture 0.2.0 "$upper"
    stub_gh_download
    assert_status 1 update_cask 0.2.0
    assert_eq "error: release-info.json has an invalid sha256: $upper" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}

test_update_cask_rejects_invalid_notarized_value() {
    setup_tap
    write_fixture 0.2.0 - '"yes"'
    stub_gh_download
    assert_status 1 update_cask 0.2.0
    assert_eq "error: release-info.json has an invalid notarized value: yes" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}

test_update_cask_rejects_invalid_version_argument() {
    setup_tap
    stub_gh_download
    assert_status 1 update_cask v0.2.0
    assert_eq "error: version must look like X.Y.Z: v0.2.0" "$(cat "$LAST_ERR")"
    assert_eq "" "$(cat "$CALL_LOG")"
}

test_update_cask_refuses_draft_release() {
    setup_tap
    write_fixture 0.2.0 -
    stub_gh_download
    GH_RELEASE_DRAFT=true assert_status 1 update_cask 0.2.0
    assert_eq "error: release v0.2.0 in example/agentmeter is not published yet; publish it first: gh release edit v0.2.0 -R example/agentmeter --draft=false" "$(cat "$LAST_ERR")"
    assert_not_contains "$(cat "$CALL_LOG")" "release download"
    assert_eq "" "$(tap_log)"
}

test_update_cask_fails_when_tap_unreachable() {
    write_fixture 0.2.0 -
    stub_gh_download
    TAP_REPO="$TEST_TMP/missing.git" assert_status 1 update_cask 0.2.0
    assert_eq "error: cannot clone tap repository: $TEST_TMP/missing.git (fatal: repository '$TEST_TMP/missing.git' does not exist)" "$(cat "$LAST_ERR")"
}

test_update_cask_never_reads_tap_repo_as_git_option() {
    write_fixture 0.2.0 -
    stub_gh_download
    TAP_REPO="--upload-pack=touch $TEST_TMP/pwned" assert_status 1 update_cask 0.2.0
    [ ! -e "$TEST_TMP/pwned" ] || fail "TAP_REPO was passed to git as an option"
    assert_contains "$(cat "$LAST_ERR")" "error: cannot clone tap repository: --upload-pack=touch $TEST_TMP/pwned"
}

test_update_cask_fails_when_tap_rejects_push() {
    setup_tap
    printf '#!/bin/sh\necho "push rejected by test hook" >&2\nexit 1\n' >"$TEST_TMP/tap.git/hooks/pre-receive"
    chmod +x "$TEST_TMP/tap.git/hooks/pre-receive"
    write_fixture 0.2.0 -
    stub_gh_download
    assert_status 1 update_cask 0.2.0
    assert_eq "error: cannot push to tap repository: $TAP_REPO (error: failed to push some refs to '$TAP_REPO')" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}

# --- checksum of the DMG asset (FINDING-29) ---------------------------------

test_update_cask_rejects_dmg_not_matching_release_info() {
    local actual
    setup_tap
    write_fixture 0.2.0 -
    echo "tampered" >>"$TEST_TMP/fixture/AgentMeter-0.2.0.dmg"
    actual="$(shasum -a 256 "$TEST_TMP/fixture/AgentMeter-0.2.0.dmg" | awk '{print $1}')"
    stub_gh_download
    assert_status 1 update_cask 0.2.0
    assert_eq "error: AgentMeter-0.2.0.dmg of release v0.2.0 has sha256 $actual, but release-info.json says $FIXTURE_SHA" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}

test_update_cask_fails_without_dmg_asset() {
    setup_tap
    write_fixture 0.2.0 -
    rm "$TEST_TMP/fixture/AgentMeter-0.2.0.dmg"
    stub_gh_download
    assert_status 1 update_cask 0.2.0
    assert_eq "error: cannot download AgentMeter-0.2.0.dmg of release v0.2.0 from example/agentmeter (no assets match the file pattern)" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}

# --- only the latest release (FINDING-32) -----------------------------------

test_update_cask_leaves_cask_for_older_release() {
    setup_tap
    write_fixture 0.2.0 -
    stub_gh_download
    GH_RELEASE_TAGS="v0.2.0 v0.3.0" assert_status 0 update_cask 0.2.0
    assert_eq "cask: v0.2.0 is not the latest release, cask left unchanged" "$(cat "$LAST_OUT")"
    assert_eq "" "$(cat "$LAST_ERR")"
    assert_not_contains "$(cat "$CALL_LOG")" "release download"
    assert_eq "" "$(tap_log)"
}

test_update_cask_orders_versions_numerically() {
    setup_tap
    write_fixture 0.10.0 -
    stub_gh_download
    GH_RELEASE_TAGS="v0.9.0 v0.10.0 v0.2.0" assert_status 0 update_cask 0.10.0
    assert_eq "agentmeter 0.10.0" "$(tap_log)"
    write_fixture 0.9.0 -
    GH_RELEASE_TAGS="v0.9.0 v0.10.0 v0.2.0" assert_status 0 update_cask 0.9.0
    assert_eq "cask: v0.9.0 is not the latest release, cask left unchanged" "$(cat "$LAST_OUT")"
    assert_eq "agentmeter 0.10.0" "$(tap_log)"
}

test_update_cask_fails_when_release_list_fails() {
    setup_tap
    write_fixture 0.2.0 -
    stub_gh_download
    GH_LIST_STATUS=1 assert_status 1 update_cask 0.2.0
    assert_eq "error: cannot list the releases of example/agentmeter (HTTP 502: Bad Gateway)" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}

test_update_cask_fails_without_any_listed_release() {
    setup_tap
    write_fixture 0.2.0 -
    stub_gh_download
    GH_RELEASE_TAGS="" assert_status 1 update_cask 0.2.0
    assert_eq "error: cannot find the latest release of example/agentmeter" "$(cat "$LAST_ERR")"
    assert_eq "" "$(tap_log)"
}
