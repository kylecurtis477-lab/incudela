#!/bin/bash
# tests/os/usb.sh: the USB smoke image (build/usb-image from tools/usb-image.cud; tools/usb-image.sh is the reference), five results. Approved addition (inv217):
# os/result-count went from 45 to 50 results.
#   os/usb-image-reproducible  two builds of the image from the same kernel are byte-identical, and its grub.cfg
#                              boots the kernel with `incudela.smoke`
#   os/usb-image-no-device     build/usb-image refuses a /dev path and a non-regular file (it only writes a file)
#   os/usb-esp-layout          the image's EFI system partition (the El Torito FAT grub-mkrescue makes) holds only the
#                              removable-media path \EFI\BOOT\BOOTX64.EFI (GRUB from the distro's modules)
#   os/usb-uefi, os/usb-bios   the image, attached only as a USB mass-storage device (qemu-xhci + usb-storage,
#                              read-only), boots under OVMF (q35) and under SeaBIOS to the smoke line and KERNEL OK on
#                              the serial console and the framebuffer; no other disk is attached; the image is
#                              unchanged afterwards
cd "$(dirname "$0")/../.."
USB_IMAGE=build/usb-image
if [ ! -x "$USB_IMAGE" ]; then
  build/cudc tools/usb-image.cud build/usb-image.s && build/fas -o build/usb-image.o build/usb-image.s && build/fld --base 0x100000000000 -o "$USB_IMAGE" build/usb-image.o || { echo "FAIL os/usb-image-build"; exit 1; }
fi
L=build/os
B=$L/boot
OVMF_CODE=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
OVMF_VARS=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
T=$(mktemp -d /tmp/forge-usb.XXXXXX)
trap 'chmod -R u+w $T 2>/dev/null; rm -rf $T' EXIT
R="os/usb-image-reproducible os/usb-image-no-device os/usb-esp-layout os/usb-uefi os/usb-bios"
[ -x $B ] || { for r in $R; do echo "FAIL $r (needs tests/os/run.sh outputs)"; done; exit 0; }
if $USB_IMAGE $T/a.img >/dev/null 2>$T/a.err && $USB_IMAGE $T/b.img >/dev/null 2>$T/b.err; then
  ha=$(sha256sum < $T/a.img | awk '{print $1}'); hb=$(sha256sum < $T/b.img | awk '{print $1}')
  xorriso -osirrox on -indev $T/a.img -extract /boot/grub/grub.cfg $T/grub.cfg >/dev/null 2>&1
  if [ "$ha" = "$hb" ] && grep -q '^    multiboot2 /boot/kernel.elf incudela.smoke$' $T/grub.cfg; then
    echo "PASS os/usb-image-reproducible ($(stat -c %s $T/a.img) bytes, sha256 $ha)"
  else
    echo "FAIL os/usb-image-reproducible ($ha vs $hb)"
  fi
else
  echo "FAIL os/usb-image-reproducible (build failed: $(head -c 200 $T/a.err $T/b.err))"
fi
o1=$($USB_IMAGE /dev/null 2>&1); r1=$?
mkdir $T/dir; o2=$($USB_IMAGE $T/dir 2>&1); r2=$?
if [ $r1 = 2 ] && [ $r2 = 2 ] && [ "$o1" = "usb-image: refusing /dev/null: this tool never writes to a device" ] && [ "$o2" = "usb-image: refusing $T/dir: not a regular file" ] && [ -z "$(ls -A $T/dir)" ]; then
  echo "PASS os/usb-image-no-device (/dev path and directory refused, exit 2)"
else
  echo "FAIL os/usb-image-no-device (rc $r1/$r2: $o1 / $o2)"
fi
xorriso -osirrox on -indev $T/a.img -extract /efi.img $T/efi.img >/dev/null 2>&1
F=$(mdir -/ -b -i $T/efi.img :: 2>/dev/null | tr 'A-Z' 'a-z' | sort | tr '\n' ' ')
[ "$F" = "::/efi/ ::/efi/boot/ ::/efi/boot/bootx64.efi " ] && echo "PASS os/usb-esp-layout (only \\EFI\\BOOT\\BOOTX64.EFI)" || echo "FAIL os/usb-esp-layout (${F:-no efi.img})"
[ -f $T/a.img ] || { echo "FAIL os/usb-uefi (no image)"; echo "FAIL os/usb-bios (no image)"; exit 0; }
H0=$(sha256sum < $T/a.img)
Q="-cpu max -display none -no-reboot -net none -m 256 -smp 4 -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04"
USB="-device qemu-xhci,id=xhci -drive if=none,id=usbstick,format=raw,readonly=on,file=$T/a.img -device usb-storage,bus=xhci.0,drive=usbstick,bootindex=1"
S="smoke (incudela.smoke): 4 cpus, |MiB free, fb 1024x768; CPU, memory, interrupts, timers, SMP scheduler, user mode and stop-machine checks done; disk, driver, module, shell and kexec tests skipped|KERNEL OK"
FB="back == front^KERNEL OK"
cp $OVMF_VARS $T/vars.fd
UEFI="-machine q35 -drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE -drive if=pflash,format=raw,file=$T/vars.fd"
$B usb-uefi $L/usb-uefi.log 300 "multiboot2 (UEFI)|$S" "$FB" -- $Q $UEFI $USB
$B usb-bios $L/usb-bios.log 300 "multiboot2 (BIOS)|$S" "$FB" -- $Q $USB
[ "$(sha256sum < $T/a.img)" = "$H0" ] || echo "FAIL os/usb-image-changed (the USB image was written during the boots)"
exit 0
