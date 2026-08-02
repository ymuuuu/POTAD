#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

# Vol Up -> 0 (Block).
export POTAD_STUB_GETEVENT="EV_KEY KEY_VOLUMEUP DOWN"
potad_choose 5 && _rc=0 || _rc=$?
[ "$_rc" = "0" ] || fail "expected 0 for KEY_VOLUMEUP, got $_rc"
assert_call "getevent -lqc 1"

# Vol Down -> 1 (Restore).
export POTAD_STUB_GETEVENT="EV_KEY KEY_VOLUMEDOWN DOWN"
potad_choose 5 && _rc=0 || _rc=$?
[ "$_rc" = "1" ] || fail "expected 1 for KEY_VOLUMEDOWN, got $_rc"

# A stray touch event is not a choice: consumed and ignored until the
# deadline, then 2 (timed out -> safe default).
export POTAD_STUB_GETEVENT="EV_ABS ABS_MT_POSITION_X 0034"
potad_choose 1 && _rc=0 || _rc=$?
[ "$_rc" = "2" ] || fail "expected 2 on timeout, got $_rc"

exit 0
