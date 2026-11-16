# espmigrate (tools/espmigrate.cud)

Moves an ESP installed before the 2026-11-16 rename from the old `\EFI\Forge\` folder to `\EFI\Incudela\`.
The old folder stays until a kernel has booted from the new one.

    espmigrate copy IMG              copy \EFI\Forge\ to \EFI\Incudela\, read it back, keep \EFI\Forge\
    espmigrate finish IMG BOOTLOG    remove \EFI\Forge\ (see the conditions below)
    espmigrate status IMG            say which folders exist (writes nothing)
    espmigrate --guard-selftest      check the write guard's decisions (no image)

IMG is a FAT volume in mtools syntax: a file, or `disk.img@@OFFSET` for the ESP inside a disk image.

- `copy` refuses (exit 1, nothing written) when there is no `\EFI\Forge\`, or when an `\EFI\Incudela\` exists and
  differs from it. An identical `\EFI\Incudela\` is "already copied" (exit 0, nothing written).
- `finish` needs both folders, identical, and a boot log with `ESP: kernel files under \EFI\Incudela\` and
  `KERNEL OK`, and without the loader's fallback line (`Incudela UEFI loader: no \EFI\Incudela\ ...`). Otherwise it
  refuses with exit 1 and `\EFI\Forge\ kept`.
- Write guard: every write goes through `guard()` before mtools runs. It allows creating and copying into
  `\EFI\Incudela\` and below, and one delete, of `\EFI\Forge\`, in `finish`. Paths with `.` or `..` components
  and any other path are refused (exit 3). Reads are not restricted.
- Exit codes: 0 done or nothing to do, 1 refused, 2 usage, 3 guard refusal, 4 mtools failed.

Until a disk is migrated, the loader and kernel read the old folder (docs/SYSTEMS.md, "Dual boot"). The build
writes the new layout, so only disks installed earlier need this tool.

Verified by `tests/espmigrate/run.sh` (no QEMU): copy is identical and keeps the old folder, nothing outside the two
folders changes, every refusal leaves the image byte-identical, finish removes only `\EFI\Forge\`, a migrated
disk is final, and the 21 guard decisions.
