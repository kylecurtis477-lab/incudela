#!/bin/sh
# tests/efi-build: examples/efi/build.cud (built to build/efi-build) must do exactly what examples/efi/build.sh
# (kept as the reference) does: same stdout, stderr and exit code, and the same build/efi artifacts (loader,
# ESP image, GPT disk, mkgpt, big.bin, notes.txt) with identical bytes and modes. Both runs pin the mtools
# timestamps (SOURCE_DATE_EPOCH), the FAT volume serial (tools/repro-mformat, low 32 bits of the epoch) and the
# GPT GUIDs (INCUDELA_GUID_SEED), so esp.fat and disk.img must be byte-identical. efi-build/esp-reproducible
# builds the script twice and compares sha256 of those two images. The missing-input case hides
# examples/efi/scripts/hello.sh: mcopy must fail with the same message and exit code in both, leaving the same
# partial build/efi. efi-build/mformat-last-sector checks tools/repro-mformat against a shim for mtools before 4.0.48.
# Needs build/ (cudc, fas, fld and the kernel/user/modules artifacts): run after build.sh.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf $T' EXIT
fail=0
./cuditor examples/efi/build.cud -o build/efi-build >/dev/null || { echo "FAIL efi-build build"; exit 1; }
export SOURCE_DATE_EPOCH=1700000000 INCUDELA_GUID_SEED=7
[ -d build/efi ] && cp -a build/efi $T/orig
man() { (cd $1 && stat -c '%a %n' * && sha256sum *); }
chk() {
  rm -rf build/efi; CUDC_FLAGS="$2" sh examples/efi/build.sh >$T/s.out 2>$T/s.err; rs=$?
  rm -rf $T/sh; cp -a build/efi $T/sh
  rm -rf build/efi; (cd / && CUDC_FLAGS="$2" "$OLDPWD/build/efi-build" >$T/f.out 2>$T/f.err); rf=$?
  rm -rf $T/fg; cp -a build/efi $T/fg
  man $T/sh >$T/m1 2>&1; man $T/fg >$T/m2 2>&1
  if [ $rs = $rf ] && cmp -s $T/s.out $T/f.out && cmp -s $T/s.err $T/f.err && cmp -s $T/m1 $T/m2 \
     && [ "$(ls $T/fg | wc -l)" = $3 ]; then echo "PASS efi-build/$1"; else echo "FAIL efi-build/$1 (rc $rs/$rf)"; diff $T/m1 $T/m2 | head -5; diff $T/s.err $T/f.err | head -5; fail=1; fi
}
chk default "" 10
# two clean script builds (the default chk already ran one, with CUDC_FLAGS=""); require byte-identical ESP and GPT
# disk. The second build pins the same (empty) CUDC_FLAGS: under the O0 gate pass the inherited -O0 would build
# a different kernel.elf (every bounds check kept since -O0 is real in freestanding code) and change the ESP.
if [ -f $T/sh/esp.fat ] && [ -f $T/sh/disk.img ]; then
  rm -rf build/efi
  CUDC_FLAGS="" sh examples/efi/build.sh >$T/s2.out 2>$T/s2.err
  rs2=$?
  if [ $rs2 = 0 ] && cmp -s $T/sh/esp.fat build/efi/esp.fat && cmp -s $T/sh/disk.img build/efi/disk.img; then
    hs=$(sha256sum < build/efi/esp.fat | awk '{print $1}')
    hd=$(sha256sum < build/efi/disk.img | awk '{print $1}')
    echo "PASS efi-build/esp-reproducible (esp.fat $hs disk.img $hd)"
  else
    echo "FAIL efi-build/esp-reproducible (rc $rs2)"
    cmp -l $T/sh/esp.fat build/efi/esp.fat 2>/dev/null | head -5
    fail=1
  fi
else
  echo "FAIL efi-build/esp-reproducible (missing images from default build)"
  fail=1
fi
chk O0 "-O0" 10
mv examples/efi/scripts/hello.sh $T/hello.sh
chk missing-input "" 6
mv $T/hello.sh examples/efi/scripts/hello.sh
# efi-build/mformat-last-sector: mformat -C sizes a new image by writing its last sector, and before mtools 4.0.48
# that write came from an uninitialized buffer (Ubuntu 24.04's 4.0.43: two clean builds' esp.fat and forge.iso
# differed there). A shim mformat that fills the new image's last sector with 0xa5 stands in for the old mtools;
# tools/repro-mformat run on it must give exactly the image the real mformat gives (and the shim's own image
# must differ, so the check can fail).
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
MF="-C -F -c 1 -T 131072 -v FORGE_ESP"
MFORMAT=$RM sh tools/repro-mformat $MF -i $T/m1.img :: && MFORMAT=$T/oldmformat sh tools/repro-mformat $MF -i $T/m2.img :: &&
  $T/oldmformat -N 6553F100 $MF -i $T/m3.img :: || echo "mformat failed"
if cmp -s $T/m1.img $T/m2.img && ! cmp -s $T/m1.img $T/m3.img; then echo "PASS efi-build/mformat-last-sector"
else echo "FAIL efi-build/mformat-last-sector"; cmp -l $T/m1.img $T/m2.img 2>&1 | head -3; fail=1; fi
rm -f $T/m1.img $T/m2.img $T/m3.img
rm -rf build/efi; [ -d $T/orig ] && cp -a $T/orig build/efi
exit $fail
