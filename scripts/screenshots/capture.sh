#!/bin/bash
# Captures the landing page screenshots from the demo build (spec 024 FR-017
# to FR-023, contracts/capture-cli.md; spec 031, contracts/capture-stems.md).
#
# Usage: capture.sh <target-dir>
#
# Builds "AgentTacho Demo.app" (make app-demo), quits a running AgentTacho,
# and plays the default scenario once in light and once in dark appearance.
# Each pass captures the dropdown's crops in the order same-provider, glance,
# budget, harnesses (spec 031 FR-010b), two strips from Settings (FR-011a),
# and takes the menu bar item from the image the demo app renders itself. The 14 WebP files go
# into a temporary folder and are moved into <target-dir> only when all of
# them exist and are valid; no other file there is touched (spec 031
# FR-016). The appearance, the demo app and AgentTacho are put back on
# success, failure and Ctrl-C.
#
# Needs Accessibility and Screen Recording permission for the terminal,
# Automation permission for System Events, Appearance set to Light or Dark
# (not Auto), a 2x main display and cwebp, dwebp, webpmux (brew install
# webp) and magick (brew install imagemagick). No shot shows a notification,
# so the demo app needs no notification permission (spec 031 FR-014).
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
# The stems the site uses (spec 031 FR-011).
STEMS="menubar budget harnesses prices menubar-settings glance same-provider"
# Seconds to wait for the demo app's last frame (FR-021).
FRAME_TIMEOUT=60
OPENAI_IMPORT="OpenAI prices (LiteLLM, direct and Vertex)"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'usage: capture.sh <target-dir>\n' >&2
    exit 2
}

# One target; an option such as the former --first-run is a usage error
# (spec 031 FR-014).
case "$#:${1:-}" in
    1:-*) usage ;;
    1:*) target="$1" ;;
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

# crop_geometry <window line> <element line> <margin x> <margin y>: the
# element's frame with the margins added and clamped to the window, as a 2x
# pixel geometry WxH+X+Y relative to the window.
crop_geometry() {
    LC_ALL=C awk -v wx="$(value x "$1")" -v wy="$(value y "$1")" -v ww="$(value w "$1")" -v wh="$(value h "$1")" \
        -v x="$(value x "$2")" -v y="$(value y "$2")" -v w="$(value w "$2")" -v h="$(value h "$2")" \
        -v m="$3" -v v="$4" 'BEGIN {
        left = x - wx - m; top = y - wy - v; right = x - wx + w + m; bottom = y - wy + h + v
        if (left < 0) left = 0
        if (top < 0) top = 0
        if (right > ww) right = ww
        if (bottom > wh) bottom = wh
        printf "%dx%d+%d+%d", (right - left) * 2, (bottom - top) * 2, left * 2, top * 2
    }'
}

# crop <image> <window line> <element line> <out> [<margin x> <margin y>]:
# the element's frame cut from a 2x window image, by default with 6 points of
# margin left and right and 2 above and below (rows sit 4 points apart). The
# Settings strips pass their own margins (spec 031 FR-011a).
crop() {
    magick "$1" -crop "$(crop_geometry "$2" "$3" "${5:-6}" "${6:-2}")" +repage "$4"
}

# strip <stem> <appearance> <image> <window line> <content frame> <out>: a
# Settings shot cut to its content frame with 8 points of margin on every
# side, clamped to the window (spec 031 FR-011a, from spec 029 FR-008). The
# landing page shows each shot in a 327 by 122 pixel box, so a strip larger
# than 727 by 271 points would show below a card scale of 0.45 and fails the
# shot instead (spec 029 FR-008a, research R6).
strip() {
    local size
    size="$(crop_geometry "$4" "$5" 8 8 | LC_ALL=C awk -F'[x+]' '$1 > 1454 || $2 > 542 { printf "%gx%g", $1 / 2, $2 / 2 }')"
    [ -z "$size" ] || shot_failed "$1" "$2" "the strip is $size points, larger than the card's 727x271"
    crop "$3" "$4" "$5" "$6" 8 8 || shot_failed "$1" "$2" "crop failed"
}

# fill_crop <image> <window line> <region line> <out> <stem> <appearance>:
# the region with a uniform margin cut from a 2x window image (spec 031
# FR-012, data-model.md): half the region's smallest distance to the
# window's edges, so the crop stays inside the panel's rounded corners, at
# most 4% of the region's shorter side, in whole pixels. The margin comes
# from the window image; nothing is synthesized. The shot fails when the
# margin is below 4 px or the image's aspect lies outside 3:4 to 4:3.
# A region reaching left of the window (a disclosure group's accessibility
# frame does on macOS) is cut to the content column first: its left inset
# mirrors its right one.
fill_crop() {
    local geometry
    geometry="$(LC_ALL=C awk -v wx="$(value x "$2")" -v wy="$(value y "$2")" -v ww="$(value w "$2")" -v wh="$(value h "$2")" \
                    -v x="$(value x "$3")" -v y="$(value y "$3")" -v w="$(value w "$3")" -v h="$(value h "$3")" 'BEGIN {
        if (x < wx) { left = wx + (wx + ww - x - w); w = x + w - left; x = left }
        d = x - wx
        if (y - wy < d) d = y - wy
        if (wx + ww - x - w < d) d = wx + ww - x - w
        if (wy + wh - y - h < d) d = wy + wh - y - h
        m = d / 2
        cap = 0.04 * (w < h ? w : h)
        if (cap < m) m = cap
        p = int(2 * m)
        if (p < 4) { printf "fail:margin %d px, below 4 px", p; exit }
        iw = int(2 * w + 0.5) + 2 * p; ih = int(2 * h + 0.5) + 2 * p
        if (iw / ih < 0.75 || iw / ih > 4 / 3) { printf "fail:aspect %d:%d (%.2f) outside 3:4 to 4:3", iw, ih, iw / ih; exit }
        printf "%dx%d+%d+%d", iw, ih, int(2 * (x - wx) + 0.5) - p, int(2 * (y - wy) + 0.5) - p
    }')"
    case "$geometry" in
        fail:*) shot_failed "$5" "$6" "${geometry#fail:}" ;;
    esac
    magick "$1" -crop "$geometry" +repage "$4" || shot_failed "$5" "$6" "crop failed"
}

# union <frame line>...: the bounding frame of all given frames, in the
# helper's frame format. The two Claude Max sections are adjacent, so their
# union is the region that shows both (spec 031 FR-010a); a Settings strip's
# content frame is the union of its identified views (FR-011a).
union() {
    local line
    for line in "$@"; do
        printf '%s %s %s %s\n' "$(value x "$line")" "$(value y "$line")" "$(value w "$line")" "$(value h "$line")"
    done | LC_ALL=C awk '
        NR == 1 { l = $1; t = $2; r = $1 + $3; b = $2 + $4 }
        {
            if ($1 < l) l = $1
            if ($2 < t) t = $2
            if ($1 + $3 > r) r = $1 + $3
            if ($2 + $4 > b) b = $2 + $4
        }
        END { printf "x=%.1f y=%.1f w=%.1f h=%.1f\n", l, t, r - l, b - t }'
}

# center <line> x|y: the center coordinate of a frame.
center() {
    if [ "$2" = x ]; then
        awk -v a="$(value x "$1")" -v b="$(value w "$1")" 'BEGIN { print a + b / 2 }'
    else
        awk -v a="$(value y "$1")" -v b="$(value h "$1")" 'BEGIN { print a + b / 2 }'
    fi
}

# -showsMemberTables NO: the harnesses crop shows the group's tables with the
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

# settings_window <pid>: the Settings window line once it is on screen. It is
# the largest layer-0 window, since the window list may name an attached
# sheet first (spec 029 research R4).
settings_window() {
    wait_for_window "$1" settings >/dev/null || return 1
    local line
    line="$(largest_window "$1" 0)"
    [ -n "$line" ] || return 1
    printf '%s\n' "$line"
}

capture_pass() {
    local appearance="$1" raw="$tmp/raw/$1" png="$tmp/png" offset pid out dropdown collapsed second
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

    # menubar: drawn by the demo app (FR-019).
    if ! wait_for_log "$offset" "demo: bar rendered" 10; then
        demo_log_problems "$offset"
        shot_failed menubar "$appearance" "the demo app did not render the bar"
    fi
    cp "$tmp/bar-$appearance/menubar-$appearance.png" "$png/menubar-$appearance.png" ||
        shot_failed menubar "$appearance" "no rendered bar image"

    # The dropdown; its first crop is same-provider.
    out="$("$UIHELPER" statusitem "$pid" 2>&1)" || shot_failed same-provider "$appearance" "$out"
    "$UIHELPER" click "$(center "$out" x)" "$(center "$out" y)" >/dev/null || shot_failed same-provider "$appearance" "click failed"
    dropdown="$(wait_for_window "$pid" dropdown)" || shot_failed same-provider "$appearance" "the dropdown did not open"

    # same-provider: both Claude Max sections stacked, details collapsed,
    # each scrolled into view (the second first, so it never sits under the
    # pinned footer), cut as one region with the uniform margin (spec 031
    # FR-009, FR-010, FR-010b, FR-012). The first section's collapsed frame
    # is the height the glance shot checks its collapse against.
    out="$("$UIHELPER" scrollto "$pid" agenttacho.claudeSection2 2>&1)" || shot_failed same-provider "$appearance" "$out"
    out="$("$UIHELPER" scrollto "$pid" agenttacho.claudeSection 2>&1)" || shot_failed same-provider "$appearance" "$out"
    dropdown="$(wait_for_window "$pid" dropdown)" || shot_failed same-provider "$appearance" "the dropdown closed"
    screencapture -x -o -l "$(value id "$dropdown")" "$raw/same-provider.png" ||
        shot_failed same-provider "$appearance" "screencapture failed"
    collapsed="$("$UIHELPER" frame "$pid" agenttacho.claudeSection 2>&1)" || shot_failed same-provider "$appearance" "$collapsed"
    second="$("$UIHELPER" frame "$pid" agenttacho.claudeSection2 2>&1)" || shot_failed same-provider "$appearance" "$second"
    # The scroll to the first section must not have pushed the second one
    # out of view again: a scroll to it now has to leave it where it is.
    out="$("$UIHELPER" scrollto "$pid" agenttacho.claudeSection2 2>&1)" || shot_failed same-provider "$appearance" "$out"
    [ "$out" = "$second" ] ||
        shot_failed same-provider "$appearance" "the two Claude Max sections do not fit in view together"
    fill_crop "$raw/same-provider.png" "$dropdown" "$(union "$collapsed" "$second")" "$png/same-provider-$appearance.png" \
        same-provider "$appearance"

    # glance: the first Claude Max section, header to details, with its
    # details expanded in the Models view. The details collapse again
    # afterwards, so the next view picker the capture presses is the only
    # one shown (spec 031 FR-008, FR-010, FR-010b, FR-012a).
    "$UIHELPER" press "$pid" agenttacho.claudeDetails >/dev/null || shot_failed glance "$appearance" "Details did not open"
    "$UIHELPER" press "$pid" Models --in agenttacho.claudeDetails >/dev/null || shot_failed glance "$appearance" "no Models view"
    sleep 0.5
    out="$("$UIHELPER" scrollto "$pid" agenttacho.claudeSection 2>&1)" || shot_failed glance "$appearance" "$out"
    dropdown="$(wait_for_window "$pid" dropdown)" || shot_failed glance "$appearance" "the dropdown closed"
    screencapture -x -o -l "$(value id "$dropdown")" "$raw/glance.png" || shot_failed glance "$appearance" "screencapture failed"
    out="$("$UIHELPER" frame "$pid" agenttacho.claudeSection 2>&1)" || shot_failed glance "$appearance" "$out"
    fill_crop "$raw/glance.png" "$dropdown" "$out" "$png/glance-$appearance.png" glance "$appearance"
    # Back at the collapsed height, or the shot counts as failed.
    "$UIHELPER" press "$pid" agenttacho.claudeDetails >/dev/null || out=""
    sleep 0.5
    [ -n "$out" ] && out="$("$UIHELPER" frame "$pid" agenttacho.claudeSection 2>&1)" || out=""
    if [ -z "$out" ] || ! awk -v a="$(value h "$out")" -v b="$(value h "$collapsed")" 'BEGIN { exit !(a == b) }'; then
        rm -f "$png/glance-$appearance.png"
        shot_failed glance "$appearance" "the details did not collapse"
    fi

    # budget: the shot budget's row, scrolled into view first, since with
    # five sections the dropdown may reach its height cap (spec 024 FR-019,
    # spec 031 research R4).
    out="$("$UIHELPER" scrollto "$pid" agenttacho.budgetRow 2>&1)" || shot_failed budget "$appearance" "$out"
    dropdown="$(wait_for_window "$pid" dropdown)" || shot_failed budget "$appearance" "the dropdown closed"
    screencapture -x -o -l "$(value id "$dropdown")" "$raw/budget.png" || shot_failed budget "$appearance" "screencapture failed"
    out="$("$UIHELPER" frame "$pid" agenttacho.budgetRow 2>&1)" || shot_failed budget "$appearance" "$out"
    crop "$raw/budget.png" "$dropdown" "$out" "$png/budget-$appearance.png" || shot_failed budget "$appearance" "crop failed"

    # harnesses: the shot budget's breakdown, expanded in the Harnesses view,
    # the only details expanded, so its picker is unambiguous (spec 031
    # FR-010b). The pinned footer leaves the expanded Details partly below
    # the scrolling sections, so the capture first scrolls the container
    # fully into view (spec 026 FR-010, FR-018). Models is restored after,
    # since the view is one stored choice.
    "$UIHELPER" press "$pid" agenttacho.details >/dev/null || shot_failed harnesses "$appearance" "Details did not open"
    "$UIHELPER" press "$pid" Harnesses --in agenttacho.details >/dev/null || shot_failed harnesses "$appearance" "no Harnesses view"
    sleep 0.5
    out="$("$UIHELPER" scrollto "$pid" agenttacho.details 2>&1)" || shot_failed harnesses "$appearance" "$out"
    dropdown="$(wait_for_window "$pid" dropdown)" || shot_failed harnesses "$appearance" "the dropdown closed"
    screencapture -x -o -l "$(value id "$dropdown")" "$raw/harnesses.png" || shot_failed harnesses "$appearance" "screencapture failed"
    out="$("$UIHELPER" frame "$pid" agenttacho.details 2>&1)" || shot_failed harnesses "$appearance" "$out"
    crop "$raw/harnesses.png" "$dropdown" "$out" "$png/harnesses-$appearance.png" || shot_failed harnesses "$appearance" "crop failed"
    "$UIHELPER" press "$pid" Models --in agenttacho.details >/dev/null || true

    # Settings tabs, opened with the dropdown's Settings button (spec 025
    # FR-027, FR-035).
    "$UIHELPER" press "$pid" agenttacho.settingsButton >/dev/null ||
        shot_failed menubar-settings "$appearance" "no Settings button in the dropdown"
    local settings preview toggle heading summary changed
    settings="$(wait_for_window "$pid" settings)" || shot_failed menubar-settings "$appearance" "Settings did not open"

    # menubar-settings: the live bar preview and the level settings down to
    # the run-out marker toggle, without the entry list (spec 031 FR-011a).
    # Frames read during the tab's crossfade are off, hence the wait.
    "$UIHELPER" press "$pid" "Menu Bar" >/dev/null || shot_failed menubar-settings "$appearance" "no Menu Bar tab"
    sleep 1
    preview="$("$UIHELPER" frame "$pid" agenttacho.menubarPreview 2>&1)" || shot_failed menubar-settings "$appearance" "$preview"
    toggle="$("$UIHELPER" frame "$pid" agenttacho.menubarRunOutToggle 2>&1)" || shot_failed menubar-settings "$appearance" "$toggle"
    settings="$(settings_window "$pid")" || shot_failed menubar-settings "$appearance" "Settings closed"
    screencapture -x -o -l "$(value id "$settings")" "$raw/menubar-settings.png" ||
        shot_failed menubar-settings "$appearance" "screencapture failed"
    strip menubar-settings "$appearance" "$raw/menubar-settings.png" "$settings" "$(union "$preview" "$toggle")" \
        "$png/menubar-settings-$appearance.png"

    "$UIHELPER" press "$pid" Prices >/dev/null || shot_failed prices "$appearance" "no Prices tab"
    "$UIHELPER" press "$pid" Import >/dev/null || shot_failed prices "$appearance" "no Import menu"
    sleep 1
    "$UIHELPER" press "$pid" "$OPENAI_IMPORT" >/dev/null || shot_failed prices "$appearance" "no OpenAI import"
    sleep 1.5
    # prices: the import sheet's title, summary and Changed section, cut from
    # the Settings window's image, which includes the attached sheet; the
    # sheet's buttons and the price table behind it stay out. The summary is
    # in the union, so a summary wider than the title and the section is not
    # clipped (spec 031 FR-011a).
    settings="$(settings_window "$pid")" || shot_failed prices "$appearance" "Settings closed"
    heading="$("$UIHELPER" frame "$pid" agenttacho.priceImportTitle 2>&1)" ||
        shot_failed prices "$appearance" "the import preview did not show: $heading"
    summary="$("$UIHELPER" frame "$pid" agenttacho.priceImportSummary 2>&1)" ||
        shot_failed prices "$appearance" "the import preview did not show: $summary"
    changed="$("$UIHELPER" frame "$pid" agenttacho.priceImportChanged 2>&1)" ||
        shot_failed prices "$appearance" "the import preview did not show: $changed"
    screencapture -x -o -l "$(value id "$settings")" "$raw/prices.png" || shot_failed prices "$appearance" "screencapture failed"
    strip prices "$appearance" "$raw/prices.png" "$settings" "$(union "$heading" "$summary" "$changed")" "$png/prices-$appearance.png"
    # An open sheet holds up quitting.
    "$UIHELPER" press "$pid" Cancel >/dev/null || true

    "$UIHELPER" quit "$DEMO_ID" --force >/dev/null || die "AgentTacho Demo did not quit ($appearance); not captured: $(not_captured)"
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
    # A fresh folder of its own: the cleanup removes only what this run
    # created, never another folder in the target (spec 031 FR-016).
    staging="$(mktemp -d "$target/.capture-staging.XXXXXX")" || die "could not create a staging folder in $target"
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
make app-demo
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
