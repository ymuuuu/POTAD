#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

_SAVED_ROOT="$POTAD_ROOT"
_SAVED_LOG="$POTAD_LOG"
_SAVED_MODDIR="$POTAD_MODDIR"
_SAVED_MERGED="$POTAD_HOSTS_MERGED"
_SAVED_LEGACY="$POTAD_HOSTS_LEGACY"

_restore_paths() {
    export POTAD_ROOT="$_SAVED_ROOT"
    export POTAD_LOG="$_SAVED_LOG"
    export POTAD_MODDIR="$_SAVED_MODDIR"
    export POTAD_HOSTS_MERGED="$_SAVED_MERGED"
    export POTAD_HOSTS_LEGACY="$_SAVED_LEGACY"
    unset POTAD_STUB_UMOUNT
}

# 1. Post-update boot: module dir replaced (no $POTAD_MODDIR/hosts), stale legacy
#    $POTAD_ROOT/hosts on disk, no mount active -> rebuilds, binds, removes legacy.
printf '127.0.0.1 localhost\n' > "$POTAD_HOSTS_TARGET"
printf '127.0.0.1 stale\n' > "$POTAD_HOSTS_LEGACY"
rm -f "$POTAD_HOSTS_MERGED"
: > "$POTAD_MOUNTS"
: > "$POTAD_MOUNTINFO"
: > "$POTAD_TEST_CALLS"

potad_apply_hosts || fail "post-update rebuild failed"
assert_call "mount -o bind $POTAD_HOSTS_MERGED $POTAD_HOSTS_TARGET"
[ ! -f "$POTAD_HOSTS_LEGACY" ] || fail "unused legacy hosts file was not deleted"
grep -qxF "127.0.0.1 ota.googlezip.net" "$POTAD_HOSTS_MERGED" || fail "rebuilt hosts missing OTA entry"

# 2. Same-boot legacy migration with /data mountpoint resolution: legacy bind in
#    mountinfo must be unmounted BEFORE binding $POTAD_HOSTS_MERGED, and legacy deleted.
_DATA_ROOT="$POTAD_TMP/data"
mkdir -p "$_DATA_ROOT/adb/potad" "$_DATA_ROOT/adb/modules/potad"
export POTAD_ROOT="$_DATA_ROOT/adb/potad"
export POTAD_LOG="$POTAD_ROOT/potad.log"
export POTAD_MODDIR="$_DATA_ROOT/adb/modules/potad"
export POTAD_HOSTS_MERGED="$POTAD_MODDIR/hosts"
export POTAD_HOSTS_LEGACY="$POTAD_ROOT/hosts"
export POTAD_STUB_UMOUNT=ok

printf '127.0.0.1 localhost\n0.0.0.0 ads.example\n' > "$POTAD_HOSTS_TARGET"
: > "$POTAD_HOSTS_LEGACY"
printf '114 37 254:52 / %s rw - f2fs /dev/block/dm-52 rw\n218 37 254:52 /adb/potad/hosts %s rw - f2fs /dev/block/dm-52 rw\n' \
    "$_DATA_ROOT" "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
printf '/dev/block/dm-52 %s f2fs rw 0 0\n' "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTS"
: > "$POTAD_TEST_CALLS"

potad_apply_hosts || fail "same-boot legacy migration failed"
_u_line=$(grep -n "^umount $POTAD_HOSTS_TARGET$" "$POTAD_TEST_CALLS" | head -n 1 | cut -d: -f1)
_m_line=$(grep -n "^mount -o bind $POTAD_HOSTS_MERGED $POTAD_HOSTS_TARGET$" "$POTAD_TEST_CALLS" | head -n 1 | cut -d: -f1)
[ -n "$_u_line" ] || fail "legacy bind was not unmounted"
[ -n "$_m_line" ] || fail "new bind was not mounted"
[ "$_u_line" -lt "$_m_line" ] || fail "umount must happen before mount -o bind (stacked binds)"
[ ! -f "$POTAD_HOSTS_LEGACY" ] || fail "legacy file must be removed after umount"
grep -qxF "0.0.0.0 ads.example" "$POTAD_HOSTS_MERGED" || fail "ads entry lost during migration"
_restore_paths

# 3. Failed legacy unmount must refuse to stack binds and keep legacy file intact.
printf '10 1 254:52 / / rw - ext4 /dev/root rw\n21 10 254:52 %s %s rw - ext4 /dev/root rw\n' \
    "$POTAD_HOSTS_LEGACY" "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
printf '/dev/root %s ext4 rw 0 0\n' "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTS"
: > "$POTAD_HOSTS_LEGACY"
: > "$POTAD_TEST_CALLS"
rm -f "$POTAD_ROOT/potad.log"
export POTAD_STUB_UMOUNT=fail

if potad_apply_hosts; then
    fail "must return non-zero when legacy umount fails"
fi
assert_no_call "mount -o bind"
assert_log "ERROR"
[ -f "$POTAD_HOSTS_LEGACY" ] || fail "legacy file must stay when umount fails"
unset POTAD_STUB_UMOUNT

# 4. Device-root mountinfo resolution check for real /data and classic modules.img.
export POTAD_MODDIR="/data/adb/modules/potad"
export POTAD_HOSTS_MERGED="/data/adb/modules/potad/hosts"
export POTAD_ROOT="/data/adb/potad"
export POTAD_HOSTS_LEGACY="/data/adb/potad/hosts"

printf '114 37 254:52 / /data rw - f2fs /dev/dm-52 rw\n218 37 254:52 /adb/modules/potad/hosts %s rw - f2fs /dev/dm-52 rw\n' \
    "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
[ "$(potad_hosts_mount_kind)" = "current" ] || fail "failed to classify /data userdata current mount"

printf '70 37 7:1 / /data/adb/modules rw - ext4 /dev/loop1 rw\n219 37 7:1 /potad/hosts %s rw - ext4 /dev/loop1 rw\n' \
    "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
[ "$(potad_hosts_mount_kind)" = "current" ] || fail "failed to classify modules.img current mount"
_restore_paths

# Active current mount early-returns without remounting even with modules.img dev_mp.
_MODIMG="$POTAD_TMP/data_img/adb/modules"
mkdir -p "$_MODIMG/potad"
export POTAD_MODDIR="$_MODIMG/potad"
export POTAD_HOSTS_MERGED="$POTAD_MODDIR/hosts"
printf '127.0.0.1 localhost\n127.0.0.1 ota.googlezip.net\n127.0.0.1 update.googleapis.com\n' > "$POTAD_HOSTS_TARGET"
cp "$POTAD_HOSTS_TARGET" "$POTAD_HOSTS_MERGED"
printf '70 37 7:1 / %s rw - ext4 /dev/loop1 rw\n219 37 7:1 /potad/hosts %s rw - ext4 /dev/loop1 rw\n' \
    "$_MODIMG" "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
printf '/dev/loop1 %s ext4 rw 0 0\n' "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTS"
: > "$POTAD_TEST_CALLS"
rm -f "$POTAD_ROOT/potad.log"

potad_apply_hosts || fail "active current mount must succeed"
assert_no_call "umount"
assert_no_call "mount -o bind"
assert_log "layer B: already active"
_restore_paths

# 5. Deleted bind source (//deleted and \040(deleted)) unmounts stale bind and rebinds.
for _suffix in '//deleted' '\040(deleted)'; do
    printf '127.0.0.1 localhost\n' > "$POTAD_HOSTS_TARGET"
    printf '127.0.0.1 ota.googlezip.net\n127.0.0.1 update.googleapis.com\n' > "$POTAD_HOSTS_MERGED"
    printf '10 1 254:52 / / rw - ext4 /dev/root rw\n21 10 254:52 %s%s %s rw - ext4 /dev/root rw\n' \
        "$POTAD_HOSTS_MERGED" "$_suffix" "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
    printf '/dev/root %s ext4 rw 0 0\n' "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTS"
    export POTAD_STUB_UMOUNT=ok
    : > "$POTAD_TEST_CALLS"

    potad_apply_hosts || fail "current_deleted recovery failed for $_suffix"
    assert_call "umount $POTAD_HOSTS_TARGET"
    assert_call "mount -o bind $POTAD_HOSTS_MERGED $POTAD_HOSTS_TARGET"
done
unset POTAD_STUB_UMOUNT

# 6. Third-party mount stacked over a buried legacy mount:
#    must NOT unmount the third-party mount, must keep buried legacy file intact,
#    and must merge third-party hosts entries into $POTAD_HOSTS_MERGED.
printf '127.0.0.1 localhost\n0.0.0.0 adaway.example\n' > "$POTAD_HOSTS_TARGET"
: > "$POTAD_HOSTS_LEGACY"
printf '10 1 254:52 / / rw - ext4 /dev/root rw\n21 10 254:52 %s %s rw - ext4 /dev/root rw\n22 10 254:52 /adb/modules/hosts/system/etc/hosts %s rw - ext4 /dev/root rw\n' \
    "$POTAD_HOSTS_LEGACY" "$POTAD_HOSTS_TARGET" "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTINFO"
printf '/dev/root %s ext4 rw 0 0\n' "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTS"
: > "$POTAD_TEST_CALLS"
rm -f "$POTAD_ROOT/potad.log"

potad_apply_hosts || fail "third-party coexistence failed"
assert_no_call "umount"
assert_log "already mounted by another module"
[ -f "$POTAD_HOSTS_LEGACY" ] || fail "buried legacy mount source was deleted while still mounted"
grep -qxF "0.0.0.0 adaway.example" "$POTAD_HOSTS_MERGED" || fail "AdAway entry lost"
assert_call "mount -o bind $POTAD_HOSTS_MERGED $POTAD_HOSTS_TARGET"

exit 0
