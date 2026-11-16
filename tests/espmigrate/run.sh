#!/bin/sh
# tests/espmigrate: tools/espmigrate.cud moves an ESP from the old \EFI\Forge\ to \EFI\Incudela\ (FAT images,
# no QEMU). copy writes only \EFI\Incudela\ and keeps \EFI\Forge\; finish removes \EFI\Forge\ only with a boot log
# from a kernel that booted from \EFI\Incudela\ and only while both folders are identical; every refusal leaves
# the image byte-identical, and no step changes anything outside the two folders. The write guard's decisions
# are checked one by one (--guard-selftest). Needs mtools (installed with the OS-test toolchain).
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf $T' EXIT
fail=0
ok() { echo "PASS espmigrate/$1"; }
no() { echo "FAIL espmigrate/$1"; fail=1; }
command -v mcopy >/dev/null && command -v mformat >/dev/null || { echo "FAIL espmigrate/mtools (mcopy/mformat missing)"; exit 1; }
./cuditor tools/espmigrate.cud -o build/espmigrate >/dev/null 2>&1 || { echo "FAIL espmigrate/build"; exit 1; }
M=build/espmigrate
$M --guard-selftest > $T/g.out; [ $? = 0 ] && grep -q "21/21 decisions right" $T/g.out && ok guard-selftest || { no guard-selftest; cat $T/g.out; }
# an old-layout disk: 1 MiB before the ESP (mtools IMG@@OFFSET, as on the GPT test disk), other loaders' folders,
# a long file name, an empty folder and a file larger than a cluster chain of a few sectors
mkesp() {
  rm -f $T/esp.fat $1
  mformat -C -F -c 1 -i $T/esp.fat -T 131072 -v FORGE_ESP :: || return 1
  mmd -i $T/esp.fat ::/EFI ::/EFI/BOOT ::/EFI/Microsoft ::/EFI/Forge ::/EFI/Forge/bin ::/EFI/Forge/docs ::/EFI/Forge/mod
  printf 'boot\n' > $T/b; head -c 200000 /dev/urandom > $T/big; printf 'notes\n' > $T/n; head -c 4096 /dev/urandom > $T/k
  mcopy -i $T/esp.fat $T/b ::/EFI/BOOT/BOOTX64.EFI && mcopy -i $T/esp.fat $T/b ::/EFI/Microsoft/bootmgfw.efi && \
  mcopy -i $T/esp.fat $T/k ::/EFI/Forge/kernel.elf && mcopy -i $T/esp.fat $T/big ::/EFI/Forge/docs/big.bin && \
  mcopy -i $T/esp.fat $T/n "::/EFI/Forge/docs/Long File Name Notes.txt" && mcopy -i $T/esp.fat $T/b ::/EFI/Forge/bin/sh || return 1
  { head -c 1048576 /dev/zero; cat $T/esp.fat; } > $1
}
I=$T/disk.img
D="$I@@1048576"
# the folders' contents (read only): FOLDER -> host dir
grab() { rm -rf $2; mkdir -p $2; mcopy -s -n -m -i "$D" "$1/*" $2/ 2>/dev/null; }
outside() { rm -rf $1; mkdir -p $1/boot $1/ms; mcopy -s -n -m -i "$D" "::/EFI/BOOT/*" $1/boot/ && mcopy -s -n -m -i "$D" "::/EFI/Microsoft/*" $1/ms/ && mdir -b -i "$D" ::/ ::/EFI | sed 's|/$||' | sort > $1/list; }
mkesp $I || { no image; exit 1; }
grab ::/EFI/Forge $T/forge0; outside $T/out0
$M copy "$D" > $T/c.out; rc=$?
grab ::/EFI/Incudela $T/inc1; grab ::/EFI/Forge $T/forge1
[ $rc = 0 ] && grep -q "copied \\\\EFI\\\\Forge\\\\ to \\\\EFI\\\\Incudela\\\\ (4 files" $T/c.out && diff -r $T/forge0 $T/inc1 >/dev/null && [ -d $T/inc1/mod ] && \
  [ -f "$T/inc1/docs/Long File Name Notes.txt" ] && ok copy-identical || { no copy-identical; cat $T/c.out; }
diff -r $T/forge0 $T/forge1 >/dev/null && ok copy-keeps-forge || no copy-keeps-forge
outside $T/out1; sed -i '/[Ii]ncudela/d' $T/out1/list; diff -r $T/out0 $T/out1 >/dev/null && ok copy-nothing-else-written || no copy-nothing-else-written
h=$(sha256sum < $I); $M copy "$D" > $T/c2.out; rc=$?
[ $rc = 0 ] && grep -q "already copied" $T/c2.out && [ "$(sha256sum < $I)" = "$h" ] && ok copy-again-no-write || { no copy-again-no-write; cat $T/c2.out; }
# finish without a proof of a boot from \EFI\Incudela\: refused, image unchanged
refuse() { # name log
  h=$(sha256sum < $I); $M finish "$D" $2 > $T/f.out; rc=$?
  [ $rc = 1 ] && [ "$(sha256sum < $I)" = "$h" ] && grep -qF '\EFI\Forge\ kept' $T/f.out && ok finish-refused-$1 || { no finish-refused-$1; cat $T/f.out; }
}
refuse no-log $T/none.log
printf 'KERNEL OK\n' > $T/l1; refuse no-esp-line $T/l1
printf 'ESP: kernel files under \\EFI\\Incudela\\\n' > $T/l2; refuse no-kernel-ok $T/l2
printf 'Incudela UEFI loader: no \\EFI\\Incudela\\, booting the old \\EFI\\Forge\\kernel.elf\nESP: kernel files under \\EFI\\Incudela\\\nKERNEL OK\n' > $T/l3; refuse loader-used-old $T/l3
printf 'ESP: kernel files under \\EFI\\Incudela\\\nKERNEL OK\n' > $T/good.log
cp $I $T/keep.img
printf 'changed\n' > $T/x; mcopy -o -i "$D" $T/x ::/EFI/Incudela/bin/sh; refuse folders-differ $T/good.log
cp $T/keep.img $I
# copy over a different \EFI\Incudela\: refused, nothing written
cp $I $T/keep2.img; mcopy -o -i "$D" $T/x ::/EFI/Incudela/bin/sh; h=$(sha256sum < $I); $M copy "$D" > $T/c3.out; rc=$?
[ $rc = 1 ] && [ "$(sha256sum < $I)" = "$h" ] && ok copy-refuses-different-target || { no copy-refuses-different-target; cat $T/c3.out; }
cp $T/keep2.img $I
# finish with the proof: \EFI\Forge\ gone, \EFI\Incudela\ still the old contents, nothing else changed
$M finish "$D" $T/good.log > $T/f2.out; rc=$?
grab ::/EFI/Incudela $T/inc2
[ $rc = 0 ] && grep -q "removed \\\\EFI\\\\Forge\\\\" $T/f2.out && ! mdir -b -i "$D" ::/EFI/Forge >/dev/null 2>&1 && diff -r $T/forge0 $T/inc2 >/dev/null && ok finish-removes-forge || { no finish-removes-forge; cat $T/f2.out; }
outside $T/out2; sed -i '/[Ii]ncudela/d; /[Ff]orge/d' $T/out2/list; sed -i '/[Ff]orge/d' $T/out0/list
diff -r $T/out0 $T/out2 >/dev/null && ok finish-nothing-else-written || no finish-nothing-else-written
h=$(sha256sum < $I); $M finish "$D" $T/good.log > $T/f3.out; rc=$?; $M copy "$D" > $T/c4.out; rc2=$?
[ $rc = 0 ] && [ $rc2 = 0 ] && grep -q "nothing to do" $T/f3.out && grep -q "nothing to do" $T/c4.out && [ "$(sha256sum < $I)" = "$h" ] && ok migrated-is-final || no migrated-is-final
# the image the build makes is already on the new layout
if [ -f build/efi/esp.fat ]; then
  $M status build/efi/esp.fat | grep -q "Incudela\\\\ present, \\\\EFI\\\\Forge\\\\ absent" && ok build-esp-new-layout || no build-esp-new-layout
fi
$M > /dev/null; [ $? = 2 ] && ok usage || no usage
exit $fail
