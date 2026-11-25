#!/bin/bash
# tests/os/syssoak.sh: item 7 batch 2 soak harness, a short deterministic OS test.
# Builds the host recorder (tools/syssoak.cud), runs its no-QEMU --self-test (the
# old-tree log with no syssoak lines is refused), then boots the kernel ISO once
# with `incudela.syssoak` on the command line. The kernel skips the long shell
# and kexec sessions, launches examples/user/syssoak.cud with 16 seeds x 100
# calls of sysfuzz, and the recorder writes build/os/syssoak-results.txt.
# Fails on the tree before this harness (unknown cmdline, no syssoak binary,
# no markers). Not a multi-hour soak.
# Invoked from tests/os/run.sh after the ISO and vdisk exist:
#   bash tests/os/syssoak.sh $B $L $Q $VD
B=$1; L=$2; shift 2
ISO=build/kernel/forge.iso
[ -x "$B" ] && [ -f "$ISO" ] || { echo "FAIL os/syssoak (need boot harness and $ISO)"; exit 0; }
if ! build/cudc tools/syssoak.cud $L/syssoak-host.s >/dev/null 2>$L/syssoak-host.err \
   || ! build/fas -o $L/syssoak-host.o $L/syssoak-host.s >/dev/null 2>>$L/syssoak-host.err \
   || ! build/fld --base 0x100000000000 -o $L/syssoak-host $L/syssoak-host.o >/dev/null 2>>$L/syssoak-host.err; then
  echo "FAIL os/syssoak (host harness build failed)"
  exit 0
fi
if ! $L/syssoak-host --self-test >$L/syssoak-self-test.out 2>&1; then
  echo "FAIL os/syssoak (host --self-test; see $L/syssoak-self-test.out)"
  exit 0
fi
[ -f build/kernel/iso/boot/grub/grub.cfg ] || { echo "FAIL os/syssoak (need build/kernel/iso)"; exit 0; }
T=$(mktemp -d /tmp/forge-syssoak.XXXXXX)
trap 'rm -rf $T' EXIT
# Copy the GRUB ISO tree (not a xorriso extract: ISO files are read-only) and add
# the soak token, same as tests/os/schedbench.sh. tools/repro-mkrescue is the
# wrapper the kernel-build path uses.
cp -r build/kernel/iso $T/iso
sed -i 's|multiboot2 /boot/kernel.elf$|multiboot2 /boot/kernel.elf incudela.syssoak|' $T/iso/boot/grub/grub.cfg
grep -q 'incudela.syssoak' $T/iso/boot/grub/grub.cfg || { echo "FAIL os/syssoak (grub.cfg edit failed)"; exit 0; }
if ! tools/repro-mkrescue -o $L/syssoak.iso $T/iso >/dev/null 2>$L/syssoak-iso.err; then
  echo "FAIL os/syssoak (repro-mkrescue failed)"
  exit 0
fi
FB=${FORGE_BOOT_SYSSOAK_FB:-"back == front^KERNEL OK"}
MARK="syssoak: start 1, 16 seeds, 100 calls each|syssoak: 16 seeds, 16 PASS, 0 FAIL, 100 calls each|syssoak: PASS|syssoak: kernel reaped exit 0|KERNEL OK|debug-exit "
out=$($B syssoak-boot $L/syssoak.log 200 "$MARK" "$FB" -- "$@" -boot d -cdrom $L/syssoak.iso 2>&1) || true
echo "$out" >$L/syssoak-boot.out
echo "$out" | grep -q "^PASS os/syssoak-boot " || { echo "FAIL os/syssoak (boot [$out])"; exit 0; }
if ! $L/syssoak-host --record $L/syssoak.log $L/syssoak-results.txt >$L/syssoak-record.out 2>&1; then
  echo "FAIL os/syssoak (record; $(cat $L/syssoak-record.out))"
  exit 0
fi
if ! $L/syssoak-host --check $L/syssoak-results.txt 16 >$L/syssoak-check.out 2>&1; then
  echo "FAIL os/syssoak (check; $(cat $L/syssoak-check.out))"
  exit 0
fi
echo "PASS os/syssoak"
exit 0
