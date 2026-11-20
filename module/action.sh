#!/system/bin/sh
# POTAD action button: status report, then a volume-key choice (D1):
#   Vol Up   -> Block   - clear staged OTA, re-apply layer A (v0.1 behaviour)
#   Vol Down -> Restore - undo everything POTAD changed
#   timeout  -> Block   - the safe default; an accidental unblock is worse
#                         than an accidental re-block
MODDIR=${0%/*}
# shellcheck disable=SC1091  # sourced file path is computed at runtime
. "$MODDIR/common/functions.sh"

potad_detect_env

potad_out "POTAD 0.2.1 - Pixel OTA Disabler"
potad_out "Root manager: $POTAD_MGR"
potad_out ""

# --- Status -----------------------------------------------------------------
potad_out "Status"
potad_verify_hosts
potad_report_update_check

# One `pm dump` per package, not per component. The GMS dump is ~50k lines
# and takes seconds; dumping it once per entry in components.list made the
# status report take half a minute. potad_pm_dump caches per process, so the
# probe further down reuses these same files.
#
# Report the real state per component, not "present" - presence says nothing
# about whether the block is actually on, which is the one question this
# section exists to answer.
for _pkg in $POTAD_PROBE_PKGS; do
    _dump=$(potad_pm_dump "$_pkg") || continue
    # shellcheck disable=SC2013
    for _comp in $(potad_read_components); do
        case "$_comp" in "$_pkg"/*) ;; *) continue ;; esac
        _state=$(potad_component_state "$_dump" "$_comp")
        case "$_state" in
            absent)  ;; # nothing on this build, nothing to say
            enabled) potad_out "  ENABLED: $_comp" ;;
            *)       potad_out "  $_state: $_comp" ;;
        esac
    done
done
potad_out ""

# --- Choose: Block or Restore -----------------------------------------------
potad_out "[Vol Up]   Block   - clear staged OTA, re-apply the block"
potad_out "[Vol Down] Restore - undo everything POTAD changed"
potad_out "[no press] Block    - safe default after 15s"
potad_out ""

potad_choose 15
_choice=$?
case "$_choice" in
    1)
        potad_out "Restore selected."
        if [ -f "$POTAD_ROOT/restore.sh" ]; then
            potad_dump_cleanup
            exec "$POTAD_ROOT/restore.sh"
        fi
        # The user asked to undo; falling through to Block would re-apply the
        # very thing they asked to remove. Stop here instead.
        potad_out "ERROR: $POTAD_ROOT/restore.sh is missing - nothing changed"
        potad_log ERROR "restore selected but $POTAD_ROOT/restore.sh is missing"
        exit 0
        ;;
    2)
        potad_out "No key pressed - defaulting to Block."
        ;;
    *)
        potad_out "Block selected."
        ;;
esac
potad_out ""

# --- Layer C: clear any staged OTA ------------------------------------------
potad_out "Clearing staged OTA"
if _client=$(potad_pick_client); then
    potad_out "  using $(basename "$_client")"
    potad_run_client "$_client" --cancel
    potad_run_client "$_client" --reset_status
else
    potad_out "  ERROR: neither update_engine_client binary links on this device"
    potad_log ERROR "layer C skipped: no usable client binary"
fi
# Outside the branch on purpose: --cancel only clears update_engine's
# in-memory view, and the payload files on disk survive it - update_engine
# fed itself from a pre-POTAD payload that way. Deleting files needs no
# client binary, and a device where neither binary links is exactly the one
# that most needs the on-disk half to still happen.
potad_clear_staged_package
potad_out ""

# --- Probe + re-apply layer A -----------------------------------------------
potad_out "Re-applying block"
potad_probe
# shellcheck disable=SC2013
for _comp in $(potad_read_components); do
    potad_disable_component "$_comp"
done
potad_verify_components
potad_out "  $POTAD_N_DISABLED disabled, $POTAD_N_ABSENT absent, $POTAD_N_FAILED failed, $POTAD_N_VERIFIED verified, $POTAD_N_REENABLED re-enabled"

# --- Layer B: re-apply the hosts blackhole ----------------------------------
# Restore lifts the bind mount, and post-fs-data only runs at boot, so without
# this a Block after a Restore would leave the endpoints reachable until the
# next reboot. potad_apply_hosts is a no-op when the mount is already live.
if potad_apply_hosts; then
    potad_out "  hosts blackhole: active"
else
    potad_out "  hosts blackhole: FAILED - reboot to re-apply"
fi

if [ "$POTAD_N_NEW" -gt 0 ]; then
    potad_out ""
    potad_out "$POTAD_N_NEW update-related component(s) found that POTAD did not touch."
    potad_out "See NEW: lines in $POTAD_LOG - report them if OTAs still get through."
fi

potad_out ""
potad_out "Done. Log: $POTAD_LOG"

potad_dump_cleanup

# KernelSU and APatch close the dialog as soon as the script exits. The hold
# comes after the chooser so the user is not made to wait before being asked.
# Credit: @osm0sis, carried over from clear_ota_updates.
if { [ "${KSU:-}" = "true" ] || [ "${APATCH:-}" = "true" ]; } &&
   [ "${KSU_NEXT:-}" != "true" ] && [ "${MMRL:-}" != "true" ]; then
    potad_out ""
    potad_out "Closing dialog in 20 seconds ..."
    sleep 20
fi

exit 0
