#!/bin/sh
# Layer C reporting. The distinction that matters: "nothing was staged" is
# success, and must not be reported the same way as a client that genuinely
# failed - otherwise the word ERROR appears on every healthy run and stops
# meaning anything.
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

_bin="$POTAD_TMP/client"
_make() {
    printf '#!/bin/sh\n%s\n' "$1" > "$_bin"
    chmod 0755 "$_bin"
}

# Real device behaviour: exit 248 with an ERROR line, meaning nothing staged.
_make 'echo "[ERROR:update_engine_client_android.cc(316)] Status(-8, EX_SERVICE_SPECIFIC): '"'"'1: No ongoing update to cancel.'"'"'"
echo "[INFO:update_engine_client_android.cc(354)] Command took 5 ms"
exit 248'
_out=$(potad_run_client "$_bin" --cancel) || fail "nothing-staged must not be reported as failure"
printf '%s\n' "$_out" | grep -q "nothing staged" || fail "expected 'nothing staged', got: $_out"
assert_no_log "ERROR"

# Plain success.
rm -f "$POTAD_ROOT/potad.log"
_make 'echo "[INFO:update_engine_client_android.cc(354)] Command took 1209 ms"; exit 0'
_out=$(potad_run_client "$_bin" --reset_status) || fail "exit 0 must be reported as success"
printf '%s\n' "$_out" | grep -q "ok" || fail "expected ok, got: $_out"
assert_no_log "ERROR"

# A genuine failure must be loud, and must carry the exit code. This is the
# one path that echoes the client's own output, so it is also where the
# flattening matters: an unflattened second line lands in the log with no
# [timestamp] [level] prefix and corrupts the format.
rm -f "$POTAD_ROOT/potad.log"
_make 'echo "[ERROR] Status(-1, EX_TRANSACTION_FAILED)"
echo "[INFO] Command took 7 ms"
exit 1'
if potad_run_client "$_bin" --cancel >/dev/null; then
    fail "a real client failure must return non-zero"
fi
assert_log "--cancel failed (exit 1)"
assert_log "Command took 7 ms"
# Anchored on the timestamp, not just "[": the client's own lines start with
# "[INFO]" / "[ERROR]" and would sail past a bare bracket check.
_unprefixed=$(grep -cvE '^\[[0-9]{4}-' "$POTAD_ROOT/potad.log")
[ "$_unprefixed" = "0" ] || fail "client output broke the log format on $_unprefixed line(s)"

exit 0
