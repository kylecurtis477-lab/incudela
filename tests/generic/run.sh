#!/bin/bash
# Phase 4.5b generics: ok.cud instantiates generic defs/structs (explicit and inferred);
# std.cud exercises std/vec.cudi + std/map.cudi; oob.cud must trap;
# each bad_*.cud is rejected with its "# expect:" text.
cd "$(dirname "$0")"
FC=$PWD/../../build/cudc
T=$(mktemp -d)
fail=0
if $FC ok.cud $T/ok.s $CUDC_FLAGS && ../../build/fas -o $T/ok.o $T/ok.s && ../../build/fld -o $T/ok $T/ok.o && [ "$($T/ok)" = "$(cat ok.expected)" ]; then
    echo "PASS generic-ok"
else
    echo "FAIL generic-ok: $($T/ok)"; fail=1
fi
if $FC std.cud $T/std.s $CUDC_FLAGS && ../../build/fas -o $T/std.o $T/std.s && ../../build/fld -o $T/std $T/std.o && [ "$($T/std)" = "$(cat std.expected)" ]; then
    echo "PASS generic-std-vec-map"
else
    echo "FAIL generic-std-vec-map: $($T/std)"; fail=1
fi
if $FC oob.cud $T/oob.s $CUDC_FLAGS && ../../build/fas -o $T/oob.o $T/oob.s && ../../build/fld -o $T/oob $T/oob.o && ! $T/oob >/dev/null 2>&1; then
    echo "PASS generic-vec-oob-trap"
else
    echo "FAIL generic-vec-oob-trap"; fail=1
fi
for f in bad_*.cud; do
    want=$(sed -n 's/^# expect: //p' $f)
    out=$($FC $f $T/x.s 2>&1)
    if [ $? -ne 0 ] && echo "$out" | grep -qF -- "$want"; then
        echo "PASS generic-${f%.cud}"
    else
        echo "FAIL generic-${f%.cud}: $out"; fail=1
    fi
done
rm -rf $T
exit $fail
