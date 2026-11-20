#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"

# 1. Active current mount -> unmounts target, removes module and unused legacy hosts, exits 0.
: > "$POTAD_MODDIR/hosts"
: > "$POTAD_ROOT/hosts"
printf '10 1 254:52 / / rw - ext4 /dev/root rw\n21 10 254:52 %s %s rw - ext4 /dev/root rw\n' \
    "$POTAD_MODDIR/hosts" "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
printf '/dev/root %s ext4 rw 0 0\n' "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTS"
export POTAD_STUB_UMOUNT=ok
: > "$POTAD_TEST_CALLS"

sh "$POTAD_MODDIR/uninstall.sh" || fail "uninstall.sh must exit 0"
assert_call "umount $POTAD_HOSTS_TARGET"
[ ! -f "$POTAD_MODDIR/hosts" ] || fail "module hosts survived uninstall"
[ ! -f "$POTAD_ROOT/hosts" ] || fail "unused legacy hosts survived uninstall"

# 2. Active legacy mount -> unmounts target and removes legacy file.
: > "$POTAD_ROOT/hosts"
printf '10 1 254:52 / / rw - ext4 /dev/root rw\n21 10 254:52 %s %s rw - ext4 /dev/root rw\n' \
    "$POTAD_ROOT/hosts" "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
: > "$POTAD_TEST_CALLS"

sh "$POTAD_MODDIR/uninstall.sh" || fail "uninstall.sh with legacy mount must exit 0"
assert_call "umount $POTAD_HOSTS_TARGET"
[ ! -f "$POTAD_ROOT/hosts" ] || fail "legacy hosts survived uninstall after umount"

# 3. Failed unmount -> logs WARN, keeps mounted backing file, still exits 0.
export POTAD_STUB_UMOUNT=fail
: > "$POTAD_MODDIR/hosts"
printf '10 1 254:52 / / rw - ext4 /dev/root rw\n21 10 254:52 %s %s rw - ext4 /dev/root rw\n' \
    "$POTAD_MODDIR/hosts" "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
rm -f "$POTAD_ROOT/potad.log"

sh "$POTAD_MODDIR/uninstall.sh" || fail "uninstall.sh must exit 0 on umount failure"
assert_log "WARN"
[ -f "$POTAD_MODDIR/hosts" ] || fail "mounted module hosts removed even though umount failed"

# 4. Third-party other mount -> never calls umount, removes module hosts, keeps buried legacy.
: > "$POTAD_MODDIR/hosts"
: > "$POTAD_ROOT/hosts"
printf '10 1 254:52 / / rw - ext4 /dev/root rw\n21 10 254:52 %s %s rw - ext4 /dev/root rw\n22 10 254:52 /adb/modules/hosts/system/etc/hosts %s rw - ext4 /dev/root rw\n' \
    "$POTAD_ROOT/hosts" "$POTAD_HOSTS_TARGET" "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
: > "$POTAD_TEST_CALLS"

sh "$POTAD_MODDIR/uninstall.sh" || fail "uninstall.sh with third-party mount must exit 0"
assert_no_call "umount"
[ ! -f "$POTAD_MODDIR/hosts" ] || fail "module hosts not removed during third-party uninstall"
[ -f "$POTAD_ROOT/hosts" ] || fail "buried legacy hosts deleted while still mounted"

# 5. No mount at all -> no umount attempted, cleans files, exits 0.
: > "$POTAD_MOUNTS"
: > "$POTAD_MOUNTINFO"
: > "$POTAD_MODDIR/hosts"
: > "$POTAD_ROOT/hosts"
: > "$POTAD_TEST_CALLS"

sh "$POTAD_MODDIR/uninstall.sh" || fail "uninstall.sh without mounts must exit 0"
assert_no_call "umount"
[ ! -f "$POTAD_MODDIR/hosts" ] || fail "module hosts not removed"
[ ! -f "$POTAD_ROOT/hosts" ] || fail "legacy hosts not removed"

exit 0
