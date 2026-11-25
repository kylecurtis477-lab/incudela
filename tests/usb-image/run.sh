#!/bin/sh
# tests/usb-image: tools/usb-image.cud must agree with tools/usb-image.sh (kept as the
# reference): identical stdout, stderr, exit code and image bytes on a normal build,
# and the same refusals for a /dev path, a directory, and a missing kernel ISO.
# This test does not start QEMU (the USB boots stay in tests/os/usb.sh).
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); ISOBAK=
trap 'if [ -d "$ISOBAK" ]; then mv "$ISOBAK" build/kernel/iso; fi; rm -rf $T' EXIT
fail=0
build/cudc tools/usb-image.cud $T/u.s && build/fas -o $T/u.o $T/u.s && build/fld --base 0x100000000000 -o $T/usb-image $T/u.o || { echo "FAIL usb-image build"; exit 1; }
# The binary must live in build/ so dirname/.. is the repo (same as tools/build.cud).
cp -p $T/usb-image build/usb-image

if [ ! -f build/kernel/iso/boot/grub/grub.cfg ] || [ ! -f build/kernel/iso/boot/kernel.elf ]; then
  echo "usb-image test: building kernel ISO first"
  examples/kernel/build.sh || { echo "FAIL usb-image kernel-build"; exit 1; }
fi

# Normal build to private paths: stdout, stderr, rc, and image bytes must match.
tools/usb-image.sh $T/sh.img >$T/sh.out 2>$T/sh.err; shr=$?
build/usb-image $T/fo.img >$T/fo.out 2>$T/fo.err; for=$?
# stdout names the path, so compare after substituting the path prefix
sed "s|$T/sh.img|OUT|;s|$T/fo.img|OUT|" $T/sh.out >$T/sh.out.n
sed "s|$T/sh.img|OUT|;s|$T/fo.img|OUT|" $T/fo.out >$T/fo.out.n
if [ $shr = $for ] && [ $shr = 0 ] && cmp -s $T/sh.out.n $T/fo.out.n && cmp -s $T/sh.err $T/fo.err && cmp -s $T/sh.img $T/fo.img; then
  echo "PASS usb-image/default (rc=0 $(stat -c %s $T/fo.img) bytes)"
else
  echo "FAIL usb-image/default (sh rc=$shr forge rc=$for)"
  echo " sh out=$(cat $T/sh.out) err=$(cat $T/sh.err)"
  echo " fo out=$(cat $T/fo.out) err=$(cat $T/fo.err)"
  fail=1
fi

# A second Cuditor build is byte-identical to the first (and to the shell).
build/usb-image $T/fo2.img >$T/fo2.out 2>$T/fo2.err; fo2=$?
if [ $fo2 = 0 ] && cmp -s $T/fo.img $T/fo2.img && cmp -s $T/sh.img $T/fo2.img; then
  echo "PASS usb-image/reproducible"
else
  echo "FAIL usb-image/reproducible (rc=$fo2)"
  fail=1
fi

# /dev path and a directory: same message and exit 2; the directory is left empty.
tools/usb-image.sh /dev/null >$T/sh-dev.out 2>$T/sh-dev.err; shr=$?
build/usb-image /dev/null >$T/fo-dev.out 2>$T/fo-dev.err; for=$?
# The shell writes the message to stderr; combine for a stable compare of the text + rc.
cat $T/sh-dev.out $T/sh-dev.err >$T/sh-dev.txt
cat $T/fo-dev.out $T/fo-dev.err >$T/fo-dev.txt
if [ $shr = $for ] && [ $shr = 2 ] && cmp -s $T/sh-dev.txt $T/fo-dev.txt; then
  echo "PASS usb-image/no-device"
else
  echo "FAIL usb-image/no-device (sh rc=$shr out=$(cat $T/sh-dev.txt), forge rc=$for out=$(cat $T/fo-dev.txt))"
  fail=1
fi

mkdir $T/dir
tools/usb-image.sh $T/dir >$T/sh-dir.out 2>$T/sh-dir.err; shr=$?
build/usb-image $T/dir >$T/fo-dir.out 2>$T/fo-dir.err; for=$?
cat $T/sh-dir.out $T/sh-dir.err >$T/sh-dir.txt
cat $T/fo-dir.out $T/fo-dir.err >$T/fo-dir.txt
if [ $shr = $for ] && [ $shr = 2 ] && cmp -s $T/sh-dir.txt $T/fo-dir.txt && [ -z "$(ls -A $T/dir)" ]; then
  echo "PASS usb-image/not-regular"
else
  echo "FAIL usb-image/not-regular (sh rc=$shr out=$(cat $T/sh-dir.txt), forge rc=$for out=$(cat $T/fo-dir.txt))"
  fail=1
fi

# Missing kernel ISO: hide iso briefly (this item runs in the alone lane).
ISOBAK=$T/iso.bak
mv build/kernel/iso "$ISOBAK"
tools/usb-image.sh $T/missing.img >$T/sh-miss.out 2>$T/sh-miss.err; shr=$?
build/usb-image $T/missing.img >$T/fo-miss.out 2>$T/fo-miss.err; for=$?
mv "$ISOBAK" build/kernel/iso
ISOBAK=
cat $T/sh-miss.out $T/sh-miss.err >$T/sh-miss.txt
cat $T/fo-miss.out $T/fo-miss.err >$T/fo-miss.txt
if [ $shr = $for ] && [ $shr = 1 ] && cmp -s $T/sh-miss.txt $T/fo-miss.txt && [ ! -e $T/missing.img ]; then
  echo "PASS usb-image/missing-iso"
else
  echo "FAIL usb-image/missing-iso (sh rc=$shr out=$(cat $T/sh-miss.txt), forge rc=$for out=$(cat $T/fo-miss.txt))"
  fail=1
  # if the hide failed to restore, say so
  [ -f build/kernel/iso/boot/kernel.elf ] || echo "FAIL usb-image/missing-iso (iso not restored)"
fi

exit $fail
