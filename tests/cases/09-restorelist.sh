#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

_NEW="com.google.android.gms/.update.SystemUpdateActivity"
_PRE="com.google.android.gms/.update.OtaSuggestionActivity"
_GONE="com.google.android.gms/.update.GoneFromThisBuild"

# $_PRE was already disabled before POTAD existed (F8); the probe recorded it.
printf '%s\n' "$_PRE" > "$POTAD_PREDISABLED"
export POTAD_STUB_PM_ABSENT="$_GONE"

potad_disable_component "$_NEW" || fail "disable must always return 0"
potad_disable_component "$_PRE" || fail "disable must always return 0"
potad_disable_component "$_GONE" || fail "absent component must return 0"

# All three were still attempted - blocking never depends on the snapshot.
assert_call "pm disable $_NEW"
assert_call "pm disable $_PRE"
assert_log "absent $_GONE"

# Only the component POTAD itself transitioned is restorable. Recording $_PRE
# would re-enable something the user disabled on purpose; recording $_GONE
# would be noise.
grep -qxF "$_NEW" "$POTAD_RESTORE" || fail "real transition not recorded"
grep -qF "$_PRE" "$POTAD_RESTORE" && fail "pre-disabled component must not be restorable"
grep -qF "$_GONE" "$POTAD_RESTORE" && fail "absent component must not be restorable"
[ "$(wc -l < "$POTAD_RESTORE")" = "1" ] || fail "restore.list must hold exactly one entry"

# De-dup: disabling the same component again adds no second line.
potad_disable_component "$_NEW" || fail "disable must always return 0"
[ "$(grep -cxF "$_NEW" "$POTAD_RESTORE")" = "1" ] || fail "restore.list not de-duplicated"

# A failed disable records nothing.
export POTAD_STUB_PM_DISABLE=refuse_all
potad_disable_component "com.google.android.gms/.update.Refused" || fail "must return 0"
grep -qF "Refused" "$POTAD_RESTORE" && fail "failed disable must not be restorable"
export POTAD_STUB_PM_DISABLE=ok

# Missing snapshot (probe could not run): disable still happens, nothing is
# recorded, and the WARN fires once per run, not once per component.
rm -f "$POTAD_PREDISABLED"
rm -f "$POTAD_ROOT/potad.log"
potad_disable_component "$_NEW" || fail "disable must always return 0"
potad_disable_component "com.google.android.gms/.update.SystemUpdateService" \
    || fail "disable must always return 0"
assert_call "pm disable com.google.android.gms/.update.SystemUpdateService"
[ "$(grep -c "restore data incomplete" "$POTAD_ROOT/potad.log")" = "1" ] \
    || fail "missing-snapshot WARN must fire exactly once"
grep -qF "SystemUpdateService" "$POTAD_RESTORE" \
    && fail "no snapshot means no restore.list entries"

exit 0
