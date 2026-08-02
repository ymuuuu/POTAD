#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

# Log file is created under the overridden root, not /data/adb.
potad_log INFO "hello world"
[ -f "$POTAD_ROOT/potad.log" ] || fail "log file not created at POTAD_ROOT"
assert_log "[INFO] hello world"

# Levels are recorded verbatim.
potad_log ERROR "something broke"
assert_log "[ERROR] something broke"

# potad_out both prints and logs.
_printed=$(potad_out "visible line")
[ "$_printed" = "visible line" ] || fail "potad_out did not print, got: $_printed"
assert_log "[INFO] visible line"

# Rotation: force the log over the limit, then log once more.
awk 'BEGIN { while (i++ < 9000) print "0123456789012345678901234567890" }' > "$POTAD_ROOT/potad.log"
potad_log INFO "after rotation"
[ -f "$POTAD_ROOT/potad.log.1" ] || fail "log was not rotated"
assert_log "[INFO] after rotation"
grep -qF "0123456789" "$POTAD_ROOT/potad.log" && fail "rotated log still holds old content"

exit 0
