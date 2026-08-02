#!/bin/sh
# The /data/adb file-descriptor rule (F9) and the dump cache that depends on it.
#
# `pm` hands its own stdin/stdout to system_server over binder, and
# system_server is denied read and write on u:object_r:adb_data_file:s0 - the
# label of everything under /data/adb. A pm call whose fds point there fails
# with "Failed transaction (2147483646)". That is a property of the device's
# SELinux policy, so no stub can reproduce it: the first half of this case
# pins the shape of the source instead, which is what the runtime behaviour
# actually depends on.
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"

_scripts="$POTAD_MODDIR/action.sh $POTAD_MODDIR/service.sh $POTAD_MODDIR/customize.sh
$POTAD_MODDIR/post-fs-data.sh $POTAD_MODDIR/restore.sh $POTAD_MODDIR/common/functions.sh"

# Every pm invocation must close stdin. Without </dev/null a pm call inside a
# `while read ... done < list` loop inherits a /data/adb file as stdin - the
# 0.2 bug that made restore fail for every single component.
# shellcheck disable=SC2013
for _f in $_scripts; do
    _bad=$(grep -n '^[^#]*[^_a-zA-Z]pm ' "$_f" | grep -v '</dev/null')
    [ -z "$_bad" ] || fail "pm call without </dev/null in $(basename "$_f"): $_bad"
done

# `pm dump` must never be redirected straight into a file: the shell would
# hand system_server a write fd under /data/adb and the dump would come back
# as a single error line. potad_pm_dump pipes through cat so the shell owns
# the write.
for _f in $_scripts; do
    # Drop stderr redirects, then look at what is left before the first pipe:
    # a `>` there means the dump is being written by system_server, not by us.
    _bad=$(grep -n 'pm dump' "$_f" \
        | grep -v '^[0-9]*:[[:space:]]*#' \
        | sed -e 's/2>&1//g' -e 's|2>/dev/null||g' -e 's/|.*$//' \
        | grep '>')
    [ -z "$_bad" ] \
        || fail "pm dump redirected to a file in $(basename "$_f"): $_bad"
done
# shellcheck disable=SC2016  # matching source text literally, not expanding it
grep -q 'pm dump "$_pkg" </dev/null 2>/dev/null | cat > "$_f"' "$POTAD_MODDIR/common/functions.sh" \
    || fail "potad_pm_dump must pipe through cat, not redirect"

. "$POTAD_MODDIR/common/functions.sh"

# --- Dump cache -------------------------------------------------------------
export POTAD_STUB_PM_DUMP="$POTAD_TEST_ROOT/tests/fixtures/gms-dump.txt"

_d1=$(potad_pm_dump com.google.android.gms) || fail "first dump failed"
_d2=$(potad_pm_dump com.google.android.gms) || fail "second dump failed"
[ "$_d1" = "$_d2" ] || fail "cache handed out two different paths: $_d1 vs $_d2"
[ "$(grep -c '^pm dump' "$POTAD_TEST_CALLS")" = "1" ] \
    || fail "package dumped more than once; the action path is slow again"

potad_dump_cleanup
[ -f "$_d1" ] && fail "cleanup left $_d1 behind"

# Every entry point that dumps must also clean up. A cached GMS dump is a few
# megabytes; leaking one per action-button press fills /data/adb.
sh "$POTAD_MODDIR/service.sh" || fail "service.sh must exit 0"
_leaked=$(find "$POTAD_ROOT" -name '.dump.*' 2>/dev/null)
[ -z "$_leaked" ] || fail "service.sh leaked cached dumps: $_leaked"

# --- Snapshot honesty -------------------------------------------------------
# A probe that could not dump a single package does not know the pre-POTAD
# state. It must remove the snapshot rather than leave an empty one behind:
# an empty file reads as "nothing was disabled before POTAD", which would make
# every component POTAD disables look restorable - including the ones the user
# disabled themselves.
export POTAD_STUB_PM_DUMP=""
: > "$POTAD_TEST_CALLS"
printf '%s\n' "com.google.android.gms/.update.WasAlreadyOff" > "$POTAD_PREDISABLED"

potad_probe || fail "probe must return 0 when dumps fail"
[ -f "$POTAD_PREDISABLED" ] && fail "stale/empty snapshot survived a failed probe"
assert_log "no package dump succeeded"

# And with no snapshot, nothing may be recorded as restorable.
: > "$POTAD_RESTORE"
potad_record_restore "com.google.android.gms/.update.SystemUpdateService"
[ -s "$POTAD_RESTORE" ] && fail "recorded a restorable component with no snapshot"
assert_log "no pre-disabled snapshot"

exit 0
