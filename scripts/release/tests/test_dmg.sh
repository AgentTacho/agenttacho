# Tests for dmg_background and dmg_filename (FR-009 to FR-012).

. "$RELEASE_DIR/lib.sh"

test_notarized_developer_id_uses_notarized_background() {
    assert_eq "Resources/dmg/background-notarized.png" "$(dmg_background developer-id true)"
}

test_not_notarized_developer_id_uses_unnotarized_background() {
    assert_eq "Resources/dmg/background-unnotarized.png" "$(dmg_background developer-id false)"
}

test_self_signed_and_ad_hoc_use_unnotarized_background() {
    assert_eq "Resources/dmg/background-unnotarized.png" "$(dmg_background self-signed false)"
    assert_eq "Resources/dmg/background-unnotarized.png" "$(dmg_background self-signed true)"
    assert_eq "Resources/dmg/background-unnotarized.png" "$(dmg_background ad-hoc true)"
}

test_dmg_filename_uses_display_version() {
    assert_eq "AgentTacho-0.2.0.dmg" "$(dmg_filename 0.2.0)"
    assert_eq "AgentTacho-0.2.0-dev.dmg" "$(dmg_filename 0.2.0-dev)"
}
