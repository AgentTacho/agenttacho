# Tests for select_identity, codesign_flags and requirement_is_certificate_based
# (research.md R3, data-model.md SigningTier).

. "$RELEASE_DIR/lib.sh"
. "$TESTS_DIR/helpers.sh"

DEVID_HASH="1111111111111111111111111111111111111111"
SELF_HASH="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
SELF2_HASH="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
OTHER_HASH="CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"

test_developer_id_wins_over_self_signed() {
    stub_identities \
        "$SELF_HASH \"AgentTacho Signing\" (CSSMERR_TP_NOT_TRUSTED)" \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\""
    assert_eq "developer-id $DEVID_HASH Developer ID Application: Roland Huss (TEAM123456)" "$(select_identity)"
}

test_find_identity_is_called_without_valid_only_flag() {
    stub_identities "$SELF_HASH \"AgentTacho Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    select_identity >/dev/null
    assert_contains "$(cat "$CALL_LOG")" "security find-identity -p codesigning"
    assert_not_contains "$(cat "$CALL_LOG")" " -v"
}

test_untrusted_self_signed_is_selected() {
    stub_identities "$SELF_HASH \"AgentTacho Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "self-signed $SELF_HASH AgentTacho Signing" "$(select_identity)"
}

test_no_identity_gives_ad_hoc() {
    stub_identities
    assert_eq "ad-hoc - no certificate" "$(select_identity)"
}

test_failing_security_gives_ad_hoc() {
    make_stub security "exit 1"
    assert_eq "ad-hoc -" "$(select_identity | awk '{print $1, $2}')"
}

test_sign_identity_dash_forces_ad_hoc() {
    stub_identities \
        "$SELF_HASH \"AgentTacho Signing\"" \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\""
    assert_eq "ad-hoc -" "$(SIGN_IDENTITY=- select_identity | awk '{print $1, $2}')"
}

test_sign_identity_name_selects_other_certificate() {
    stub_identities \
        "$SELF_HASH \"AgentTacho Signing\"" \
        "$OTHER_HASH \"Other Cert\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "self-signed $OTHER_HASH Other Cert" "$(SIGN_IDENTITY_NAME="Other Cert" select_identity)"
}

test_sign_identity_name_without_match_gives_ad_hoc() {
    stub_identities "$SELF_HASH \"AgentTacho Signing\""
    assert_eq "ad-hoc -" "$(SIGN_IDENTITY_NAME="Missing" select_identity | awk '{print $1, $2}')"
}

test_explicit_developer_id_name_derives_tier() {
    stub_identities \
        "$SELF_HASH \"AgentTacho Signing\"" \
        "$DEVID_HASH \"Developer ID Application: X (TEAM)\""
    assert_eq "developer-id $DEVID_HASH Developer ID Application: X (TEAM)" \
        "$(SIGN_IDENTITY="Developer ID Application: X (TEAM)" select_identity)"
}

test_explicit_hash_selects_that_identity() {
    stub_identities \
        "$SELF_HASH \"AgentTacho Signing\"" \
        "$OTHER_HASH \"Other Cert\""
    assert_eq "self-signed $OTHER_HASH Other Cert" "$(SIGN_IDENTITY="$OTHER_HASH" select_identity)"
}

test_explicit_unknown_identity_fails() {
    stub_identities "$SELF_HASH \"AgentTacho Signing\""
    SIGN_IDENTITY="Nope" assert_status 1 select_identity
    assert_contains "$(cat "$LAST_ERR")" "error: signing identity not found: Nope"
}

test_duplicate_names_select_first_hash() {
    stub_identities \
        "$SELF_HASH \"AgentTacho Signing\" (CSSMERR_TP_NOT_TRUSTED)" \
        "$SELF2_HASH \"AgentTacho Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "self-signed $SELF_HASH AgentTacho Signing" "$(select_identity)"
}

# The selection itself still skips an expired or revoked Developer ID; a
# release stops in preflight instead (spec 015 FR-012, test_preflight.sh).
test_expired_developer_id_is_not_selected() {
    stub_identities \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_CERT_EXPIRED)" \
        "$SELF_HASH \"AgentTacho Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "self-signed $SELF_HASH AgentTacho Signing" "$(select_identity)"
}

test_revoked_developer_id_is_not_selected() {
    stub_identities \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_CERT_REVOKED)" \
        "$SELF_HASH \"AgentTacho Signing\""
    assert_eq "self-signed $SELF_HASH AgentTacho Signing" "$(select_identity)"
}

test_untrusted_developer_id_is_accepted() {
    stub_identities \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "developer-id $DEVID_HASH" "$(select_identity | awk '{print $1, $2}')"
}

# --- unusable_developer_ids (spec 015 FR-012) ---------------------------------

test_expired_developer_id_is_listed_as_unusable() {
    stub_identities \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_CERT_EXPIRED)" \
        "$SELF_HASH \"AgentTacho Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "$(printf '%s\t%s\t%s' "$DEVID_HASH" "Developer ID Application: Roland Huss (TEAM123456)" expired)" \
        "$(unusable_developer_ids)"
}

test_revoked_developer_id_is_listed_as_unusable() {
    stub_identities \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_CERT_REVOKED)"
    assert_eq "$(printf '%s\t%s\t%s' "$DEVID_HASH" "Developer ID Application: Roland Huss (TEAM123456)" revoked)" \
        "$(unusable_developer_ids)"
}

test_several_unusable_developer_ids_are_listed_once_each() {
    stub_identities \
        "$DEVID_HASH \"Developer ID Application: Old (TEAM1)\" (CSSMERR_TP_CERT_EXPIRED)" \
        "$OTHER_HASH \"Developer ID Application: Other (TEAM2)\" (CSSMERR_TP_CERT_REVOKED)" \
        "$DEVID_HASH \"Developer ID Application: Old (TEAM1)\" (CSSMERR_TP_CERT_EXPIRED)"
    assert_eq "$(printf '%s\t%s\t%s\n%s\t%s\t%s' "$DEVID_HASH" "Developer ID Application: Old (TEAM1)" expired \
        "$OTHER_HASH" "Developer ID Application: Other (TEAM2)" revoked)" "$(unusable_developer_ids)"
}

test_usable_and_other_certificates_are_not_listed_as_unusable() {
    stub_identities \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_NOT_TRUSTED)" \
        "$OTHER_HASH \"Developer ID Application: Valid (TEAM2)\"" \
        "$SELF_HASH \"AgentTacho Signing\" (CSSMERR_TP_CERT_EXPIRED)" \
        "$SELF2_HASH \"Apple Development: Roland Huss (TEAM3)\" (CSSMERR_TP_CERT_REVOKED)"
    assert_eq "" "$(unusable_developer_ids)"
}

test_failing_security_lists_no_unusable_developer_id() {
    make_stub security "exit 1"
    assert_eq "" "$(unusable_developer_ids)"
}

test_codesign_flags_per_tier() {
    assert_eq "--options runtime --timestamp" "$(codesign_flags developer-id)"
    assert_eq "--timestamp=none" "$(codesign_flags self-signed)"
    assert_eq "--timestamp=none" "$(codesign_flags ad-hoc)"
}

test_cdhash_requirement_is_not_certificate_based() {
    assert_status 1 requirement_is_certificate_based 'designated => cdhash H"0123456789abcdef0123456789abcdef01234567"'
}

test_empty_requirement_is_not_certificate_based() {
    assert_status 1 requirement_is_certificate_based ""
}

test_certificate_root_requirement_is_certificate_based() {
    assert_status 0 requirement_is_certificate_based \
        'designated => identifier "dev.rhuss.agenttacho" and certificate root = H"0123456789abcdef0123456789abcdef01234567"'
}

test_certificate_leaf_requirement_is_certificate_based() {
    assert_status 0 requirement_is_certificate_based \
        'designated => identifier "dev.rhuss.agenttacho" and certificate leaf = H"0123456789abcdef0123456789abcdef01234567"'
}

test_developer_id_requirement_is_certificate_based() {
    assert_status 0 requirement_is_certificate_based \
        'designated => identifier "dev.rhuss.agenttacho" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = TEAM123456'
}
