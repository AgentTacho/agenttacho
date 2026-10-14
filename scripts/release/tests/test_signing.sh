# Tests for select_identity, codesign_flags and requirement_is_certificate_based
# (research.md R3, data-model.md SigningTier).

. "$RELEASE_DIR/lib.sh"

DEVID_HASH="1111111111111111111111111111111111111111"
SELF_HASH="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
SELF2_HASH="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
OTHER_HASH="CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"

# stub_identities <lines...>: a `security` stub whose `find-identity -p
# codesigning` output lists the given identity lines (format: `HASH "Name"`
# optionally followed by ` (STATUS)`) in both sections, like the real tool.
stub_identities() {
    local fixture="$TEST_TMP/identities.txt" i=1 valid=0 line
    {
        echo "Policy: Code Signing"
        echo "  Matching identities"
        for line in "$@"; do
            echo "  $i) $line"
            i=$((i + 1))
        done
        echo "     $# identities found"
        echo ""
        echo "  Valid identities only"
        i=1
        for line in "$@"; do
            case "$line" in
                *CSSMERR*) ;;
                *) echo "  $i) $line"; i=$((i + 1)); valid=$((valid + 1)) ;;
            esac
        done
        echo "     $valid valid identities found"
    } >"$fixture"
    make_stub security "
echo \"security \$*\" >>\"$CALL_LOG\"
if [ \"\$1\" = find-identity ]; then cat \"$fixture\"; exit 0; fi
exit 1"
}

test_developer_id_wins_over_self_signed() {
    stub_identities \
        "$SELF_HASH \"AgentMeter Signing\" (CSSMERR_TP_NOT_TRUSTED)" \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\""
    assert_eq "developer-id $DEVID_HASH Developer ID Application: Roland Huss (TEAM123456)" "$(select_identity)"
}

test_find_identity_is_called_without_valid_only_flag() {
    stub_identities "$SELF_HASH \"AgentMeter Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    select_identity >/dev/null
    assert_contains "$(cat "$CALL_LOG")" "security find-identity -p codesigning"
    assert_not_contains "$(cat "$CALL_LOG")" " -v"
}

test_untrusted_self_signed_is_selected() {
    stub_identities "$SELF_HASH \"AgentMeter Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "self-signed $SELF_HASH AgentMeter Signing" "$(select_identity)"
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
        "$SELF_HASH \"AgentMeter Signing\"" \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\""
    assert_eq "ad-hoc -" "$(SIGN_IDENTITY=- select_identity | awk '{print $1, $2}')"
}

test_sign_identity_name_selects_other_certificate() {
    stub_identities \
        "$SELF_HASH \"AgentMeter Signing\"" \
        "$OTHER_HASH \"Other Cert\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "self-signed $OTHER_HASH Other Cert" "$(SIGN_IDENTITY_NAME="Other Cert" select_identity)"
}

test_sign_identity_name_without_match_gives_ad_hoc() {
    stub_identities "$SELF_HASH \"AgentMeter Signing\""
    assert_eq "ad-hoc -" "$(SIGN_IDENTITY_NAME="Missing" select_identity | awk '{print $1, $2}')"
}

test_explicit_developer_id_name_derives_tier() {
    stub_identities \
        "$SELF_HASH \"AgentMeter Signing\"" \
        "$DEVID_HASH \"Developer ID Application: X (TEAM)\""
    assert_eq "developer-id $DEVID_HASH Developer ID Application: X (TEAM)" \
        "$(SIGN_IDENTITY="Developer ID Application: X (TEAM)" select_identity)"
}

test_explicit_hash_selects_that_identity() {
    stub_identities \
        "$SELF_HASH \"AgentMeter Signing\"" \
        "$OTHER_HASH \"Other Cert\""
    assert_eq "self-signed $OTHER_HASH Other Cert" "$(SIGN_IDENTITY="$OTHER_HASH" select_identity)"
}

test_explicit_unknown_identity_fails() {
    stub_identities "$SELF_HASH \"AgentMeter Signing\""
    SIGN_IDENTITY="Nope" assert_status 1 select_identity
    assert_contains "$(cat "$LAST_ERR")" "error: signing identity not found: Nope"
}

test_duplicate_names_select_first_hash() {
    stub_identities \
        "$SELF_HASH \"AgentMeter Signing\" (CSSMERR_TP_NOT_TRUSTED)" \
        "$SELF2_HASH \"AgentMeter Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "self-signed $SELF_HASH AgentMeter Signing" "$(select_identity)"
}

test_expired_developer_id_falls_through_to_self_signed() {
    stub_identities \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_CERT_EXPIRED)" \
        "$SELF_HASH \"AgentMeter Signing\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "self-signed $SELF_HASH AgentMeter Signing" "$(select_identity)"
}

test_revoked_developer_id_falls_through_to_self_signed() {
    stub_identities \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_CERT_REVOKED)" \
        "$SELF_HASH \"AgentMeter Signing\""
    assert_eq "self-signed $SELF_HASH AgentMeter Signing" "$(select_identity)"
}

test_untrusted_developer_id_is_accepted() {
    stub_identities \
        "$DEVID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\" (CSSMERR_TP_NOT_TRUSTED)"
    assert_eq "developer-id $DEVID_HASH" "$(select_identity | awk '{print $1, $2}')"
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
        'designated => identifier "dev.rhuss.agentmeter" and certificate root = H"0123456789abcdef0123456789abcdef01234567"'
}

test_certificate_leaf_requirement_is_certificate_based() {
    assert_status 0 requirement_is_certificate_based \
        'designated => identifier "dev.rhuss.agentmeter" and certificate leaf = H"0123456789abcdef0123456789abcdef01234567"'
}

test_developer_id_requirement_is_certificate_based() {
    assert_status 0 requirement_is_certificate_based \
        'designated => identifier "dev.rhuss.agentmeter" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = TEAM123456'
}
