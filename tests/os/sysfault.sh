#!/bin/bash
# tests/os/sysfault.sh: item 7 batch 3 fault injection, a short deterministic OS test.
# Builds the host recorder (tools/sysfault.cud), runs its no-QEMU --self-test (an
# old-tree log with no sysfault lines is refused), then boots the kernel ISO once
# with `incudela.sysfault` on the command line. The kernel arms ktest_hooks, launches
# examples/user/sysfault.cud (408 b=2/3/4 kmalloc injection, a user-space error-path
# battery, then sysfuzz 1 50), and the recorder writes build/os/sysfault-results.txt.
# Fails on the tree before this harness. 408/409 stay ktest_hooks gated. Not a
# multi-hour soak. Invoked from tests/os/run.sh after the ISO and vdisk exist:
#   bash tests/os/sysfault.sh $B $L $Q $VD
B=$1; L=$2; shift 2
ISO=build/kernel/forge.iso
[ -x "$B" ] && [ -f "$ISO" ] || { echo "FAIL os/sysfault (need boot harness and $ISO)"; exit 0; }
if ! build/cudc tools/sysfault.cud $L/sysfault-host.s >/dev/null 2>$L/sysfault-host.err \
   || ! build/fas -o $L/sysfault-host.o $L/sysfault-host.s >/dev/null 2>>$L/sysfault-host.err \
   || ! build/fld --base 0x100000000000 -o $L/sysfault-host $L/sysfault-host.o >/dev/null 2>>$L/sysfault-host.err; then
  echo "FAIL os/sysfault (host harness build failed)"
  exit 0
fi
if ! $L/sysfault-host --self-test >$L/sysfault-self-test.out 2>&1; then
  echo "FAIL os/sysfault (host --self-test; see $L/sysfault-self-test.out)"
  exit 0
fi
[ -f build/kernel/iso/boot/grub/grub.cfg ] || { echo "FAIL os/sysfault (need build/kernel/iso)"; exit 0; }
T=$(mktemp -d /tmp/forge-sysfault.XXXXXX)
trap 'rm -rf $T' EXIT
cp -r build/kernel/iso $T/iso
sed -i 's|multiboot2 /boot/kernel.elf$|multiboot2 /boot/kernel.elf incudela.sysfault|' $T/iso/boot/grub/grub.cfg
grep -q 'incudela.sysfault' $T/iso/boot/grub/grub.cfg || { echo "FAIL os/sysfault (grub.cfg edit failed)"; exit 0; }
if ! tools/repro-mkrescue -o $L/sysfault.iso $T/iso >/dev/null 2>$L/sysfault-iso.err; then
  echo "FAIL os/sysfault (repro-mkrescue failed)"
  exit 0
fi
FB=${FORGE_BOOT_SYSFAULT_FB:-"back == front^KERNEL OK"}
MARK="sysfault: start seed 1, sysfuzz 50 calls|sysfault: alloc-inject PASS|sysfault: user-faults PASS|sysfault: sysfuzz PASS|sysfault: PASS|sysfault: kernel reaped exit 0|KERNEL OK|debug-exit "
out=$($B sysfault-boot $L/sysfault.log 200 "$MARK" "$FB" -- "$@" -boot d -cdrom $L/sysfault.iso 2>&1) || true
echo "$out" >$L/sysfault-boot.out
echo "$out" | grep -q "^PASS os/sysfault-boot " || { echo "FAIL os/sysfault (boot [$out])"; exit 0; }
if ! $L/sysfault-host --record $L/sysfault.log $L/sysfault-results.txt >$L/sysfault-record.out 2>&1; then
  echo "FAIL os/sysfault (record; $(cat $L/sysfault-record.out))"
  exit 0
fi
if ! $L/sysfault-host --check $L/sysfault-results.txt >$L/sysfault-check.out 2>&1; then
  echo "FAIL os/sysfault (check; $(cat $L/sysfault-check.out))"
  exit 0
fi
echo "PASS os/sysfault"
exit 0
