#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

# Ready immediately when boot is complete and pm answers.
potad_wait_boot 5 || fail "expected wait_boot to succeed"
assert_call "getprop sys.boot_completed"
assert_call "pm list packages"

# Times out and returns 1 when the package manager never answers.
: > "$POTAD_TEST_CALLS"
export POTAD_STUB_PM_READY=0
if potad_wait_boot 3; then
    fail "expected wait_boot to time out"
fi
assert_log "timed out"

# Manager detection.
: > "$POTAD_TEST_CALLS"
KSU=true KSU_NEXT='' APATCH='' MAGISK_VER_CODE='' potad_detect_env
[ "$POTAD_MGR" = "kernelsu" ] || fail "expected kernelsu, got $POTAD_MGR"

KSU=true KSU_NEXT=true APATCH='' MAGISK_VER_CODE='' potad_detect_env
[ "$POTAD_MGR" = "kernelsu_next" ] || fail "expected kernelsu_next, got $POTAD_MGR"

KSU='' KSU_NEXT='' APATCH=true MAGISK_VER_CODE='' potad_detect_env
[ "$POTAD_MGR" = "apatch" ] || fail "expected apatch, got $POTAD_MGR"

KSU='' KSU_NEXT='' APATCH='' MAGISK_VER_CODE=27000 potad_detect_env
[ "$POTAD_MGR" = "magisk" ] || fail "expected magisk, got $POTAD_MGR"

KSU='' KSU_NEXT='' APATCH='' MAGISK_VER_CODE='' potad_detect_env
[ "$POTAD_MGR" = "unknown" ] || fail "expected unknown, got $POTAD_MGR"

exit 0
