#!/bin/sh
# Build the Incudela kernel (ELF64 multiboot2) and a BIOS+UEFI hybrid GRUB ISO.
set -e
cd "$(dirname "$0")"
B=../../build/kernel; mkdir -p $B/iso/boot/grub
# image KASLR: tools/fld --format kernel lays the image out (low boot stub at 1 MiB, the rest at
# -2 GiB + phys) and writes the self-relocation table (.krel, last) from the relocations it applies
klink() {
    ../../build/fld --format kernel -o $1.elf $1.o
}
# the user programs: examples/user/build.cud, BusyBox via build/busybox-build (tools/busybox/build.cud);
# examples/user/build.sh and tools/busybox/build.sh are kept as the references (tests/user-build, tests/busybox-build)
../../cuditor ../../tools/busybox/build.cud -o ../../build/busybox-build
../../cuditor ../user/build.cud -o ../../build/user-build
../../build/user-build
# the test modules: examples/modules/build.cud (examples/modules/build.sh is kept as the reference;
# tests/modules-build checks they produce identical artifacts)
../../cuditor ../modules/build.cud -o ../../build/modules-build
../../build/modules-build
../../build/cudc kernel.cud $B/kernel.s --fs-temps $CUDC_FLAGS
../../build/fas -I ../../build/user -o $B/kernel.o $B/kernel.s
klink $B/kernel
grub-file --is-x86-multiboot2 $B/kernel.elf
# a genuinely different build for the kexec test (\EFI\Forge\kernel-next.elf): another version string
sed 's/"incudela-kernel 0.2.6"/"incudela-kernel 0.2.6-next"/' kernel.cud > .kernel_next.cud
grep -q '"incudela-kernel 0.2.6-next"' .kernel_next.cud
../../build/cudc .kernel_next.cud $B/kernel-next.s --fs-temps $CUDC_FLAGS; rm -f .kernel_next.cud
../../build/fas -I ../../build/user -o $B/kernel-next.o $B/kernel-next.s
klink $B/kernel-next
cmp -s $B/kernel.elf $B/kernel-next.elf && { echo "kernel-next.elf is identical to kernel.elf"; exit 1; }
cp $B/kernel.elf $B/iso/boot/kernel.elf
cp grub.cfg $B/iso/boot/grub/grub.cfg
# ISO UUID/date and the El Torito FAT serial: tools/repro-mkrescue pins them from SOURCE_DATE_EPOCH
../../tools/repro-mkrescue -o $B/forge.iso $B/iso >/dev/null 2>&1
echo "built $B/kernel.elf and $B/forge.iso"
