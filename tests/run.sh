#!/bin/sh
# POTAD test runner. Runs every tests/cases/NN-*.sh; exit 0 = that case passed.
set -u

# shellcheck disable=SC1007  # CDPATH= prefix is an intentional env override for cd
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
_pass=0
_fail=0

for _case in "$ROOT"/tests/cases/[0-9]*.sh; do
    [ -f "$_case" ] || continue
    _name=$(basename "$_case")
    if _out=$(sh "$_case" 2>&1); then
        echo "PASS  $_name"
        _pass=$((_pass + 1))
    else
        echo "FAIL  $_name"
        printf '%s\n' "$_out" | sed 's/^/        /'
        _fail=$((_fail + 1))
    fi
done

echo "---"
echo "$_pass passed, $_fail failed"
[ "$_fail" -eq 0 ]
