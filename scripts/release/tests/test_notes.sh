# Tests for release_notes, release_info_json (contracts/release-info.md) and
# notary_profile_state (FR-014a, FR-017).

. "$RELEASE_DIR/lib.sh"

SHA="3b1f0c9e4a8d2b7f6e5c4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d"

test_notes_for_self_signed_release() {
    local notes
    notes="$(release_notes 0.2.0 self-signed false)"
    assert_contains "$notes" "self-signed, not notarized"
    assert_contains "$notes" "AgentTacho-0.2.0.dmg"
    # spec 023 FR-014: the exact install command.
    assert_contains "$notes" 'brew install --cask rhuss/tap/agenttacho'
    assert_contains "$notes" "macOS 14"
    assert_contains "$notes" "Control-click AgentTacho in Applications"
    assert_contains "$notes" "macOS 15 or later"
    assert_contains "$notes" "Open Anyway"
    assert_contains "$notes" "xattr -dr com.apple.quarantine /Applications/AgentTacho.app"
}

test_notes_say_homebrew_reopens_after_upgrade() {
    local tier notarized notes
    for tier in self-signed developer-id ad-hoc; do
        for notarized in true false; do
            notes="$(release_notes 0.2.0 "$tier" "$notarized")"
            assert_contains "$notes" "Homebrew quits AgentTacho before an upgrade and opens it again afterwards."
            assert_contains "$notes" "To upgrade from a DMG, quit AgentTacho, replace it in Applications and open it again."
            assert_not_contains "$notes" "do not restart"
        done
    done
}

test_notes_for_notarized_developer_id_release() {
    local notes
    notes="$(release_notes 0.3.0 developer-id true)"
    assert_contains "$notes" "Developer ID, notarized"
    assert_contains "$notes" 'brew install --cask rhuss/tap/agenttacho'
    assert_not_contains "$notes" "not notarized"
    assert_not_contains "$notes" "macOS 14"
    assert_not_contains "$notes" "xattr"
}

test_notes_for_developer_id_without_notarization() {
    local notes
    notes="$(release_notes 0.3.0 developer-id false)"
    assert_contains "$notes" "Developer ID, not notarized"
    assert_contains "$notes" "xattr -dr com.apple.quarantine"
}

test_notes_for_ad_hoc_release() {
    local notes
    notes="$(release_notes 0.3.0 ad-hoc false)"
    assert_contains "$notes" "Signing: ad-hoc, not notarized."
    assert_contains "$notes" "xattr -dr com.apple.quarantine /Applications/AgentTacho.app"
    assert_contains "$notes" "This build is ad-hoc signed: notification permission and start at login must be granted again after every upgrade."
}

test_ad_hoc_paragraph_only_for_ad_hoc() {
    assert_not_contains "$(release_notes 0.3.0 self-signed false)" "ad-hoc signed"
    assert_not_contains "$(release_notes 0.3.0 developer-id true)" "ad-hoc signed"
}

test_notes_ignore_notarized_flag_for_other_tiers() {
    assert_contains "$(release_notes 0.3.0 self-signed true)" "self-signed, not notarized"
}

test_release_info_json_has_exactly_the_five_keys() {
    local json
    json="$(release_info_json 0.2.0 "$SHA" self-signed false)"
    printf '%s' "$json" | jq -e . >/dev/null || fail "invalid JSON: $json"
    assert_eq '["dmg","notarized","sha256","tier","version"]' "$(printf '%s' "$json" | jq -c 'keys')"
    assert_eq "0.2.0" "$(printf '%s' "$json" | jq -r .version)"
    assert_eq "AgentTacho-0.2.0.dmg" "$(printf '%s' "$json" | jq -r .dmg)"
    assert_eq "$SHA" "$(printf '%s' "$json" | jq -r .sha256)"
    assert_eq "self-signed" "$(printf '%s' "$json" | jq -r .tier)"
    assert_eq "false" "$(printf '%s' "$json" | jq -r .notarized)"
}

test_release_info_notarized_only_for_developer_id() {
    assert_eq "true" "$(release_info_json 0.2.0 "$SHA" developer-id true | jq -r .notarized)"
    assert_eq "false" "$(release_info_json 0.2.0 "$SHA" developer-id false | jq -r .notarized)"
    assert_eq "false" "$(release_info_json 0.2.0 "$SHA" self-signed true | jq -r .notarized)"
    assert_eq "boolean" "$(release_info_json 0.2.0 "$SHA" developer-id true | jq -r '.notarized | type')"
}

# stub_xcrun <status> [message]: `notarytool history` prints the message on
# stderr and exits with the status.
stub_xcrun() {
    make_stub xcrun "
echo \"xcrun \$*\" >>\"$CALL_LOG\"
[ -z \"${2:-}\" ] || echo \"${2:-}\" >&2
exit $1"
}

test_notary_available_when_history_succeeds() {
    stub_xcrun 0
    assert_eq "available" "$(notary_profile_state)"
    assert_contains "$(cat "$CALL_LOG")" "xcrun notarytool history --keychain-profile agenttacho-notary"
}

test_notary_missing_when_keychain_has_no_profile() {
    stub_xcrun 69 "Error: No Keychain password item found for profile: agenttacho-notary"
    assert_eq "missing" "$(notary_profile_state)"
}

test_notary_error_on_other_failures() {
    stub_xcrun 1 "Error: HTTP status code: 401. Unable to authenticate."
    assert_eq "error Error: HTTP status code: 401. Unable to authenticate." "$(notary_profile_state)"
}

test_notary_profile_override() {
    stub_xcrun 0
    NOTARY_PROFILE=ci-notary notary_profile_state >/dev/null
    assert_contains "$(cat "$CALL_LOG")" "--keychain-profile ci-notary"
}

test_notary_profile_state_does_not_read_stdin() {
    make_stub xcrun "read -r line && exit 0; echo 'Error: No Keychain password item found' >&2; exit 69"
    assert_eq "missing" "$(echo y | notary_profile_state)"
}

# --- release_changes and the Changes section (About tab) ----------------------

# commit_subject <subject>: commits a change to README with that subject.
commit_subject() {
    echo "$1" >>README
    git commit -q -am "$1"
}

# changes_repo: a repository with v0.1.0 on its first commit, followed by
# conventional feat, fix and perf commits and commits of other kinds. Leaves
# the current directory in it.
changes_repo() {
    cd "$(make_git_repo)"
    git tag v0.1.0
    commit_subject "feat(menubar): arrange entries in one order (#3)"
    commit_subject "chore: bump tooling"
    commit_subject 'fix: handle "quoted" and back\slash subjects'
    commit_subject "docs(readme): explain the bar"
    commit_subject "perf(logs)!: read only changed files"
    commit_subject "Add brainstorm: menu bar arrangement"
    commit_subject "refactor: rename"
    commit_subject "test: more cases"
    commit_subject "Feat: wrong case is not conventional"
}

test_release_changes_lists_feat_fix_perf_since_previous_tag() {
    local json
    changes_repo
    json="$(release_changes dev)"
    printf '%s' "$json" | jq -e . >/dev/null || fail "invalid JSON: $json"
    assert_eq '["perf","fix","feat"]' "$(printf '%s' "$json" | jq -c 'map(.type)')"
    assert_eq '["logs",null,"menubar"]' "$(printf '%s' "$json" | jq -c 'map(.scope)')"
    assert_eq "arrange entries in one order (#3)" "$(printf '%s' "$json" | jq -r '.[2].subject')"
    assert_eq 'handle "quoted" and back\slash subjects' "$(printf '%s' "$json" | jq -r '.[1].subject')"
    assert_eq "read only changed files" "$(printf '%s' "$json" | jq -r '.[0].subject')"
    assert_eq "$(git rev-parse --short=7 HEAD~8)" "$(printf '%s' "$json" | jq -r '.[2].hash')"
    assert_eq '["hash","scope","subject","type"]' "$(printf '%s' "$json" | jq -c '.[0] | keys')"
}

test_release_changes_of_a_release_build_skip_the_tag_on_head() {
    changes_repo
    git tag v0.2.0
    assert_eq '["perf","fix","feat"]' "$(release_changes release | jq -c 'map(.type)')"
    # A development build after v0.2.0 starts from v0.2.0.
    commit_subject "fix(prices): count models used in this window"
    assert_eq '["count models used in this window"]' "$(release_changes dev | jq -c 'map(.subject)')"
}

test_release_changes_are_empty_without_previous_tag() {
    cd "$(make_git_repo)"
    commit_subject "feat: first feature"
    assert_eq "[]" "$(release_changes dev | jq -c .)"
    git tag v0.1.0
    assert_eq "[]" "$(release_changes release | jq -c .)"
    assert_eq "[]" "$(release_changes dev | jq -c .)"
}

test_release_changes_skip_merge_commits() {
    changes_repo
    git checkout -q -b side
    commit_subject "fix(side): fixed on a branch"
    git checkout -q main
    git merge -q --no-ff -m "feat: merge the side branch" side
    assert_eq '["fixed on a branch"]' "$(release_changes dev | jq -c 'map(select(.scope == "side") | .subject)')"
    assert_not_contains "$(release_changes dev)" "merge the side branch"
}

CHANGES_JSON='[
  {"type": "fix", "scope": "prices", "subject": "count models used in this window", "hash": "7975e1b"},
  {"type": "perf", "scope": null, "subject": "read only changed files", "hash": "1234567"},
  {"type": "feat", "scope": "dmg", "subject": "mascot artwork as the DMG background", "hash": "9a00be6"}
]'

test_notes_list_changes_by_group() {
    local notes features fixes performance installation
    notes="$(release_notes 0.3.0 developer-id true "$CHANGES_JSON")"
    assert_contains "$notes" "## Changes"
    assert_contains "$notes" "### Features

- dmg: mascot artwork as the DMG background (9a00be6)"
    assert_contains "$notes" "### Fixes

- prices: count models used in this window (7975e1b)"
    assert_contains "$notes" "### Performance

- read only changed files (1234567)"
    features="$(printf '%s\n' "$notes" | grep -n '^### Features$' | cut -d: -f1)"
    fixes="$(printf '%s\n' "$notes" | grep -n '^### Fixes$' | cut -d: -f1)"
    performance="$(printf '%s\n' "$notes" | grep -n '^### Performance$' | cut -d: -f1)"
    installation="$(printf '%s\n' "$notes" | grep -n '^## Installation$' | cut -d: -f1)"
    [ "$features" -lt "$fixes" ] && [ "$fixes" -lt "$performance" ] && [ "$performance" -lt "$installation" ] ||
        fail "sections out of order: $notes"
}

test_notes_omit_empty_change_groups() {
    local notes
    notes="$(release_notes 0.3.0 developer-id true '[{"type": "fix", "scope": null, "subject": "a fix", "hash": "abcdef0"}]')"
    assert_contains "$notes" "### Fixes"
    assert_not_contains "$notes" "### Features"
    assert_not_contains "$notes" "### Performance"
}

test_notes_without_changes_have_no_changes_section() {
    assert_not_contains "$(release_notes 0.3.0 developer-id true "[]")" "## Changes"
    assert_not_contains "$(release_notes 0.3.0 developer-id true)" "## Changes"
    assert_not_contains "$(release_notes 0.3.0 developer-id true "")" "## Changes"
}
