#!/bin/bash
# Phase 4.4 ownership: ok.cud builds and runs; each bad_*.cud is rejected with its "# expect:" text.
cd "$(dirname "$0")"
FC=$PWD/../../build/cudc
T=$(mktemp -d)
fail=0
if $FC ok.cud $T/ok.s && ../../build/fas -o $T/ok.o $T/ok.s && ../../build/fld -o $T/ok $T/ok.o && [ "$($T/ok)" = "own ok" ]; then
    echo "PASS own-ok"
else
    echo "FAIL own-ok"; fail=1
fi
if $FC field_layout.cud $T/field.s && ../../build/fas -o $T/field.o $T/field.s && ../../build/fld -o $T/field $T/field.o && $T/field | diff -q - field_layout.expected >/dev/null; then
    echo "PASS own-field-layout"
else
    echo "FAIL own-field-layout"; fail=1
fi
if $FC fields_ok.cud $T/fields.s && ../../build/fas -o $T/fields.o $T/fields.s && ../../build/fld -o $T/fields $T/fields.o && $T/fields | diff -q - fields_ok.expected >/dev/null; then
    echo "PASS own-fields-ok"
else
    echo "FAIL own-fields-ok"; fail=1
fi
if $FC fields_place_ok.cud $T/place.s && ../../build/fas -o $T/place.o $T/place.s && ../../build/fld -o $T/place $T/place.o && $T/place | diff -q - fields_place_ok.expected >/dev/null; then
    echo "PASS own-fields-place-ok"
else
    echo "FAIL own-fields-place-ok"; fail=1
fi
if $FC addr_paths_ok.cud $T/ap.s && ../../build/fas -o $T/ap.o $T/ap.s && ../../build/fld -o $T/ap $T/ap.o && $T/ap | diff -q - addr_paths_ok.expected >/dev/null; then
    echo "PASS own-addr-paths-ok"
else
    echo "FAIL own-addr-paths-ok"; fail=1
fi
if $FC ptr_field_place_ok.cud $T/ptr.s && ../../build/fas -o $T/ptr.o $T/ptr.s && ../../build/fld -o $T/ptr $T/ptr.o && $T/ptr | diff -q - ptr_field_place_ok.expected >/dev/null; then
    echo "PASS own-ptr-field-place"
else
    echo "FAIL own-ptr-field-place"; fail=1
fi
if $FC nown_ok.cud $T/nown.s && ../../build/fas -o $T/nown.o $T/nown.s && ../../build/fld -o $T/nown $T/nown.o && $T/nown | diff -q - nown_ok.expected >/dev/null; then
    echo "PASS own-nown-ok"
else
    echo "FAIL own-nown-ok"; fail=1
fi
if $FC nown_forms_ok.cud $T/nf.s && ../../build/fas -o $T/nf.o $T/nf.s && ../../build/fld -o $T/nf $T/nf.o && $T/nf | diff -q - nown_forms_ok.expected >/dev/null; then
    echo "PASS own-nown-forms-ok"
else
    echo "FAIL own-nown-forms-ok"; fail=1
fi
if $FC take_ok.cud $T/tk.s && ../../build/fas -o $T/tk.o $T/tk.s && ../../build/fld -o $T/tk $T/tk.o && $T/tk | diff -q - take_ok.expected >/dev/null; then
    echo "PASS own-take-ok"
else
    echo "FAIL own-take-ok"; fail=1
fi
if $FC take_shadow_ok.cud $T/tks.s && ../../build/fas -o $T/tks.o $T/tks.s && ../../build/fld -o $T/tks $T/tks.o && $T/tks | diff -q - take_shadow_ok.expected >/dev/null; then
    echo "PASS own-take-shadow-ok"
else
    echo "FAIL own-take-shadow-ok"; fail=1
fi
if $FC rborrow_ok.cud $T/rb.s && ../../build/fas -o $T/rb.o $T/rb.s && ../../build/fld -o $T/rb $T/rb.o && $T/rb | diff -q - rborrow_ok.expected >/dev/null; then
    echo "PASS own-rborrow-ok"
else
    echo "FAIL own-rborrow-ok"; fail=1
fi
if $FC nown_global_ok.cud $T/ng.s && ../../build/fas -o $T/ng.o $T/ng.s && ../../build/fld -o $T/ng $T/ng.o && $T/ng | diff -q - nown_global_ok.expected >/dev/null; then
    echo "PASS own-nown-global-ok"
else
    echo "FAIL own-nown-global-ok"; fail=1
fi
if $FC runqueue_ok.cud $T/rq.s && ../../build/fas -o $T/rq.o $T/rq.s && ../../build/fld -o $T/rq $T/rq.o && $T/rq | diff -q - runqueue_ok.expected >/dev/null; then
    echo "PASS own-runqueue-ok"
else
    echo "FAIL own-runqueue-ok"; fail=1
fi
for f in bad_*.cud; do
    want=$(sed -n 's/^# expect: //p' $f)
    out=$($FC $f $T/x.s 2>&1)
    if [ $? -ne 0 ] && echo "$out" | grep -qF -- "$want"; then
        echo "PASS own-${f%.cud}"
    else
        echo "FAIL own-${f%.cud}: $out"; fail=1
    fi
done
rm -rf $T
exit $fail
