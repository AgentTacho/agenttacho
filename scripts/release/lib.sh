#!/bin/bash
# Shared functions for the AgentMeter release scripts.
#
# Sourced by the scripts in scripts/release/ and by their tests. Defines
# functions only: sourcing it has no side effects. Every function is safe under
# `set -euo pipefail` and prints its result on stdout. Most signal failure
# through their exit status; these exit the calling shell (or the command
# substitution they run in) through `die` instead:
#   die                  always
#   version_info         git failures, invalid build number
#   select_identity      SIGN_IDENTITY names no available identity
#   preflight            any problem in release mode, an unknown mode
#   render_cask          missing cask template
# Configuration comes from the environment variables listed in
# specs/005-macos-distribution/contracts/make-targets.md; release_defaults
# holds their defaults.

# log <prefix> <msg>: informational line such as "signing: self-signed (...)".
log() {
    printf '%s: %s\n' "$1" "$2"
}

# warn <msg>: "warning: <msg>" on stderr.
warn() {
    printf 'warning: %s\n' "$1" >&2
}

# die <msg>: "error: <msg>" on stderr, then exit 1.
die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# release_defaults: the one place for the defaults of the release
# configuration. Fills unset or empty variables (make passes empty values),
# exports them for helper scripts, and sets the fixed output paths APP and
# OUT_DIR (relative to the repository root). Every entry script calls it right
# after sourcing this file; the functions below that read the configuration
# call it as well, which only fills what is still unset.
release_defaults() {
    GH_REPO="${GH_REPO:-rhuss/agentmeter}"
    TAP_REPO="${TAP_REPO:-git@github.com:rhuss/homebrew-tap.git}"
    NOTARY_PROFILE="${NOTARY_PROFILE:-agentmeter-notary}"
    SIGN_IDENTITY_NAME="${SIGN_IDENTITY_NAME:-AgentMeter Signing}"
    APP_ICON="${APP_ICON:-Resources/icons/macos/AgentMeter.icns}"
    export GH_REPO TAP_REPO NOTARY_PROFILE SIGN_IDENTITY_NAME APP_ICON
    APP="build/AgentMeter.app"
    OUT_DIR="build/release"
}

# --- version (research.md R7) ----------------------------------------------

# Reads tag names on stdin and prints the highest one matching vX.Y.Z
# (numeric comparison per component), or nothing.
highest_release_tag() {
    { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } |
        sed 's/^v//' |
        sort -t. -k1,1n -k2,2n -k3,3n |
        tail -n 1 |
        sed 's/^\(..*\)$/v\1/'
}

# nearest_release_tag [exclude-tag...]: prints the highest vX.Y.Z tag
# reachable from HEAD on the nearest tagged commit, or nothing when there is
# none. The given tags are skipped (git refuses glob characters in tag names,
# so each one only matches itself).
nearest_release_tag() {
    local excludes="" candidate commit tag
    for tag in "$@"; do
        excludes="$excludes --exclude $tag"
    done
    while :; do
        # shellcheck disable=SC2086
        candidate="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' $excludes HEAD 2>/dev/null)" || return 0
        if printf '%s\n' "$candidate" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            commit="$(git rev-list -n 1 "refs/tags/$candidate")"
            git tag --points-at "$commit" | highest_release_tag
            return 0
        fi
        excludes="$excludes --exclude $candidate"
    done
}

# version_info: prints `mode short_version display_version build_number tag`
# for the current git repository (tag only in release mode).
version_info() {
    local tag short build dirty
    # Bash 3.2 does not apply `set -e` inside command substitutions, so every
    # git failure is checked explicitly.
    if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
        warn "shallow clone, build number may be wrong"
    fi
    dirty="$(git status --porcelain)" || die "cannot read the git status"
    tag="$(git tag --points-at HEAD | highest_release_tag)" || die "cannot read the git tags"
    build="$(git rev-list --count HEAD)" || die "cannot count the commits of HEAD"
    case "$build" in
        "" | *[!0-9]*) die "invalid build number: ${build:-none}" ;;
    esac
    if [ -n "$tag" ] && [ -z "$dirty" ]; then
        short="${tag#v}"
        printf 'release %s %s %s %s\n' "$short" "$short" "$build" "$tag"
        return 0
    fi
    tag="$(nearest_release_tag)"
    short="${tag#v}"
    short="${short:-0.0.0}"
    printf 'dev %s %s-dev %s\n' "$short" "$short" "$build"
}

# --- release changes (About tab, release notes) ------------------------------

# previous_release_tag <mode>: the release tag the changes of a build start
# from, or nothing. A release build (mode `release` of version_info) skips the
# tags on HEAD, which name the release being built; a development build starts
# from the nearest release tag.
previous_release_tag() {
    if [ "$1" = "release" ]; then
        # shellcheck disable=SC2046
        nearest_release_tag $(git tag --points-at HEAD)
    else
        nearest_release_tag
    fi
}

# release_changes <mode>: JSON array of the feat, fix and perf commits since
# previous_release_tag, newest first, merges skipped. Each entry has `type`,
# `scope` (null without one), `subject` and `hash` (abbreviated). Other
# commit types and non-conventional subjects are left out; without a previous
# tag the array is empty. build-app.sh bundles it as changes.json for the
# About tab, release.sh renders it into the release notes.
release_changes() {
    local base log hash subject re
    base="$(previous_release_tag "$1")"
    if [ -z "$base" ]; then
        echo "[]"
        return 0
    fi
    log="$(git log --no-merges --abbrev=7 --format='%h%x09%s' "$base..HEAD")" ||
        die "cannot read the commits since $base"
    # type(scope)!: subject, with scope and ! optional.
    re='^(feat|fix|perf)(\(([^)]*)\))?!?: (.+)$'
    while IFS="$(printf '\t')" read -r hash subject; do
        [[ "$subject" =~ $re ]] || continue
        printf '%s\t%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "$hash" "${BASH_REMATCH[4]}"
    done <<<"$log" |
        jq -R -s 'split("\n") | map(select(length > 0) | split("\t") |
            {type: .[0], scope: (if .[1] == "" then null else .[1] end), subject: (.[3:] | join("\t")), hash: .[2]})'
}

# changes_markdown <changes-json>: the "## Changes" section of the release
# notes, with Features, Fixes and Performance subsections in this order (the
# About tab groups them the same way), followed by a blank line. Prints
# nothing when the list or the argument is empty.
changes_markdown() {
    [ -n "${1:-}" ] || return 0
    printf '%s' "$1" | jq -r '
        def group($type; $title):
            [.[] | select(.type == $type)] as $entries
            | if ($entries | length) == 0 then empty
              else "### \($title)\n\n"
                + ($entries | map("- " + (if .scope then "\(.scope): " else "" end) + "\(.subject) (\(.hash))") | join("\n"))
              end;
        [group("feat"; "Features"), group("fix"; "Fixes"), group("perf"; "Performance")]
        | if length == 0 then empty else "## Changes\n\n" + join("\n\n") + "\n" end'
}

# --- signing (research.md R3, data-model.md SigningTier) -------------------

# Prints `HASH<TAB>NAME` for every usable code-signing identity in the order
# `security find-identity -p codesigning` lists them. The `-v` flag is not
# used, so an untrusted self-signed certificate is found; identities with any
# status other than CSSMERR_TP_NOT_TRUSTED (expired, revoked, ...) are skipped.
codesigning_identities() {
    local output line re hash name rest
    output="$(security find-identity -p codesigning 2>/dev/null)" || return 0
    re='^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-Fa-f]{40})[[:space:]]+"(.*)"(.*)$'
    while IFS= read -r line; do
        if [[ "$line" =~ $re ]]; then
            hash="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"
            rest="${BASH_REMATCH[3]}"
            case "$rest" in
                *CSSMERR_TP_NOT_TRUSTED*) ;;
                *[A-Za-z]*) continue ;;
            esac
            printf '%s\t%s\n' "$hash" "$name"
        fi
    done <<<"$output"
}

# Prints `HASH<TAB>NAME<TAB>PROBLEM` for every Developer ID Application
# identity that macOS reports as expired or revoked (PROBLEM is `expired` or
# `revoked`), once per hash, in listing order. Parses the same
# `security find-identity -p codesigning` output as codesigning_identities. A
# Developer ID that is only not trusted stays usable and is not listed (spec
# 015 FR-012, research R6).
unusable_developer_ids() {
    local output line re hash name rest problem seen=" "
    output="$(security find-identity -p codesigning 2>/dev/null)" || return 0
    re='^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-Fa-f]{40})[[:space:]]+"(.*)"(.*)$'
    while IFS= read -r line; do
        [[ "$line" =~ $re ]] || continue
        hash="${BASH_REMATCH[1]}"
        name="${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]}"
        case "$name" in
            "Developer ID Application:"*) ;;
            *) continue ;;
        esac
        case "$rest" in
            *CSSMERR_TP_CERT_EXPIRED*) problem=expired ;;
            *CSSMERR_TP_CERT_REVOKED*) problem=revoked ;;
            *) continue ;;
        esac
        case "$seen" in
            *" $hash "*) continue ;;
        esac
        seen="$seen$hash "
        printf '%s\t%s\t%s\n' "$hash" "$name" "$problem"
    done <<<"$output"
}

# Prints the tier for an identity name. `self-signed` stands for every
# certificate that is not a Developer ID Application certificate, also one
# that is not self-signed (for example "Apple Development: ..." passed through
# SIGN_IDENTITY): such a build is stable but not notarizable, which is what the
# tier decides (FINDING-26, data-model.md SigningTier).
tier_for_name() {
    case "$1" in
        "Developer ID Application:"*) echo "developer-id" ;;
        *) echo "self-signed" ;;
    esac
}

# select_identity: prints `tier hash-or-dash name` for the identity a build
# uses (FR-001, FR-004). SIGN_IDENTITY (name or SHA-1, `-` for ad-hoc) skips
# the automatic order Developer ID, $SIGN_IDENTITY_NAME, ad-hoc. The tier
# `self-signed` means any certificate other than Developer ID (tier_for_name).
select_identity() {
    local identities wanted hash name self_name explicit
    release_defaults
    self_name="$SIGN_IDENTITY_NAME"
    explicit="${SIGN_IDENTITY:-}"
    if [ "$explicit" = "-" ]; then
        echo "ad-hoc - no certificate"
        return 0
    fi
    identities="$(codesigning_identities)"
    if [ -n "$explicit" ]; then
        wanted="$(printf '%s' "$explicit" | tr '[:lower:]' '[:upper:]')"
        while IFS="$(printf '\t')" read -r hash name; do
            [ -n "$hash" ] || continue
            if [ "$hash" = "$wanted" ] || [ "$name" = "$explicit" ]; then
                echo "$(tier_for_name "$name") $hash $name"
                return 0
            fi
        done <<<"$identities"
        die "signing identity not found: $explicit"
    fi
    while IFS="$(printf '\t')" read -r hash name; do
        case "$name" in
            "Developer ID Application:"*) echo "developer-id $hash $name"; return 0 ;;
        esac
    done <<<"$identities"
    while IFS="$(printf '\t')" read -r hash name; do
        if [ -n "$hash" ] && [ "$name" = "$self_name" ]; then
            echo "self-signed $hash $name"
            return 0
        fi
    done <<<"$identities"
    echo "ad-hoc - no certificate"
}

# codesign_flags <tier>: hardened runtime and secure timestamp for Developer
# ID (FR-005), no timestamp otherwise.
codesign_flags() {
    case "$1" in
        developer-id) echo "--options runtime --timestamp" ;;
        *) echo "--timestamp=none" ;;
    esac
}

# requirement_is_certificate_based <codesign -d -r- text>: exit 0 when the
# designated requirement names a signing certificate and no build hash (FR-003).
requirement_is_certificate_based() {
    case "$1" in
        "" | *cdhash*) return 1 ;;
        *"certificate root"* | *"certificate leaf"*) return 0 ;;
        *) return 1 ;;
    esac
}

# --- DMG (research.md R4, R5) ----------------------------------------------

# dmg_background <tier> <notarized>: repo-relative 1x background path; the
# instructions-free variant only for a notarized Developer ID build.
dmg_background() {
    if [ "$(effective_notarized "$1" "$2")" = "true" ]; then
        echo "Resources/dmg/background-notarized.png"
    else
        echo "Resources/dmg/background-unnotarized.png"
    fi
}

# dmg_filename <display_version>
dmg_filename() {
    echo "AgentMeter-$1.dmg"
}

# --- preflight (FR-016, FR-019) --------------------------------------------

# with_reason <message> <command output>: the message plus, in parentheses,
# the last non-empty line of a failed remote command's stderr, so a failure
# explains itself (host key, missing SSH key, permission denied). git's
# generic access hint after the real error is skipped.
with_reason() {
    local reason
    reason="$(printf '%s\n' "$2" |
        grep -v -e '^[[:space:]]*$' \
            -e '^fatal: Could not read from remote repository\.$' \
            -e '^Please make sure you have the correct access rights$' \
            -e '^and the repository exists\.$' |
        tail -n 1)" || true
    if [ -n "$reason" ]; then
        printf '%s (%s)\n' "$1" "$reason"
    else
        printf '%s\n' "$1"
    fi
}

# Runs a command that may contact a remote without ever prompting (FR-018).
noninteractive() {
    GIT_TERMINAL_PROMPT=0 GH_PROMPT_DISABLED=1 \
        GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" "$@" </dev/null
}

# unusable_developer_ids_text <unusable_developer_ids output>: names every
# listed certificate with its problem, for example
# `Developer ID certificate "Developer ID Application: X (T)" is expired`.
unusable_developer_ids_text() {
    local hash name problem text=""
    while IFS="$(printf '\t')" read -r hash name problem; do
        [ -n "$hash" ] || continue
        text="${text:+$text, }\"$name\" is $problem"
    done <<<"$1"
    printf 'Developer ID certificate %s\n' "$text"
}

# tier_guard <release|dry-run> <selected tier>: an automatic identity
# selection that falls below Developer ID while the keychain holds an
# expired or revoked Developer ID certificate stops a release unless
# ALLOW_TIER_DOWNGRADE=1, and only warns in a dry run (spec 015 FR-012 to
# FR-015, contracts/release-command.md). With the opt-out it warns that the
# downgrade is deliberate. A forced SIGN_IDENTITY skips the guard, and the
# ad-hoc check of preflight stays independent of it.
tier_guard() {
    local mode="$1" tier="$2" unusable facts next
    [ -z "${SIGN_IDENTITY:-}" ] || return 0
    [ "$tier" != "developer-id" ] || return 0
    unusable="$(unusable_developer_ids)"
    [ -n "$unusable" ] || return 0
    facts="$(unusable_developer_ids_text "$unusable")"
    if [ "${ALLOW_TIER_DOWNGRADE:-}" = "1" ]; then
        warn "$facts, releasing on a lower tier than Developer ID (deliberate tier downgrade)"
        return 0
    fi
    if [ "$tier" = "self-signed" ]; then
        next="to release as self-signed"
    else
        next="to release on the next tier (ad-hoc, which also needs ALLOW_ADHOC=1)"
    fi
    if [ "$mode" = "release" ]; then
        die "$facts; renew it, or set ALLOW_TIER_DOWNGRADE=1 $next"
    fi
    warn "$facts; renew it, or set ALLOW_TIER_DOWNGRADE=1 $next; a real release would stop unless ALLOW_TIER_DOWNGRADE=1 is set"
}

# preflight <release|dry-run>: checks that a release can be published. In
# release mode the first problem stops with `die`; in dry-run mode every
# problem is printed with `warn` and the function returns 0.
preflight() {
    local mode="$1" report tag head remote_refs remote_commit identity err
    case "$mode" in
        release) report=die ;;
        dry-run) report=warn ;;
        *) die "unknown preflight mode: $mode" ;;
    esac
    release_defaults
    local gh_repo="$GH_REPO" tap_repo="$TAP_REPO"

    if [ -n "$(git status --porcelain)" ]; then
        "$report" "working tree has uncommitted changes"
    fi

    # The build number is the commit count (FR-007); a shallow clone would
    # publish a too small one.
    if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
        "$report" "shallow clone, the build number would be wrong (git fetch --unshallow --tags)"
    fi

    tag="$(git tag --points-at HEAD | highest_release_tag)"
    if [ -z "$tag" ]; then
        "$report" "HEAD has no vX.Y.Z tag"
    else
        head="$(git rev-parse HEAD)"
        # stderr goes along: the awk filters below only match ref lines.
        if ! remote_refs="$(noninteractive git ls-remote -- origin "refs/tags/$tag" "refs/tags/$tag^{}" 2>&1)"; then
            "$report" "$(with_reason "cannot read tags from origin" "$remote_refs")"
        else
            remote_commit="$(printf '%s\n' "$remote_refs" | awk -v ref="refs/tags/$tag^{}" '$2 == ref {print $1}')"
            if [ -z "$remote_commit" ]; then
                remote_commit="$(printf '%s\n' "$remote_refs" | awk -v ref="refs/tags/$tag" '$2 == ref {print $1}')"
            fi
            if [ -z "$remote_commit" ]; then
                "$report" "tag $tag is not pushed to origin (git push origin $tag)"
            elif [ "$remote_commit" != "$head" ]; then
                "$report" "tag $tag on origin points to a different commit ($remote_commit, HEAD is $head)"
            fi
        fi
    fi

    if ! err="$(noninteractive gh auth status 2>&1 >/dev/null)"; then
        "$report" "$(with_reason "gh is not authenticated" "$err")"
    elif [ -n "$tag" ] && noninteractive gh release view "$tag" -R "$gh_repo" >/dev/null 2>&1 &&
        [ "${REPLACE:-}" != "1" ]; then
        "$report" "release $tag already exists in $gh_repo (set REPLACE=1 to replace its assets)"
    fi

    identity="$(select_identity)"
    tier_guard "$mode" "${identity%% *}"
    if [ "${identity%% *}" = "ad-hoc" ] && [ "${ALLOW_ADHOC:-}" != "1" ]; then
        "$report" "no signing certificate available, the build would be ad-hoc signed (set ALLOW_ADHOC=1 to release anyway)"
    fi

    if ! err="$(noninteractive git ls-remote -- "$tap_repo" 2>&1 >/dev/null)"; then
        "$report" "$(with_reason "tap repository not reachable: $tap_repo" "$err")"
    fi
    return 0
}

# --- release notes and release info (FR-017, contracts/release-info.md) ------

# Prints true only for a notarized Developer ID build.
effective_notarized() {
    if [ "$1" = "developer-id" ] && [ "$2" = "true" ]; then
        echo true
    else
        echo false
    fi
}

tier_label() {
    case "$1" in
        developer-id) echo "Developer ID" ;;
        *) echo "$1" ;;
    esac
}

# release_notes <version> <tier> <notarized> [changes-json]: Markdown for the
# GitHub release. The changes (release_changes) come first, as a "## Changes"
# section that is left out when there are none.
release_notes() {
    local version="$1" tier="$2" notarized dmg
    notarized="$(effective_notarized "$tier" "$3")"
    dmg="$(dmg_filename "$version")"
    changes_markdown "${4:-}"
    printf '## Installation\n\n'
    printf 'Download `%s`, open it and drag AgentMeter to Applications, or install it with Homebrew:\n\n' "$dmg"
    printf '```\nbrew install --cask rhuss/tap/agentmeter\n```\n\n'
    printf 'The SHA-256 checksum is in `%s.sha256`.\n\n' "$dmg"
    if [ "$notarized" = "true" ]; then
        printf 'Signing: %s, notarized.\n\n' "$(tier_label "$tier")"
    else
        printf 'Signing: %s, not notarized.\n\n' "$(tier_label "$tier")"
        printf '### First launch after each install or upgrade\n\n'
        printf 'AgentMeter is not notarized by Apple, so macOS blocks the first launch of each new version until you allow it:\n\n'
        printf -- '- macOS 14: Control-click AgentMeter in Applications and choose Open.\n'
        printf -- '- macOS 15 or later: open AgentMeter, then choose "Open Anyway" in System Settings > Privacy & Security.\n'
        printf -- '- Or run: `xattr -dr com.apple.quarantine /Applications/AgentMeter.app`\n\n'
    fi
    if [ "$tier" = "ad-hoc" ]; then
        printf 'This build is ad-hoc signed: notification permission and start at login must be granted again after every upgrade.\n\n'
    fi
    printf 'Homebrew quits AgentMeter before an upgrade and opens it again afterwards. To upgrade from a DMG, quit AgentMeter, replace it in Applications and open it again.\n'
}

# release_info_json <version> <sha256> <tier> <notarized>
release_info_json() {
    jq -n \
        --arg version "$1" \
        --arg dmg "$(dmg_filename "$1")" \
        --arg sha256 "$2" \
        --arg tier "$3" \
        --argjson notarized "$(effective_notarized "$3" "$4")" \
        '{version: $version, dmg: $dmg, sha256: $sha256, tier: $tier, notarized: $notarized}'
}

# notary_profile_state: prints `available` when the notarytool keychain
# profile $NOTARY_PROFILE (default agentmeter-notary) works, `missing` when
# the keychain has no such profile (FR-014a), and `error <message>` for any
# other failure (network, Apple service, expired credentials, locked
# keychain), which must not silently downgrade a release.
notary_profile_state() {
    local output
    release_defaults
    if output="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1 </dev/null)"; then
        echo available
    elif printf '%s\n' "$output" | grep -q 'No Keychain password item found'; then
        echo missing
    else
        printf 'error %s\n' "$(printf '%s\n' "$output" | grep -v '^[[:space:]]*$' | head -n 1)"
    fi
}

# --- Homebrew cask (contracts/cask.md) -------------------------------------

# Prints the body of the cask caveats (indented for the heredoc). The last
# paragraph reflects `brew upgrade`: Homebrew quits the app through
# `uninstall quit:` and opens it again after the upgrade (FR-024).
cask_caveats() {
    if [ "$1" != "true" ]; then
        cat <<'EOS'
    AgentMeter is not notarized by Apple. After each install or upgrade,
    allow it once before it starts:
      macOS 14:          Control-click AgentMeter in Applications and choose Open.
      macOS 15 or later: open AgentMeter, then choose "Open Anyway" in
                         System Settings > Privacy & Security.
    Or run: xattr -dr com.apple.quarantine /Applications/AgentMeter.app

EOS
    fi
    cat <<'EOS'
    Homebrew quits AgentMeter before an upgrade and opens it
    again afterwards.
EOS
}

# render_cask <version> <sha256> <notarized>: the cask Ruby source rendered
# from packaging/homebrew/agentmeter.rb.tmpl (CASK_TEMPLATE overrides it).
render_cask() {
    local version="$1" sha256="$2" notarized="$3" line
    # BASH_SOURCE[0] is this file, also when lib.sh is sourced from elsewhere.
    local template="${CASK_TEMPLATE:-$(dirname "${BASH_SOURCE[0]}")/../../packaging/homebrew/agentmeter.rb.tmpl}"
    [ -f "$template" ] || die "missing cask template: $template"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "@CAVEATS@") cask_caveats "$notarized" ;;
            *)
                line="${line//@VERSION@/$version}"
                printf '%s\n' "${line//@SHA256@/$sha256}" ;;
        esac
    done <"$template"
}
