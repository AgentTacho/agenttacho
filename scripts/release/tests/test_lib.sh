# Tests for the logging helpers in lib.sh and the icon check of build-app.sh.

. "$RELEASE_DIR/lib.sh"

test_die_prints_error_and_exits_1() {
    assert_status 1 die "something broke"
    assert_eq "error: something broke" "$(cat "$LAST_ERR")"
    assert_eq "" "$(cat "$LAST_OUT")"
}

test_warn_prints_warning_on_stderr() {
    assert_status 0 warn "careful"
    assert_eq "warning: careful" "$(cat "$LAST_ERR")"
    assert_eq "" "$(cat "$LAST_OUT")"
}

test_log_prints_prefixed_line_on_stdout() {
    assert_eq "dmg: build/release/x.dmg" "$(log dmg build/release/x.dmg)"
}

test_build_app_fails_without_icon_before_building() {
    make_stub swift "echo \"swift \$*\" >>\"$CALL_LOG\""
    make_stub codesign "echo \"codesign \$*\" >>\"$CALL_LOG\""
    APP_ICON=/nonexistent assert_status 1 bash "$RELEASE_DIR/build-app.sh"
    assert_eq "error: missing app icon: /nonexistent" "$(cat "$LAST_ERR")"
    assert_eq "" "$(cat "$CALL_LOG")" "no build step may run"
}

# --- release_defaults (FINDING-25) -------------------------------------------

test_release_defaults_fill_unset_and_empty_values() {
    (
        unset GH_REPO TAP_REPO SITE_REPO SIGN_IDENTITY_NAME APP_ICON
        NOTARY_PROFILE=""
        release_defaults
        assert_eq "AgentTacho/agenttacho" "$GH_REPO"
        assert_eq "git@github.com:AgentTacho/homebrew-tap.git" "$TAP_REPO"
        assert_eq "AgentTacho/agenttacho.github.io" "$SITE_REPO"
        assert_eq "agenttacho-notary" "$NOTARY_PROFILE"
        assert_eq "AgentTacho Signing" "$SIGN_IDENTITY_NAME"
        assert_eq "Resources/icons/macos/AgentTacho.icns" "$APP_ICON"
        assert_eq "build/AgentTacho.app" "$APP"
        assert_eq "build/release" "$OUT_DIR"
        # Exported, so helper scripts and stubs see the same values.
        assert_eq "AgentTacho/agenttacho" "$(bash -c 'echo "$GH_REPO"')"
        assert_eq "AgentTacho/agenttacho.github.io" "$(bash -c 'echo "$SITE_REPO"')"
    )
}

# spec 024 FR-001: the demo build has its own app name and bundle id.
test_release_defaults_demo_identity() {
    (
        unset DEMO
        release_defaults
        assert_eq "build/AgentTacho.app" "$APP"
        assert_eq "dev.rhuss.agenttacho" "$BUNDLE_ID"
    )
    (
        DEMO=1
        release_defaults
        assert_eq "build/AgentTacho Demo.app" "$APP"
        assert_eq "dev.rhuss.agenttacho.demo" "$BUNDLE_ID"
    )
}

test_release_defaults_keep_overrides() {
    (
        GH_REPO=example/app TAP_REPO=/tmp/tap NOTARY_PROFILE=ci \
            SIGN_IDENTITY_NAME="Other" APP_ICON=icon.icns SITE_REPO=example/site
        release_defaults
        assert_eq "example/app /tmp/tap ci Other icon.icns example/site" \
            "$GH_REPO $TAP_REPO $NOTARY_PROFILE $SIGN_IDENTITY_NAME $APP_ICON $SITE_REPO"
    )
}

# --- with_reason (FINDING-33) -------------------------------------------------

test_with_reason_without_output_keeps_message() {
    assert_eq "cannot clone" "$(with_reason "cannot clone" "")"
    assert_eq "cannot clone" "$(with_reason "cannot clone" "

")"
}

test_with_reason_appends_last_non_empty_line() {
    assert_eq "cannot push (second line)" "$(with_reason "cannot push" "first line
second line

")"
}

test_with_reason_skips_git_access_hint() {
    local output="git@github.com: Permission denied (publickey).
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists."
    assert_eq "tap not reachable (git@github.com: Permission denied (publickey).)" \
        "$(with_reason "tap not reachable" "$output")"
}
