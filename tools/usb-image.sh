#!/bin/sh
# tools/usb-image.sh [OUT]: the USB smoke image (default build/usb/incudela-usb.img), a raw BIOS+UEFI hybrid image
# to copy onto a USB stick (docs/usb.md). It is the kernel ISO tree from build/kernel/iso (examples/kernel/build.cud)
# with `incudela.smoke` on the multiboot2 command line, packed by tools/repro-mkrescue (distro GRUB modules,
# xorriso and mtools; nothing prebuilt is shipped) with SOURCE_DATE_EPOCH pinned (default 1700000000), so the same
# kernel gives a byte-identical image. In smoke mode the kernel runs only the self-tests that need no QEMU device
# and touches no disk or controller of the PC. This script only writes OUT, a regular file: it refuses anything
# under /dev or any existing non-regular file, and never writes to a device (copying to a stick is the user's step).
set -e
cd "$(dirname "$0")/.."
OUT=${1:-build/usb/incudela-usb.img}
case "$OUT" in /dev/*) echo "usb-image: refusing $OUT: this tool never writes to a device" >&2; exit 2;; esac
if [ -e "$OUT" ] && [ ! -f "$OUT" ]; then echo "usb-image: refusing $OUT: not a regular file" >&2; exit 2; fi
[ -f build/kernel/iso/boot/grub/grub.cfg ] && [ -f build/kernel/iso/boot/kernel.elf ] || { echo "usb-image: needs build/kernel/iso (build the kernel first)" >&2; exit 1; }
T=$(mktemp -d /tmp/incudela-usb.XXXXXX)
trap 'rm -rf "$T"' EXIT
cp -r build/kernel/iso "$T/iso"
sed -i 's|multiboot2 /boot/kernel.elf$|multiboot2 /boot/kernel.elf incudela.smoke|' "$T/iso/boot/grub/grub.cfg"
grep -q '^    multiboot2 /boot/kernel.elf incudela.smoke$' "$T/iso/boot/grub/grub.cfg" || { echo "usb-image: grub.cfg edit failed" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1700000000} tools/repro-mkrescue -o "$T/usb.img" "$T/iso" >"$T/log" 2>&1 || { cat "$T/log" >&2; exit 1; }
mv "$T/usb.img" "$OUT"
echo "usb-image: $OUT ($(stat -c %s "$OUT") bytes, sha256 $(sha256sum < "$OUT" | awk '{print $1}'))"
