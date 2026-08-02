#!/system/bin/sh
# POTAD install-time setup.
# shellcheck disable=SC2154  # MODPATH and ui_print come from the installer

POTAD_MODDIR="$MODPATH"
export POTAD_MODDIR
# shellcheck disable=SC1091  # sourced file path is computed at runtime
. "$MODPATH/common/functions.sh"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/bin/update_engine_client_r28" 0 0 0755
set_perm "$MODPATH/bin/update_engine_client_r72" 0 0 0755

mkdir -p "$POTAD_ROOT"
chmod 0700 "$POTAD_ROOT"

# D4: restore.sh lives outside the module directory so it still works after
# the module itself is removed - the exact scenario it exists for.
cp "$MODPATH/restore.sh" "$POTAD_ROOT/restore.sh"
chmod 0700 "$POTAD_ROOT/restore.sh"

potad_detect_env
potad_log INFO "=== POTAD 0.1.1 installed ==="
potad_log INFO "manager=$POTAD_MGR model=$(getprop ro.product.model) android=$(getprop ro.build.version.release)"

ui_print "- POTAD 0.1.1"
ui_print "- Root manager: $POTAD_MGR"

# Best-effort: an install from recovery has no working package manager, in
# which case the probe skips and service.sh covers it on the next boot.
potad_probe
_discovered=0
[ -f "$POTAD_DISCOVERED" ] && _discovered=$(wc -l < "$POTAD_DISCOVERED")

potad_dump_cleanup

ui_print "- Auto-discovered OTA components: $_discovered"
if [ "$POTAD_N_NEW" -gt 0 ]; then
    ui_print "- $POTAD_N_NEW more flagged for review (see log)"
fi
ui_print "- Log: $POTAD_LOG"
ui_print "- Reboot to activate, then use the action button to clear staged OTAs"
ui_print "- Undo: action button -> Vol Down, or: sh $POTAD_ROOT/restore.sh"
