#!/bin/sh
# tests/repro-mformat: tools/repro-mformat.cud must agree with tools/repro-mformat
# (kept as the reference). Does not start QEMU.
set -e
cd "$(dirname "$0")/../.."
T=$(mktemp -d)
trap 'rm -rf $T' EXIT

build/cudc tools/repro-mformat.cud $T/m.s && build/fas -o $T/m.o $T/m.s && build/fld --base 0x100000000000 -o $T/repro-mformat $T/m.o || { echo "FAIL repro-mformat build"; exit 1; }
# The binary lives in build/ so later callers can use it; this test invokes it from here too.
cp -p $T/repro-mformat build/repro-mformat

EPOCH=1700000000
# 1700000000 & 0xffffffff = 0x6553F100, same as efi-build/mformat-last-sector
MF="-C -F -c 1 -T 131072 -v FORGE_ESP"
fail=0

# Normal build with the epoch: same image, rc, stdout, stderr as the shell.
shr=0; SOURCE_DATE_EPOCH=$EPOCH sh tools/repro-mformat $MF -i $T/sh.img :: >$T/sh.out 2>$T/sh.err || shr=$?
for=0; SOURCE_DATE_EPOCH=$EPOCH build/repro-mformat $MF -i $T/fo.img :: >$T/fo.out 2>$T/fo.err || for=$?
if [ "$shr" = 0 ] && [ "$for" = 0 ] && cmp -s $T/sh.out $T/fo.out && cmp -s $T/sh.err $T/fo.err && cmp -s $T/sh.img $T/fo.img; then
  echo "PASS repro-mformat/default (rc=0 $(stat -c %s $T/fo.img) bytes, serial 6553F100)"
else
  echo "FAIL repro-mformat/default (sh rc=$shr forge rc=$for)"
  fail=1
fi

# Second Cuditor build is byte-identical.
fo2=0; SOURCE_DATE_EPOCH=$EPOCH build/repro-mformat $MF -i $T/fo2.img :: >$T/fo2.out 2>$T/fo2.err || fo2=$?
if [ "$fo2" = 0 ] && cmp -s $T/fo.img $T/fo2.img && cmp -s $T/fo.out $T/fo2.out && cmp -s $T/fo.err $T/fo2.err; then
  echo "PASS repro-mformat/reproducible"
else
  echo "FAIL repro-mformat/reproducible (rc=$fo2)"
  fail=1
fi

# An explicit -N wins over the epoch.
shr=0; SOURCE_DATE_EPOCH=$EPOCH sh tools/repro-mformat -N DEADBEEF $MF -i $T/shN.img :: >$T/shN.out 2>$T/shN.err || shr=$?
for=0; SOURCE_DATE_EPOCH=$EPOCH build/repro-mformat -N DEADBEEF $MF -i $T/foN.img :: >$T/foN.out 2>$T/foN.err || for=$?
if [ "$shr" = 0 ] && [ "$for" = 0 ] && cmp -s $T/shN.img $T/foN.img && cmp -s $T/shN.out $T/foN.out && cmp -s $T/shN.err $T/foN.err && ! cmp -s $T/fo.img $T/foN.img; then
  echo "PASS repro-mformat/explicit-N"
else
  echo "FAIL repro-mformat/explicit-N (sh rc=$shr forge rc=$for)"
  fail=1
fi

# Argv: with the epoch, both prepend -N 6553F100; without it, both pass the original args through.
{
  echo '#!/bin/sh'
  echo 'printf "%s\n" "$@" > "$RECORD"'
  echo 'exit 0'
} > $T/rec
chmod +x $T/rec

RECORD=$T/sh.args SOURCE_DATE_EPOCH=$EPOCH MFORMAT=$T/rec sh tools/repro-mformat $MF -i $T/unused.img ::
RECORD=$T/fo.args SOURCE_DATE_EPOCH=$EPOCH MFORMAT=$T/rec build/repro-mformat $MF -i $T/unused.img ::
if cmp -s $T/sh.args $T/fo.args && grep -q '^-N$' $T/fo.args && grep -q '^6553F100$' $T/fo.args; then
  echo "PASS repro-mformat/argv-epoch"
else
  echo "FAIL repro-mformat/argv-epoch"
  echo " sh: $(tr '\n' ' ' < $T/sh.args)"
  echo " fo: $(tr '\n' ' ' < $T/fo.args)"
  fail=1
fi

unset SOURCE_DATE_EPOCH
RECORD=$T/sh0.args MFORMAT=$T/rec sh tools/repro-mformat $MF -i $T/unused.img ::
RECORD=$T/fo0.args MFORMAT=$T/rec build/repro-mformat $MF -i $T/unused.img ::
if cmp -s $T/sh0.args $T/fo0.args && ! grep -q '^-N$' $T/fo0.args; then
  echo "PASS repro-mformat/argv-no-epoch"
else
  echo "FAIL repro-mformat/argv-no-epoch"
  echo " sh: $(tr '\n' ' ' < $T/sh0.args)"
  echo " fo: $(tr '\n' ' ' < $T/fo0.args)"
  fail=1
fi

# Last-sector zeroing, same shape as efi-build/mformat-last-sector: a shim that fills the
# last sector with 0xa5 stands in for mtools before 4.0.48. The Cuditor tool must make
# the same image as the shell (and as real mformat), and the shim's own image must differ.
RM=$(command -v mformat)
{
  echo '#!/bin/sh'
  echo "$RM"' "$@" || exit $?'
  echo 'img=; p='
  echo 'for a in "$@"; do [ "$p" = -i ] && img=$a; p=$a; done'
  echo 's=$(wc -c < "$img")'
  printf '%s\n' "tr '\\000' '\\245' < /dev/zero | dd of=\"\$img\" bs=512 count=1 seek=\$((s / 512 - 1)) conv=notrunc iflag=fullblock status=none"
} > $T/oldmformat
chmod +x $T/oldmformat
SOURCE_DATE_EPOCH=$EPOCH MFORMAT=$RM sh tools/repro-mformat $MF -i $T/m1.img ::
SOURCE_DATE_EPOCH=$EPOCH MFORMAT=$T/oldmformat sh tools/repro-mformat $MF -i $T/m2.img ::
SOURCE_DATE_EPOCH=$EPOCH MFORMAT=$T/oldmformat build/repro-mformat $MF -i $T/m2f.img ::
SOURCE_DATE_EPOCH=$EPOCH $T/oldmformat -N 6553F100 $MF -i $T/m3.img :: || echo "mformat failed"
if cmp -s $T/m1.img $T/m2.img && cmp -s $T/m2.img $T/m2f.img && ! cmp -s $T/m1.img $T/m3.img; then
  echo "PASS repro-mformat/last-sector"
else
  echo "FAIL repro-mformat/last-sector"
  fail=1
fi

# Missing mformat: both fail with the same exit code.
shr=0; SOURCE_DATE_EPOCH=$EPOCH MFORMAT=/no/such/mformat sh tools/repro-mformat $MF -i $T/miss.img :: >$T/sh-miss.out 2>$T/sh-miss.err || shr=$?
for=0; SOURCE_DATE_EPOCH=$EPOCH MFORMAT=/no/such/mformat build/repro-mformat $MF -i $T/miss2.img :: >$T/fo-miss.out 2>$T/fo-miss.err || for=$?
# stderr text may differ (shell vs os.run); require a non-zero rc on both and no image.
if [ "$shr" != 0 ] && [ "$for" != 0 ] && [ ! -f $T/miss.img ] && [ ! -f $T/miss2.img ]; then
  echo "PASS repro-mformat/missing-mformat (sh rc=$shr forge rc=$for)"
else
  echo "FAIL repro-mformat/missing-mformat (sh rc=$shr forge rc=$for)"
  fail=1
fi

exit $fail
