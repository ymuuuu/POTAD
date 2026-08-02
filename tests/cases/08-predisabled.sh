#!/bin/sh
# shellcheck disable=SC1091  # sourced file paths are computed at runtime
. "$(dirname -- "$0")/_common.sh"
. "$POTAD_MODDIR/common/functions.sh"

export POTAD_STUB_PM_DUMP="$POTAD_TEST_ROOT/tests/fixtures/gms-dump-disabled.txt"

# A stale entry from an earlier run must not survive a fresh probe.
printf '%s\n' "com.google.android.gms/.update.StaleEntry" > "$POTAD_PREDISABLED"

potad_probe || fail "probe must always return 0"

# Dot-form names from the disabledComponents: block, normalised to slash form.
grep -qxF "com.google.android.gms/.update.OtaSuggestionActivity" "$POTAD_PREDISABLED" \
    || fail "pre-disabled component missing from snapshot"
grep -qxF "com.google.android.gms/.update.UucNotificationReceiverService" "$POTAD_PREDISABLED" \
    || fail "probe-invisible component missing from snapshot"

# A component listed only under enabledComponents: is not pre-disabled.
grep -qF "SystemUpdateService" "$POTAD_PREDISABLED" \
    && fail "enabled component leaked into the pre-disabled snapshot"

# No raw dot-form or block headers leak through.
grep -qF "com.google.android.gms.update.OtaSuggestionActivity" "$POTAD_PREDISABLED" \
    && fail "dot form was not normalised to slash form"
grep -qF "Components:" "$POTAD_PREDISABLED" \
    && fail "block header leaked into the snapshot"

# Rewritten fresh, not appended: the stale entry is gone.
grep -qF "StaleEntry" "$POTAD_PREDISABLED" \
    && fail "snapshot was not rewritten on a fresh probe"

# The snapshot comes from the same dump the classifier uses: one dump per
# probe package, no extra pm dump call for the snapshot.
_n=$(grep -c "pm dump " "$POTAD_TEST_CALLS")
[ "$_n" = "2" ] || fail "expected 2 pm dump calls (one per probe package), got $_n"

exit 0
