#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"

_A="com.google.android.gms/.update.SystemUpdateActivity"
_B="com.google.android.gms/.update.SystemUpdateService"

_seed_state() {
    printf '%s\n%s\n' "$_A" "$_B" > "$POTAD_ROOT/restore.list"
    : > "$POTAD_ROOT/predisabled.list"
    : > "$POTAD_ROOT/discovered.list"
    : > "$POTAD_ROOT/hosts"
    : > "$POTAD_ROOT/potad.log"
}

_seed_state
sh "$POTAD_MODDIR/restore.sh" || fail "restore.sh must exit 0"

# Every recorded component is returned to its manifest default state - never
# `pm enable`, which forces ENABLED regardless of the manifest (D3).
assert_call "pm default-state $_A"
assert_call "pm default-state $_B"
assert_no_call "pm enable"
_n=$(grep -c "^pm " "$POTAD_TEST_CALLS")
[ "$_n" = "2" ] || fail "expected exactly 2 pm calls, got $_n"

# Working files are cleaned up; the log and restore.sh itself survive.
[ ! -f "$POTAD_ROOT/restore.list" ] || fail "restore.list not deleted"
[ ! -f "$POTAD_ROOT/predisabled.list" ] || fail "predisabled.list not deleted"
[ ! -f "$POTAD_ROOT/discovered.list" ] || fail "discovered.list not deleted"
[ ! -f "$POTAD_ROOT/hosts" ] || fail "hosts not deleted"
[ -f "$POTAD_ROOT/potad.log" ] || fail "potad.log must survive restore"
[ -f "$POTAD_MODDIR/restore.sh" ] || fail "restore.sh must survive its own run"
assert_log "restore done"

# The hosts file is half of what a restore restores, so its outcome is
# reported on screen next to the component count - not buried in the log.

# No hosts mount present: no umount attempted, and it says so.
assert_no_call "umount "
_seed_state
_o=$(sh "$POTAD_MODDIR/restore.sh") || fail "restore.sh must exit 0"
printf '%s\n' "$_o" | grep -q "was not blackholed" \
    || fail "an unmounted hosts file must be reported too; got: $_o"

# N2: a live hosts mount is umounted best-effort; failure is not an error.
_seed_state
: > "$POTAD_TEST_CALLS"
printf 'tmpfs %s tmpfs rw 0 0\n' "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTS"
_o=$(sh "$POTAD_MODDIR/restore.sh") || fail "umount failure must not fail restore"
assert_call "umount $POTAD_HOSTS_TARGET"
printf '%s\n' "$_o" | grep -q "could not unmount" \
    || fail "umount failure must be on screen; got: $_o"
assert_log "it lifts on reboot"

# Same, but the umount succeeds.
_seed_state
: > "$POTAD_TEST_CALLS"
export POTAD_STUB_UMOUNT=ok
_o=$(sh "$POTAD_MODDIR/restore.sh") || fail "restore.sh must exit 0"
assert_call "umount $POTAD_HOSTS_TARGET"
printf '%s\n' "$_o" | grep -q "restored $POTAD_HOSTS_TARGET" \
    || fail "a lifted blackhole must be on screen; got: $_o"
unset POTAD_STUB_UMOUNT

# Nothing recorded: explains and exits 0 without touching pm.
rm -f "$POTAD_ROOT/restore.list"
: > "$POTAD_TEST_CALLS"
_out=$(sh "$POTAD_MODDIR/restore.sh") || fail "empty restore.list must exit 0"
assert_no_call "pm "
case "$_out" in
    *"Nothing recorded to restore"*) ;;
    *) fail "expected nothing-to-restore message, got: $_out" ;;
esac

exit 0
