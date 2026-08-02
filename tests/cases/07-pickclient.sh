#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

export POTAD_BIN_DIR="$POTAD_TMP/bin"
mkdir -p "$POTAD_BIN_DIR"

_make_bin() {
    printf '#!/bin/sh\n%s\n' "$2" > "$POTAD_BIN_DIR/$1"
    chmod 0755 "$POTAD_BIN_DIR/$1"
}

# Both link: r72 wins.
_make_bin update_engine_client_r72 'echo "usage: update_engine_client"; exit 0'
_make_bin update_engine_client_r28 'echo "usage: update_engine_client"; exit 0'
_got=$(potad_pick_client) || fail "expected a client to be picked"
[ "$_got" = "$POTAD_BIN_DIR/update_engine_client_r72" ] || fail "expected r72, got $_got"

# r72 cannot link: falls back to r28.
_make_bin update_engine_client_r72 'echo "CANNOT LINK EXECUTABLE: libfoo.so not found" >&2; exit 1'
_got=$(potad_pick_client) || fail "expected fallback to r28"
[ "$_got" = "$POTAD_BIN_DIR/update_engine_client_r28" ] || fail "expected r28, got $_got"

# Neither links: returns 1, prints nothing.
_make_bin update_engine_client_r28 'echo "CANNOT LINK EXECUTABLE: libbar.so not found" >&2; exit 1'
if _got=$(potad_pick_client); then
    fail "expected failure when neither binary links, got $_got"
fi
[ -z "$_got" ] || fail "expected empty output on failure, got $_got"

exit 0
