#!/bin/bash
# Dependency-free test runner for the release scripts (Bash 3.2 compatible).
#
# Every scripts/release/tests/test_*.sh file is sourced in a fresh subshell for
# each function named test_* it defines. Each test gets its own temporary
# directory ($TEST_TMP), a stub directory at the front of PATH ($STUB_DIR), an
# isolated git configuration, and none of the release, GIT_* or stub control
# variables from the caller's environment.
#
# Usage: run.sh [name-filter]   (only tests whose name contains the filter)

set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$RELEASE_DIR/../.." && pwd)"
export TESTS_DIR RELEASE_DIR REPO_ROOT

FILTER="${1:-}"

# --- assertion and fixture helpers (available inside every test) ----------

fail() {
    printf 'assertion failed: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-values differ}"
    if [ "$expected" != "$actual" ]; then
        printf 'assertion failed: %s\n  expected: [%s]\n  actual:   [%s]\n' "$msg" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_contains() {
    local haystack="$1" needle="$2"
    case "$haystack" in
        *"$needle"*) ;;
        *) printf 'assertion failed: expected to find [%s] in:\n%s\n' "$needle" "$haystack" >&2
           exit 1 ;;
    esac
}

assert_not_contains() {
    local haystack="$1" needle="$2"
    case "$haystack" in
        *"$needle"*) printf 'assertion failed: did not expect [%s] in:\n%s\n' "$needle" "$haystack" >&2
                     exit 1 ;;
    esac
}

# assert_status <expected> <cmd...>: runs the command in a subshell (so `exit`
# and `die` do not end the test) and compares its exit status. The command's
# stdout and stderr are kept in $LAST_OUT and $LAST_ERR files. The subshell
# runs with `set -e` like the release scripts do: a command on the left of
# `||` would run with errexit disabled, so the status is read with errexit
# switched off around the subshell instead.
assert_status() {
    local expected="$1" actual errexit=false
    shift
    case "$-" in *e*) errexit=true ;; esac
    set +e
    (set -e; "$@") >"$LAST_OUT" 2>"$LAST_ERR"
    actual=$?
    [ "$errexit" = "false" ] || set -e
    if [ "$expected" != "$actual" ]; then
        printf 'assertion failed: exit status of [%s]\n  expected: %s\n  actual:   %s\n  stdout: %s\n  stderr: %s\n' \
            "$*" "$expected" "$actual" "$(cat "$LAST_OUT")" "$(cat "$LAST_ERR")" >&2
        exit 1
    fi
}

# make_stub <name> <script-body>: creates an executable named <name> in
# $STUB_DIR, which is first on PATH. The body runs under /bin/bash; $CALL_LOG
# is a shared file stubs can append their invocations to.
make_stub() {
    local name="$1" body="$2"
    printf '#!/bin/bash\n%s\n' "$body" >"$STUB_DIR/$name"
    chmod +x "$STUB_DIR/$name"
}

# make_git_repo [dir]: initialises a repository with one commit and prints its
# path. Without an argument a new directory below $TEST_TMP is used.
make_git_repo() {
    local dir="${1:-}"
    if [ -z "$dir" ]; then
        dir="$(mktemp -d "$TEST_TMP/repo.XXXXXX")"
    fi
    mkdir -p "$dir"
    git -C "$dir" init -q
    echo "initial" >"$dir/README"
    git -C "$dir" add README
    git -C "$dir" commit -q -m "initial"
    printf '%s\n' "$dir"
}

# --- runner ----------------------------------------------------------------

run_test() {
    local file="$1" name="$2"
    TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/release-test.XXXXXX")"
    STUB_DIR="$TEST_TMP/bin"
    CALL_LOG="$TEST_TMP/calls.log"
    LAST_OUT="$TEST_TMP/last.out"
    LAST_ERR="$TEST_TMP/last.err"
    mkdir -p "$STUB_DIR"
    : >"$CALL_LOG"
    printf '[user]\n\tname = Release Test\n\temail = test@example.com\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n[tag]\n\tgpgsign = false\n[advice]\n\tdetachedHead = false\n' \
        >"$TEST_TMP/gitconfig"
    (
        export TEST_TMP STUB_DIR CALL_LOG LAST_OUT LAST_ERR
        export PATH="$STUB_DIR:$PATH"
        # Every GIT_* variable of the caller (GIT_DIR, GIT_WORK_TREE,
        # GIT_INDEX_FILE, ... set by git hooks) would redirect the tests'
        # git calls.
        for var in $(compgen -e); do
            case "$var" in GIT_*) unset "$var" ;; esac
        done
        export GIT_CONFIG_GLOBAL="$TEST_TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
        # Release variables and the control variables of the stubs.
        unset SIGN_IDENTITY SIGN_IDENTITY_NAME NOTARY_PROFILE ALLOW_ADHOC ALLOW_TIER_DOWNGRADE REPLACE \
            TAP_REPO GH_REPO APP_ICON VERSION DISTRIBUTION NOTARIZE RELEASE_ROOT CASK_TEMPLATE \
            BUILD_APP_SH MAKE_DMG_SH NOTARIZE_SH UPDATE_CASK_SH \
            GH_AUTH_STATUS GH_RELEASE_EXISTS GH_RELEASE_DRAFT GH_FAIL_ON GH_VIEW_STATUS \
            GH_DOWNLOAD_STATUS GH_DOWNLOAD_NOTHING GH_RELEASE_TAGS NOTARY_OK NOTARY_ERROR \
            NOTARIZE_STATUS CASK_STATUS STALE_SHA GH_LIST_STATUS UPDATE_CASK_SH_REAL \
            UPDATE_TEST UPDATE_SOURCE
        cd "$TEST_TMP" || exit 1
        set -euo pipefail
        # shellcheck source=/dev/null
        . "$file"
        "$name"
    ) >"$TEST_TMP/output" 2>&1
    local status=$?
    local label
    label="$(basename "$file" .sh)::$name"
    if [ "$status" -eq 0 ]; then
        printf 'ok   %s\n' "$label"
        passed=$((passed + 1))
    else
        printf 'FAIL %s\n' "$label"
        sed 's/^/     /' "$TEST_TMP/output"
        failed=$((failed + 1))
    fi
    rm -rf "$TEST_TMP"
}

passed=0
failed=0

for file in "$TESTS_DIR"/test_*.sh; do
    [ -f "$file" ] || continue
    # Test functions in file order, including one-line ones such as
    # `test_x() { ...; }`.
    for name in $(sed -n 's/^\(test_[A-Za-z0-9_]*\)[[:space:]]*().*$/\1/p' "$file"); do
        if [ -n "$FILTER" ]; then
            case "$name" in *"$FILTER"*) ;; *) continue ;; esac
        fi
        run_test "$file" "$name"
    done
done

printf '%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
