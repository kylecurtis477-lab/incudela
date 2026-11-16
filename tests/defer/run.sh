#!/bin/bash
# Phase 4.5 defer: ok.cud prints ok.expected (LIFO order, every return path, rax kept);
# each bad_*.cud is rejected with its "# expect:" text.
cd "$(dirname "$0")"
FC=$PWD/../../build/cudc
T=$(mktemp -d)
fail=0
if $FC ok.cud $T/ok.s $CUDC_FLAGS && ../../build/fas -o $T/ok.o $T/ok.s && ../../build/fld -o $T/ok $T/ok.o && [ "$($T/ok)" = "$(cat ok.expected)" ]; then
    echo "PASS defer-ok"
else
    echo "FAIL defer-ok: $($T/ok)"; fail=1
fi
for f in bad_*.cud; do
    want=$(sed -n 's/^# expect: //p' $f)
    out=$($FC $f $T/x.s 2>&1)
    if [ $? -ne 0 ] && echo "$out" | grep -qF -- "$want"; then
        echo "PASS defer-${f%.cud}"
    else
        echo "FAIL defer-${f%.cud}: $out"; fail=1
    fi
done
rm -rf $T
exit $fail
