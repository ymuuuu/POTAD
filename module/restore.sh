#!/system/bin/sh
# POTAD restore: return every component POTAD disabled to its manifest default
# state, lift the hosts blackhole, and remove POTAD's working files.
#
# D4: this file is deliberately standalone. It must NOT source
# common/functions.sh: the scenario it exists for is "the user removed the
# module and wants the phone back", in which case /data/adb/modules/potad -
# including common/functions.sh - is already gone. customize.sh installs a
# copy at $POTAD_ROOT/restore.sh, which survives module removal. The
# duplicated path defaults and logger below are intentional. Do not
# "deduplicate" them; that would break the exact case this file exists for.

POTAD_ROOT="${POTAD_ROOT:-/data/adb/potad}"
POTAD_LOG="$POTAD_ROOT/potad.log"
POTAD_RESTORE="$POTAD_ROOT/restore.list"
POTAD_PREDISABLED="$POTAD_ROOT/predisabled.list"
POTAD_DISCOVERED="$POTAD_ROOT/discovered.list"
POTAD_HOSTS_MERGED="$POTAD_ROOT/hosts"
POTAD_HOSTS_TARGET="${POTAD_HOSTS_TARGET:-/system/etc/hosts}"
POTAD_MOUNTS="${POTAD_MOUNTS:-/proc/mounts}"

# Three-line logger, duplicated from common/functions.sh on purpose (D4).
_log() {
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "$2" >> "$POTAD_LOG" 2>/dev/null
}

_out() {
    printf '%s\n' "$*"
    _log INFO "$*"
}

_log INFO "=== POTAD restore ==="

# restore.list holds only components POTAD itself transitioned to disabled
# (D2). Missing or empty means there is nothing to undo.
if [ ! -s "$POTAD_RESTORE" ]; then
    _out "Nothing recorded to restore."
    _out "POTAD never disabled anything that was not already disabled."
    exit 0
fi

_ok=0
_fail=0
while IFS= read -r _comp; do
    [ -n "$_comp" ] || continue
    # default-state, not enable (D3): enable forces ENABLED, default-state
    # clears POTAD's override and returns the component to its manifest state.
    #
    # </dev/null is required, not tidiness (F9). Without it pm inherits this
    # loop's stdin - $POTAD_RESTORE, a file under /data/adb - and hands that
    # fd to system_server over binder. system_server is denied read on
    # u:object_r:adb_data_file:s0, so every call fails with
    #   cmd: Failure calling service package: Failed transaction (2147483646)
    # which is exactly how restore failed for every component in 0.2.
    if _res=$(pm default-state "$_comp" </dev/null 2>&1); then
        _out "restored $_comp"
        _ok=$((_ok + 1))
    else
        _out "FAILED $_comp: ${_res:-unknown error}"
        _log ERROR "default-state failed for $_comp: ${_res:-unknown error}"
        _fail=$((_fail + 1))
    fi
done < "$POTAD_RESTORE"

# Lift the hosts blackhole without a reboot. Best-effort (N2): the mount dies
# with the next reboot anyway, so failure here is not an error. Reported with
# _out, not _log: the user asked for a restore and the hosts file is half of
# what gets restored, so every outcome - including "there was nothing to lift"
# - belongs on screen next to the component count.
if grep -q " $POTAD_HOSTS_TARGET " "$POTAD_MOUNTS" 2>/dev/null; then
    if umount "$POTAD_HOSTS_TARGET" 2>/dev/null; then
        _out "restored $POTAD_HOSTS_TARGET (blackhole lifted)"
    else
        _out "could not unmount $POTAD_HOSTS_TARGET - it lifts on reboot"
        _log WARN "umount $POTAD_HOSTS_TARGET failed; it lifts on reboot"
    fi
else
    _out "$POTAD_HOSTS_TARGET was not blackholed - nothing to lift"
fi

rm -f "$POTAD_RESTORE" "$POTAD_PREDISABLED" "$POTAD_DISCOVERED" "$POTAD_HOSTS_MERGED"

_out ""
_out "Restore complete: $_ok restored, $_fail failed."
_out "Final step, run by hand: rm -rf $POTAD_ROOT"
_log INFO "=== POTAD restore done: $_ok restored, $_fail failed ==="
exit 0
