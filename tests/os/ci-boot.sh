#!/bin/bash
# tests/os/ci-boot.sh: the public CI kernel boot (.github/workflows/ci.yml, job boot-o0). The kernel, its user
# programs and modules and the EFI disk are built with CUDC_FLAGS=-O0, then the kernel boots once in headless QEMU
# (BIOS, GRUB multiboot2, 4 CPUs, the GPT disk as a read-only virtio-blk data disk, as os/kernel-bios) and must
# reach KERNEL OK on the serial console and on the framebuffer (tests/os/boot.cud). No retry: a hang is a FAIL
# (FORGE_BOOT_NO_RETRY=1). Needs build.sh's build/ plus qemu-system-x86_64, grub-mkrescue, xorriso and mtools from
# the host's distro packages. Prints PASS/FAIL lines; exit 1 on any FAIL. TIMEOUT (default 300 s) is the boot's
# timeout passed to the harness. The full OS suite (tests/os/run.sh, 45 results) is the gate on the dev box.
cd "$(dirname "$0")/../.."
L=build/os-ci; rm -rf $L; mkdir -p $L; B=$L/boot; T=${TIMEOUT:-300}
fail() { echo "FAIL $1"; [ -f "$2" ] && tail -n 40 "$2"; exit 1; }
{ CUDC_FLAGS=-O0 ./cuditor examples/kernel/build.cud -o build/kernel-build && CUDC_FLAGS=-O0 build/kernel-build; } > $L/kernel-build.log 2>&1 || fail ci/kernel-build-O0 $L/kernel-build.log
{ CUDC_FLAGS=-O0 ./cuditor examples/efi/build.cud -o build/efi-build && CUDC_FLAGS=-O0 build/efi-build; } > $L/efi-build.log 2>&1 || fail ci/efi-build-O0 $L/efi-build.log
echo "PASS ci/kernel-build-O0 ($(stat -c %s build/kernel/kernel.elf) bytes)"
build/cudc tests/os/boot.cud $L/boot.s && build/fas -o $L/boot.o $L/boot.s && build/fld --base 0x100000000000 -o $B $L/boot.o || fail ci/boot-harness-build
cp build/efi/disk.img $L/vdisk.img && mdel -i $L/vdisk.img@@1048576 ::/EFI/BOOT/BOOTX64.EFI || fail ci/vdisk
VD="-drive file=$L/vdisk.img,format=raw,if=none,id=vd,readonly=on -device virtio-blk-pci,drive=vd"
Q="-cpu max -display none -no-reboot -net none -m 256 -smp 4 -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04"
FORGE_BOOT_NO_RETRY=1 $B kernel-bios-O0 $L/bios.log $T "multiboot2 (BIOS)|KERNEL OK" "back == front^KERNEL OK" -- $Q $VD -boot d -cdrom build/kernel/forge.iso > $L/result.txt 2>&1
cat $L/result.txt
grep -q "^PASS os/kernel-bios-O0" $L/result.txt && ! grep -qE "^(FAIL|HANG)" $L/result.txt || fail ci/kernel-bios-O0 $L/bios.log
