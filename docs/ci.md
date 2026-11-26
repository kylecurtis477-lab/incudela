# Public CI

`.github/workflows/ci.yml` runs on every push to `master`, on pull requests and by hand (workflow_dispatch).
Status: [![ci](https://github.com/kylecurtis477-lab/incudela/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/kylecurtis477-lab/incudela/actions/workflows/ci.yml)

## Jobs (ubuntu-24.04)

| Job | What it runs | Timeout |
|---|---|---|
| `build` | `./build.sh` from the committed seed; fails unless it prints FIXPOINT OK, SEED OK, TOOLS OK and SEED TOOLS OK | 15 min |
| `tests-o2` | `./build.sh`, then `SKIP_OS=1 ./run_tests.sh` (every non-QEMU item, parallel lanes); fails on any `FAIL` line and prints the failed items' `build/par` logs | 60 min |
| `boot-o0` | `./build.sh`, then `tests/os/ci-boot.sh`: kernel, user programs, modules and EFI disk built with `CUDC_FLAGS=-O0`, one BIOS boot (GRUB multiboot2, 4 CPUs, TCG) that must reach KERNEL OK on the serial console and the framebuffer; no retry on a hang | 30 min |

The full OS suite (`tests/os/run.sh`, 69 expected entries / 76 PASS lines, BIOS/UEFI/kexec/desktop/IOMMU/release-kernel/soak/fault paths) is not run on GitHub: it is
the gate on the development box (pregate, `tests/os/run.sh` alone, then `run_tests.sh` / `build/forge-run-tests` at O2 and O0). On the box `build/forge-build` (`tools/build.cud`) and `build/forge-run-tests` (`tools/run_tests.cud`) are the documented entry points; the GitHub workflow still calls `./build.sh` and `SKIP_OS=1 ./run_tests.sh` (kept as references; workflow edits wait on the `workflow` token scope).

## Rules

- **Seed only.** The toolchain is built from `seed/cudc-seed`, `seed/fas-seed` and `seed/fld-seed`, which build.sh
  checks against `seed/seed.sha256`. No Cuditor binary is downloaded, cached or published.
- **Distro packages only.** QEMU, GRUB (pc and efi), xorriso, mtools, OVMF and gdb come from the runner's Ubuntu
  archive through `apt-get`. Nothing from them is committed, cached or shipped.
- **No secrets, read-only token.** Top-level `permissions: contents: read`, nothing else granted; checkout keeps
  no credentials (`persist-credentials: false`).
- **Pinned actions.** Every `uses:` names a full 40-hex commit SHA (`actions/checkout` v7.0.1, `3d3c42e5…`).
- **Timeouts** on every job; a newer push to the same ref cancels the older run.

## Runner tool versions (open)

The byte-for-byte checks compare against the dev box's tools (Debian 13: GNU as 2.44, mtools 4.0.48); the
`ubuntu-24.04` runner has GNU as 2.42 and mtools 4.0.43. Run 45432443010 (0a1502d) had 12 tests-o2 FAILs:

- mtools (7, fixed in inv235): `mformat -C` before 4.0.48 wrote the created image's last sector from an
  uninitialized buffer, so two clean builds' ESP and ISO differed. `tools/repro-mformat` zeroes that sector
  (docs/SYSTEMS.md, "Reproducible ESP and ISO"). Images from 4.0.43 and 4.0.48 still differ in the boot sector's
  OEM name (`MTOO4043` / `MTOO4048`); no test compares images across machines.
- GNU as (4: fas tests-corpus, fas self, fas build/os/boot.s, fas build/kernel-build.s): as 2.42 output differs
  from 2.44 by 8 bytes. Planned: run tests-o2 in a Debian 13 container pinned by digest with the box's package
  versions (test tooling only, nothing from it is shipped); pushing a workflow change needs a token with the
  `workflow` scope.
- bounds-bench-overhead: median 1.0552 with every pair between 1.0515 and 1.0576, so not noise; earlier runs gave
  1.0106 to 1.0292, which points at the runner's CPU model. The 5% limit stays. Probe (2026-11-24, 19 runs, the
  bench assembly byte-identical across them): grouped by the unchecked last-pair time, runners near 262 ms gave
  1.009-1.018 (10 runs; the dev box, an Emerald Rapids Xeon, is this class at 1.004-1.007), runners near 343 ms
  gave 1.0538-1.0559 (6 runs, every failure), a third group 1.041 (3 runs), one 179 ms runner 1.029. The logs
  name no CPU model and reading /proc/cpuinfo needs a workflow change, so the classes are unnamed. The bench's
  13 checked sites ran about 6.4M checks a round; the elision rules of 2026-11-24 (docs/SYSTEMS.md, bounds)
  leave 9 checked sites and about 1M checks (only the histogram's `h[s[i] % 256]` in a hot loop), and the box
  ratio went from 1.0068 to 0.9998. Since then, 0.23.0 CI runs passed on both a slow-class ~343 ms runner (1.0212) and fast/class-A runners (0.9875-1.0107, limit 1.0500); the four GNU as 2.42 vs 2.44 `fas` gaps (with sizes 461624 vs 461616, 299440 vs 299432, and 181928 vs 181920) remain the only CI failures until the `workflow` scope lets us pin Debian 13.

`tests/ci/run.sh` (a `run_tests.sh` item) checks these rules on the workflow file and checks that a copy breaking
each one (tag pin, short SHA, write token, extra write permission, a secret, a download, a missing timeout, kept
credentials, a missing boot job) is refused. It also checks the O0 boot script and the README badge.

## Running the CI checks locally

```sh
./build.sh && SKIP_OS=1 ./run_tests.sh   # tests-o2
tests/os/ci-boot.sh                      # boot-o0 (needs qemu-system-x86_64, grub-mkrescue, xorriso, mtools)
tests/ci/run.sh                          # the workflow rules
```
