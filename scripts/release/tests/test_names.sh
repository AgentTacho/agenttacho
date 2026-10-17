# The name check (spec 023 FR-026, SC-003, contracts/name-check.md): the
# app's former name may appear only where a requirement needs it, as listed
# in names-allowlist.txt. Historical specs, brainstorms and docs/superpowers
# keep the old name and are not searched.

NAMES_ALLOWLIST="$TESTS_DIR/names-allowlist.txt"
OLD_NAME_PATTERN='agentmeter|agent meter'

# names_check <repository> <allowlist>: searches the tracked files for the old
# name (any case). Every allowlist entry `path:pattern` (an extended regular
# expression, case-sensitive) whose path is the file of a match is removed
# from the matching line; what is left must not name the old name. Prints one
# `path:line: text` per leftover and `names: <n> leftover(s) of the old name`,
# or `names: ok (<n> allowed matches)`; an entry that removes nothing anywhere
# is reported as stale. Exit status 1 for leftovers or stale entries.
names_check() {
    local repo="$1" allowlist="$2"
    local entries matches used="" leftovers=0 allowed=0 stale=0
    local match path rest number text stripped entry entry_path pattern
    # Entries without blank lines and comments ("  # " starts a comment).
    entries="$(sed -e 's/[[:space:]][[:space:]]*#[[:space:]].*$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$allowlist")"
    matches="$(git -C "$repo" grep -n -I -i -E "$OLD_NAME_PATTERN" -- . \
        ':(exclude)specs' ':(exclude)brainstorm' ':(exclude)docs/superpowers' 2>/dev/null || true)"
    # File and folder names carry the new name too (FR-006); no allowlist.
    local named
    named="$(git -C "$repo" ls-files -- . ':(exclude)specs' ':(exclude)brainstorm' ':(exclude)docs/superpowers' |
        grep -E -i -- "$OLD_NAME_PATTERN" || true)"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        printf '%s: file name\n' "$path"
        leftovers=$((leftovers + 1))
    done <<EOF
$named
EOF

    while IFS= read -r match; do
        [ -n "$match" ] || continue
        path="${match%%:*}"
        rest="${match#*:}"
        number="${rest%%:*}"
        text="${rest#*:}"
        stripped="$text"
        while IFS= read -r entry; do
            [ -n "$entry" ] || continue
            entry_path="${entry%%:*}"
            pattern="${entry#*:}"
            [ "$entry_path" = "$path" ] || continue
            if printf '%s\n' "$stripped" | grep -Eq -- "$pattern"; then
                stripped="$(printf '%s\n' "$stripped" | sed -E "s#$pattern##g")"
                used="$used$entry
"
            fi
        done <<EOF
$entries
EOF
        if printf '%s\n' "$stripped" | grep -Eiq -- "$OLD_NAME_PATTERN"; then
            printf '%s:%s: %s\n' "$path" "$number" "$text"
            leftovers=$((leftovers + 1))
        else
            allowed=$((allowed + 1))
        fi
    done <<EOF
$matches
EOF

    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        case "$used" in
            *"$entry
"*) ;;
            *)
                printf 'names: stale allowlist entry %s\n' "$entry"
                stale=$((stale + 1))
                ;;
        esac
    done <<EOF
$entries
EOF

    if [ "$leftovers" -gt 0 ]; then
        printf 'names: %s leftover(s) of the old name\n' "$leftovers"
    fi
    [ "$leftovers" -eq 0 ] && [ "$stale" -eq 0 ] || return 1
    printf 'names: ok (%s allowed matches)\n' "$allowed"
}

test_repository_has_no_leftovers_of_the_old_name() {
    assert_status 0 names_check "$REPO_ROOT" "$NAMES_ALLOWLIST"
    assert_contains "$(cat "$LAST_OUT")" "names: ok ("
}

# spec 023 User Story 5, scenario 1: the README says "formerly AgentMeter"
# exactly once, near the top.
test_readme_names_the_former_name_once_near_the_top() {
    assert_eq "1" "$(grep -c 'formerly AgentMeter' "$REPO_ROOT/README.md")"
    head -n 10 "$REPO_ROOT/README.md" | grep -q 'formerly AgentMeter' ||
        fail "the former name is not in the first 10 lines of README.md"
}

# --- the check itself, on scratch repositories ------------------------------

# names_repo <file> <text> ...: a git repository with the given tracked files.
names_repo() {
    local repo
    repo="$(make_git_repo)"
    while [ "$#" -gt 1 ]; do
        mkdir -p "$(dirname "$repo/$1")"
        printf '%s\n' "$2" >"$repo/$1"
        git -C "$repo" add "$1"
        shift 2
    done
    printf '%s\n' "$repo"
}

test_name_check_reports_leftovers_in_any_case() {
    local repo
    repo="$(names_repo a.txt "Hello AgentMeter" b.txt "AGENT METER here")"
    : >"$TEST_TMP/allow.txt"
    assert_status 1 names_check "$repo" "$TEST_TMP/allow.txt"
    assert_contains "$(cat "$LAST_OUT")" "a.txt:1: Hello AgentMeter"
    assert_contains "$(cat "$LAST_OUT")" "b.txt:1: AGENT METER here"
    assert_contains "$(cat "$LAST_OUT")" "names: 2 leftover(s) of the old name"
}

test_name_check_allows_only_the_listed_phrase() {
    local repo
    repo="$(names_repo a.txt "copied from AgentMeter: x
copied from AgentMeter and from AgentMeter.app")"
    printf 'a.txt:copied from AgentMeter  # FR-011\n' >"$TEST_TMP/allow.txt"
    assert_status 1 names_check "$repo" "$TEST_TMP/allow.txt"
    assert_eq "a.txt:2: copied from AgentMeter and from AgentMeter.app
names: 1 leftover(s) of the old name" "$(cat "$LAST_OUT")"
}

test_name_check_entries_apply_to_their_own_file_only() {
    local repo
    repo="$(names_repo a.txt "dev.rhuss.agentmeter" b.txt "dev.rhuss.agentmeter")"
    printf '# the legacy identifier\na.txt:dev\\.rhuss\\.agentmeter  # FR-012\n' >"$TEST_TMP/allow.txt"
    assert_status 1 names_check "$repo" "$TEST_TMP/allow.txt"
    assert_eq "b.txt:1: dev.rhuss.agentmeter
names: 1 leftover(s) of the old name" "$(cat "$LAST_OUT")"
}

test_name_check_reports_stale_entries() {
    local repo
    repo="$(names_repo a.txt "AgentTacho only")"
    printf 'a.txt:AgentMeter  # FR-023\n' >"$TEST_TMP/allow.txt"
    assert_status 1 names_check "$repo" "$TEST_TMP/allow.txt"
    assert_eq "names: stale allowlist entry a.txt:AgentMeter" "$(cat "$LAST_OUT")"
}

test_name_check_reports_file_names() {
    local repo
    repo="$(names_repo Resources/AgentMeter.icns "icon" docs/agentmeter/x.md "fine")"
    : >"$TEST_TMP/allow.txt"
    assert_status 1 names_check "$repo" "$TEST_TMP/allow.txt"
    assert_contains "$(cat "$LAST_OUT")" "Resources/AgentMeter.icns: file name"
    assert_contains "$(cat "$LAST_OUT")" "docs/agentmeter/x.md: file name"
    assert_contains "$(cat "$LAST_OUT")" "names: 2 leftover(s) of the old name"
}

test_name_check_skips_historical_folders() {
    local repo
    repo="$(names_repo specs/001-agentmeter/spec.md "AgentMeter" brainstorm/attic/01-agentmeter.md "AgentMeter" \
        docs/superpowers/agentmeter.md "AgentMeter" ok.txt "fine")"
    : >"$TEST_TMP/allow.txt"
    assert_status 0 names_check "$repo" "$TEST_TMP/allow.txt"
    assert_eq "names: ok (0 allowed matches)" "$(cat "$LAST_OUT")"
}
