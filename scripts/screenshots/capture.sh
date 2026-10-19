#!/bin/bash
# Captures the landing page screenshots from the demo build (spec 024 FR-017
# to FR-023, contracts/capture-cli.md).
#
# Usage: capture.sh [--first-run] <target-dir>
#
# Builds "AgentTacho Demo.app" (make app-demo), quits a running AgentTacho,
# and plays the default scenario once in light and once in dark appearance.
# Each pass captures the notification banner, the dropdown and its cards and
# three Settings tabs, and takes the menu bar item from the image the demo app
# renders itself. The 22 WebP files go into a temporary folder and are moved
# into <target-dir> only when all of them exist and are valid. The appearance,
# the demo app and AgentTacho are put back on success, failure and Ctrl-C.
#
# --first-run launches the demo app once so macOS asks for its notification
# permission, waits for the answer and stops; it captures nothing.
#
# Needs Accessibility and Screen Recording permission for the terminal,
# Automation permission for System Events, notification permission for
# AgentTacho Demo in the Banners style, Appearance set to Light or Dark (not
# Auto), a 2x main display and cwebp, dwebp, webpmux (brew install webp) and
# magick (brew install imagemagick).
#
# Exit status: 0 done, 1 preflight or capture failed, 2 usage, 130 interrupted.
#
# Environment for tests: CAPTURE_ROOT (repository, default the one holding
# this script), UIHELPER (helper to use instead of compiling
# scripts/screenshots/uihelper.swift), DEMO_LOG (the demo app's log).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The app names and bundle ids come from the release scripts' one place for
# them (spec 024 FR-001).
# shellcheck source=../release/lib.sh
. "$SCRIPT_DIR/../release/lib.sh"
DEMO=1 release_defaults
DEMO_APP="$APP"
DEMO_ID="$BUNDLE_ID"
DEMO= release_defaults
REAL_ID="$BUNDLE_ID"
REAL_APP="$(basename "$APP")"
ROOT="${CAPTURE_ROOT:-$SCRIPT_DIR/../..}"
DEMO_LOG="${DEMO_LOG:-$HOME/Library/Logs/agenttacho-demo/usage.log}"
STEMS="menubar plan-limits pace budget groups details alert prices menubar-settings harnesses dropdown"
# Seconds to wait for the demo app's last frame (FR-021), for its
# notification settings, and on the first run for the answer to the
# permission prompt.
FRAME_TIMEOUT=60
SETTINGS_TIMEOUT=30
PERMISSION_TIMEOUT=120
OPENAI_IMPORT="OpenAI prices (LiteLLM, direct and Vertex)"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'usage: capture.sh [--first-run] <target-dir>\n' >&2
    exit 2
}

first_run_mode=false
case "$#:${1:-}" in
    1:--first-run | 0:*) usage ;;
    1:*) target="$1" ;;
    2:--first-run) first_run_mode=true; target="$2" ;;
    *) usage ;;
esac
# Relative to where the script was started, not to the repository.
case "$target" in
    /*) ;;
    *) target="$PWD/$target" ;;
esac
cd "$ROOT"

# --- helpers -------------------------------------------------------------------

# value <key> <line>: the value of key=value in a helper output line.
value() {
    printf '%s\n' "$2" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -n 1
}

log_lines() {
    if [ -f "$DEMO_LOG" ]; then wc -l <"$DEMO_LOG" | tr -d ' '; else echo 0; fi
}

# new_log_line <offset> <pattern>: the last line after line <offset> of the
# demo log that contains <pattern>. A log shorter than the offset was rolled
# over by the app (2.5 MB), so it is read from the start.
new_log_line() {
    [ -f "$DEMO_LOG" ] || return 0
    local offset="$1"
    [ "$(log_lines)" -ge "$offset" ] || offset=0
    tail -n +"$((offset + 1))" "$DEMO_LOG" | grep -F -- "$2" | tail -n 1 || true
}

# wait_for_log <offset> <pattern> <seconds>: waits until the demo log has a
# matching line after <offset>; fails after <seconds>.
wait_for_log() {
    local tries=$(($3 * 2))
    while [ "$tries" -gt 0 ]; do
        [ -n "$(new_log_line "$1" "$2")" ] && return 0
        sleep 0.5
        tries=$((tries - 1))
    done
    return 1
}

# demo_log_problems <offset>: the demo app's own lines about the scenario or
# errors since <offset>, on stderr, so a timeout shows its cause.
demo_log_problems() {
    [ -f "$DEMO_LOG" ] || return 0
    tail -n +"$(($1 + 1))" "$DEMO_LOG" | grep -E 'scenario|not rendered|error' >&2 || true
}

appearance_script() {
    printf 'tell application "System Events" to tell appearance preferences to %s' "$1"
}

get_dark_mode() {
    osascript -e "$(appearance_script "get dark mode")"
}

set_dark_mode() {
    osascript -e "$(appearance_script "set dark mode to $1")" >/dev/null
}

demo_pid() {
    pgrep -f "$(basename "$DEMO_APP")/Contents/MacOS/AgentTacho" | head -n 1 || true
}

real_pid() {
    pgrep -f "/$REAL_APP/Contents/MacOS/AgentTacho" | head -n 1 || true
}

# window_line <pid> <kind>: the on-screen window of the demo app that is the
# dropdown (above the normal layer, at least 300 points wide and 80 high) or
# the Settings window (normal layer).
window_line() {
    "$UIHELPER" windows "$1" | while read -r line; do
        local layer w h
        layer="$(value layer "$line")"
        w="$(value w "$line")"
        h="$(value h "$line")"
        case "$2" in
            dropdown) awk -v l="$layer" -v w="$w" -v h="$h" 'BEGIN { exit !(l > 0 && w >= 300 && h >= 80) }' && { echo "$line"; break; } ;;
            settings) awk -v l="$layer" -v w="$w" 'BEGIN { exit !(l == 0 && w >= 500) }' && { echo "$line"; break; } ;;
        esac
    done
}

# wait_for_window <pid> <kind>: the window line, waiting up to 10 s.
wait_for_window() {
    local tries=20 line
    while [ "$tries" -gt 0 ]; do
        line="$(window_line "$@")"
        if [ -n "$line" ]; then
            printf '%s\n' "$line"
            return 0
        fi
        sleep 0.5
        tries=$((tries - 1))
    done
    return 1
}

# crop <image> <window line> <element line> <out>: the element's frame with
# 6 points of margin left and right and 2 above and below (rows sit 4 points
# apart), cut from a 2x window image.
crop() {
    local geometry
    geometry="$(awk -v wx="$(value x "$2")" -v wy="$(value y "$2")" -v ww="$(value w "$2")" -v wh="$(value h "$2")" \
                    -v x="$(value x "$3")" -v y="$(value y "$3")" -v w="$(value w "$3")" -v h="$(value h "$3")" 'BEGIN {
        m = 6; v = 2
        left = x - wx - m; top = y - wy - v; right = x - wx + w + m; bottom = y - wy + h + v
        if (left < 0) left = 0
        if (top < 0) top = 0
        if (right > ww) right = ww
        if (bottom > wh) bottom = wh
        printf "%dx%d+%d+%d", (right - left) * 2, (bottom - top) * 2, left * 2, top * 2
    }')"
    magick "$1" -crop "$geometry" +repage "$4"
}

# center <line> x|y: the center coordinate of a frame.
center() {
    if [ "$2" = x ]; then
        awk -v a="$(value x "$1")" -v b="$(value w "$1")" 'BEGIN { print a + b / 2 }'
    else
        awk -v a="$(value y "$1")" -v b="$(value h "$1")" 'BEGIN { print a + b / 2 }'
    fi
}

# -showsMemberTables NO: the details crop shows the group's tables with the
# "Show accounts" button but never member tables a walkthrough left open; the
# argument domain overrides the stored choice (spec 026 FR-018, research R8).
launch_demo() {
    open -n "$DEMO_APP" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario default -showsMemberTables NO "$@"
}

# --- preflight (FR-018): nothing changes before it passes ---------------------

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "missing tool: $1 ($2)"
}

preflight() {
    need_tool cwebp "brew install webp"
    need_tool dwebp "brew install webp"
    need_tool webpmux "brew install webp"
    need_tool magick "brew install imagemagick"
    need_tool osascript "part of macOS"
    need_tool screencapture "part of macOS"
    if [ -z "${UIHELPER:-}" ]; then
        need_tool swiftc "xcode-select --install"
        UIHELPER="build/screenshots/uihelper"
        if [ ! -x "$UIHELPER" ] || [ "$SCRIPT_DIR/uihelper.swift" -nt "$UIHELPER" ]; then
            mkdir -p build/screenshots
            # The SDK the Makefile builds with, when it is installed.
            local sdk
            sdk="$(xcode-select -p)/SDKs/MacOSX26.sdk"
            if [ -z "${SDKROOT:-}" ] && [ -d "$sdk" ]; then export SDKROOT="$sdk"; fi
            swiftc -O -o "$UIHELPER" "$SCRIPT_DIR/uihelper.swift" || die "could not compile scripts/screenshots/uihelper.swift"
        fi
    fi

    local perms
    perms="$("$UIHELPER" perms)" || die "uihelper perms failed"
    [ "$(value accessibility "$perms")" = true ] ||
        die "Accessibility permission missing for this terminal: System Settings > Privacy & Security > Accessibility"
    [ "$(value screenRecording "$perms")" = true ] ||
        die "Screen Recording permission missing for this terminal: System Settings > Privacy & Security > Screen & System Audio Recording"
    case "$(value automation "$perms")" in
        granted) ;;
        denied) die "Automation permission for System Events missing: System Settings > Privacy & Security > Automation > this terminal > System Events" ;;
        *)
            # Not asked yet: a read asks once and changes nothing.
            get_dark_mode >/dev/null 2>&1 ||
                die "Automation permission for System Events missing: System Settings > Privacy & Security > Automation > this terminal > System Events"
            ;;
    esac
    [ "$(value scale "$("$UIHELPER" display)")" = 2 ] ||
        die "the main display is not a 2x (Retina) display; the screenshots need 2x"
    # Switching the appearance turns Auto off, and setting it back cannot turn
    # it on again (SC-004).
    [ "$(defaults read -g AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || true)" != 1 ] ||
        die "Appearance is set to Auto: set it to Light or Dark in System Settings > Appearance for the capture"

    if [ "$first_run_mode" = false ]; then
        local answer
        answer="$(new_log_line 0 "[notifications] authorization")"
        case "$answer" in
            *"authorization granted"*) ;;
            "") die "notification permission for AgentTacho Demo not asked yet: run capture.sh --first-run <target-dir> once and allow it" ;;
            *) die "notification permission for AgentTacho Demo missing: allow it in System Settings > Notifications > AgentTacho Demo (alert style Banners), or run capture.sh --first-run <target-dir>" ;;
        esac
    fi
}

# check_notifications: launches the demo app briefly and reads the
# notification settings it logs, so a style other than Banners, or
# notifications turned off since the first run, stop the run before the
# appearance or AgentTacho change (FR-018). Quits the demo app again.
check_notifications() {
    "$UIHELPER" quit "$DEMO_ID" --force >/dev/null || die "an earlier AgentTacho Demo did not quit"
    local offset style
    offset="$(log_lines)"
    # The demo app goes again on any exit, Ctrl-C included.
    trap '"$UIHELPER" quit "$DEMO_ID" --force >/dev/null 2>&1 || true' EXIT
    trap 'exit 130' INT TERM
    launch_demo
    if ! wait_for_log "$offset" "[notifications] alert style" "$SETTINGS_TIMEOUT"; then
        "$UIHELPER" quit "$DEMO_ID" --force >/dev/null || true
        demo_log_problems "$offset"
        die "AgentTacho Demo did not report its notification settings within $SETTINGS_TIMEOUT s; run capture.sh --first-run <target-dir> and allow notifications"
    fi
    style="$(new_log_line "$offset" "[notifications] alert style")"
    "$UIHELPER" quit "$DEMO_ID" --force >/dev/null || die "AgentTacho Demo did not quit after the notification check"
    trap - EXIT INT TERM
    case "$style" in
        *"alert style banner") ;;
        *) die "notifications for AgentTacho Demo must use the Banners style (now: ${style##*alert style }): System Settings > Notifications > AgentTacho Demo" ;;
    esac
}

# --- cleanup (FR-021, SC-004) ------------------------------------------------

tmp=""
staging=""
original_dark=""
real_quit=false
real_path=""

# Runs once, with Ctrl-C ignored so a second press cannot cut it short. The
# appearance comes first: it matters most and is quick.
cleanup() {
    local status=$?
    trap - EXIT
    trap '' INT TERM
    if [ -n "$original_dark" ] && [ "$(get_dark_mode 2>/dev/null || true)" != "$original_dark" ]; then
        set_dark_mode "$original_dark" || printf 'error: could not restore the appearance (dark mode %s)\n' "$original_dark" >&2
    fi
    "$UIHELPER" quit "$DEMO_ID" --force >/dev/null 2>&1 || true
    if [ "$real_quit" = true ] && [ -z "$(real_pid)" ]; then
        if [ -n "$real_path" ]; then
            open "$real_path" || printf 'error: could not start %s again\n' "$real_path" >&2
        else
            open -b "$REAL_ID" || printf 'error: could not start AgentTacho again\n' >&2
        fi
    fi
    [ -z "$tmp" ] || rm -rf "$tmp"
    [ -z "$staging" ] || rm -rf "$staging"
    exit "$status"
}

# --- first run (contracts/capture-cli.md step 2) --------------------------------

first_run() {
    make app-demo
    trap cleanup EXIT
    trap 'exit 130' INT TERM
    "$UIHELPER" quit "$DEMO_ID" --force >/dev/null || die "an earlier AgentTacho Demo did not quit"
    local offset answer style
    offset="$(log_lines)"
    launch_demo
    echo "Waiting for the answer to the notification prompt of AgentTacho Demo..."
    wait_for_log "$offset" "[notifications] authorization" "$PERMISSION_TIMEOUT" ||
        die "no answer to the notification prompt within $PERMISSION_TIMEOUT s"
    answer="$(new_log_line "$offset" "[notifications] authorization")"
    case "$answer" in
        *"authorization granted"*) echo "notification permission: authorization granted" ;;
        *) die "notification permission for AgentTacho Demo was not granted: ${answer#*] }; allow it in System Settings > Notifications > AgentTacho Demo" ;;
    esac
    wait_for_log "$offset" "[notifications] alert style" 10 || die "AgentTacho Demo did not report its notification style"
    style="$(new_log_line "$offset" "[notifications] alert style")"
    case "$style" in
        *"alert style banner") echo "notification style: Banners" ;;
        *) die "set the notification style of AgentTacho Demo to Banners: System Settings > Notifications > AgentTacho Demo" ;;
    esac
}

# --- one pass (FR-021) ---------------------------------------------------------

# not_captured: every stem and appearance without an image yet (FR-022).
not_captured() {
    local stem appearance list=""
    for stem in $STEMS; do
        for appearance in light dark; do
            [ -f "$tmp/png/$stem-$appearance.png" ] || list="$list $stem-$appearance"
        done
    done
    printf '%s' "${list# }"
}

# shot_failed <stem> <appearance> <reason>: names the failing shot and every
# shot the run did not capture (FR-022).
shot_failed() {
    die "could not capture $1 ($2): $3; not captured: $(not_captured)"
}

# largest_window <pid> <layer>: the demo app's largest on-screen window at
# that layer.
largest_window() {
    "$UIHELPER" windows "$1" | awk -v layer="layer=$2" '
        $2 == layer {
            w = $5; h = $6; sub("w=", "", w); sub("h=", "", h)
            if (w * h > best) { best = w * h; line = $0 }
        }
        END { if (line != "") print line }'
}

capture_pass() {
    local appearance="$1" raw="$tmp/raw/$1" png="$tmp/png" offset pid out line nc sent title dropdown
    mkdir -p "$raw" "$png"
    "$UIHELPER" quit "$DEMO_ID" --force >/dev/null || die "an earlier AgentTacho Demo did not quit; not captured: $(not_captured)"
    offset="$(log_lines)"
    launch_demo -demoRenderBar "$tmp/bar-$appearance"
    if ! wait_for_log "$offset" "demo: last frame applied" "$FRAME_TIMEOUT"; then
        demo_log_problems "$offset"
        die "the demo app did not apply its last frame within $FRAME_TIMEOUT s ($appearance); not captured: $(not_captured)"
    fi
    pid="$(demo_pid)"
    [ -n "$pid" ] || die "the demo app is not running ($appearance); not captured: $(not_captured)"

    # alert: the banner of this launch's crossing, owned by Notification
    # Center. Only a banner that shows the crossing's title counts.
    wait_for_log "$offset" "[notifications] sent:" 10 || shot_failed alert "$appearance" "the demo app sent no notification"
    sent="$(new_log_line "$offset" "[notifications] sent:")"
    title="$(printf '%s' "${sent#*sent: }" | sed 's/ (.*//') reached"
    nc="$(pgrep -x NotificationCenter | head -n 1 || true)"
    [ -n "$nc" ] || shot_failed alert "$appearance" "Notification Center is not running"
    line=""
    local tries=20
    while [ "$tries" -gt 0 ]; do
        line="$("$UIHELPER" windows "$nc" | head -n 1)"
        [ -n "$line" ] && break
        sleep 0.5
        tries=$((tries - 1))
    done
    [ -n "$line" ] || shot_failed alert "$appearance" "the notification banner did not appear; check Focus and the notification style of AgentTacho Demo"
    "$UIHELPER" hastext "$nc" "$title" >/dev/null 2>&1 ||
        shot_failed alert "$appearance" "the banner on screen is not \"$title ...\""
    screencapture -x -o -l "$(value id "$line")" "$raw/alert.png" || shot_failed alert "$appearance" "screencapture failed"
    magick "$raw/alert.png" -trim +repage "$png/alert-$appearance.png" || shot_failed alert "$appearance" "trim failed"

    # menubar: drawn by the demo app (FR-019).
    if ! wait_for_log "$offset" "demo: bar rendered" 10; then
        demo_log_problems "$offset"
        shot_failed menubar "$appearance" "the demo app did not render the bar"
    fi
    cp "$tmp/bar-$appearance/menubar-$appearance.png" "$png/menubar-$appearance.png" ||
        shot_failed menubar "$appearance" "no rendered bar image"

    # dropdown and its cards.
    out="$("$UIHELPER" statusitem "$pid" 2>&1)" || shot_failed dropdown "$appearance" "$out"
    "$UIHELPER" click "$(center "$out" x)" "$(center "$out" y)" >/dev/null || shot_failed dropdown "$appearance" "click failed"
    dropdown="$(wait_for_window "$pid" dropdown)" || shot_failed dropdown "$appearance" "the dropdown did not open"
    screencapture -x -o -l "$(value id "$dropdown")" "$raw/dropdown.png" || shot_failed dropdown "$appearance" "screencapture failed"
    cp "$raw/dropdown.png" "$png/dropdown-$appearance.png"
    local plan
    plan="$("$UIHELPER" frame "$pid" agenttacho.claudePlan 2>&1)" || shot_failed plan-limits "$appearance" "$plan"
    crop "$raw/dropdown.png" "$dropdown" "$plan" "$png/plan-limits-$appearance.png" || shot_failed plan-limits "$appearance" "crop failed"
    out="$("$UIHELPER" frame "$pid" agenttacho.budgetRow 2>&1)" || shot_failed budget "$appearance" "$out"
    crop "$raw/dropdown.png" "$dropdown" "$out" "$png/budget-$appearance.png" || shot_failed budget "$appearance" "crop failed"

    # pace: Claude's 7-day row with its bar, tick and orange note, cut from
    # the dropdown like the budget row; the pace shows without a hover
    # (spec 024 FR-019, spec 025 FR-005, FR-035).
    out="$("$UIHELPER" frame "$pid" agenttacho.paceRow 2>&1)" || shot_failed pace "$appearance" "$out"
    crop "$raw/dropdown.png" "$dropdown" "$out" "$png/pace-$appearance.png" || shot_failed pace "$appearance" "crop failed"

    # details and harnesses: the shot budget's breakdown, expanded. The
    # pinned footer leaves the expanded Details partly below the scrolling
    # sections, so each capture first scrolls the container fully into view
    # (spec 026 FR-010, FR-018).
    "$UIHELPER" press "$pid" agenttacho.details >/dev/null || shot_failed details "$appearance" "Details did not open"
    "$UIHELPER" press "$pid" Models >/dev/null || shot_failed details "$appearance" "no Models view"
    sleep 0.5
    out="$("$UIHELPER" scrollto "$pid" agenttacho.details 2>&1)" || shot_failed details "$appearance" "$out"
    dropdown="$(wait_for_window "$pid" dropdown)" || shot_failed details "$appearance" "the dropdown closed"
    screencapture -x -o -l "$(value id "$dropdown")" "$raw/details.png" || shot_failed details "$appearance" "screencapture failed"
    out="$("$UIHELPER" frame "$pid" agenttacho.details 2>&1)" || shot_failed details "$appearance" "$out"
    crop "$raw/details.png" "$dropdown" "$out" "$png/details-$appearance.png" || shot_failed details "$appearance" "crop failed"
    "$UIHELPER" press "$pid" Harnesses >/dev/null || shot_failed harnesses "$appearance" "no Harnesses view"
    sleep 0.5
    out="$("$UIHELPER" scrollto "$pid" agenttacho.details 2>&1)" || shot_failed harnesses "$appearance" "$out"
    dropdown="$(wait_for_window "$pid" dropdown)" || shot_failed harnesses "$appearance" "the dropdown closed"
    screencapture -x -o -l "$(value id "$dropdown")" "$raw/harnesses.png" || shot_failed harnesses "$appearance" "screencapture failed"
    out="$("$UIHELPER" frame "$pid" agenttacho.details 2>&1)" || shot_failed harnesses "$appearance" "$out"
    crop "$raw/harnesses.png" "$dropdown" "$out" "$png/harnesses-$appearance.png" || shot_failed harnesses "$appearance" "crop failed"
    "$UIHELPER" press "$pid" Models >/dev/null || true

    # Settings tabs, opened with the dropdown's Settings button (spec 025
    # FR-027, FR-035).
    "$UIHELPER" press "$pid" agenttacho.settingsButton >/dev/null || shot_failed groups "$appearance" "no Settings button in the dropdown"
    local settings
    settings="$(wait_for_window "$pid" settings)" || shot_failed groups "$appearance" "Settings did not open"
    settings_tab "$pid" Groups groups "$appearance" "$png"
    settings_tab "$pid" "Menu Bar" menubar-settings "$appearance" "$png"
    "$UIHELPER" press "$pid" Prices >/dev/null || shot_failed prices "$appearance" "no Prices tab"
    "$UIHELPER" press "$pid" Import >/dev/null || shot_failed prices "$appearance" "no Import menu"
    sleep 1
    "$UIHELPER" press "$pid" "$OPENAI_IMPORT" >/dev/null || shot_failed prices "$appearance" "no OpenAI import"
    sleep 1.5
    settings="$(wait_for_window "$pid" settings)" || shot_failed prices "$appearance" "Settings closed"
    # The Settings window: its capture includes the attached import sheet,
    # which is also listed as a window of its own (and may come first).
    settings="$(largest_window "$pid" 0)"
    [ -n "$settings" ] || shot_failed prices "$appearance" "Settings closed"
    screencapture -x -o -l "$(value id "$settings")" "$png/prices-$appearance.png" || shot_failed prices "$appearance" "screencapture failed"
    # An open sheet holds up quitting.
    "$UIHELPER" press "$pid" Cancel >/dev/null || true

    "$UIHELPER" quit "$DEMO_ID" --force >/dev/null || die "AgentTacho Demo did not quit ($appearance); not captured: $(not_captured)"
}

# settings_tab <pid> <tab title> <stem> <appearance> <png>
settings_tab() {
    "$UIHELPER" press "$1" "$2" >/dev/null || shot_failed "$3" "$4" "no $2 tab"
    sleep 1
    local window
    window="$(wait_for_window "$1" settings)" || shot_failed "$3" "$4" "Settings closed"
    screencapture -x -o -l "$(value id "$window")" "$5/$3-$4.png" || shot_failed "$3" "$4" "screencapture failed"
}

# --- convert and move (FR-022, FR-023) -----------------------------------------

finish() {
    local webp="$tmp/webp" missing="" stem appearance name
    mkdir -p "$webp"
    for stem in $STEMS; do
        for appearance in light dark; do
            name="$stem-$appearance"
            if [ -f "$tmp/png/$name.png" ] && cwebp -quiet -lossless "$tmp/png/$name.png" -o "$webp/$name.webp" >/dev/null 2>&1 &&
                dwebp "$webp/$name.webp" -o /dev/null >/dev/null 2>&1; then
                continue
            fi
            missing="$missing $name"
        done
    done
    [ -z "$missing" ] || die "could not capture:$missing"
    # Copied next to the target first, so the move into it is a rename on the
    # same volume; Ctrl-C cannot stop it half way.
    mkdir -p "$target" || die "could not create $target"
    staging="$target/.capture-staging.$$"
    mkdir "$staging"
    cp "$webp"/*.webp "$staging/" || die "could not copy the images into $target"
    trap '' INT TERM
    for name in "$staging"/*.webp; do
        mv -f "$name" "$target/"
    done
    rmdir "$staging"
    staging=""
    trap 'exit 130' INT TERM
    for stem in $STEMS; do
        for appearance in light dark; do
            name="$stem-$appearance.webp"
            printf '%s %s\n' "$name" "$(webpmux -info "$target/$name" | sed -n 's/^Canvas size: \([0-9]*\) x \([0-9]*\).*/\1x\2/p')"
        done
    done
}

# --- main ------------------------------------------------------------------------

preflight
if [ "$first_run_mode" = true ]; then
    first_run
    exit 0
fi

make app-demo
check_notifications
original_dark="$(get_dark_mode)" || die "could not read the appearance"
pid="$(real_pid)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/agenttacho-shots.XXXXXX")"
trap cleanup EXIT
trap 'exit 130' INT TERM
if [ -n "$pid" ]; then
    # The copy that runs is the copy that starts again (FR-020).
    real_path="$(ps -o comm= -p "$pid" 2>/dev/null | sed -n 's|\(.*\.app\)/Contents/MacOS/.*|\1|p' || true)"
    real_quit=true
    "$UIHELPER" quit "$REAL_ID" >/dev/null 2>&1 || die "AgentTacho did not quit within 10 s (is a dialog open?); nothing was changed"
fi
for appearance in light dark; do
    dark=false
    [ "$appearance" = light ] || dark=true
    set_dark_mode "$dark" || die "could not switch the appearance to $appearance"
    capture_pass "$appearance"
done
finish
