#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

_C="com.google.android.gms/.update.SystemUpdateService"

# Happy path.
potad_disable_component "$_C" || fail "disable must always return 0"
assert_call "pm disable $_C"
assert_log "disabled $_C"
[ "$POTAD_N_DISABLED" = "1" ] || fail "expected 1 disabled, got $POTAD_N_DISABLED"

# Absent component: logged as absent, no fallback attempted, still returns 0.
: > "$POTAD_TEST_CALLS"
export POTAD_STUB_PM_DISABLE=absent
potad_disable_component "$_C" || fail "absent component must return 0"
assert_log "absent $_C"
assert_no_call "pm disable-user"
[ "$POTAD_N_ABSENT" = "1" ] || fail "expected 1 absent, got $POTAD_N_ABSENT"

# Refused: falls back to disable-user --user 0 and succeeds.
: > "$POTAD_TEST_CALLS"
export POTAD_STUB_PM_DISABLE=refuse
potad_disable_component "$_C" || fail "must return 0"
assert_call "pm disable-user --user 0 $_C"
assert_log "disabled (user 0) $_C"
[ "$POTAD_N_DISABLED" = "2" ] || fail "expected 2 disabled, got $POTAD_N_DISABLED"

# Both refused: logged failed, still returns 0.
: > "$POTAD_TEST_CALLS"
export POTAD_STUB_PM_DISABLE=refuse_all
potad_disable_component "$_C" || fail "must return 0 even when both refuse"
assert_log "failed $_C"
[ "$POTAD_N_FAILED" = "1" ] || fail "expected 1 failed, got $POTAD_N_FAILED"

exit 0
