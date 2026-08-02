#!/bin/sh
# shellcheck disable=SC1091  # sourced file path is computed at runtime
. "$(dirname -- "$0")/_common.sh"

export POTAD_STUB_PM_DUMP="$POTAD_TEST_ROOT/tests/fixtures/gms-dump.txt"

# Happy path: probes, then disables seed union discovered.
sh "$POTAD_MODDIR/service.sh" || fail "service.sh must exit 0"
assert_call "pm disable com.google.android.gms/.update.SystemUpdateActivity"
assert_call "pm disable com.google.android.gms/.update.SystemUpdateService"
assert_call "pm disable com.google.android.gsf/.update.SystemUpdateService"
assert_call "pm disable com.google.android.gms/.update.SystemUpdateRenamedInAndroid17"
assert_no_call "pm disable com.google.android.gms/.chimera.PlayUpdateService"
assert_log "layer A:"

# N1: package manager never comes up. Must still exit 0 and touch nothing.
: > "$POTAD_TEST_CALLS"
rm -f "$POTAD_ROOT/potad.log"
export POTAD_STUB_PM_READY=0
sh "$POTAD_MODDIR/service.sh" || fail "service.sh must exit 0 even on boot timeout"
assert_no_call "pm disable "
assert_log "timed out"

exit 0
