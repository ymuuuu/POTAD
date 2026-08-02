# POTAD shared helpers. Sourced by every entry point; never executed directly.
# Every absolute path is overridable so the host test harness can redirect it.
# shellcheck shell=sh

# Globals are exported: they are the contract shared with the entry-point
# scripts that source this file (and silences cross-file SC2034).
export POTAD_ROOT="${POTAD_ROOT:-/data/adb/potad}"
export POTAD_LOG="$POTAD_ROOT/potad.log"
export POTAD_DISCOVERED="$POTAD_ROOT/discovered.list"
export POTAD_PREDISABLED="$POTAD_ROOT/predisabled.list"
export POTAD_RESTORE="$POTAD_ROOT/restore.list"
export POTAD_HOSTS_MERGED="$POTAD_ROOT/hosts"
export POTAD_HOSTS_TARGET="${POTAD_HOSTS_TARGET:-/system/etc/hosts}"
export POTAD_MOUNTS="${POTAD_MOUNTS:-/proc/mounts}"
export POTAD_MODDIR="${POTAD_MODDIR:-${MODDIR:-/data/adb/modules/potad}}"
POTAD_LOG_MAX=262144

# Counters, summed across a layer-A run.
export POTAD_N_DISABLED=0
export POTAD_N_ABSENT=0
export POTAD_N_FAILED=0
export POTAD_N_NEW=0

potad_log() {
    _lvl="$1"
    shift
    [ -d "$POTAD_ROOT" ] || mkdir -p "$POTAD_ROOT" 2>/dev/null
    if [ -f "$POTAD_LOG" ]; then
        _sz=$(wc -c < "$POTAD_LOG" 2>/dev/null || echo 0)
        if [ "${_sz:-0}" -gt "$POTAD_LOG_MAX" ] 2>/dev/null; then
            mv -f "$POTAD_LOG" "$POTAD_LOG.1" 2>/dev/null
        fi
    fi
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$_lvl" "$*" >> "$POTAD_LOG" 2>/dev/null
}

potad_out() {
    printf '%s\n' "$*"
    potad_log INFO "$*"
}

# --- The /data/adb file-descriptor rule (F9) --------------------------------
# `pm` is a shell wrapper around `cmd`, which hands its own stdin, stdout and
# stderr to system_server over binder. system_server is denied both read and
# write on u:object_r:adb_data_file:s0, the label of everything under
# /data/adb - so any pm invocation whose fds point in there dies with
#
#   cmd: Failure calling service package: Failed transaction (2147483646)
#
# and the kernel logs an avc denial for comm="cmd". Two consequences, and
# both were live bugs in 0.2:
#
#   * stdin - `pm ...` inside `while read ... done < /data/adb/potad/x`
#     inherits the list file as stdin. Every pm call in this file therefore
#     reads from /dev/null.
#   * stdout - `pm dump pkg > /data/adb/potad/x` writes nothing but the error
#     line. potad_pm_dump pipes through `cat` so the shell, not system_server,
#     opens the destination.

# One dump per package per process: `pm dump com.google.android.gms` is around
# 50k lines and takes seconds, and the action path needs it twice.
#
# Callers read the path off stdout, so this runs inside a command substitution
# and cannot record what it created in a variable - the subshell's assignment
# would never reach potad_dump_cleanup. The $$ in the name is the cleanup
# handle instead: it is the sourcing shell's pid even inside the subshell, so
# the glob below matches exactly this process's dumps and no other's.
potad_pm_dump() {
    _pkg="$1"
    _f="$POTAD_ROOT/.dump.$_pkg.$$"
    if [ ! -s "$_f" ]; then
        # The `cat` is load-bearing, not redundant - see the fd rule above.
        pm dump "$_pkg" </dev/null 2>/dev/null | cat > "$_f"
    fi
    [ -s "$_f" ] || return 1
    printf '%s\n' "$_f"
}

potad_dump_cleanup() {
    rm -f "$POTAD_ROOT"/.dump.*."$$"
}

# APatch and KernelSU Next are checked before plain KernelSU because both also
# set KSU=true. SukiSU is indistinguishable from KernelSU at the script level
# and reports as "kernelsu"; this is cosmetic, it only affects the log line.
potad_detect_env() {
    if [ "${APATCH:-}" = "true" ]; then
        POTAD_MGR=apatch
    elif [ "${KSU_NEXT:-}" = "true" ]; then
        POTAD_MGR=kernelsu_next
    elif [ "${KSU:-}" = "true" ]; then
        POTAD_MGR=kernelsu
    elif [ -n "${MAGISK_VER_CODE:-}" ]; then
        POTAD_MGR=magisk
    else
        POTAD_MGR=unknown
    fi
    POTAD_MMRL="${MMRL:-false}"
    export POTAD_MGR POTAD_MMRL
}

# Polls until the framework is up. Returns 1 on timeout; callers must treat
# that as non-fatal and exit 0 anyway (constraint N1).
potad_wait_boot() {
    _timeout="${1:-120}"
    _waited=0
    while [ "$_waited" -lt "$_timeout" ]; do
        if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] &&
           pm list packages </dev/null >/dev/null 2>&1; then
            potad_log INFO "boot ready after ${_waited}s"
            return 0
        fi
        sleep 1
        _waited=$((_waited + 1))
    done
    potad_log ERROR "timed out after ${_timeout}s waiting for boot / package manager"
    return 1
}

# Records a component POTAD just transitioned to disabled, so restore.sh can
# later undo exactly POTAD's own changes and nothing else (D2). A component
# that was already disabled before POTAD - listed in the probe's
# $POTAD_PREDISABLED snapshot - is disabled as normal but never recorded:
# restoring it would re-enable something the user disabled on purpose (F8).
potad_record_restore() {
    _comp="$1"
    if [ ! -f "$POTAD_PREDISABLED" ]; then
        # The probe could not run, so there is no trustworthy snapshot.
        # Blocking must not depend on it, but restoring must.
        if [ "${POTAD_RESTORE_WARNED:-0}" != "1" ]; then
            POTAD_RESTORE_WARNED=1
            potad_log WARN "no pre-disabled snapshot; restore data incomplete"
        fi
        return 0
    fi
    grep -qxF "$_comp" "$POTAD_PREDISABLED" 2>/dev/null && return 0
    grep -qxF "$_comp" "$POTAD_RESTORE" 2>/dev/null && return 0
    printf '%s\n' "$_comp" >> "$POTAD_RESTORE"
}

# Never fatal. A component that is absent on this build is the normal case,
# not an error - that is what makes the module version-agnostic (R4).
potad_disable_component() {
    _comp="$1"
    if _out=$(pm disable "$_comp" </dev/null 2>&1); then
        potad_log INFO "disabled $_comp"
        POTAD_N_DISABLED=$((POTAD_N_DISABLED + 1))
        potad_record_restore "$_comp"
        return 0
    fi
    case "$_out" in
        *"Unknown component"*|*"Unknown package"*|*"does not exist"*)
            potad_log INFO "absent $_comp"
            POTAD_N_ABSENT=$((POTAD_N_ABSENT + 1))
            return 0
            ;;
    esac
    # Newer builds refuse `disable` on some GMS components but accept
    # `disable-user` scoped to user 0.
    if _out=$(pm disable-user --user 0 "$_comp" </dev/null 2>&1); then
        potad_log INFO "disabled (user 0) $_comp"
        POTAD_N_DISABLED=$((POTAD_N_DISABLED + 1))
        potad_record_restore "$_comp"
        return 0
    fi
    potad_log ERROR "failed $_comp: $_out"
    POTAD_N_FAILED=$((POTAD_N_FAILED + 1))
    return 0
}

POTAD_PROBE_PKGS="com.google.android.gms com.google.android.gsf"

potad_read_components() {
    {
        cat "$POTAD_MODDIR/common/components.list" 2>/dev/null
        cat "$POTAD_DISCOVERED" 2>/dev/null
    } | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
      | grep -v '^$' \
      | sort -u
}

# Discovers OTA components on the running build so a Google rename does not
# require a module update (R4).
#
# Classification is the safety boundary. Only the `.update.System*` family is
# auto-disabled: it is unambiguously the OTA path. Everything else matching
# "Update" is logged for human review and left running, because components
# like PlayUpdateService and AppUpdateService drive Play Store app updates,
# which spec section 9 puts out of scope.
#
# The same dump also feeds $POTAD_PREDISABLED: the disabledComponents: block
# is the pre-POTAD state potad_disable_component consults before recording a
# restorable transition. Some real OTA components appear only in that block
# and never in slash form (F7), which is why they are hand-seeded instead.
potad_probe() {
    if ! pm list packages </dev/null >/dev/null 2>&1; then
        potad_log WARN "probe skipped: package manager unavailable"
        return 0
    fi
    [ -f "$POTAD_DISCOVERED" ] || : > "$POTAD_DISCOVERED"
    : > "$POTAD_PREDISABLED"
    _hits="$POTAD_ROOT/.probe.$$"
    _dumped=0
    : > "$_hits"
    for _pkg in $POTAD_PROBE_PKGS; do
        # One dump per package feeds both the classifier and the snapshot.
        # A package that is not installed has no dump; that is the normal
        # case for com.google.android.gsf and not an error.
        _dump=$(potad_pm_dump "$_pkg") || continue
        _dumped=$((_dumped + 1))
        grep -oE "$_pkg/[A-Za-z0-9_.\$]*[Uu]pdate[A-Za-z0-9_.\$]*" "$_dump" \
            >> "$_hits" 2>/dev/null
        # The block is a `disabledComponents:` header followed by indented
        # dot-form class names, ended by the NEXT HEADER - real dumpsys output
        # indents headers too (6 spaces vs 8 for entries), so a terminator
        # anchored on column 0 would swallow the enabledComponents: block and
        # everything after it. Any line ending in a colon ends the block.
        # Dot form is normalised to slash form so entries compare against
        # components.list; only the package being dumped is rewritten.
        # The package name is dot-escaped before going into a grep/sed pattern
        # so its dots are literals, not wildcards.
        _pkgre=$(printf '%s' "$_pkg" | sed 's/\./\\./g')
        awk '/disabledComponents:/ { f = 1; next }
             f && /:[[:space:]]*$/ { f = 0 }
             f { print }' "$_dump" \
            | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
            | grep "^$_pkgre\." \
            | sed "s|^$_pkgre\.|$_pkg/.|" \
            >> "$POTAD_PREDISABLED"
    done
    # An empty snapshot file and a missing one mean different things to
    # potad_record_restore: empty is "nothing was disabled before POTAD",
    # missing is "we do not know". If not one package could be dumped we do
    # not know, and claiming otherwise would make every component POTAD
    # disables look restorable - including ones the user disabled themselves.
    if [ "$_dumped" -eq 0 ]; then
        rm -f "$POTAD_PREDISABLED" "$_hits"
        potad_log WARN "probe: no package dump succeeded; snapshot not written"
        return 0
    fi
    sort -u "$POTAD_PREDISABLED" -o "$POTAD_PREDISABLED" 2>/dev/null
    sort -u "$_hits" -o "$_hits" 2>/dev/null
    while IFS= read -r _comp; do
        [ -n "$_comp" ] || continue
        case "$_comp" in
            *.update.System*)
                if ! grep -qxF "$_comp" "$POTAD_DISCOVERED" 2>/dev/null; then
                    printf '%s\n' "$_comp" >> "$POTAD_DISCOVERED"
                    potad_log INFO "auto $_comp"
                fi
                ;;
            *)
                potad_log INFO "NEW: $_comp"
                POTAD_N_NEW=$((POTAD_N_NEW + 1))
                ;;
        esac
    done < "$_hits"
    rm -f "$_hits"
    return 0
}

POTAD_HOSTS_ENTRIES="ota.googlezip.net update.googleapis.com"

# Layer B: blackhole the OTA endpoints with a self-managed bind mount, merging
# into whatever hosts file is live so AdAway and friends keep working.
#
# Called from post-fs-data and again from the action button's Block path, so
# re-blocking after a restore does not need a reboot. The early return is what
# makes the second caller safe: once our own bind mount is live,
# $POTAD_HOSTS_TARGET and $POTAD_HOSTS_MERGED are the same inode, and copying
# a file onto itself would truncate the mount source.
potad_apply_hosts() {
    if grep -q "^127\.0\.0\.1[[:space:]]*ota\.googlezip\.net" "$POTAD_HOSTS_TARGET" 2>/dev/null &&
       grep -q " $POTAD_HOSTS_TARGET " "$POTAD_MOUNTS" 2>/dev/null; then
        potad_log INFO "layer B: already active"
        return 0
    fi
    if grep -q " $POTAD_HOSTS_TARGET " "$POTAD_MOUNTS" 2>/dev/null; then
        potad_log WARN "hosts already mounted by another module; last mount wins"
    fi

    # Start from whatever is currently live so other modules' entries survive.
    if [ -f "$POTAD_HOSTS_TARGET" ]; then
        cp -f "$POTAD_HOSTS_TARGET" "$POTAD_HOSTS_MERGED" 2>/dev/null || : > "$POTAD_HOSTS_MERGED"
    else
        : > "$POTAD_HOSTS_MERGED"
    fi

    # A source file without a trailing newline would otherwise glue onto our
    # first appended entry.
    if [ -s "$POTAD_HOSTS_MERGED" ] && [ -n "$(tail -c 1 "$POTAD_HOSTS_MERGED")" ]; then
        printf '\n' >> "$POTAD_HOSTS_MERGED"
    fi

    for _host in $POTAD_HOSTS_ENTRIES; do
        _line="127.0.0.1 $_host"
        if ! grep -qxF "$_line" "$POTAD_HOSTS_MERGED" 2>/dev/null; then
            printf '%s\n' "$_line" >> "$POTAD_HOSTS_MERGED"
        fi
    done

    chmod 0644 "$POTAD_HOSTS_MERGED" 2>/dev/null

    # Match the original file's SELinux label; fall back to the standard one
    # when `ls -Z` is unavailable or formatted differently.
    # shellcheck disable=SC2010  # parsing `ls -Z` SELinux context, not filenames
    _ctx=$(ls -Z "$POTAD_HOSTS_TARGET" 2>/dev/null | grep -oE 'u:object_r:[a-z_]+:s0' | head -n 1)
    chcon "${_ctx:-u:object_r:system_file:s0}" "$POTAD_HOSTS_MERGED" 2>/dev/null

    if mount -o bind "$POTAD_HOSTS_MERGED" "$POTAD_HOSTS_TARGET" 2>/dev/null; then
        potad_log INFO "layer B: hosts bind-mounted over $POTAD_HOSTS_TARGET"
        return 0
    fi
    potad_log ERROR "layer B: bind mount of $POTAD_HOSTS_TARGET failed"
    return 1
}

# Probes the prebuilt AOSP clients newest-first. A binary built against a
# different libc/linker prints "CANNOT LINK EXECUTABLE" and is unusable.
# Technique carried over from Badabing2005's clear_ota_updates.
potad_pick_client() {
    _bindir="${POTAD_BIN_DIR:-$POTAD_MODDIR/bin}"
    for _bin in "$_bindir/update_engine_client_r72" "$_bindir/update_engine_client_r28"; do
        [ -x "$_bin" ] || continue
        _probe=$("$_bin" 2>&1)
        case "$_probe" in
            *"CANNOT LINK EXECUTABLE"*) continue ;;
        esac
        printf '%s\n' "$_bin"
        return 0
    done
    return 1
}

# Runs one update_engine_client flag and reports what actually happened.
#
# The client exits non-zero and prints an ERROR line when there is simply
# nothing staged - "No ongoing update to cancel", exit 248, measured on the
# device. That is the healthy case and the one users see almost every time, so
# reporting it verbatim trains people to ignore the word ERROR and hides a
# genuine failure among the noise. Only an unrecognised non-zero exit is real.
#
# The client also prints multiple lines; they are flattened to one so a single
# log entry cannot break the [timestamp] [level] format.
potad_run_client() {
    _cbin="$1"
    _cflag="$2"
    _cout=$("$_cbin" "$_cflag" 2>&1)
    _crc=$?
    _cout=$(printf '%s' "$_cout" | tr '\n' ' ')
    if [ "$_crc" -eq 0 ]; then
        potad_out "  $_cflag: ok"
        return 0
    fi
    case "$_cout" in
        *"No ongoing update to cancel"*)
            potad_out "  $_cflag: nothing staged"
            return 0
            ;;
    esac
    potad_out "  $_cflag: FAILED (exit $_crc) $_cout"
    potad_log ERROR "$_cflag failed (exit $_crc): $_cout"
    return 1
}

# Volume-key chooser for the action dialog (D1).
# Returns 0 = Vol Up, 1 = Vol Down, 2 = timed out.
# A single `getevent -c 1` can be consumed by a stray touch event, so poll
# in short slices until a volume key arrives or the deadline passes.
# No device path: the no-argument form works on the verified device (F6),
# and hardcoding event0 would be wrong on other Pixels.
potad_choose() {
    _deadline=$(( $(date +%s) + ${1:-15} ))
    while [ "$(date +%s)" -lt "$_deadline" ]; do
        _ev=$(timeout 3 getevent -lqc 1 2>/dev/null)
        case "$_ev" in
            *KEY_VOLUMEUP*)   return 0 ;;
            *KEY_VOLUMEDOWN*) return 1 ;;
        esac
    done
    return 2
}
