# USB smoke image

`tools/usb-image.sh` makes `build/usb/incudela-usb.img`: a raw image to copy onto a USB stick that boots the
Incudela kernel on a real PC through UEFI or BIOS (legacy/CSM). It is the first real-hardware step of
BUILD_PLAN item 8; *Kyle* boots it once and reports what the screen shows.

## Building it

```sh
./build.sh
./cuditor examples/kernel/build.cud -o build/kernel-build && build/kernel-build   # build/kernel/iso
tools/usb-image.sh            # -> build/usb/incudela-usb.img (prints its size and sha256)
```

- **What it is.** The kernel ISO tree (`build/kernel/iso`) with `incudela.smoke` on the GRUB `multiboot2` line,
  packed by `tools/repro-mkrescue` into a BIOS+UEFI hybrid image (GPT and a protective MBR, the ISO 9660
  filesystem, and an EFI system partition). GRUB comes from the distro's `grub-pc-bin`/`grub-efi-amd64-bin`
  modules, assembled by `grub-mkrescue`, and xorriso and mtools are distro packages too. Nothing prebuilt is
  committed or shipped.
- **Reproducible.** `SOURCE_DATE_EPOCH` is pinned (default 1700000000), so the same kernel always gives a
  byte-identical image (`os/usb-image-reproducible`).
- **The EFI system partition** is the image's own FAT, made by `grub-mkrescue`. It holds only
  `\EFI\BOOT\BOOTX64.EFI` (GRUB), the removable-media path that UEFI firmware boots from a stick without a boot
  entry, the same layout as `forge.iso` (`os/usb-esp-layout`). No Incudela tool writes to an existing ESP here,
  and no firmware variable is set. The rule for installed systems stays as it is: Incudela tools write only under
  `\EFI\Incudela\` on an ESP they did not create.
- **Smoke mode.** With `incudela.smoke` the kernel runs only the self-tests that need no QEMU device: CPU
  features, memory, paging, interrupts and timers, SMP bring-up and the scheduler, the user-mode test, user
  pointer checks and stop-machine. It skips the virtio disk, the hardware drivers (so it never touches the PC's
  own NVMe, AHCI, xHCI or network controllers), modules, the shell and kexec. Then it prints the `smoke
  (incudela.smoke):` line and `KERNEL OK`.
- **Test.** `tests/os/usb.sh` (part of `tests/os/run.sh`) boots the image attached only as a USB mass-storage
  device (`qemu-xhci` + `usb-storage`, read-only) under OVMF and under SeaBIOS, and requires the smoke line and
  KERNEL OK on the serial console and the framebuffer (`os/usb-uefi`, `os/usb-bios`).

## Writing it to a stick

`tools/usb-image.sh` only writes a regular file. It refuses any `/dev` path and never writes to a device: copying
the image to a stick is your step.

> **Warning: pick the right device.** Writing the image destroys everything on the target device. Writing to the
> wrong one (your system disk, a backup drive) wipes it. Unplug other removable drives first, and check the size
> and model of the device before you write.

Linux:

```sh
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS     # find the stick: TRAN usb, the size you expect
sudo umount /dev/sdX?* 2>/dev/null            # sdX = the stick, never a partition or your system disk
sudo dd if=build/usb/incudela-usb.img of=/dev/sdX bs=4M conv=fsync status=progress
```

macOS: `diskutil list` (find the external disk), `diskutil unmountDisk /dev/diskN`, then
`sudo dd if=build/usb/incudela-usb.img of=/dev/rdiskN bs=4m`.

Windows: a raw image writer that writes the whole device (Rufus in DD mode, or balenaEtcher). Pick the stick by
its size and name.

## Checklist for the first real-hardware boot

1. Boot the stick from the firmware's one-time boot menu: the UEFI entry first, then the legacy/BIOS entry if
   the PC has CSM. Secure Boot must be off (GRUB here is not signed for it).
2. Expected: GRUB starts the kernel straight away (no menu), and the screen fills with the boot log, ending in
   the `smoke (incudela.smoke): N cpus, M MiB free, fb WxH; ...` line and `KERNEL OK`.
3. Note or photograph the last screen: the cpu count, memory and resolution in the smoke line, and any
   `PANIC` line with the text above it.
4. Nothing is written to the PC's disks. Power off to leave.
