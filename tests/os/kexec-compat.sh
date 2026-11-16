#!/bin/bash
# tests/os/kexec-compat.sh: old-to-new kexec handoff. Every other kexec test hands over between two kernels built
# from the same tree, so a record layout change on both sides would still agree with itself. Here the first
# kernel is built from an older commit (KXC_OLD, default 61b3e85: the last one before the Stage 3e/3f run queue
# and handoff-record conversions) and it kexecs into this tree's kernel-next.elf, which must adopt the old
# kernel's handoff (format v5, process-state v2 records, driver-state record), then hand over once more to itself.
#   kexec-compat-build    the old tree (git archive of KXC_OLD, no worktree, no change to this repository; old
#                         build plus the 411b601 self-test teardown fix, handoff format untouched) builds
#                         its compiler, kernel, ISO and ESP disk; user programs are sealed with this tree's key so
#                         both kernels trust the same images; the old kernel differs from this tree's kernel.elf
#   kexec-old-to-new      BIOS boot of the old ISO, the usual shell session, `kexec next` into the new kernel
#                         (generation 1) and again (generation 2), with the processes, the fd and the input
#                         service state carried across
# KXC_BUILD_ONLY=1 stops after the build (no QEMU).
cd "$(dirname "$0")/../.."
OLD=${KXC_OLD:-61b3e85}
Q="-cpu max -display none -no-reboot -net none -m 256 -smp 4 -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04"
L=build/os
B=$L/boot
FB="back == front^KERNEL OK"
mkdir -p $L
T=$(mktemp -d /tmp/forge-kxcompat.XXXXXX)
trap 'rm -rf $T' EXIT
fail_all() { for n in kexec-compat-build kexec-old-to-new; do echo "FAIL os/$n ($1)"; done; exit 0; }
[ -f build/kernel/kernel.elf ] && [ -f build/kernel/kernel-next.elf ] && [ -f build/user/seal.key ] && [ -f build/user/seal2.key ] || fail_all "needs this tree's kernel and user builds"
git rev-parse -q --verify "$OLD^{commit}" >/dev/null || fail_all "commit $OLD not in this repository"
# the old tree, built like a fresh checkout; its logs stay in $L for a failure report
O=$T/old
mkdir -p $O && git archive "$OLD" | tar -x -C $O || fail_all "git archive $OLD"
# old build plus the 411b601 self-test teardown fix; the handoff format is untouched. The old tlb_test freed its
# workers once they had reported, while they could still be running, and panicked "thread_free: thread still
# alive" under host load (inv167 repeats); this one line makes it reap them (wait for T_DEAD) like this tree does
OK=$O/examples/kernel/kernel.cud; [ -f $OK ] || OK=$O/examples/kernel/kernel.forge
FREE="^        thread_free(ptr\[Thread\](ths\[i\]))$"
if [ "$(grep -c "$FREE" $OK)" = 1 ]; then
  sed -i "s/$FREE/        thread_reap(ptr[Thread](ths[i]))/" $OK
  grep -q "$FREE" $OK && fail_all "tlb_test teardown fix did not apply to $OLD"
elif grep -q "$FREE" $OK; then
  fail_all "more than one tlb_test-style thread_free in $OLD"
fi
mkdir -p $O/build/user && cp build/user/seal.key build/user/seal2.key $O/build/user/ || fail_all "seal keys"
( cd $O && ./build.sh ) > $L/kxcompat-build.log 2>&1
grep -q "^SEED OK" $L/kxcompat-build.log || fail_all "old compiler build, see $L/kxcompat-build.log"
grep -q "fas: " $L/kxcompat-build.log && fail_all "old compiler build has fas errors, see $L/kxcompat-build.log"
# the old tree is driven by its own names (before the Cuditor rename: ./forge and .forge sources)
X=cud; [ -f $O/examples/kernel/build.cud ] || X=forge
DRV=./cuditor; [ -x $O/cuditor ] || DRV=./forge
( cd $O && $DRV examples/kernel/build.$X -o build/kernel-build && build/kernel-build && \
  $DRV examples/efi/build.$X -o build/efi-build && build/efi-build ) >> $L/kxcompat-build.log 2>&1 || fail_all "old kernel/efi build, see $L/kxcompat-build.log"
[ -f $O/build/kernel/forge.iso ] && [ -f $O/build/efi/disk.img ] || fail_all "old artifacts missing"
cmp -s $O/build/kernel/kernel.elf build/kernel/kernel.elf && fail_all "the old kernel.elf is identical to this tree's"
cmp -s $O/build/user/seal.pub build/user/seal.pub || fail_all "old and new builds trust different seal keys"
# the old ESP, with this tree's kernel-next.elf as the kexec target (only \EFI\Forge\ is written, in a test copy)
cp $O/build/efi/disk.img $T/vdisk.img && mdel -i $T/vdisk.img@@1048576 ::/EFI/BOOT/BOOTX64.EFI && \
  mcopy -o -i $T/vdisk.img@@1048576 build/kernel/kernel-next.elf ::/EFI/Forge/kernel-next.elf || fail_all "vdisk"
echo "PASS os/kexec-compat-build (old $OLD = $(git rev-parse --short "$OLD"), kernel.elf differs, same seal key)"
[ "$KXC_BUILD_ONLY" = 1 ] && exit 0
[ -x $B ] || { echo "FAIL os/kexec-old-to-new (needs the boot harness from tests/os/run.sh)"; exit 0; }
VD="-drive file=$T/vdisk.img,format=raw,if=none,id=vd,readonly=on -device virtio-blk-pci,drive=vd"
M="multiboot2 (BIOS)|kernel version: forge-kernel 0.2.6|KERNEL OK|kexec: generation 1 kernel (kernel-next.elf) loaded at"
M="$M|kexec: handoff format v5 from forge-kernel 0.2.6 (this kernel, incudela-kernel 0.2.6-next, adopts v5..v5)"
M="$M|kexec: generation 1 kernel adopted|hashes ok; handoff region|sh: survived kexec: |hello: args = 'after kexec'"
M="$M|driver state carried across kexec OK|kexec handoff OK|kexec: generation 2 kernel adopted"
FORGE_BOOT_KEXEC=2 $B kexec-old-to-new $L/kxcompat.log 200 "$M" "$FB" -- $Q $VD -boot d -cdrom $O/build/kernel/forge.iso
