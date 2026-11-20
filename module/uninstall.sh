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
_kind=$(potad_hosts_mount_kind)
_still_mounted=""
case "$_kind" in
    current|current_deleted|legacy)
        if umount "$POTAD_HOSTS_TARGET" 2>/dev/null; then
            potad_log INFO "uninstall: unmounted $POTAD_HOSTS_TARGET"
        else
            potad_log WARN "uninstall: could not unmount $POTAD_HOSTS_TARGET; it lifts on reboot"
            _still_mounted="$_kind"
        fi
        ;;
    unknown)
        if potad_hosts_entries_present; then
            if umount "$POTAD_HOSTS_TARGET" 2>/dev/null; then
                potad_log INFO "uninstall: unmounted $POTAD_HOSTS_TARGET"
            else
                potad_log WARN "uninstall: could not unmount $POTAD_HOSTS_TARGET; it lifts on reboot"
                _still_mounted="unknown"
            fi
        fi
        ;;
    other)
        potad_log INFO "uninstall: leaving third-party hosts mount intact"
        ;;
esac

case "$_still_mounted" in
    current|current_deleted|unknown) ;;
    *) rm -f "$POTAD_HOSTS_MERGED" 2>/dev/null ;;
esac

case "$_still_mounted" in
    legacy|unknown) ;;
    *)
        if [ "$_kind" = "legacy" ] || ! potad_hosts_legacy_mounted; then
            rm -f "$POTAD_HOSTS_LEGACY" 2>/dev/null
        fi
        ;;
esac

potad_log INFO "module removed; OTA components are still disabled"
potad_log INFO "to restore them, run: sh $POTAD_ROOT/restore.sh"
potad_log INFO "=== POTAD uninstalled ==="
exit 0
