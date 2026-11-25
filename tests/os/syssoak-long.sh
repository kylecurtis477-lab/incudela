#!/bin/bash
# tests/os/syssoak-long.sh: item 7 batch 4 multi-hour soak support, a short
# deterministic OS test. Builds the host recorder (tools/syssoak.cud), runs its
# no-QEMU --self-test (a clean checkpoint is recorded and a full --check is
# refused; a FAIL checkpoint and an old-tree log are refused), then boots the
# kernel ISO once with `incudela.syssoaklong`. The kernel skips the long shell
# and kexec sessions, launches examples/user/syssoak.cud as `syssoak 1 16 100 1`
# (a 1-tick budget, 10 ms), and the recorder writes
# build/os/syssoak-long-results.txt. The budget expires after the first seed;
# the guest must print a checkpoint and exit 0 so a later session can resume.
# Fails on the tree before this harness (unknown cmdline, no checkpoint). This
# is not itself a multi-hour soak.
# Invoked from tests/os/run.sh after the ISO and vdisk exist:
#   bash tests/os/syssoak-long.sh $B $L $Q $VD
B=$1; L=$2; shift 2
ISO=build/kernel/forge.iso
[ -x "$B" ] && [ -f "$ISO" ] || { echo "FAIL os/syssoak-long (need boot harness and $ISO)"; exit 0; }
if ! build/cudc tools/syssoak.cud $L/syssoak-long-host.s >/dev/null 2>$L/syssoak-long-host.err \
   || ! build/fas -o $L/syssoak-long-host.o $L/syssoak-long-host.s >/dev/null 2>>$L/syssoak-long-host.err \
   || ! build/fld --base 0x100000000000 -o $L/syssoak-long-host $L/syssoak-long-host.o >/dev/null 2>>$L/syssoak-long-host.err; then
  echo "FAIL os/syssoak-long (host harness build failed)"
  exit 0
fi
if ! $L/syssoak-long-host --self-test >$L/syssoak-long-self-test.out 2>&1; then
  echo "FAIL os/syssoak-long (host --self-test; see $L/syssoak-long-self-test.out)"
  exit 0
fi
[ -f build/kernel/iso/boot/grub/grub.cfg ] || { echo "FAIL os/syssoak-long (need build/kernel/iso)"; exit 0; }
T=$(mktemp -d /tmp/forge-syssoak-long.XXXXXX)
trap 'rm -rf $T' EXIT
cp -r build/kernel/iso $T/iso
sed -i 's|multiboot2 /boot/kernel.elf$|multiboot2 /boot/kernel.elf incudela.syssoaklong|' $T/iso/boot/grub/grub.cfg
grep -q 'incudela.syssoaklong' $T/iso/boot/grub/grub.cfg || { echo "FAIL os/syssoak-long (grub.cfg edit failed)"; exit 0; }
if ! tools/repro-mkrescue -o $L/syssoak-long.iso $T/iso >/dev/null 2>$L/syssoak-long-iso.err; then
  echo "FAIL os/syssoak-long (repro-mkrescue failed)"
  exit 0
fi
FB=${FORGE_BOOT_SYSSOAKLONG_FB:-"back == front^KERNEL OK"}
MARK="syssoak: start 1, 16 seeds, 100 calls each, budget 1 ticks|syssoak: seed 1 n 100 result PASS|syssoak: checkpoint next 2 done 1 fail 0|syssoak: CHECKPOINT|syssoak-long: kernel reaped exit 0|KERNEL OK|debug-exit "
out=$($B syssoak-long-boot $L/syssoak-long.log 200 "$MARK" "$FB" -- "$@" -boot d -cdrom $L/syssoak-long.iso 2>&1) || true
echo "$out" >$L/syssoak-long-boot.out
echo "$out" | grep -q "^PASS os/syssoak-long-boot " || { echo "FAIL os/syssoak-long (boot [$out])"; exit 0; }
# The budget must not have run the full 16-seed session.
if grep -q "syssoak: 16 seeds, 16 PASS" $L/syssoak-long.log; then
  echo "FAIL os/syssoak-long (budget did not stop the soak; see $L/syssoak-long.log)"
  exit 0
fi
if ! $L/syssoak-long-host --record $L/syssoak-long.log $L/syssoak-long-results.txt >$L/syssoak-long-record.out 2>&1; then
  echo "FAIL os/syssoak-long (record; $(cat $L/syssoak-long-record.out))"
  exit 0
fi
if ! $L/syssoak-long-host --check-checkpoint $L/syssoak-long-results.txt 1 >$L/syssoak-long-check.out 2>&1; then
  echo "FAIL os/syssoak-long (check-checkpoint; $(cat $L/syssoak-long-check.out))"
  exit 0
fi
if $L/syssoak-long-host --check $L/syssoak-long-results.txt 1 >$L/syssoak-long-fullcheck.out 2>&1; then
  echo "FAIL os/syssoak-long (full --check accepted a checkpoint)"
  exit 0
fi
nxt=$($L/syssoak-long-host --resume $L/syssoak-long-results.txt 2>/dev/null) || nxt=""
[ "$nxt" = "2" ] || { echo "FAIL os/syssoak-long (resume was '$nxt', want 2)"; exit 0; }
echo "PASS os/syssoak-long"
exit 0
