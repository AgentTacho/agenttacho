# End-to-end tests for release.sh and notarize.sh with stubbed helpers and
# tools (FR-015 to FR-019, SC-005). Nothing here talks to GitHub or Apple.

. "$RELEASE_DIR/lib.sh"
. "$TESTS_DIR/helpers.sh"

FAKE_SHA="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
# Checksum of the DMG the make-dmg stub writes (the text "dmg").
DMG_SHA="$(printf 'dmg\n' | shasum -a 256 | awk '{print $1}')"

# Helper script stubs; each records its call. CASK_STATUS and NOTARIZE_STATUS
# set their exit status; STALE_SHA=1 makes the DMG stub write a checksum that
# does not match the DMG.
stub_helpers() {
    mkdir -p "$TEST_TMP/helpers"
    cat >"$TEST_TMP/helpers/build-app.sh" <<EOF
echo "build SIGN_IDENTITY=\$SIGN_IDENTITY DISTRIBUTION=\${DISTRIBUTION:-} NOTARIZE=\${NOTARIZE:-}" >>"$CALL_LOG"
EOF
    cat >"$TEST_TMP/helpers/make-dmg.sh" <<EOF
echo "dmg \$*" >>"$CALL_LOG"
mkdir -p build/release
echo "dmg" >"build/release/AgentMeter-\$2.dmg"
if [ "\${STALE_SHA:-0}" = 1 ]; then
    echo "$FAKE_SHA  AgentMeter-\$2.dmg" >"build/release/AgentMeter-\$2.dmg.sha256"
else
    (cd build/release && shasum -a 256 "AgentMeter-\$2.dmg" >"AgentMeter-\$2.dmg.sha256")
fi
EOF
    # Like stapling, a successful notarization changes the DMG.
    cat >"$TEST_TMP/helpers/notarize.sh" <<EOF
echo "notarize \$*" >>"$CALL_LOG"
[ "\${NOTARIZE_STATUS:-0}" = 0 ] || exit "\$NOTARIZE_STATUS"
echo "stapled ticket" >>"\$1"
EOF
    cat >"$TEST_TMP/helpers/update-cask.sh" <<EOF
echo "cask \$*" >>"$CALL_LOG"
exit \${CASK_STATUS:-0}
EOF
}

# stub_xcrun: `notarytool history` succeeds when NOTARY_OK=1, fails with
# NOTARY_ERROR when that is set, and otherwise reports a missing profile.
stub_xcrun() {
    make_stub xcrun "
echo \"xcrun \$*\" >>\"$CALL_LOG\"
[ \"\${NOTARY_OK:-0}\" = 1 ] && exit 0
if [ -n \"\${NOTARY_ERROR:-}\" ]; then echo \"Error: \$NOTARY_ERROR\" >&2; exit 1; fi
echo 'Error: No Keychain password item found for profile: agentmeter-notary' >&2
exit 69"
}

prepare() {
    stub_security "${1:-self-signed}"
    stub_gh
    stub_xcrun
    stub_helpers
    setup_release_repo
}

# run_release [--dry-run]: release.sh with the helper stubs; with
# UPDATE_CASK_SH_REAL=1 the real update-cask.sh runs against the gh stub.
run_release() {
    local update_cask="$TEST_TMP/helpers/update-cask.sh"
    [ "${UPDATE_CASK_SH_REAL:-0}" = 0 ] || update_cask="$RELEASE_DIR/update-cask.sh"
    RELEASE_ROOT="$PWD" \
        BUILD_APP_SH="$TEST_TMP/helpers/build-app.sh" \
        MAKE_DMG_SH="$TEST_TMP/helpers/make-dmg.sh" \
        NOTARIZE_SH="$TEST_TMP/helpers/notarize.sh" \
        UPDATE_CASK_SH="$update_cask" \
        bash "$RELEASE_DIR/release.sh" "$@" </dev/null
}

assert_before() {
    local first second
    first="$(line_of "$1")"
    second="$(line_of "$2")"
    [ "$first" -gt 0 ] || fail "no call matching [$1] in: $(cat "$CALL_LOG")"
    [ "$second" -gt 0 ] || fail "no call matching [$2] in: $(cat "$CALL_LOG")"
    [ "$first" -lt "$second" ] || fail "[$1] (line $first) not before [$2] (line $second)"
}

test_release_runs_steps_in_order() {
    prepare
    tag_and_push v0.2.0
    assert_status 0 run_release
    assert_before "gh auth status" "build "
    assert_before "build " "dmg "
    assert_before "dmg " "gh release create v0.2.0"
    assert_before "gh release create v0.2.0" "gh release upload v0.2.0 build/release/AgentMeter-0.2.0.dmg "
    assert_before "gh release upload v0.2.0 build/release/AgentMeter-0.2.0.dmg " "gh release upload v0.2.0 build/release/AgentMeter-0.2.0.dmg.sha256"
    assert_before "gh release upload v0.2.0 build/release/AgentMeter-0.2.0.dmg.sha256" "gh release upload v0.2.0 build/release/release-info.json"
    assert_before "gh release upload v0.2.0 build/release/release-info.json" "gh release edit v0.2.0"
    assert_before "gh release edit v0.2.0" "cask 0.2.0"
    local log
    log="$(cat "$CALL_LOG")"
    assert_contains "$log" "build SIGN_IDENTITY=$SELF_SIGNED_HASH DISTRIBUTION=1"
    assert_contains "$log" "dmg build/AgentMeter.app 0.2.0 self-signed false $SELF_SIGNED_HASH"
    assert_contains "$log" "--draft --verify-tag"
    assert_contains "$log" "--draft=false --notes-file build/release/release-notes.md"
    # spec 015 FR-016: the highest release is published as latest.
    assert_contains "$log" "gh release edit v0.2.0 -R example/agentmeter --draft=false --notes-file build/release/release-notes.md --latest"
    assert_not_contains "$log" "--latest=false"
    assert_not_contains "$log" "--draft=true"
    assert_not_contains "$log" "notarize "
    assert_not_contains "$log" "--clobber"
    assert_eq "0.2.0" "$(jq -r .version build/release/release-info.json)"
    assert_eq "$DMG_SHA" "$(jq -r .sha256 build/release/release-info.json)"
    assert_contains "$(cat build/release/release-notes.md)" "self-signed, not notarized"
}

# The plist is sealed by the signature, so the build learns before it runs
# whether it gets notarized (About tab).
test_release_passes_notarize_decision_to_build() {
    prepare developer-id
    tag_and_push v0.2.0
    NOTARY_OK=1 assert_status 0 run_release
    assert_contains "$(cat "$CALL_LOG")" "build SIGN_IDENTITY=$DEVELOPER_ID_HASH DISTRIBUTION=1 NOTARIZE=true"
}

test_release_without_notarization_tells_build_so() {
    prepare
    tag_and_push v0.2.0
    assert_status 0 run_release
    assert_contains "$(cat "$CALL_LOG")" "build SIGN_IDENTITY=$SELF_SIGNED_HASH DISTRIBUTION=1 NOTARIZE=false"
}

test_release_notes_list_changes_since_previous_release() {
    prepare
    git tag v0.1.0
    echo "feature" >>README
    git commit -q -am "feat(menubar): one order for bar and dropdown (#3)"
    echo "docs" >>README
    git commit -q -am "docs: explain"
    git push -q origin main
    tag_and_push v0.2.0
    assert_status 0 run_release
    local notes
    notes="$(cat build/release/release-notes.md)"
    assert_contains "$notes" "## Changes"
    assert_contains "$notes" "- menubar: one order for bar and dropdown (#3) ($(git rev-parse --short=7 HEAD~1))"
    assert_not_contains "$notes" "explain"
}

test_checksum_not_matching_the_dmg_stops_before_github() {
    prepare
    tag_and_push v0.2.0
    STALE_SHA=1 assert_status 1 run_release
    assert_eq "error: release-info.json has sha256 $FAKE_SHA, but build/release/AgentMeter-0.2.0.dmg has $DMG_SHA" "$(cat "$LAST_ERR")"
    assert_not_contains "$(cat "$CALL_LOG")" "gh release create"
    assert_not_contains "$(cat "$CALL_LOG")" "gh release upload"
}

test_preflight_failure_builds_nothing() {
    prepare
    assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "error: HEAD has no vX.Y.Z tag"
    assert_not_contains "$(cat "$CALL_LOG")" "build "
    assert_not_contains "$(cat "$CALL_LOG")" "gh release create"
}

test_failing_upload_keeps_draft_and_never_publishes() {
    prepare
    tag_and_push v0.2.0
    GH_FAIL_ON="release-info.json" assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "error: uploading release-info.json failed; draft release v0.2.0 left in place, retry with: make release REPLACE=1, or delete with: gh release delete v0.2.0 -R example/agentmeter --yes"
    assert_not_contains "$(cat "$CALL_LOG")" "gh release edit"
    assert_not_contains "$(cat "$CALL_LOG")" "cask "
}

test_failing_draft_creation_publishes_nothing() {
    prepare
    tag_and_push v0.2.0
    GH_FAIL_ON="release create" assert_status 1 run_release
    assert_not_contains "$(cat "$LAST_ERR")" "draft release v0.2.0 left in place"
    assert_not_contains "$(cat "$CALL_LOG")" "gh release upload"
}

test_failing_cask_update_names_cask_command() {
    prepare
    tag_and_push v0.2.0
    CASK_STATUS=1 assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "error: cask update failed; finish with: make cask VERSION=0.2.0"
    assert_contains "$(cat "$CALL_LOG")" "gh release edit v0.2.0"
}

test_developer_id_with_profile_notarizes_before_release() {
    prepare developer-id
    tag_and_push v0.2.0
    NOTARY_OK=1 assert_status 0 run_release
    assert_before "notarize build/release/AgentMeter-0.2.0.dmg" "gh release create v0.2.0"
    assert_contains "$(cat "$CALL_LOG")" "dmg build/AgentMeter.app 0.2.0 developer-id true $DEVELOPER_ID_HASH"
    assert_eq "true" "$(jq -r .notarized build/release/release-info.json)"
    assert_contains "$(cat build/release/release-notes.md)" "Developer ID, notarized"
    # The checksum is taken again after stapling changed the DMG.
    local stapled_sha
    stapled_sha="$(shasum -a 256 build/release/AgentMeter-0.2.0.dmg | awk '{print $1}')"
    [ "$stapled_sha" != "$DMG_SHA" ] || fail "the notarize stub did not change the DMG"
    assert_eq "$stapled_sha" "$(jq -r .sha256 build/release/release-info.json)"
    assert_eq "$stapled_sha  AgentMeter-0.2.0.dmg" "$(cat build/release/AgentMeter-0.2.0.dmg.sha256)"
}

test_notary_service_error_stops_release_before_building() {
    prepare developer-id
    tag_and_push v0.2.0
    NOTARY_ERROR="HTTP status code: 401" assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "error: cannot check notarization profile agentmeter-notary: Error: HTTP status code: 401"
    assert_not_contains "$(cat "$CALL_LOG")" "build "
    assert_not_contains "$(cat "$CALL_LOG")" "gh release create"
}

test_notary_service_error_in_dry_run_only_warns() {
    prepare developer-id
    tag_and_push v0.2.0
    NOTARY_ERROR="network down" assert_status 0 run_release --dry-run
    assert_contains "$(cat "$LAST_ERR")" "warning: cannot check notarization profile agentmeter-notary (Error: network down)"
    assert_contains "$(cat "$CALL_LOG")" "dmg build/AgentMeter.app 0.2.0 developer-id false $DEVELOPER_ID_HASH"
}

test_failing_notarization_writes_nothing_to_github() {
    prepare developer-id
    tag_and_push v0.2.0
    NOTARY_OK=1 NOTARIZE_STATUS=1 assert_status 1 run_release
    local log
    log="$(cat "$CALL_LOG")"
    assert_contains "$log" "notarize "
    assert_not_contains "$log" "gh release create"
    assert_not_contains "$log" "gh release upload"
    assert_not_contains "$log" "gh release edit"
    assert_not_contains "$log" "cask "
}

test_developer_id_without_profile_warns_and_skips_notarization() {
    prepare developer-id
    tag_and_push v0.2.0
    assert_status 0 run_release
    assert_contains "$(cat "$LAST_ERR")" "warning: Developer ID certificate without notarization profile agentmeter-notary"
    assert_not_contains "$(cat "$CALL_LOG")" "notarize "
    assert_contains "$(cat "$CALL_LOG")" "dmg build/AgentMeter.app 0.2.0 developer-id false $DEVELOPER_ID_HASH"
    assert_contains "$(cat build/release/release-notes.md)" "Developer ID, not notarized"
}

test_dry_run_on_dirty_untagged_repo_publishes_nothing() {
    prepare developer-id
    echo "change" >>README
    NOTARY_OK=1 GH_AUTH_STATUS=1 assert_status 0 run_release --dry-run
    local log
    log="$(cat "$CALL_LOG")"
    assert_contains "$(cat "$LAST_ERR")" "warning: working tree has uncommitted changes"
    assert_contains "$(cat "$LAST_ERR")" "warning: HEAD has no vX.Y.Z tag"
    assert_contains "$log" "build SIGN_IDENTITY=$DEVELOPER_ID_HASH DISTRIBUTION=1"
    assert_contains "$log" "dmg build/AgentMeter.app 0.0.0-dev developer-id true $DEVELOPER_ID_HASH"
    assert_not_contains "$log" "gh release create"
    assert_not_contains "$log" "gh release upload"
    assert_not_contains "$log" "gh release edit"
    assert_not_contains "$log" "notarize "
    assert_not_contains "$log" "cask "
    [ -f build/release/release-info.json ] || fail "dry run writes release-info.json"
    # The dry run previews the notarized background but never notarizes, so
    # its notes and release info must not claim notarization.
    assert_eq "false" "$(jq -r .notarized build/release/release-info.json)"
    assert_contains "$(cat build/release/release-notes.md)" "Developer ID, not notarized"
}

# spec 015 FR-016: a published release becomes a draft before any asset is
# replaced and is published again after every upload succeeded.
test_replace_on_published_release_goes_through_a_draft() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_EXISTS=1 REPLACE=1 assert_status 0 run_release
    local log
    log="$(cat "$CALL_LOG")"
    assert_not_contains "$log" "gh release create"
    assert_contains "$log" "gh release edit v0.2.0 -R example/agentmeter --draft=true"
    assert_contains "$log" "gh release upload v0.2.0 build/release/AgentMeter-0.2.0.dmg -R example/agentmeter --clobber"
    assert_before "gh release edit v0.2.0 -R example/agentmeter --draft=true" "gh release upload v0.2.0"
    assert_before "gh release upload v0.2.0 build/release/release-info.json" "--draft=false"
    assert_contains "$log" "gh release edit v0.2.0 -R example/agentmeter --draft=false --notes-file build/release/release-notes.md --latest"
    assert_not_contains "$log" "--latest=false"
    assert_before "--draft=false" "cask 0.2.0"
}

test_replace_failure_on_published_release_leaves_a_draft() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_EXISTS=1 REPLACE=1 GH_FAIL_ON="release upload" assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "error: uploading AgentMeter-0.2.0.dmg failed; draft release v0.2.0 left in place, retry with: make release REPLACE=1, or delete with: gh release delete v0.2.0 -R example/agentmeter --yes"
    assert_contains "$(cat "$LAST_ERR")" "note: v0.2.0 was published before; its downloads (also through the Homebrew cask) fail until a retry publishes it again"
    assert_not_contains "$(cat "$LAST_ERR")" "is published"
    assert_before "gh release edit v0.2.0 -R example/agentmeter --draft=true" "gh release upload v0.2.0"
    assert_not_contains "$(cat "$CALL_LOG")" "--draft=false"
}

# A failure after the DMG was already replaced (the set no longer matches)
# still leaves a draft, never a published release.
test_later_asset_failure_on_published_release_leaves_a_draft() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_EXISTS=1 REPLACE=1 GH_FAIL_ON="release-info.json" assert_status 1 run_release
    assert_contains "$(cat "$CALL_LOG")" "gh release upload v0.2.0 build/release/AgentMeter-0.2.0.dmg"
    assert_before "gh release edit v0.2.0 -R example/agentmeter --draft=true" "gh release upload v0.2.0 build/release/AgentMeter-0.2.0.dmg"
    assert_contains "$(cat "$LAST_ERR")" "error: uploading release-info.json failed; draft release v0.2.0 left in place"
    assert_not_contains "$(cat "$CALL_LOG")" "--draft=false"
}

# A failing publish after the uploads leaves a draft with the retry advice.
test_publish_failure_on_published_release_leaves_a_draft() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_EXISTS=1 REPLACE=1 GH_FAIL_ON="--draft=false" assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "error: publishing the release failed; draft release v0.2.0 left in place, retry with: make release REPLACE=1"
    assert_contains "$(cat "$LAST_ERR")" "note: v0.2.0 was published before"
    assert_not_contains "$(cat "$CALL_LOG")" "cask 0.2.0"
}

# A replacement of a release that was a draft all along adds no note.
test_replace_failure_on_draft_release_adds_no_published_note() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_EXISTS=1 GH_RELEASE_DRAFT=true REPLACE=1 GH_FAIL_ON="release upload" assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "error: uploading AgentMeter-0.2.0.dmg failed; draft release v0.2.0 left in place"
    assert_not_contains "$(cat "$LAST_ERR")" "was published before"
}

# A failing draft switch leaves the published release as it was.
test_failing_draft_switch_leaves_the_release_published() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_EXISTS=1 REPLACE=1 GH_FAIL_ON="--draft=true" assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "error: switching the release to a draft failed; release v0.2.0 is published, retry with: make release REPLACE=1"
    assert_not_contains "$(cat "$CALL_LOG")" "gh release upload"
    assert_not_contains "$(cat "$CALL_LOG")" "--draft=false"
}

# Whether a publish marks the release as latest is decided by version.
test_retry_of_an_older_draft_is_not_marked_latest() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_EXISTS=1 GH_RELEASE_DRAFT=true REPLACE=1 GH_RELEASE_TAGS="v0.1.0 v0.3.0" assert_status 0 run_release
    assert_contains "$(cat "$CALL_LOG")" "gh release edit v0.2.0 -R example/agentmeter --draft=false --notes-file build/release/release-notes.md --latest=false"
    assert_contains "$(cat "$CALL_LOG")" "gh release list -R example/agentmeter --exclude-drafts"
}

test_replacing_an_older_published_release_is_not_marked_latest() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_EXISTS=1 REPLACE=1 GH_RELEASE_TAGS="v0.2.0 v0.10.0" assert_status 0 run_release
    assert_contains "$(cat "$CALL_LOG")" "--draft=false --notes-file build/release/release-notes.md --latest=false"
}

test_new_release_older_than_a_published_one_is_not_marked_latest() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_TAGS="v0.3.0" assert_status 0 run_release
    assert_contains "$(cat "$CALL_LOG")" "gh release create v0.2.0"
    assert_contains "$(cat "$CALL_LOG")" "--draft=false --notes-file build/release/release-notes.md --latest=false"
}

test_new_highest_release_is_marked_latest() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_TAGS="v0.1.0 v0.1.9" assert_status 0 run_release
    assert_contains "$(cat "$CALL_LOG")" "--draft=false --notes-file build/release/release-notes.md --latest"
    assert_not_contains "$(cat "$CALL_LOG")" "--latest=false"
}

# The release list is read before anything changes on GitHub.
test_failing_release_list_changes_nothing() {
    prepare
    tag_and_push v0.2.0
    GH_FAIL_ON="release list" assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "error: cannot list the releases of example/agentmeter"
    assert_not_contains "$(cat "$CALL_LOG")" "gh release create"
    assert_not_contains "$(cat "$CALL_LOG")" "gh release edit"
}

test_replace_on_draft_release_resumes_and_publishes() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_EXISTS=1 GH_RELEASE_DRAFT=true REPLACE=1 assert_status 0 run_release
    local log
    log="$(cat "$CALL_LOG")"
    assert_not_contains "$log" "gh release create"
    assert_contains "$log" "gh release upload v0.2.0 build/release/AgentMeter-0.2.0.dmg -R example/agentmeter --clobber"
    assert_before "gh release upload v0.2.0 build/release/release-info.json" "gh release edit v0.2.0"
    assert_before "gh release edit v0.2.0" "cask 0.2.0"
}

test_replace_failure_on_draft_release_says_draft() {
    prepare
    tag_and_push v0.2.0
    GH_RELEASE_EXISTS=1 GH_RELEASE_DRAFT=true REPLACE=1 GH_FAIL_ON="release upload" assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "draft release v0.2.0 left in place, retry with: make release REPLACE=1"
    assert_not_contains "$(cat "$LAST_ERR")" "is published"
    assert_not_contains "$(cat "$CALL_LOG")" "gh release edit"
}

test_replace_without_existing_release_creates_draft() {
    prepare
    tag_and_push v0.2.0
    REPLACE=1 assert_status 0 run_release
    local log
    log="$(cat "$CALL_LOG")"
    assert_contains "$log" "gh release create v0.2.0 -R example/agentmeter --draft --verify-tag"
    assert_contains "$log" "gh release upload v0.2.0 build/release/AgentMeter-0.2.0.dmg -R example/agentmeter --clobber"
    assert_before "gh release create v0.2.0" "gh release upload v0.2.0"
}

test_replace_on_older_release_leaves_cask_unchanged() {
    prepare
    tag_and_push v0.2.0
    # The real cask update: v0.3.0 is the latest release, so v0.2.0 must not
    # move the cask back (FINDING-32).
    GH_RELEASE_EXISTS=1 REPLACE=1 GH_RELEASE_TAGS="v0.2.0 v0.3.0" \
        UPDATE_CASK_SH_REAL=1 assert_status 0 run_release
    assert_contains "$(cat "$LAST_OUT")" "cask: v0.2.0 is not the latest release, cask left unchanged"
    assert_contains "$(cat "$LAST_OUT")" "release: done: AgentMeter 0.2.0"
    assert_contains "$(cat "$CALL_LOG")" "gh release list -R example/agentmeter --exclude-drafts"
    assert_not_contains "$(cat "$CALL_LOG")" "gh release download"
    assert_eq "" "$(git --git-dir="$TEST_TMP/tap.git" log --format=%s 2>/dev/null || true)"
}

# --- notarize.sh -----------------------------------------------------------

# stub_notarytool <status>: `notarytool submit` reports the given status;
# `notarytool log` writes a log file.
stub_notarytool() {
    make_stub xcrun "
echo \"xcrun \$*\" >>\"$CALL_LOG\"
case \"\$1 \$2\" in
    'notarytool submit') echo '{\"id\":\"sub-1\",\"status\":\"$1\"}' ;;
    'notarytool log') echo '{\"issues\":[]}' >\"\${@: -1}\" ;;
esac
exit 0"
}

test_notarize_accepted_staples_and_validates() {
    stub_notarytool Accepted
    mkdir -p build/release
    echo dmg >build/release/x.dmg
    RELEASE_ROOT="$PWD" assert_status 0 bash "$RELEASE_DIR/notarize.sh" build/release/x.dmg
    local log
    log="$(cat "$CALL_LOG")"
    assert_contains "$log" "notarytool submit build/release/x.dmg --wait --timeout 1h --keychain-profile agentmeter-notary --output-format json"
    assert_before "notarytool submit" "stapler staple build/release/x.dmg"
    assert_before "stapler staple" "stapler validate build/release/x.dmg"
}

test_notarize_rejected_saves_log_and_stops() {
    stub_notarytool Invalid
    mkdir -p build/release
    echo dmg >build/release/x.dmg
    RELEASE_ROOT="$PWD" NOTARY_PROFILE=ci assert_status 1 bash "$RELEASE_DIR/notarize.sh" build/release/x.dmg
    assert_contains "$(cat "$LAST_ERR")" "notarization not accepted (status: Invalid"
    assert_contains "$(cat "$LAST_ERR")" "build/release/notary-log.json"
    [ -f build/release/notary-log.json ] || fail "notary log not saved"
    assert_contains "$(cat "$CALL_LOG")" "notarytool log sub-1 --keychain-profile ci"
    assert_not_contains "$(cat "$CALL_LOG")" "stapler"
}

test_notarize_timeout_counts_as_rejection() {
    stub_notarytool "In Progress"
    mkdir -p build/release
    echo dmg >build/release/x.dmg
    RELEASE_ROOT="$PWD" assert_status 1 bash "$RELEASE_DIR/notarize.sh" build/release/x.dmg
    assert_contains "$(cat "$LAST_ERR")" "status: In Progress"
    assert_not_contains "$(cat "$CALL_LOG")" "stapler"
}

test_notarize_submission_failure_stops_without_log() {
    # notarytool fails before it has a submission: no JSON on stdout.
    make_stub xcrun "
echo \"xcrun \$*\" >>\"$CALL_LOG\"
echo 'Error: HTTP status code: 401. Unable to authenticate.' >&2
exit 1"
    mkdir -p build/release
    echo dmg >build/release/x.dmg
    RELEASE_ROOT="$PWD" assert_status 1 bash "$RELEASE_DIR/notarize.sh" build/release/x.dmg
    assert_eq "notary: submitting build/release/x.dmg (profile agentmeter-notary), this can take several minutes" "$(cat "$LAST_OUT")"
    assert_contains "$(cat "$LAST_ERR")" "error: notarization submission failed: no response from notarytool"
    assert_not_contains "$(cat "$CALL_LOG")" "notarytool log"
    assert_not_contains "$(cat "$CALL_LOG")" "stapler"
    [ ! -e build/release/notary-log.json ] || fail "no log expected"
}

test_notarize_rejection_without_log_names_log_command() {
    # Apple has the submission but its log is not available yet.
    make_stub xcrun "
echo \"xcrun \$*\" >>\"$CALL_LOG\"
case \"\$1 \$2\" in
    'notarytool submit') echo '{\"id\":\"sub-2\",\"status\":\"Invalid\"}' ;;
    'notarytool log') echo 'Error: Submission log is not available yet' >&2; exit 1 ;;
esac
exit 0"
    mkdir -p build/release
    echo dmg >build/release/x.dmg
    RELEASE_ROOT="$PWD" NOTARY_PROFILE=ci assert_status 1 bash "$RELEASE_DIR/notarize.sh" build/release/x.dmg
    assert_eq "error: notarization not accepted (status: Invalid, submission sub-2); no log yet, fetch it later with: xcrun notarytool log sub-2 --keychain-profile ci" "$(cat "$LAST_ERR")"
    assert_contains "$(cat "$CALL_LOG")" "notarytool log sub-2 --keychain-profile ci"
    assert_not_contains "$(cat "$CALL_LOG")" "stapler"
}

# --- ad-hoc release (US4 scenario 4, FINDING-38) -----------------------------

test_ad_hoc_release_with_allow_adhoc_publishes_ad_hoc() {
    prepare ad-hoc
    tag_and_push v0.2.0
    ALLOW_ADHOC=1 assert_status 0 run_release
    local log notes
    log="$(cat "$CALL_LOG")"
    notes="$(cat build/release/release-notes.md)"
    assert_contains "$log" "build SIGN_IDENTITY=- DISTRIBUTION=1"
    assert_contains "$log" "dmg build/AgentMeter.app 0.2.0 ad-hoc false -"
    assert_not_contains "$log" "notarytool"
    assert_not_contains "$log" "notarize "
    assert_before "gh release edit v0.2.0" "cask 0.2.0"
    assert_eq "ad-hoc" "$(jq -r .tier build/release/release-info.json)"
    assert_eq "false" "$(jq -r .notarized build/release/release-info.json)"
    assert_contains "$notes" "Signing: ad-hoc, not notarized."
    assert_contains "$notes" "This build is ad-hoc signed: notification permission and start at login must be granted again after every upgrade."
}

test_ad_hoc_release_without_allow_adhoc_stops() {
    prepare ad-hoc
    tag_and_push v0.2.0
    assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "error: no signing certificate available, the build would be ad-hoc signed (set ALLOW_ADHOC=1 to release anyway)"
    assert_not_contains "$(cat "$CALL_LOG")" "build "
}

# spec 015 FR-012 to FR-014 end to end: an expired Developer ID next to the
# self-signed certificate stops a release before anything is built or sent
# to GitHub; the opt-out builds self-signed, and the dry run only warns.
prepare_expired_developer_id() {
    prepare
    stub_identities \
        "$DEVELOPER_ID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_CERT_EXPIRED)" \
        "$SELF_SIGNED_HASH \"AgentMeter Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    tag_and_push v0.2.0
}

test_expired_developer_id_stops_the_release_before_building() {
    prepare_expired_developer_id
    assert_status 1 run_release
    assert_contains "$(cat "$LAST_ERR")" "is expired; renew it, or set ALLOW_TIER_DOWNGRADE=1 to release as self-signed"
    assert_not_contains "$(cat "$CALL_LOG")" "build "
    assert_not_contains "$(cat "$CALL_LOG")" "gh release create"
    assert_not_contains "$(cat "$CALL_LOG")" "gh release edit"
}

test_tier_downgrade_opt_out_releases_self_signed() {
    prepare_expired_developer_id
    ALLOW_TIER_DOWNGRADE=1 assert_status 0 run_release
    assert_contains "$(cat "$LAST_ERR")" "deliberate tier downgrade"
    assert_contains "$(cat "$CALL_LOG")" "build SIGN_IDENTITY=$SELF_SIGNED_HASH DISTRIBUTION=1"
}

test_dry_run_with_expired_developer_id_falls_back_with_a_warning() {
    prepare_expired_developer_id
    assert_status 0 run_release --dry-run
    assert_contains "$(cat "$LAST_ERR")" "a real release would stop unless ALLOW_TIER_DOWNGRADE=1 is set"
    assert_contains "$(cat "$CALL_LOG")" "build SIGN_IDENTITY=$SELF_SIGNED_HASH DISTRIBUTION=1"
}
