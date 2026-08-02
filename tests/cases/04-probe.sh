#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

export POTAD_STUB_PM_DUMP="$POTAD_TEST_ROOT/tests/fixtures/gms-dump.txt"

potad_probe || fail "probe must always return 0"

# Auto class: matches .update.System*, recorded and logged as auto.
grep -qxF "com.google.android.gms/.update.SystemUpdateRenamedInAndroid17" "$POTAD_DISCOVERED" \
    || fail "renamed SystemUpdate component was not auto-discovered"
assert_log "auto com.google.android.gms/.update.SystemUpdateRenamedInAndroid17"

# Review class: must be logged only, never written to discovered.list.
assert_log "NEW: com.google.android.gms/.chimera.PlayUpdateService"
grep -qF "PlayUpdateService" "$POTAD_DISCOVERED" \
    && fail "PlayUpdateService must never be auto-disabled - breaks Play Store updates"
grep -qF "AppUpdateService" "$POTAD_DISCOVERED" \
    && fail "AppUpdateService must never be auto-disabled"
assert_log "NEW: com.google.android.gms/.update.phone.PopupDialog"

# Idempotence: a second probe adds no duplicates.
_before=$(wc -l < "$POTAD_DISCOVERED")
potad_probe
_after=$(wc -l < "$POTAD_DISCOVERED")
[ "$_before" = "$_after" ] || fail "probe not idempotent: $_before -> $_after"

# Probe is a no-op, not a crash, when the package manager is down.
: > "$POTAD_TEST_CALLS"
export POTAD_STUB_PM_READY=0
potad_probe || fail "probe must return 0 when pm is unavailable"
assert_log "probe skipped"

# Union: seed list plus discovered, de-duplicated.
export POTAD_STUB_PM_READY=1
_all=$(potad_read_components)
printf '%s\n' "$_all" | grep -qxF "com.google.android.gms/.update.SystemUpdateActivity" \
    || fail "seed entry missing from union"
printf '%s\n' "$_all" | grep -qxF "com.google.android.gms/.update.SystemUpdateRenamedInAndroid17" \
    || fail "discovered entry missing from union"
printf '%s\n' "$_all" | grep -qF "#" && fail "comments not stripped"
[ "$(printf '%s\n' "$_all" | grep -cxF "com.google.android.gms/.update.SystemUpdateActivity")" = "1" ] \
    || fail "union not de-duplicated"

exit 0
