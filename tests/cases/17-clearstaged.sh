#!/bin/sh
# Gap 3: --cancel reported "nothing staged" on the live device while
# /data/ota_package held a payload dated before POTAD was installed, and
# update_engine fed itself from it. Clear the directory - by whitelist only,
# because a deletion path on a user's device has to be auditable.
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

export POTAD_OTA_PACKAGE_DIR="$POTAD_TMP/ota_package"
mkdir -p "$POTAD_OTA_PACKAGE_DIR/subdir"

# Known OTA artifacts, with sizes chosen so the freed-bytes report is exact.
printf '1234567890' > "$POTAD_OTA_PACKAGE_DIR/payload_metadata.bin"
printf '12345' > "$POTAD_OTA_PACKAGE_DIR/metadata.pb"
printf 'x' > "$POTAD_OTA_PACKAGE_DIR/payload_properties.txt"
# Not on the whitelist: must survive, and must be logged.
printf 'keep me' > "$POTAD_OTA_PACKAGE_DIR/random.bin"

_out=$(potad_clear_staged_package) || fail "clear must return 0"

[ ! -e "$POTAD_OTA_PACKAGE_DIR/payload_metadata.bin" ] || fail "whitelisted file survived"
[ ! -e "$POTAD_OTA_PACKAGE_DIR/metadata.pb" ] || fail "whitelisted file survived"
[ ! -e "$POTAD_OTA_PACKAGE_DIR/payload_properties.txt" ] || fail "whitelisted file survived"
[ -f "$POTAD_OTA_PACKAGE_DIR/random.bin" ] || fail "unrecognised file was deleted"
[ -d "$POTAD_OTA_PACKAGE_DIR/subdir" ] || fail "subdirectory was touched"
[ -d "$POTAD_OTA_PACKAGE_DIR" ] || fail "the directory itself must survive"
assert_log "left alone (unrecognised)"
printf '%s\n' "$_out" | grep -qF "removed 3 file(s), freed 16 bytes" \
    || fail "count/bytes report wrong: $_out"

# A missing directory is the normal case on a device with nothing staged.
rm -rf "$POTAD_OTA_PACKAGE_DIR"
potad_clear_staged_package || fail "missing directory must return 0"

# Restore must never reach this: it has to work after the module directory is
# gone, and a re-downloadable cache is not something restore should undo.
grep -q "potad_clear_staged_package\|OTA_PACKAGE" "$POTAD_MODDIR/restore.sh" \
    && fail "restore.sh references the staged-package clear"

exit 0
