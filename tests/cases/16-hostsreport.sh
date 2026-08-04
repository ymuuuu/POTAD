#!/bin/sh
# Gap 1: visibility, not blocking. android.googleapis.com stays reachable by
# design - it also carries sign-in, FCM push, Play Store and device checkin,
# so blackholing it breaks the phone. What ships instead is honest reporting:
# whether each blocked host is actually blocked, and when GMS last checked.
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

# --- potad_verify_hosts ------------------------------------------------------
# Fully healthy: both entries live in the target and the bind mount is up.
printf '127.0.0.1 localhost\n127.0.0.1 ota.googlezip.net\n127.0.0.1 update.googleapis.com\n' > "$POTAD_HOSTS_TARGET"
printf 'tmpfs %s tmpfs rw 0 0\n' "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTS"
_out=$(potad_verify_hosts)
printf '%s\n' "$_out" | grep -qF "ota.googlezip.net: blocked" \
    || fail "healthy host not reported blocked: $_out"
printf '%s\n' "$_out" | grep -qF "update.googleapis.com: blocked" \
    || fail "second healthy host not reported blocked: $_out"

# The entry without the mount means POTAD wrote a file nobody reads.
: > "$POTAD_MOUNTS"
_out=$(potad_verify_hosts)
printf '%s\n' "$_out" | grep -qF "ota.googlezip.net: hosts entry present but blackhole NOT mounted" \
    || fail "unmounted entry not reported: $_out"

# Nothing applied at all.
printf '127.0.0.1 localhost\n' > "$POTAD_HOSTS_TARGET"
_out=$(potad_verify_hosts)
printf '%s\n' "$_out" | grep -qF "ota.googlezip.net: NOT blocked (no hosts entry)" \
    || fail "missing entry not reported: $_out"

# --- potad_report_update_check ----------------------------------------------
export POTAD_GMS_UPDATE_PREFS="$POTAD_TMP/gms_update_prefs.xml"
cat > "$POTAD_GMS_UPDATE_PREFS" <<'EOF'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <long name="last_check_time_millis" value="1754301339000" />
</map>
EOF
_out=$(potad_report_update_check) || fail "present prefs must return 0"
printf '%s\n' "$_out" | grep -qE 'last update check: [0-9]{4}-[0-9]{2}-[0-9]{2}' \
    || fail "timestamp not rendered human-readable: $_out"

# Missing prefs are the normal case without root: reported at INFO, never an
# error, and the function still succeeds.
rm -f "$POTAD_GMS_UPDATE_PREFS"
_out=$(potad_report_update_check) || fail "missing prefs must return 0"
printf '%s\n' "$_out" | grep -qF "unreadable" || fail "missing prefs not reported: $_out"
assert_no_log "ERROR"

exit 0
