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
POTAD_MODDIR="${POTAD_MODDIR:-/data/adb/modules/potad}"
POTAD_HOSTS_MERGED="${POTAD_HOSTS_MERGED:-$POTAD_MODDIR/hosts}"
POTAD_HOSTS_LEGACY="$POTAD_ROOT/hosts"
POTAD_HOSTS_TARGET="${POTAD_HOSTS_TARGET:-/system/etc/hosts}"
POTAD_MOUNTS="${POTAD_MOUNTS:-/proc/mounts}"
POTAD_MOUNTINFO="${POTAD_MOUNTINFO:-/proc/self/mountinfo}"

# Three-line logger, duplicated from common/functions.sh on purpose (D4).
_log() {
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "$2" >> "$POTAD_LOG" 2>/dev/null
}

_out() {
    printf '%s\n' "$*"
    _log INFO "$*"
}

_mountinfo_query() {
    _mode="$1"
    [ -r "$POTAD_MOUNTINFO" ] || return 2
    _cur_rel="${POTAD_HOSTS_MERGED#/data}"
    [ "$_cur_rel" = "$POTAD_HOSTS_MERGED" ] && _cur_rel=""
    _leg_rel="${POTAD_HOSTS_LEGACY#/data}"
    [ "$_leg_rel" = "$POTAD_HOSTS_LEGACY" ] && _leg_rel=""
    awk -v mode="$_mode" \
        -v target="$POTAD_HOSTS_TARGET" \
        -v cur="$POTAD_HOSTS_MERGED" -v cur_rel="$_cur_rel" \
        -v leg="$POTAD_HOSTS_LEGACY" -v leg_rel="$_leg_rel" '
        function norm_root(d, r, d_arr,    is_del, full) {
            is_del = 0
            if (sub(/\/\/deleted$/, "", r) || sub(/\\040\(deleted\)$/, "", r)) {
                is_del = 1
            }
            full = r
            if (d in d_arr && d_arr[d] != "/") {
                full = d_arr[d] r
            }
            return is_del "|" full
        }
        function is_match(path, exact, rel) {
            return (path == exact || (rel != "" && path == rel))
        }
        BEGIN { has_lines = 0; n = 0 }
        {
            has_lines = 1
            if ($4 == "/") {
                if (!($3 in dev_mp) || length($5) < length(dev_mp[$3])) {
                    dev_mp[$3] = $5
                }
            }
            if ($5 == target) {
                n++
                devs[n] = $3
                roots[n] = $4
            }
        }
        END {
            if (!has_lines) { exit 2 }
            if (mode == "has_legacy") {
                for (i = 1; i <= n; i++) {
                    split(norm_root(devs[i], roots[i], dev_mp), p, "|")
                    if (is_match(p[2], leg, leg_rel)) { exit 0 }
                }
                exit 1
            }
            if (n == 0) { print "none"; exit 0 }
            split(norm_root(devs[n], roots[n], dev_mp), p, "|")
            if (is_match(p[2], cur, cur_rel)) {
                print (p[1] == "1" ? "current_deleted" : "current")
            } else if (is_match(p[2], leg, leg_rel)) {
                print "legacy"
            } else {
                print "other"
            }
        }
    ' "$POTAD_MOUNTINFO" 2>/dev/null
}

_hosts_mount_kind() {
    if _kind=$(_mountinfo_query kind); then
        printf '%s\n' "$_kind"
        return 0
    fi
    if grep -q " $POTAD_HOSTS_TARGET " "$POTAD_MOUNTS" 2>/dev/null; then
        printf '%s\n' unknown
    else
        printf '%s\n' none
    fi
}

_legacy_hosts_mounted() {
    _mountinfo_query has_legacy
}

_log INFO "=== POTAD restore ==="

_kind=$(_hosts_mount_kind)
_has_hosts_mount=0
case "$_kind" in
    current|current_deleted|legacy|unknown) _has_hosts_mount=1 ;;
esac

# restore.list holds only components POTAD itself transitioned to disabled
# (D2). Exit early only when neither component overrides nor Layer B artifacts exist.
if [ ! -s "$POTAD_RESTORE" ] &&
   [ "$_has_hosts_mount" -eq 0 ] &&
   [ ! -f "$POTAD_HOSTS_MERGED" ] &&
   [ ! -f "$POTAD_HOSTS_LEGACY" ]; then
    _out "Nothing recorded to restore."
    _out "POTAD never disabled anything that was not already disabled."
    exit 0
fi

_ok=0
_fail=0
if [ -s "$POTAD_RESTORE" ]; then
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
fi

# Lift the hosts blackhole without a reboot. Best-effort (N2): the mount dies
# with the next reboot anyway, so failure here is not an error. Reported with
# _out, not _log: the user asked for a restore and the hosts file is half of
# what gets restored, so every outcome - including "there was nothing to lift"
# - belongs on screen next to the component count.
_still_mounted=""
if [ "$_has_hosts_mount" -eq 1 ]; then
    if umount "$POTAD_HOSTS_TARGET" 2>/dev/null; then
        _out "restored $POTAD_HOSTS_TARGET (blackhole lifted)"
    else
        _still_mounted="$_kind"
        _out "could not unmount $POTAD_HOSTS_TARGET - it lifts on reboot"
        _log WARN "umount $POTAD_HOSTS_TARGET failed; it lifts on reboot"
    fi
elif [ "$_kind" = "other" ]; then
    _out "$POTAD_HOSTS_TARGET is mounted by another module - left intact"
else
    _out "$POTAD_HOSTS_TARGET was not blackholed - nothing to lift"
fi

rm -f "$POTAD_RESTORE" "$POTAD_PREDISABLED" "$POTAD_DISCOVERED"

case "$_still_mounted" in
    current|current_deleted|unknown) ;;
    *) rm -f "$POTAD_HOSTS_MERGED" 2>/dev/null ;;
esac
case "$_still_mounted" in
    legacy|unknown) ;;
    *)
        if [ "$_kind" = "legacy" ] || ! _legacy_hosts_mounted; then
            rm -f "$POTAD_HOSTS_LEGACY" 2>/dev/null
        fi
        ;;
esac

_out ""
_out "Restore complete: $_ok restored, $_fail failed."
_out "Final step, run by hand: rm -rf $POTAD_ROOT"
_log INFO "=== POTAD restore done: $_ok restored, $_fail failed ==="
exit 0
