#!/bin/sh
# Layer B is re-appliable without a reboot. Restore lifts the bind mount and
# post-fs-data only runs at boot, so a Block after a Restore has to put the
# blackhole back itself.
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

printf '127.0.0.1 localhost\n127.0.0.1 ads.example\n' > "$POTAD_HOSTS_TARGET"

potad_apply_hosts || fail "first apply failed"
assert_call "mount -o bind"
grep -qxF "127.0.0.1 ota.googlezip.net" "$POTAD_HOSTS_MERGED" || fail "blackhole entry missing"
grep -qxF "127.0.0.1 ads.example" "$POTAD_HOSTS_MERGED" || fail "other module's entry was dropped"

# With the mount live, $POTAD_HOSTS_TARGET and $POTAD_HOSTS_MERGED are the
# same inode on device. Re-applying must be a no-op, not a copy of the file
# onto itself - that would truncate the mount source and empty the hosts file.
cp "$POTAD_HOSTS_MERGED" "$POTAD_HOSTS_TARGET"
printf 'tmpfs %s tmpfs rw 0 0\n' "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTS"
: > "$POTAD_TEST_CALLS"

potad_apply_hosts || fail "re-apply over a live mount must succeed"
assert_no_call "mount -o bind"
assert_log "layer B: already active"
grep -qxF "127.0.0.1 ads.example" "$POTAD_HOSTS_MERGED" || fail "re-apply clobbered the merged file"

# After a restore: mount gone, merged file deleted, hosts back to stock. The
# Block path must rebuild both.
: > "$POTAD_MOUNTS"
rm -f "$POTAD_HOSTS_MERGED"
printf '127.0.0.1 localhost\n' > "$POTAD_HOSTS_TARGET"
: > "$POTAD_TEST_CALLS"

potad_apply_hosts || fail "re-apply after restore failed"
assert_call "mount -o bind"
grep -qxF "127.0.0.1 ota.googlezip.net" "$POTAD_HOSTS_MERGED" \
    || fail "blackhole not rebuilt after a restore"
grep -qxF "127.0.0.1 update.googleapis.com" "$POTAD_HOSTS_MERGED" \
    || fail "second endpoint not rebuilt after a restore"

exit 0
