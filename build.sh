#!/bin/sh
# Builds dist/POTAD-<version>.zip from module/.
set -eu

# shellcheck disable=SC1007  # CDPATH= prefix is an intentional env override for cd
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$ROOT/module"
OUT="$ROOT/dist"

[ -f "$SRC/module.prop" ] || { echo "error: $SRC/module.prop not found" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "error: zip not installed" >&2; exit 1; }

VERSION=$(sed -n 's/^version=//p' "$SRC/module.prop")
[ -n "$VERSION" ] || { echo "error: no version= in module.prop" >&2; exit 1; }

mkdir -p "$OUT"
ZIP="$OUT/POTAD-$VERSION.zip"
rm -f "$ZIP"

chmod 0755 "$SRC/action.sh" "$SRC/bin/update_engine_client_r28" "$SRC/bin/update_engine_client_r72"

# -r from inside SRC so module.prop sits at the archive root.
(cd "$SRC" && zip -r -q -X "$ZIP" . -x '.*' -x '*/.*')

echo "built $ZIP"
unzip -l "$ZIP" | sed 's/^/  /'
