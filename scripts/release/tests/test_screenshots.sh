# Tests for scripts/screenshots/capture.sh (spec 024 FR-017 to FR-023,
# research R12, contracts/capture-cli.md) with every macOS tool stubbed:
# uihelper, osascript, screencapture, the WebP tools, magick, open, make and
# pgrep. A fake demo log stands in for the demo app's own log.

CAPTURE_SH="$REPO_ROOT/scripts/screenshots/capture.sh"
STEMS="menubar plan-limits pace budget groups details alert prices menubar-settings harnesses dropdown"

# capture_stubs: the stubs and the fake state. Control variables:
#   PERM_AX, PERM_SR, PERM_AE  uihelper perms values (default true, true, granted)
#   SCALE                      uihelper display scale (default 2)
#   AUTO_APPEARANCE=1          Appearance is set to Auto
#   INITIAL_DARK=1             the system starts in dark appearance
#   REAL_RUNNING=1             AgentTacho runs before the capture
#   REAL_QUIT_FAIL=1           AgentTacho does not quit
#   DEMO_RUNNING=1             a demo app of an earlier run is still running
#   STATUSITEM_MISSING=1       uihelper cannot find the status item
#   NO_BANNER=1                the notification banner never shows
#   FOREIGN_BANNER=1           the banner on screen is not the demo's
#   CAPTURE_FAIL_DARK=1        screencapture fails in dark appearance
#   DWEBP_FAIL_ON=<name>       dwebp rejects the WebP file whose path contains <name>
#   APPEARANCE_FAIL_ON=<bool>  setting dark mode to <bool> fails
#   INTERRUPT_DARK=1           the dark pass's demo launch interrupts the run
#   NO_LAST_FRAME=1            the capture launches never apply their last frame
#   NO_AUTHORIZATION=1         the demo app never logs its authorization
#   ALERT_STYLE=<style>        the demo app's notification style (default banner)
#   COLLAPSE_FAIL=1            the first Claude Max details do not collapse again
#   FRAME_claudeSection_open=<frame>
#                              the first Claude Max section's frame while its
#                              details are expanded
# The appearance lives in $TEST_TMP/dark. The dropdown window is at x=900
# y=24 w=360 h=600; the first Claude Max section at x=910 y=34 w=340, 200
# high with its details collapsed and 380 expanded (an odd number of presses
# of agenttacho.claudeDetails since the demo launch, in
# $TEST_TMP/details-presses); the second at x=910 y=242 w=340 h=140; every
# other element at x=910 y=40 w=340 h=80 (spec 031 FR-012).
capture_stubs() {
    DEMO_LOG="$TEST_TMP/demo/usage.log"
    mkdir -p "$TEST_TMP/demo" "$TEST_TMP/root"
    printf '2026-10-18T06:00:00Z [notifications] authorization granted\n' >"$DEMO_LOG"
    if [ "${INITIAL_DARK:-0}" = 1 ]; then echo true >"$TEST_TMP/dark"; else echo false >"$TEST_TMP/dark"; fi
    export DEMO_LOG
    : >"$TEST_TMP/demo-running"
    [ "${DEMO_RUNNING:-0}" = 1 ] && echo running >"$TEST_TMP/demo-running"
    echo 0 >"$TEST_TMP/details-presses"
    make_stub uihelper "
echo \"uihelper \$*\" >>\"$CALL_LOG\"
case \"\$1\" in
    perms) echo \"accessibility=\${PERM_AX:-true} screenRecording=\${PERM_SR:-true} automation=\${PERM_AE:-granted}\" ;;
    display) echo \"scale=\${SCALE:-2}\" ;;
    quit)
        if [ \"\$2\" = dev.rhuss.agenttacho ]; then
            [ \"\${REAL_QUIT_FAIL:-0}\" = 1 ] && { echo 'error: dev.rhuss.agenttacho did not quit within 10 s' >&2; exit 1; }
            if [ \"\${REAL_RUNNING:-0}\" = 1 ]; then touch \"$TEST_TMP/real-quit\"; echo quit=done; else echo quit=none; fi
        else
            if [ -s \"$TEST_TMP/demo-running\" ]; then : >\"$TEST_TMP/demo-running\"; echo quit=done; else echo quit=none; fi
        fi ;;
    statusitem)
        [ \"\${STATUSITEM_MISSING:-0}\" = 1 ] && { echo 'error: menubar item not found' >&2; exit 1; }
        echo 'x=1000.0 y=0.0 w=220.0 h=24.0' ;;
    windows)
        if [ \"\$2\" = 500 ]; then
            # The banner shows once, then times out like a real one.
            if [ -e \"$TEST_TMP/banner\" ]; then rm \"$TEST_TMP/banner\"; echo 'id=31 layer=21 x=0.0 y=0.0 w=1512.0 h=982.0 title='; fi
        else
            echo 'id=14 layer=25 x=1000.0 y=0.0 w=220.0 h=24.0 title='
            echo 'id=11 layer=101 x=900.0 y=24.0 w=360.0 h=600.0 title='
            # The import preview sheet is a window of its own, listed first.
            echo 'id=15 layer=0 x=350.0 y=180.0 w=620.0 h=420.0 title='
            echo 'id=12 layer=0 x=300.0 y=100.0 w=720.0 h=560.0 title=Groups'
            echo 'id=13 layer=103 x=1100.0 y=120.0 w=325.0 h=18.0 title='
        fi ;;
    hastext)
        [ \"\${FOREIGN_BANNER:-0}\" = 1 ] && { echo \"error: no text containing \$3\" >&2; exit 1; }
        echo \"found=\$3\" ;;
    frame|scrollto)
        case \"\$3\" in
            agenttacho.claudeSection)
                if [ \$((\$(cat \"$TEST_TMP/details-presses\") % 2)) = 1 ]; then
                    echo \"\${FRAME_claudeSection_open:-x=910.0 y=34.0 w=340.0 h=380.0}\"
                else
                    echo 'x=910.0 y=34.0 w=340.0 h=200.0'
                fi ;;
            agenttacho.claudeSection2) echo 'x=910.0 y=242.0 w=340.0 h=140.0' ;;
            *) echo 'x=910.0 y=40.0 w=340.0 h=80.0' ;;
        esac ;;
    press)
        if [ \"\$3\" = agenttacho.claudeDetails ] && [ \$# = 3 ]; then
            presses=\$(cat \"$TEST_TMP/details-presses\")
            # With COLLAPSE_FAIL the expanded details stay open.
            if [ \"\${COLLAPSE_FAIL:-0}\" != 1 ] || [ \$((presses % 2)) = 0 ]; then
                echo \$((presses + 1)) >\"$TEST_TMP/details-presses\"
            fi
        fi
        echo ok ;;
    click) echo ok ;;
esac"
    make_stub osascript "
echo \"osascript \$*\" >>\"$CALL_LOG\"
case \"\$*\" in
    *'set dark mode to true'*)
        [ \"\${APPEARANCE_FAIL_ON:-}\" = true ] && exit 1
        echo true >\"$TEST_TMP/dark\" ;;
    *'set dark mode to false'*)
        [ \"\${APPEARANCE_FAIL_ON:-}\" = false ] && exit 1
        echo false >\"$TEST_TMP/dark\" ;;
    *'get dark mode'*) cat \"$TEST_TMP/dark\" ;;
esac"
    make_stub defaults "[ \"\${AUTO_APPEARANCE:-0}\" = 1 ] && echo 1 || exit 1"
    make_stub screencapture "
echo \"screencapture \$*\" >>\"$CALL_LOG\"
[ \"\${CAPTURE_FAIL_DARK:-0}\" = 1 ] && [ \"\$(cat \"$TEST_TMP/dark\")\" = true ] && exit 1
for last in \"\$@\"; do :; done
echo png >\"\$last\""
    make_stub magick "
echo \"magick \$*\" >>\"$CALL_LOG\"
echo \"magick args=\$#\" >>\"$CALL_LOG\"
for last in \"\$@\"; do :; done
echo png >\"\$last\""
    make_stub cwebp "
echo \"cwebp \$*\" >>\"$CALL_LOG\"
for last in \"\$@\"; do :; done
echo webp >\"\$last\""
    make_stub dwebp "
case \"\$1\" in *\"\${DWEBP_FAIL_ON:-no-such-file}\"*) exit 1 ;; esac
exit 0"
    make_stub webpmux 'echo "Canvas size: 640 x 480"'
    make_stub make "echo \"make \$*\" >>\"$CALL_LOG\""
    make_stub sleep 'exit 0'
    make_stub ps 'echo "/Applications/AgentTacho.app/Contents/MacOS/AgentTacho"'
    make_stub pgrep "
case \"\$*\" in
    *NotificationCenter*) echo 500 ;;
    *'AgentTacho Demo.app'*) echo 600 ;;
    *'AgentTacho.app'*) [ \"\${REAL_RUNNING:-0}\" = 1 ] && [ ! -e \"$TEST_TMP/real-quit\" ] && echo 400 || exit 1 ;;
    *) exit 1 ;;
esac"
    # The demo app as `open` starts it: it logs its launch lines and, for a
    # capture launch (-demoRenderBar), plays the scenario, posts the alert
    # and writes the two bar images.
    make_stub open "
echo \"open \$*\" >>\"$CALL_LOG\"
case \"\$*\" in
    *'AgentTacho Demo.app'*)
        echo running >\"$TEST_TMP/demo-running\"
        # A launch starts with every Details section collapsed.
        echo 0 >\"$TEST_TMP/details-presses\"
        dir=''
        previous=''
        for arg in \"\$@\"; do
            [ \"\$previous\" = -demoRenderBar ] && dir=\"\$arg\"
            previous=\"\$arg\"
        done
        if [ -n \"\$dir\" ] && [ \"\${INTERRUPT_DARK:-0}\" = 1 ] && [ \"\$(cat \"$TEST_TMP/dark\")\" = true ]; then
            kill -INT \$PPID
            exit 0
        fi
        {
            echo '2026-10-18T06:00:01Z [app] demo build, scenario default'
            if [ \"\${NO_AUTHORIZATION:-0}\" != 1 ]; then
                echo '2026-10-18T06:00:01Z [notifications] authorization granted'
                echo \"2026-10-18T06:00:01Z [notifications] alert style \${ALERT_STYLE:-banner}\"
            fi
            if [ -n \"\$dir\" ] && [ \"\${NO_LAST_FRAME:-0}\" != 1 ]; then
                echo '2026-10-18T06:00:14Z [notifications] sent: Company budget (grp-company) monthly crossed 80% at 86%'
                echo '2026-10-18T06:00:14Z [app] demo: last frame applied'
                echo '2026-10-18T06:00:14Z [app] demo: bar rendered'
            fi
        } >>\"$DEMO_LOG\"
        if [ -n \"\$dir\" ]; then
            [ \"\${NO_BANNER:-0}\" = 1 ] || touch \"$TEST_TMP/banner\"
            mkdir -p \"\$dir\"
            echo png >\"\$dir/menubar-light.png\"
            echo png >\"\$dir/menubar-dark.png\"
        fi ;;
esac"
}

run_capture() {
    CAPTURE_ROOT="$TEST_TMP/root" UIHELPER=uihelper bash "$CAPTURE_SH" "$@" </dev/null
}

# assert_untouched: no appearance change and no quit or launch of any app.
assert_untouched() {
    local log
    log="$(cat "$CALL_LOG")"
    assert_not_contains "$log" "set dark mode"
    assert_not_contains "$log" "uihelper quit"
    assert_not_contains "$log" "open "
    assert_eq false "$(cat "$TEST_TMP/dark")"
}

# assert_restored [expected-dark]: the appearance is back (default light)
# and the demo app is gone.
assert_restored() {
    assert_eq "${1:-false}" "$(cat "$TEST_TMP/dark")" "appearance not restored"
    assert_eq "" "$(cat "$TEST_TMP/demo-running")" "demo app still running"
}

# seed_target: a target folder holding one image of an earlier run.
seed_target() {
    mkdir -p "$TEST_TMP/out"
    echo old >"$TEST_TMP/out/dropdown-light.webp"
}

assert_target_unchanged() {
    assert_eq "dropdown-light.webp" "$(ls "$TEST_TMP/out")"
    assert_eq old "$(cat "$TEST_TMP/out/dropdown-light.webp")"
}

test_screenshots_without_argument_exits_2() {
    capture_stubs
    assert_status 2 run_capture
    assert_contains "$(cat "$LAST_ERR")" "usage: capture.sh [--first-run] <target-dir>"
    assert_status 2 run_capture --first-run
    assert_status 2 run_capture a b
}

test_screenshots_missing_tool_stops_before_any_change() {
    capture_stubs
    local tool
    for tool in cwebp dwebp webpmux magick screencapture; do
        mv "$STUB_DIR/$tool" "$STUB_DIR/$tool.off"
        PATH="$STUB_DIR:/usr/bin:/bin" assert_status 1 run_capture "$TEST_TMP/out"
        assert_contains "$(cat "$LAST_ERR")" "missing tool: $tool"
        mv "$STUB_DIR/$tool.off" "$STUB_DIR/$tool"
    done
    assert_untouched
}

test_screenshots_missing_permission_stops_before_any_change() {
    capture_stubs
    PERM_AX=false assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "Accessibility"
    assert_contains "$(cat "$LAST_ERR")" "Privacy & Security"
    PERM_SR=false assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "Screen Recording"
    PERM_AE=denied assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "Automation"
    assert_untouched
}

test_screenshots_requires_a_2x_display() {
    capture_stubs
    SCALE=1 assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "2x"
    assert_untouched
}

test_screenshots_requires_notification_permission() {
    capture_stubs
    printf '2026-10-18T06:00:00Z [notifications] authorization denied\n' >"$DEMO_LOG"
    assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "notification permission for AgentTacho Demo"
    assert_contains "$(cat "$LAST_ERR")" "--first-run"
    rm "$DEMO_LOG"
    assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "--first-run"
    assert_untouched
}

test_screenshots_writes_the_22_files_and_restores_the_appearance() {
    capture_stubs
    mkdir -p "$TEST_TMP/out"
    assert_status 0 run_capture "$TEST_TMP/out"
    local expected actual stem
    expected="$(for stem in $STEMS; do echo "$stem-dark.webp"; echo "$stem-light.webp"; done | sort)"
    actual="$(ls "$TEST_TMP/out" | sort)"
    assert_eq "$expected" "$actual"
    assert_contains "$(cat "$LAST_OUT")" "dropdown-light.webp 640x480"
    assert_contains "$(cat "$CALL_LOG")" "make app-demo"
    # The details crop never shows member tables a walkthrough left open:
    # the argument domain overrides the stored "Show accounts" choice
    # (spec 026 FR-018, research R8).
    assert_contains "$(cat "$CALL_LOG")" "-AppleLanguages (en) -AppleLocale en_US -demoScenario default -showsMemberTables NO -demoRenderBar"
    assert_contains "$(cat "$CALL_LOG")" "osascript -e tell application \"System Events\" to tell appearance preferences to set dark mode to true"
    # The alert is the demo's own banner; no screen region is ever captured.
    # The pace shot is Claude's 7-day row cut from the dropdown image like
    # the budget row, without a hover; the small window above the normal
    # layer (id 13, a tooltip) is never captured (spec 025 FR-035).
    assert_contains "$(cat "$CALL_LOG")" "uihelper hastext 500 Company budget reached"
    assert_not_contains "$(cat "$CALL_LOG")" "screencapture -x -R"
    assert_contains "$(cat "$CALL_LOG")" "uihelper frame 600 agenttacho.paceRow"
    assert_contains "$(grep "/png/pace-light.png" "$CALL_LOG" | head -1)" "/raw/light/dropdown.png -crop 704x168+8+28 +repage"
    assert_not_contains "$(cat "$CALL_LOG")" "uihelper hover"
    assert_not_contains "$(cat "$CALL_LOG")" "screencapture -x -o -l 13"
    assert_not_contains "$(cat "$CALL_LOG")" "-composite"
    # The prices shot is the Settings window (id 12), not the sheet (id 15)
    # listed before it.
    assert_contains "$(cat "$CALL_LOG")" "/png/prices-light.png"
    # Settings opens through the dropdown's Settings button; the gear menu
    # is gone (spec 025 FR-028, FR-035).
    assert_contains "$(cat "$CALL_LOG")" "uihelper press 600 agenttacho.settingsButton"
    assert_not_contains "$(cat "$CALL_LOG")" "appMenu"
    assert_contains "$(grep "prices-light.png" "$CALL_LOG" | head -1)" "screencapture -x -o -l 12 "
    assert_restored
}

test_screenshots_scrolls_the_details_into_view_before_each_crop() {
    capture_stubs
    mkdir -p "$TEST_TMP/out"
    assert_status 0 run_capture "$TEST_TMP/out"
    # The pinned footer (spec 026 FR-010) leaves the expanded Details partly
    # below the scrolling sections; each details and harnesses capture first
    # scrolls the container fully into view (spec 026 FR-018).
    local scroll details
    scroll="$(grep -n "uihelper scrollto 600 agenttacho.details" "$CALL_LOG" | head -1 | cut -d: -f1)"
    details="$(grep -n "raw/light/details.png" "$CALL_LOG" | head -1 | cut -d: -f1)"
    assert_eq 1 "$([ -n "$scroll" ] && [ -n "$details" ] && [ "$scroll" -lt "$details" ] && echo 1 || echo 0)"
    assert_eq 4 "$(grep -c "uihelper scrollto 600 agenttacho.details" "$CALL_LOG")"
}

test_screenshots_restores_a_dark_appearance() {
    INITIAL_DARK=1 capture_stubs
    assert_status 0 run_capture "$TEST_TMP/out"
    assert_restored true
    : >"$CALL_LOG"
    INITIAL_DARK=1 STATUSITEM_MISSING=1 assert_status 1 run_capture "$TEST_TMP/out2"
    assert_restored true
    INITIAL_DARK=1 INTERRUPT_DARK=1 assert_status 130 run_capture "$TEST_TMP/out3"
    assert_restored true
}

test_screenshots_relative_target_is_taken_from_the_caller() {
    capture_stubs
    assert_status 0 run_capture rel/out
    assert_eq 22 "$(ls "$TEST_TMP/rel/out" | wc -l | tr -d ' ')"
    [ ! -e "$TEST_TMP/root/rel" ] || fail "images written below the repository"
}

test_screenshots_waits_for_the_last_frame_of_each_launch() {
    capture_stubs
    seed_target
    # A line from an earlier launch must not count.
    echo '2026-10-18T05:00:00Z [app] demo: last frame applied' >>"$DEMO_LOG"
    NO_LAST_FRAME=1 assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "did not apply its last frame"
    assert_contains "$(cat "$LAST_ERR")" "not captured: menubar-light"
    assert_not_contains "$(cat "$CALL_LOG")" "screencapture"
    assert_target_unchanged
    assert_restored
}

test_screenshots_invalid_webp_keeps_the_target() {
    capture_stubs
    seed_target
    DWEBP_FAIL_ON=pace-dark assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "could not capture: pace-dark"
    assert_target_unchanged
    assert_restored
}

test_screenshots_requires_banners() {
    capture_stubs
    ALERT_STYLE=alert REAL_RUNNING=1 assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "Banners style (now: alert)"
    local log
    log="$(cat "$CALL_LOG")"
    assert_not_contains "$log" "set dark mode"
    assert_not_contains "$log" "uihelper quit dev.rhuss.agenttacho
"
    assert_not_contains "$log" "-demoRenderBar"
    assert_eq "" "$(cat "$TEST_TMP/demo-running")"
}

test_screenshots_refuses_auto_appearance() {
    capture_stubs
    AUTO_APPEARANCE=1 assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "Appearance is set to Auto"
    assert_untouched
}

test_screenshots_foreign_banner_fails_the_alert() {
    capture_stubs
    FOREIGN_BANNER=1 assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "could not capture alert (light): the banner on screen is not \"Company budget reached ...\""
    assert_restored
}


test_screenshots_creates_a_missing_target() {
    capture_stubs
    assert_status 0 run_capture "$TEST_TMP/new/dir"
    assert_eq 22 "$(ls "$TEST_TMP/new/dir" | wc -l | tr -d ' ')"
}

test_screenshots_failure_in_the_dark_pass_keeps_the_target() {
    capture_stubs
    seed_target
    CAPTURE_FAIL_DARK=1 REAL_RUNNING=1 assert_status 1 run_capture "$TEST_TMP/out"
    assert_target_unchanged
    assert_contains "$(cat "$CALL_LOG")" "open /Applications/AgentTacho.app"
    assert_contains "$(cat "$LAST_ERR")" "could not capture"
    assert_contains "$(cat "$LAST_ERR")" "not captured: menubar-dark"
    assert_contains "$(cat "$LAST_ERR")" "alert-dark"
    assert_contains "$(cat "$LAST_ERR")" "dropdown-dark"
    assert_not_contains "$(cat "$LAST_ERR")" "dropdown-light"
    assert_restored
}

test_screenshots_interrupt_cleans_up() {
    capture_stubs
    seed_target
    INTERRUPT_DARK=1 REAL_RUNNING=1 assert_status 130 run_capture "$TEST_TMP/out"
    assert_target_unchanged
    assert_contains "$(cat "$CALL_LOG")" "open /Applications/AgentTacho.app"
    assert_restored
}

test_screenshots_restarts_agenttacho_only_if_it_ran() {
    capture_stubs
    assert_status 0 run_capture "$TEST_TMP/out"
    assert_not_contains "$(cat "$CALL_LOG")" "open /Applications/AgentTacho.app"
    : >"$CALL_LOG"
    REAL_RUNNING=1 assert_status 0 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$CALL_LOG")" "uihelper quit dev.rhuss.agenttacho"
    # The copy that ran starts again.
    assert_contains "$(cat "$CALL_LOG")" "open /Applications/AgentTacho.app"
}

test_screenshots_stops_when_agenttacho_does_not_quit() {
    capture_stubs
    REAL_RUNNING=1 REAL_QUIT_FAIL=1 assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "AgentTacho did not quit"
    local log
    log="$(cat "$CALL_LOG")"
    assert_not_contains "$log" "set dark mode"
    assert_not_contains "$log" "-demoRenderBar"
    assert_not_contains "$log" "open /Applications/AgentTacho.app"
}

test_screenshots_first_run_only_asks_for_permission() {
    capture_stubs
    rm "$DEMO_LOG"
    assert_status 0 run_capture --first-run "$TEST_TMP/out"
    local log
    log="$(cat "$CALL_LOG")"
    assert_contains "$log" "open -n"
    assert_not_contains "$log" "screencapture"
    assert_not_contains "$log" "set dark mode"
    assert_contains "$(cat "$LAST_OUT")" "authorization granted"
    assert_contains "$(cat "$LAST_OUT")" "notification style: Banners"
    assert_eq "" "$(cat "$TEST_TMP/demo-running")"
}

test_screenshots_first_run_fails_without_an_answer() {
    capture_stubs
    rm "$DEMO_LOG"
    NO_AUTHORIZATION=1 assert_status 1 run_capture --first-run "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "notification"
}

test_screenshots_quits_an_earlier_demo_first() {
    capture_stubs
    DEMO_RUNNING=1 assert_status 0 run_capture "$TEST_TMP/out"
    local quit_line open_line
    quit_line="$(grep -n "uihelper quit dev.rhuss.agenttacho.demo --force" "$CALL_LOG" | head -1 | cut -d: -f1)"
    open_line="$(grep -n "open -n" "$CALL_LOG" | head -1 | cut -d: -f1)"
    [ -n "$quit_line" ] && [ "$quit_line" -lt "$open_line" ] || fail "the earlier demo app was not quit before the launch"
}

test_screenshots_missing_status_item_fails_the_pass() {
    capture_stubs
    STATUSITEM_MISSING=1 assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "menubar item not found"
    assert_restored
}

test_screenshots_missing_banner_names_the_alert_shot() {
    capture_stubs
    seed_target
    NO_BANNER=1 assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "could not capture alert (light): the notification banner did not appear"
    assert_contains "$(cat "$LAST_ERR")" "not captured:"
    assert_target_unchanged
    assert_restored
}

test_screenshots_failing_appearance_switch_restores() {
    capture_stubs
    APPEARANCE_FAIL_ON=true assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "appearance"
    assert_restored
    [ ! -e "$TEST_TMP/out" ] || [ -z "$(ls "$TEST_TMP/out")" ] || fail "files written after a failed run"
}

# line_of <pattern>: the first line number of the call log that contains
# <pattern>, empty when none does.
line_of() {
    grep -n -F -- "$1" "$CALL_LOG" | head -1 | cut -d: -f1
}

# assert_before <first> <second>: both patterns are in the call log, the
# first one earlier.
assert_before() {
    local a b
    a="$(line_of "$1")"
    b="$(line_of "$2")"
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] || fail "expected [$1] (line ${a:-none}) before [$2] (line ${b:-none})"
}

# The glance crop: the region plus half its smallest distance to the window
# on every side, at most 4% of its shorter side, in whole pixels at 2x
# (spec 031 FR-012, data-model.md).
test_screenshots_glance_crop_has_a_uniform_margin() {
    capture_stubs
    mkdir -p "$TEST_TMP/out"
    assert_status 0 run_capture "$TEST_TMP/out"
    # 10 points to the window on three sides: 5 points, 10 px.
    assert_contains "$(grep "/png/glance-light.png" "$CALL_LOG" | head -1)" "/raw/light/glance.png -crop 700x780+10+10 +repage"
    : >"$CALL_LOG"
    # 100 points away, capped at 4% of 150 points: 6 points, 12 px.
    FRAME_claudeSection_open="x=1000 y=150 w=150 h=180" assert_status 0 run_capture "$TEST_TMP/out"
    assert_contains "$(grep "/png/glance-light.png" "$CALL_LOG" | head -1)" "/raw/light/glance.png -crop 324x384+188+240 +repage"
}

test_screenshots_glance_fails_on_a_margin_below_4_px() {
    capture_stubs
    seed_target
    FRAME_claudeSection_open="x=901 y=34 w=340 h=380" assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$CALL_LOG")" "/png/same-provider-light.png"
    assert_not_contains "$(cat "$CALL_LOG")" "/png/glance-light.png"
    assert_contains "$(cat "$LAST_ERR")" "could not capture glance (light): margin 1 px, below 4 px"
    assert_target_unchanged
    assert_restored
}

test_screenshots_glance_fails_on_an_aspect_outside_the_range() {
    capture_stubs
    seed_target
    FRAME_claudeSection_open="x=910 y=34 w=340 h=120" assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$CALL_LOG")" "/png/same-provider-light.png"
    assert_not_contains "$(cat "$CALL_LOG")" "/png/glance-light.png"
    assert_contains "$(cat "$LAST_ERR")" "could not capture glance (light): aspect 698:258 (2.71) outside 3:4 to 4:3"
    assert_target_unchanged
    assert_restored
}

# The glance steps: expand the first Claude Max details, pick Models inside
# them, scroll the section into view, capture, crop, collapse and check the
# collapse, all before the budget's details are pressed (spec 031 FR-008,
# FR-010, FR-010b).
test_screenshots_glance_expands_captures_and_collapses() {
    capture_stubs
    mkdir -p "$TEST_TMP/out"
    assert_status 0 run_capture "$TEST_TMP/out"
    assert_before "uihelper press 600 agenttacho.claudeDetails" "uihelper press 600 Models --in agenttacho.claudeDetails"
    assert_before "uihelper press 600 Models --in agenttacho.claudeDetails" "uihelper scrollto 600 agenttacho.claudeSection"
    assert_before "uihelper scrollto 600 agenttacho.claudeSection" "/raw/light/glance.png"
    assert_contains "$(grep "/raw/light/glance.png" "$CALL_LOG" | head -1)" "screencapture -x -o -l 11 "
    assert_before "/raw/light/glance.png" "/png/glance-light.png"
    # The collapse: the second press and the frame read come after the crop.
    local crop collapse check details
    crop="$(line_of "/png/glance-light.png")"
    collapse="$(grep -n -F "uihelper press 600 agenttacho.claudeDetails" "$CALL_LOG" | sed -n 2p | cut -d: -f1)"
    check="$(grep -n -F "uihelper frame 600 agenttacho.claudeSection" "$CALL_LOG" | cut -d: -f1 |
        awk -v after="$collapse" '$1 > after { print; exit }')"
    details="$(line_of "uihelper press 600 agenttacho.details")"
    [ -n "$collapse" ] && [ "$crop" -lt "$collapse" ] || fail "the details were not collapsed after the glance crop"
    [ -n "$check" ] && [ "$check" -lt "$details" ] || fail "the collapse was not checked before the budget details"
    # Collapsed again at the end of the last pass: an even number of presses.
    assert_eq 0 "$(($(cat "$TEST_TMP/details-presses") % 2))"
}

test_screenshots_glance_fails_when_the_details_stay_open() {
    capture_stubs
    seed_target
    COLLAPSE_FAIL=1 assert_status 1 run_capture "$TEST_TMP/out"
    assert_contains "$(cat "$LAST_ERR")" "could not capture glance (light): the details did not collapse"
    # The failed shot counts as not captured, though its crop was written.
    assert_contains "$(cat "$LAST_ERR")" "not captured: "
    assert_contains "$(cat "$LAST_ERR")" " glance-light"
    assert_not_contains "$(cat "$CALL_LOG")" "uihelper press 600 agenttacho.details"
    assert_target_unchanged
    assert_restored
}
