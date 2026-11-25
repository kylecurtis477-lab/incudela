#!/bin/bash
# tests/forge-build: tools/build.cud (built to build/forge-build) must do exactly what
# build.sh (kept as the reference) does: same stdout, stderr and exit code, and
# the same bootstrap artifacts (stage2/3/4, cudc, fas, fld, embed, runtime.s and
# the intermediate .s/.o plus stage3.chk) with identical bytes and modes.
# Cases: default, and missing-input (selfhost/runtime.cud hidden: both print
# "runtime.cud failed" and the same seed-compiler error, same exit code).
# Needs a working build/cudc (run after build.sh). Does not run QEMU.
# Reservation 6 batch 1: the run_tests.sh port stays a later batch.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
./cuditor tools/build.cud -o build/forge-build >/dev/null || { echo "FAIL build/forge-build build"; exit 1; }
ART="embed.s embed.o embed runtime.s stage2.s stage2.o stage2 fas.s fas.o fas fld.s fld.o fld stage3.s stage3.o stage3 stage4.s cudc stage3.chk.o stage3.chk"
snap() {
  mkdir -p "$1"
  for f in $ART; do
    if [ -e "build/$f" ]; then
      cp -a "build/$f" "$1/$f"
    fi
  done
}
man() {
  (cd "$1" && find . -type f | sort | xargs -r stat -c '%a %n' && find . -type f | sort | xargs -r sha256sum)
}

# default: a full bootstrap
sh ./build.sh >$T/s.out 2>$T/s.err; rs=$?
snap $T/sh
./build/forge-build >$T/f.out 2>$T/f.err; rf=$?
snap $T/fg
man $T/sh >$T/m1; man $T/fg >$T/m2
if [ $rs = $rf ] && cmp -s $T/s.out $T/f.out && cmp -s $T/s.err $T/f.err && cmp -s $T/m1 $T/m2 \
   && grep -q '^FIXPOINT OK:' $T/f.out && grep -q '^SEED OK:' $T/f.out && grep -q '^TOOLS OK:' $T/f.out \
   && grep -q '^SEED TOOLS OK:' $T/f.out; then
  echo "PASS build/default"
else
  echo "FAIL build/default (rc $rs/$rf)"
  diff -u $T/s.out $T/f.out | head -20
  diff -u $T/s.err $T/f.err | head -10
  diff -u $T/m1 $T/m2 | head -20
  fail=1
fi

# missing runtime.cud: both must fail the same way and not leave a new cudc from this run
# (the previous default run already left a working tree).
mv selfhost/runtime.cud selfhost/runtime.cud.bak
sh ./build.sh >$T/ms.out 2>$T/ms.err; mrs=$?
./build/forge-build >$T/mf.out 2>$T/mf.err; mrf=$?
mv selfhost/runtime.cud.bak selfhost/runtime.cud
if [ $mrs = $mrf ] && [ $mrs != 0 ] && cmp -s $T/ms.out $T/mf.out && cmp -s $T/ms.err $T/mf.err \
   && grep -q 'runtime.cud failed' $T/mf.out; then
  echo "PASS build/missing-input"
else
  echo "FAIL build/missing-input (rc $mrs/$mrf)"
  diff -u $T/ms.out $T/mf.out | head -20
  diff -u $T/ms.err $T/mf.err | head -10
  fail=1
fi

[ $fail = 0 ]
exit $fail
