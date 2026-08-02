#!/bin/sh
# shellcheck disable=SC1091  # sourced file path is computed at runtime
. "$(dirname -- "$0")/_common.sh"

# Stub is on PATH and records its invocation.
pm list packages >/dev/null
assert_call "pm list packages"

# Stub honours its behaviour knob.
export POTAD_STUB_PM_DISABLE=absent
_out=$(pm disable com.example/.Foo 2>&1) && fail "expected non-zero exit"
case "$_out" in
    *"Unknown component"*) ;;
    *) fail "expected Unknown component, got: $_out" ;;
esac

# assert_no_call works.
assert_no_call "pm enable"

exit 0
