# Fixtures shared by the signing, build, preflight, release flow and cask
# tests. Sourced by test files; the runner only runs files named test_*.sh.

SELF_SIGNED_HASH="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
DEVELOPER_ID_HASH="1111111111111111111111111111111111111111"

# stub_security <tier>: `security find-identity` lists a self-signed
# certificate (self-signed), a Developer ID certificate (developer-id) or
# nothing (ad-hoc).
stub_security() {
    local listing=""
    case "$1" in
        self-signed) listing="  1) $SELF_SIGNED_HASH \"AgentTacho Signing\" (CSSMERR_TP_NOT_TRUSTED)" ;;
        developer-id) listing="  1) $DEVELOPER_ID_HASH \"Developer ID Application: Roland Huss (TEAM123456)\"" ;;
    esac
    printf 'Policy: Code Signing\n  Matching identities\n%s\n\n  Valid identities only\n' "$listing" >"$TEST_TMP/identities.txt"
    make_stub security "
echo \"security \$*\" >>\"$CALL_LOG\"
[ \"\$1\" = find-identity ] && cat \"$TEST_TMP/identities.txt\""
}

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

# stub_gh: records every call. Behaviour is controlled by environment
# variables read when the stub runs:
#   GH_AUTH_STATUS     exit status of `gh auth status` (default 0)
#   GH_RELEASE_EXISTS  1: `gh release view` succeeds (default: not found)
#   GH_RELEASE_DRAFT   value printed for `--json isDraft` (default false)
#   GH_FAIL_ON         substring of the arguments that makes the call fail
#   GH_RELEASE_TAGS    tags printed by `gh release list` (default none)
stub_gh() {
    make_stub gh "
echo \"gh \$*\" >>\"$CALL_LOG\"
if [ -n \"\${GH_FAIL_ON:-}\" ]; then
    case \"\$*\" in *\"\$GH_FAIL_ON\"*) echo \"gh: simulated failure\" >&2; exit 1 ;; esac
fi
case \"\$1 \$2\" in
    'auth status')
        [ \"\${GH_AUTH_STATUS:-0}\" = 0 ] || echo 'You are not logged into any GitHub hosts. To log in, run: gh auth login' >&2
        exit \"\${GH_AUTH_STATUS:-0}\" ;;
    'release view')
        [ \"\${GH_RELEASE_EXISTS:-0}\" = 1 ] || { echo 'release not found' >&2; exit 1; }
        case \"\$*\" in *isDraft*) echo \"\${GH_RELEASE_DRAFT:-false}\" ;; esac
        exit 0 ;;
    'release list')
        printf '%s\\n' \${GH_RELEASE_TAGS:-}
        exit 0 ;;
esac
exit 0"
}

# setup_release_repo: a work repository with a bare `origin` (main pushed) and
# a bare tap repository exported as TAP_REPO. Leaves the current directory in
# the work repository and prints nothing.
setup_release_repo() {
    local origin="$TEST_TMP/origin.git" work="$TEST_TMP/work"
    git init -q --bare "$origin"
    make_git_repo "$work" >/dev/null
    git -C "$work" remote add origin "$origin"
    git -C "$work" push -q origin main
    git init -q --bare "$TEST_TMP/tap.git"
    TAP_REPO="$TEST_TMP/tap.git"
    GH_REPO="example/agenttacho"
    export TAP_REPO GH_REPO
    cd "$work"
}

# tag_and_push <tag> [annotated]: tags HEAD and pushes the tag to origin.
tag_and_push() {
    if [ "${2:-}" = annotated ]; then
        git tag -a "$1" -m "release $1"
    else
        git tag "$1"
    fi
    git push -q origin "$1"
}

# line_of <pattern>: line number of the first call-log entry containing the
# pattern, or 0.
line_of() {
    local n
    n="$(grep -nF -- "$1" "$CALL_LOG" | head -n 1 | cut -d: -f1)"
    echo "${n:-0}"
}
