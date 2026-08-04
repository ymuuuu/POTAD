#!/bin/sh
# Gap 2: honest reporting after the disable loop. On the live device two
# components potad_disable_component logged as "disabled" sat in the dump's
# enabledComponents: block afterwards - the exit status of pm disable was
# believed and never re-read. potad_verify_components re-reads, reports the
# truth, and re-asserts exactly once.
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

_D="$POTAD_TEST_ROOT/tests/fixtures/gms-dump-reenabled.txt"

# --- potad_component_state: one of each -------------------------------------
[ "$(potad_component_state "$_D" com.google.android.gms/.update.SystemUpdateGcmTaskService)" = "disabled" ] \
    || fail "disabledComponents: entry not classified disabled"
[ "$(potad_component_state "$_D" com.google.android.gms/.update.SystemUpdateActivity)" = "enabled" ] \
    || fail "enabledComponents: entry not classified enabled"
# SystemUpdateService appears only in a resolver table, in no state block.
# It sits AFTER the enabledComponents: block in the fixture, so a default
# here also proves the block scanner stops at the next colon-terminated
# header instead of swallowing the rest of the dump.
[ "$(potad_component_state "$_D" com.google.android.gms/.update.SystemUpdateService)" = "default" ] \
    || fail "resolver-table-only entry not classified default"
[ "$(potad_component_state "$_D" com.google.android.gms/.update.GhostComponent)" = "absent" ] \
    || fail "unknown component not classified absent"

# A component whose name is a prefix of a DIFFERENT component in the other
# block. GMS really does ship these - the live dump carries 25 such pairs -
# and enabledComponents: comes second, so a substring match would hand back
# "enabled" for a component that is genuinely disabled: a false ERROR and a
# pointless re-assert on the one path that exists to report the truth.
[ "$(potad_component_state "$_D" com.google.android.gms/.update.SystemUpdateGcmTaskService)" = "disabled" ] \
    || fail "longer name in enabledComponents: hijacked a disabled component's state"

# --- potad_verify_components ------------------------------------------------
# Seed the cache with a pre-disable dump first: verify must drop it before
# re-reading, or it would classify against the state POTAD started from.
export POTAD_STUB_PM_DUMP="$POTAD_TEST_ROOT/tests/fixtures/gms-dump.txt"
potad_pm_dump com.google.android.gms >/dev/null || fail "pre-dump failed"
export POTAD_STUB_PM_DUMP="$_D"

potad_verify_components

# The seed list against the fixture: four in disabledComponents:, two in
# enabledComponents:, one default, two (gsf) absent.
[ "$POTAD_N_VERIFIED" = "4" ] || fail "expected 4 verified, got $POTAD_N_VERIFIED"
[ "$POTAD_N_REENABLED" = "2" ] \
    || fail "expected 2 re-enabled, got $POTAD_N_REENABLED (stale cache used?)"

# The re-assert must not inflate the disabled count. These components were
# already counted by the disable loop, and a summary claiming more disabled
# than there are components is not a report anyone trusts. Nothing ran a
# disable loop here, so anything above zero is the re-assert leaking.
[ "$POTAD_N_DISABLED" = "0" ] \
    || fail "re-assert inflated POTAD_N_DISABLED to $POTAD_N_DISABLED"

assert_log "re-enabled after disable: com.google.android.gms/.update.SystemUpdateActivity"
assert_log "still enabled after re-assert: com.google.android.gms/.update.SystemUpdateActivity"

# Re-assert fires exactly once per re-enabled component. The stub dump is
# static, so a second attempt would mean a re-assert loop - on a real device
# that is a fight with GMS that never settles.
_n=$(grep -c "pm disable com.google.android.gms/.update.SystemUpdateActivity" "$POTAD_TEST_CALLS")
[ "$_n" = "1" ] || fail "re-assert fired $_n times for SystemUpdateActivity, expected exactly 1"
_n=$(grep -c "pm disable com.google.android.gms/.update.OtaSuggestionSummaryProvider" "$POTAD_TEST_CALLS")
[ "$_n" = "1" ] || fail "re-assert fired $_n times for OtaSuggestionSummaryProvider, expected exactly 1"

exit 0
