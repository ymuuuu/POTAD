# Sourced by every test case. Sets up an isolated fake environment.
# shellcheck shell=sh

# shellcheck disable=SC1007  # CDPATH= prefix is an intentional env override for cd
POTAD_TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export PATH="$POTAD_TEST_ROOT/tests/stubs:$PATH"

POTAD_TMP=$(mktemp -d)
trap 'rm -rf "$POTAD_TMP"' EXIT INT TERM

export POTAD_ROOT="$POTAD_TMP/potad"
export POTAD_MODDIR="$POTAD_TEST_ROOT/module"
export POTAD_TEST_CALLS="$POTAD_TMP/calls"
export POTAD_HOSTS_TARGET="$POTAD_TMP/hosts_target"
export POTAD_MOUNTS="$POTAD_TMP/mounts"

mkdir -p "$POTAD_ROOT"
: > "$POTAD_TEST_CALLS"
: > "$POTAD_MOUNTS"

# Stub defaults: package manager up, boot complete, disable succeeds.
export POTAD_STUB_PM_READY=1
export POTAD_STUB_BOOT=1
export POTAD_STUB_PM_DISABLE=ok
export POTAD_STUB_PM_DUMP=""

fail() {
    echo "ASSERT FAILED: $*" >&2
    exit 1
}

assert_call() {
    grep -qF -- "$1" "$POTAD_TEST_CALLS" \
        || fail "expected call [$1]; calls were:$(printf '\n  %s' "$(cat "$POTAD_TEST_CALLS")")"
}

assert_no_call() {
    if grep -qF -- "$1" "$POTAD_TEST_CALLS"; then
        fail "unexpected call [$1]"
    fi
}

assert_log() {
    grep -qF -- "$1" "$POTAD_ROOT/potad.log" \
        || fail "expected log [$1]; log was:$(printf '\n  %s' "$(cat "$POTAD_ROOT/potad.log" 2>/dev/null)")"
}

assert_no_log() {
    if grep -qF -- "$1" "$POTAD_ROOT/potad.log" 2>/dev/null; then
        fail "unexpected log [$1]"
    fi
}
