#!/bin/bash
# Phase 4.2 no-null checks: ok.cud must build and run; each bad_*.cud must be rejected with its "# expect:" text.
cd "$(dirname "$0")"
FC=../../build/cudc
T=$(mktemp -d)
fail=0
if $FC ok.cud $T/ok.s && ../../build/fas -o $T/ok.o $T/ok.s && ../../build/fld -o $T/ok $T/ok.o && [ "$($T/ok)" = "nonnull ok" ]; then
    echo "PASS nonnull-ok"
else
    echo "FAIL nonnull-ok"; fail=1
fi
for f in bad_*.cud; do
    want=$(sed -n 's/^# expect: //p' $f)
    out=$($FC $f $T/x.s 2>&1)
    if [ $? -ne 0 ] && echo "$out" | grep -qF "$want"; then
        echo "PASS nonnull-${f%.cud}"
    else
        echo "FAIL nonnull-${f%.cud}: $out"; fail=1
    fi
done
rm -rf $T
exit $fail
