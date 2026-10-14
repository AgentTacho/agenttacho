# Tests for release_notes, release_info_json (contracts/release-info.md) and
# notary_profile_state (FR-014a, FR-017).

. "$RELEASE_DIR/lib.sh"

SHA="3b1f0c9e4a8d2b7f6e5c4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d"

test_notes_for_self_signed_release() {
    local notes
    notes="$(release_notes 0.2.0 self-signed false)"
    assert_contains "$notes" "self-signed, not notarized"
    assert_contains "$notes" "AgentMeter-0.2.0.dmg"
    assert_contains "$notes" "macOS 14"
    assert_contains "$notes" "Control-click AgentMeter in Applications"
    assert_contains "$notes" "macOS 15 or later"
    assert_contains "$notes" "Open Anyway"
    assert_contains "$notes" "xattr -dr com.apple.quarantine /Applications/AgentMeter.app"
}

test_notes_say_homebrew_reopens_after_upgrade() {
    local tier notarized notes
    for tier in self-signed developer-id ad-hoc; do
        for notarized in true false; do
            notes="$(release_notes 0.2.0 "$tier" "$notarized")"
            assert_contains "$notes" "Homebrew quits AgentMeter before an upgrade and opens it again afterwards."
            assert_contains "$notes" "To upgrade from a DMG, quit AgentMeter, replace it in Applications and open it again."
            assert_not_contains "$notes" "do not restart"
        done
    done
}

test_notes_for_notarized_developer_id_release() {
    local notes
    notes="$(release_notes 0.3.0 developer-id true)"
    assert_contains "$notes" "Developer ID, notarized"
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
    assert_contains "$notes" "xattr -dr com.apple.quarantine /Applications/AgentMeter.app"
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
    assert_eq "AgentMeter-0.2.0.dmg" "$(printf '%s' "$json" | jq -r .dmg)"
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
    assert_contains "$(cat "$CALL_LOG")" "xcrun notarytool history --keychain-profile agentmeter-notary"
}

test_notary_missing_when_keychain_has_no_profile() {
    stub_xcrun 69 "Error: No Keychain password item found for profile: agentmeter-notary"
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
