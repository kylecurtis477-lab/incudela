# Public CI

`.github/workflows/ci.yml` runs on every push to `master`, on pull requests and by hand (workflow_dispatch).
Status: [![ci](https://github.com/kylecurtis477-lab/incudela/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/kylecurtis477-lab/incudela/actions/workflows/ci.yml)

## Jobs (ubuntu-24.04)

| Job | What it runs | Timeout |
|---|---|---|
| `build` | `./build.sh` from the committed seed; fails unless it prints FIXPOINT OK, SEED OK, TOOLS OK and SEED TOOLS OK | 15 min |
| `tests-o2` | `./build.sh`, then `SKIP_OS=1 ./run_tests.sh` (every non-QEMU item, parallel lanes); fails on any `FAIL` line and prints the failed items' `build/par` logs | 60 min |
| `boot-o0` | `./build.sh`, then `tests/os/ci-boot.sh`: kernel, user programs, modules and EFI disk built with `CUDC_FLAGS=-O0`, one BIOS boot (GRUB multiboot2, 4 CPUs, TCG) that must reach KERNEL OK on the serial console and the framebuffer; no retry on a hang | 30 min |

The full OS suite (`tests/os/run.sh`, 62 results, BIOS/UEFI/kexec/desktop/IOMMU/release-kernel paths) is not run on GitHub: it is
the gate on the development box (pregate, `tests/os/run.sh` alone, then `run_tests.sh` at O2 and O0).

## Rules

- **Seed only.** The toolchain is built from `seed/cudc-seed`, `seed/fas-seed` and `seed/fld-seed`, which build.sh
  checks against `seed/seed.sha256`. No Cuditor binary is downloaded, cached or published.
- **Distro packages only.** QEMU, GRUB (pc and efi), xorriso, mtools, OVMF and gdb come from the runner's Ubuntu
  archive through `apt-get`. Nothing from them is committed, cached or shipped.
- **No secrets, read-only token.** Top-level `permissions: contents: read`, nothing else granted; checkout keeps
  no credentials (`persist-credentials: false`).
- **Pinned actions.** Every `uses:` names a full 40-hex commit SHA (`actions/checkout` v7.0.1, `3d3c42e5…`).
- **Timeouts** on every job; a newer push to the same ref cancels the older run.

`tests/ci/run.sh` (a `run_tests.sh` item) checks these rules on the workflow file and checks that a copy breaking
each one (tag pin, short SHA, write token, extra write permission, a secret, a download, a missing timeout, kept
credentials, a missing boot job) is refused. It also checks the O0 boot script and the README badge.

## Running the CI checks locally

```sh
./build.sh && SKIP_OS=1 ./run_tests.sh   # tests-o2
tests/os/ci-boot.sh                      # boot-o0 (needs qemu-system-x86_64, grub-mkrescue, xorriso, mtools)
tests/ci/run.sh                          # the workflow rules
```
