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
export POTAD_GMS_UPDATE_PREFS="${POTAD_GMS_UPDATE_PREFS:-/data/data/com.google.android.gms/shared_prefs/UPDATE_INFO_METADATA_PREFS.xml}"
export POTAD_OTA_PACKAGE_DIR="${POTAD_OTA_PACKAGE_DIR:-/data/ota_package}"
POTAD_LOG_MAX=262144

# Counters, summed across a layer-A run.
export POTAD_N_DISABLED=0
export POTAD_N_ABSENT=0
export POTAD_N_FAILED=0
export POTAD_N_NEW=0
# Filled by potad_verify_components after a layer-A run: how many components
# the re-read dump confirms as disabled, and how many came back enabled.
export POTAD_N_VERIFIED=0
export POTAD_N_REENABLED=0

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

# Drops one package's cached dump. A re-assert changes only that package;
# potad_dump_cleanup would throw away every other package's dump too. With
# today's two packages that costs nothing measurable - gsf sorts after gms, so
# it is dumped after the last re-assert either way - so this is about not
# discarding state we know is still good. It stops being free the moment
# POTAD_PROBE_PKGS grows.
potad_dump_drop() {
    rm -f "$POTAD_ROOT/.dump.$1.$$"
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

# Ground truth for whether a disable actually stuck. potad_disable_component
# trusts the exit status of `pm disable`, and on the live device two
# components it logged as disabled sat in the dump's enabledComponents: block
# afterwards - either GMS re-asserted them or the pm call silently did
# nothing. The dump is the only honest source, so that is what this reads.
#
# Slash form in, dot form compared: components arrive as pkg/.Class but the
# disabledComponents:/enabledComponents: blocks list pkg.Class. The block
# scanning is the same shape as potad_probe's - a header line, indented
# entries, terminated by the next line ending in a colon - because real
# dumpsys output indents headers too, so a column-0 anchor would swallow
# everything after the block.
potad_component_state() {
    _dump="$1"
    _comp="$2"
    _dot="${_comp%%/*}${_comp#*/}"
    # Slash form appears in resolver tables, dot form in the state blocks;
    # finding neither means the component does not exist on this build.
    if ! grep -qF "$_comp" "$_dump" 2>/dev/null && ! grep -qF "$_dot" "$_dump" 2>/dev/null; then
        printf '%s\n' absent
        return 0
    fi
    # The entry is compared whole, not with index(): GMS ships components whose
    # names are prefixes of others (SystemUpdateActivity is a prefix of a
    # hypothetical SystemUpdateActivityAlias, and the live dump carries 25 such
    # pairs already). A substring match would let a longer name in the OTHER
    # block decide this component's state - and because enabledComponents:
    # comes second, the wrong answer would be "enabled", producing a false
    # ERROR and a pointless re-assert on the one path that exists to report
    # the truth.
    awk -v c="$_dot" '
        /disabledComponents:/ { b = "disabled"; next }
        /enabledComponents:/  { b = "enabled"; next }
        b && /:[[:space:]]*$/ { b = "" }
        b { entry = $0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", entry)
            if (entry == c) found = b }
        END { print (found ? found : "default") }
    ' "$_dump"
}

# Runs after the disable loop and checks what actually happened, because the
# loop's own reporting cannot be trusted (see above). A component that comes
# back enabled is re-asserted exactly once. Not looping is deliberate: an
# infinite re-assert fight with GMS would be worse than reporting the truth.
potad_verify_components() {
    # Any cached dump predates the disables and would show the state POTAD
    # started from, not the one it left.
    potad_dump_cleanup
    # shellcheck disable=SC2013
    for _comp in $(potad_read_components); do
        _dump=$(potad_pm_dump "${_comp%%/*}") || continue
        _state=$(potad_component_state "$_dump" "$_comp")
        case "$_state" in
            disabled)
                POTAD_N_VERIFIED=$((POTAD_N_VERIFIED + 1))
                potad_log INFO "verified $_comp"
                ;;
            enabled)
                potad_log ERROR "re-enabled after disable: $_comp"
                POTAD_N_REENABLED=$((POTAD_N_REENABLED + 1))
                # The re-assert goes through potad_disable_component for its
                # absent/disable-user fallbacks and restore-list recording, but
                # it must not inflate the disabled count - this component was
                # already counted by the disable loop, and a summary reading
                # "9 disabled" for 8 components is not a report anyone trusts.
                # A failed re-assert still increments POTAD_N_FAILED, which is
                # the one number that should move here.
                _n_before=$POTAD_N_DISABLED
                potad_disable_component "$_comp"
                POTAD_N_DISABLED=$_n_before
                # The re-assert changed the state, so the dump just taken is
                # stale again before the re-check.
                potad_dump_drop "${_comp%%/*}"
                _dump=$(potad_pm_dump "${_comp%%/*}") || continue
                _state=$(potad_component_state "$_dump" "$_comp")
                if [ "$_state" = "disabled" ]; then
                    POTAD_N_VERIFIED=$((POTAD_N_VERIFIED + 1))
                    potad_log INFO "re-assert held $_comp"
                else
                    potad_log ERROR "still $_state after re-assert: $_comp"
                fi
                ;;
            default)
                # pm said "disabled" yet the dump shows the component in
                # neither block - the disable did not take effect either.
                potad_log WARN "not disabled (default state): $_comp"
                ;;
            absent)
                potad_log INFO "absent $_comp"
                ;;
        esac
    done
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

# android.googleapis.com is deliberately absent from this list. It serves the
# update *check*, but it also carries sign-in, FCM push, Play Store and device
# checkin - blackholing it breaks the phone. A check that finds an update it
# can never download is harmless: the payload hosts below are the ones that
# matter. This is a decided design call (verified on-device 2026-08-04), not
# an oversight - do not "fix" the list by adding it.
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

# Per-host layer-B health. Both halves matter: the entry without the mount
# means POTAD wrote a file nobody reads, and the mount without the entry
# blackholes nothing.
potad_verify_hosts() {
    for _host in $POTAD_HOSTS_ENTRIES; do
        if ! grep -qxF "127.0.0.1 $_host" "$POTAD_HOSTS_TARGET" 2>/dev/null; then
            potad_out "  $_host: NOT blocked (no hosts entry)"
            continue
        fi
        if ! grep -q " $POTAD_HOSTS_TARGET " "$POTAD_MOUNTS" 2>/dev/null; then
            potad_out "  $_host: hosts entry present but blackhole NOT mounted"
            continue
        fi
        potad_out "  $_host: blocked"
    done
}

# Update *checks* still succeed with POTAD fully active - android.googleapis.com
# is reachable by design (see POTAD_HOSTS_ENTRIES) - so GMS keeps recording
# last_check_time_millis. That is harmless, but invisible state reads as
# broken, so surface it. Best-effort: unreadable prefs are the normal case
# without root and never an error.
potad_report_update_check() {
    if [ ! -r "$POTAD_GMS_UPDATE_PREFS" ]; then
        potad_out "  last update check: unknown (GMS prefs unreadable)"
        return 0
    fi
    _ms=$(sed -n 's/.*name="last_check_time_millis" value="\([0-9]*\)".*/\1/p' \
        "$POTAD_GMS_UPDATE_PREFS" 2>/dev/null | head -n 1)
    if [ -z "$_ms" ]; then
        potad_out "  last update check: never recorded"
        return 0
    fi
    # Toybox and busybox date both take -d @<epoch>; if neither does, print
    # the raw value rather than nothing.
    _when=$(date -d "@$((_ms / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    if [ -n "$_when" ]; then
        potad_out "  last update check: $_when"
    else
        potad_out "  last update check: ${_ms}ms epoch"
    fi
    return 0
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

# Layer C's blind spot: --cancel clears update_engine's in-memory view, but
# leftover payload files in /data/ota_package survive it - on the live device
# --cancel reported "nothing staged" while a payload dated before POTAD was
# installed sat there, and update_engine fed itself from it.
#
# Whitelist, never rm -rf: this is a deletion path on a user's device and has
# to be auditable. Anything unrecognised is logged and left alone, and the
# directory itself survives. The files are a re-downloadable cache, so
# restore.sh deliberately does NOT recreate them - there is nothing to undo.
potad_clear_staged_package() {
    [ -d "$POTAD_OTA_PACKAGE_DIR" ] || {
        potad_log INFO "no staged package directory ($POTAD_OTA_PACKAGE_DIR)"
        return 0
    }
    _n=0
    _bytes=0
    for _f in "$POTAD_OTA_PACKAGE_DIR"/*; do
        # Globs that matched nothing and non-regular files (subdirectories):
        # not ours to touch.
        [ -f "$_f" ] || continue
        case "${_f##*/}" in
            payload.bin|payload_metadata.bin|payload_properties.txt|metadata|metadata.pb|apex_info.pb|care_map.pb|*.zip)
                _sz=$(wc -c < "$_f" 2>/dev/null || echo 0)
                rm -f "$_f"
                _n=$((_n + 1))
                _bytes=$((_bytes + ${_sz:-0}))
                ;;
            *)
                potad_log WARN "left alone (unrecognised): $_f"
                ;;
        esac
    done
    potad_out "  staged package: removed $_n file(s), freed $_bytes bytes"
    return 0
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
