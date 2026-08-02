#!/bin/sh
# shellcheck disable=SC1091  # sourced file path is computed at runtime
. "$(dirname -- "$0")/_common.sh"

# A pre-existing hosts file with a third-party ad-block entry.
cat > "$POTAD_HOSTS_TARGET" <<'EOF'
127.0.0.1 localhost
0.0.0.0 ads.example.com
EOF

sh "$POTAD_MODDIR/post-fs-data.sh" || fail "post-fs-data.sh must exit 0"

# Existing entries survive.
grep -qxF "127.0.0.1 localhost" "$POTAD_ROOT/hosts" || fail "localhost entry lost"
grep -qxF "0.0.0.0 ads.example.com" "$POTAD_ROOT/hosts" || fail "ad-block entry lost"

# POTAD entries added.
grep -qxF "127.0.0.1 ota.googlezip.net" "$POTAD_ROOT/hosts" || fail "ota.googlezip.net missing"
grep -qxF "127.0.0.1 update.googleapis.com" "$POTAD_ROOT/hosts" || fail "update.googleapis.com missing"

# The bind mount was attempted against the right target.
assert_call "mount -o bind $POTAD_ROOT/hosts $POTAD_HOSTS_TARGET"

# Never touches pm this early in boot.
assert_no_call "pm "

# Idempotent: running again must not duplicate entries.
cp "$POTAD_ROOT/hosts" "$POTAD_HOSTS_TARGET"
sh "$POTAD_MODDIR/post-fs-data.sh" || fail "second run must exit 0"
_n=$(grep -c "ota.googlezip.net" "$POTAD_ROOT/hosts")
[ "$_n" = "1" ] || fail "duplicate ota.googlezip.net entries: $_n"

# A hosts file with no trailing newline must not glue onto our first entry.
printf '127.0.0.1 localhost' > "$POTAD_HOSTS_TARGET"
rm -f "$POTAD_ROOT/hosts"
sh "$POTAD_MODDIR/post-fs-data.sh" || fail "must exit 0"
grep -qxF "127.0.0.1 localhost" "$POTAD_ROOT/hosts" || fail "trailing-newline handling corrupted last line"
grep -qxF "127.0.0.1 ota.googlezip.net" "$POTAD_ROOT/hosts" || fail "entry glued to previous line"

# Conflict with another module is warned about, not silently ignored.
rm -f "$POTAD_ROOT/potad.log"
printf 'tmpfs %s tmpfs rw 0 0\n' "$POTAD_HOSTS_TARGET" > "$POTAD_MOUNTS"
sh "$POTAD_MODDIR/post-fs-data.sh" || fail "must exit 0"
assert_log "already mounted"

exit 0
