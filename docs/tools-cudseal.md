# cudseal (tools/cudseal.cud)

This is the Cuditor port of `tools/cudseal.py`, the build-time sealer (Phase 6.1, Seal v3). The build scripts compile
it to `build/cudseal`.

    cudseal [--module] [--v2] [--extra-key KEY2] [--alg-id N] [--proof-byte] SRC.cud IMAGE KEYFILE BASELINE
    cudseal --foreign IMAGE KEYFILE      level-3 seal of a Linux-ABI ELF (EI_OSABI = 3), caps 0
    cudseal --config FILE KEYFILE        kind-2 seal of a boot config (\EFI\Incudela\boot.cfg); Forge only, no Python reference
    cudseal --pub KEYFILE                the 32-byte Ed25519 public key on stdout

Output is byte-identical to the Python version: the same appended trailer, the same `sealed NAME (vN): level L, U
unsafe ops, caps 0x..` line, the same error messages on stderr and the same exit codes. The trailer layouts are in
the cudseal.py docstring and docs/SYSTEMS.md.

## How it works

- **Verifier.** It runs `ROOT/build/cudc FILE /dev/null --unsafe-report` in SRC's directory using fork, chdir and
  execve, with stdout and stderr captured in two memfds. The parent concatenates them (stdout first, as Python's
  `r.stdout + r.stderr`) and splits at `str.splitlines` boundaries. It then hand-matches the last
  `unsafe: N functions, N blocks, N ops, N top-level` line and sums `ops=` over the lines whose location token ends
  in `FILE:LINE` (the `\S*{f}:\d+ .*ops=(\d+)` regex, last `ops=` per line).
- **Baseline.** It computes `relpath(dirname(abspath(SRC)), ROOT)` with Python's normpath rules and takes the last
  6-token line `REL FILE fn blk ops top`.
- **Caps.** Every line that starts `#\s*cuditor:\s*caps(` (or the pre-rename `#\s*forge:\s*caps(`, accepted for one release) contributes its comma-separated names. The group runs to the
  line's *last* `)`, as the greedy regex does.
- **Image.** The image is streamed: its length comes from fstat, the head and the last 384 bytes from pread (for the
  ELF/OSABI and already-sealed checks), and the SHA-256 is computed in 64 KiB reads. The trailer is then appended
  with O_APPEND, so even BusyBox is never held in memory.
- **Signing.** Ed25519 runs over the trailer in memory. The code is shared with `tools/ed25519.cud` through
  `tools/ed25519sign.cudi`, on top of the kernel's `examples/kernel/ed25519.cudi`. SHA-256 is the kernel seal
  verifier's (`tools/sha256.cudi`).
- **Root.** ROOT is `dirname(dirname(/proc/self/exe))`, so the binary must sit directly in `ROOT/build/`.

The program is freestanding (its own `_start`, raw syscalls). Its `@unsafe` code is the pointer and syscall plumbing.

## Differences

When an input file can't be read, Python dies with a traceback and exits 1. Forge prints
`cudseal: PATH: cannot read ...` and also exits 1. Missing positional arguments: Python raises an exception
(rc 1), Forge prints a usage line (rc 2). `--alg-id` takes a plain decimal number. Python's `int()` also accepts
signs, underscores and spaces, which no build uses. An unknown capability is quoted with `'...'`. Python's `repr`
would switch to double quotes for a name containing `'`.

## Status and tests

tests/cudseal/run.sh (in run_tests.sh) runs both versions on identically named copies and compares the image,
stdout, stderr and rc in 33 cases:

- v3 sealing, `--extra-key` (including an empty key file, which adds no slot), caps, `--v2`, `--alg-id 2`,
  `--proof-byte`, and all options combined;
- `--module` with v3 and v2, and an EI_OSABI = 3 image;
- caps parsing, a relative `..` SRC path, `--foreign`, and `--pub` with seeds of 0, 1, 32 and 100 bytes;
- every Python error: already sealed (v3, v2, foreign), not a Linux ELF, not in the baseline, unknown capability
  (including the greedy group), unknown option, and verifier rejection;
- the missing-input cases.

Switched to `build/cudseal`:

- examples/user/build.sh and examples/modules/build.sh. Their complete output trees (every sealed .elf and .ko,
  plus seal.pub) were byte-identical to a Python-sealed build with the same keys.
- tools/busybox/build.sh. Its `--foreign` seal of the real BusyBox image matched Python byte for byte.

The QEMU boot tests that load these images (tests/os) were not run for this port. `tools/cudseal.py` stays as the
reference.

## Boot configs (`--config`)

`--config` appends a v3 trailer with kind 2 (`SEAL_CONFIG`), level 0 and caps 0 to a text file. The kernel's
`boot_policy` (examples/kernel/bootpol.cudi) reads `\EFI\Incudela\boot.cfg` and accepts it only when `image_verify`
passes with that kind, so no program image, module or edited config can stand in for it. The file must be at least
64 bytes (the kernel's minimum for a sealed image; pad with a comment). An ELF or an already sealed file is refused.
The option was added after the port, so it has no Python counterpart; tests/os/bootpol.sh seals real configs with it
and boots them.

