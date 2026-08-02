#!/system/bin/sh
# POTAD layer B at boot. The work itself lives in potad_apply_hosts so the
# action button's Block path can re-apply the blackhole without a reboot.
#
# This script must never call pm - the package manager does not exist this
# early in boot. That was the latent bug in PixelSystemupdateBlock_v3, which
# papered over it with a backgrounded `sleep 15`.
MODDIR=${0%/*}
# shellcheck disable=SC1091  # sourced file path is computed at runtime
. "$MODDIR/common/functions.sh"

mkdir -p "$POTAD_ROOT" 2>/dev/null
chmod 0700 "$POTAD_ROOT" 2>/dev/null

potad_apply_hosts

exit 0
