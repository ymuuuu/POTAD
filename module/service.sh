#!/system/bin/sh
# POTAD layer A: disable OTA components once the framework is up.
MODDIR=${0%/*}
# shellcheck disable=SC1091  # sourced file path is computed at runtime
. "$MODDIR/common/functions.sh"

potad_detect_env
potad_log INFO "service.sh start (manager=$POTAD_MGR, version=0.2.0)"

if ! potad_wait_boot 120; then
    potad_log ERROR "layer A skipped: framework never came up"
    exit 0
fi

potad_probe

# Component names never contain whitespace, so word-splitting is safe here and
# avoids the subshell a `... | while read` pipeline would create.
# shellcheck disable=SC2013
for _comp in $(potad_read_components); do
    potad_disable_component "$_comp"
done

# The disable loop's own log lines cannot be trusted (a pm exit status of 0
# does not mean the component stayed disabled); re-read and re-assert.
potad_verify_components

potad_log INFO "layer A: $POTAD_N_DISABLED disabled, $POTAD_N_ABSENT absent, $POTAD_N_FAILED failed, $POTAD_N_NEW new-for-review, $POTAD_N_VERIFIED verified, $POTAD_N_REENABLED re-enabled"

potad_dump_cleanup
exit 0
