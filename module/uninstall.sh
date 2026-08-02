#!/system/bin/sh
# POTAD uninstall.
#
# This script cannot re-enable anything: component disable state lives in
# /data/system/users/0/package-restrictions.xml and survives module removal
# (F1), and uninstall.sh runs before the framework is up, so there is no
# working pm at this point (F2). The v0.1 `pm enable` loop here was dead code
# that silently did nothing. Restore is a separate, deliberate step; see D5.
MODDIR=${0%/*}
# shellcheck disable=SC1091  # sourced file path is computed at runtime
. "$MODDIR/common/functions.sh"

potad_log INFO "=== POTAD uninstalling ==="
potad_log INFO "module removed; OTA components are still disabled"
potad_log INFO "to restore them, run: sh $POTAD_ROOT/restore.sh"
potad_log INFO "=== POTAD uninstalled ==="
exit 0
