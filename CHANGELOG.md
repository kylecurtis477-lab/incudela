<!-- CHANGELOG.md: release notes for Incudela (the OS) and Cuditor (the language), both named Forge until
     2026-11-16, from 0.17.1 (5b8e7af) on. Each entry names its commit; the
     version-to-commit mapping comes from the project plan. There are no git tags: the versions are
     groupings of commits, not contiguous ranges of history (for example the 0.17.4 fixes 0bbe40c, 4ecde04,
     f5c66be and 2aba6e2 come before the 0.17.2 commits in the log). Newest version first. 0.18.1 is cut as
     a grouping only; 0.19.0, 0.20.0, 0.23.1 and 0.24.0 are open; 0.22.0 (2026-11-19) and 0.23.0
     (2026-11-25) are closed. Entries before 0.21.0 use the names of their time (Forge, forgec,
     c2forge, `\EFI\Forge\`). -->
# Incudela and Cuditor changelog

## 0.24.0 (open): Linux pipe, fork/wait4, and file-backed mmap (no git tag)

- `0862dc4` Linux personality grows from 39 to 43 syscalls. `pipe`/`pipe2` (22/293) is a
  4096-byte ring (`F_PIPE`); close of the write end is EOF and close of the read end is
  EPIPE; pipe2 accepts only `O_CLOEXEC`. `fork` (57) is the existing eager-copy process
  fork. musl's `fork()` is `clone(SIGCHLD)`, so a clone whose flags are only the CSIGNAL
  byte is now a process fork (`lxthreads` reaps that child instead of expecting ENOSYS).
  `wait4` (61) honours `WNOHANG` and writes a 4-byte Linux status. File-backed `mmap` of
  a granted regular file is a `MAP_PRIVATE` copy into anonymous pages; `MAP_SHARED` with
  `PROT_WRITE` is EACCES (ESP files are read-only). `examples/user/lxipc.cud` (sealed
  like lxtest, launched with `run lxipc`) covers those calls. The application pass/fail
  list is in `docs/linux-compat.md`. Ash pipelines are not yet in the boot script.
  Syscalls 408/409 stay `ktest_hooks` gated. The kernel unsafe cap stays 709.
- `sys_wait` / `lx_wait4`: a bad status pointer returns EFAULT and the zombie
  stays waitable (the previous `sys_wait` behavior). `0862dc4`'s `sys_wait_ex`
  had destroyed the child before the copy, so `badptr` saw ECHILD on the later
  wait probes. `badptr` is unchanged. `lxipc` also checks Linux `wait4`. The
  `lxthreads` boot pattern is `PASS (11 checks)` after fork-style clone grew
  by a wait4 check. The kernel unsafe cap stays 709.
- `tests/user-build/run.sh`: the expected artifact count is 134, not 130.
  `0862dc4` added `lxipc` (`.s` `.o` `.elf` `.raw`). Shell and Forge builds
  already matched (exit codes agreed; `fresh-keys` passed); only the expected
  count was stale. Default and O0 still skip BusyBox (`BB_SRC=/nonexist`).
- `70ae881` docs-only speculative-execution policy (`docs/spec-exec.md`).
  IBPB, VERW (MD_CLEAR) and retpoline are not implemented: the kernel does
  not program `IA32_PRED_CMD` or `IA32_SPEC_CTRL`, does not flush buffers
  with `verw`, and the compiler does not emit retpoline thunks. Process
  page tables keep the kernel half mapped. SMEP/SMAP, W^X, canaries, guard
  pages and KASLR are listed there and are not substitutes. README,
  `docs/BUILD_PLAN.md`, `docs/SYSTEMS.md` and `docs/kernel-core.md`
  Appendix A.2 point at the note. No compiler, kernel or runtime change.
  The kernel unsafe cap stays 709.
- `ceac345` Linux `vfork` (58) is the same eager-copy process fork as
  `fork` (57): address spaces are not shared and the parent is not
  suspended. Ash uses vfork to run a simple external command. A first
  sandbox run of a BusyBox pipeline got ENOSYS on syscall 58 after the
  builtin pipeline and a pipeline to an external image had both worked.
  The personality is 44 syscalls. `lxipc` reaps a vfork child. Syscalls
  408/409 stay `ktest_hooks` gated. The kernel unsafe cap stays 709.
- `20cdd09` `run busybox sh /efi/incudela/docs/pipeline.sh` is in the
  OS boot script: a builtin `echo | while read` pipeline, a pipeline to
  `/efi/incudela/docs/busybox wc -c`, and a simple
  `/efi/incudela/docs/busybox echo`. The busybox manifest still grants
  only `dir /efi/incudela/docs`, so a sealed copy of busybox is installed
  under docs; `/efi/incudela/bin` stays denied. `lxfs` expects five docs
  dirents. The application pass/fail list in `docs/linux-compat.md` is
  updated. The kernel unsafe cap stays 709.
- `42b81e2` `hw_quiesce` and `nvme_init` disable NVMe MSI-X after the
  controller is stopped, so a leftover vector 0x53 cannot #GP a kexec
  successor before its IDT gate is installed. `hw_quiesce` already
  cleared CC.EN, but PCI MSI-X Enable survives the jump; the successor
  then re-enabled the controller while IDT[0x53] was still a null
  descriptor (#GP err=0x29a). Needed so a boot with the Incudela NVMe
  disk attached can finish the existing kexec self-test. The kernel
  unsafe cap stays 709.
- `11d0930` Writable files on `/data` for the Linux personality: an
  explicitly created Incudela FS partition, never the ESP. `wdir /data`
  in a sandbox manifest grants WRITE (the kernel still refuses WRITE on
  a FAT or /obj handle). User-visible files can be created, written,
  read, appended, listed and unlinked; kernel and object-store names
  (`persist.dat`, `hello.txt`, `objects.*`) stay EACCES and are hidden
  from getdents. Write opens of the ESP stay EROFS; MAP_SHARED+PROT_WRITE
  of an ESP file stays EACCES. The personality is 45 syscalls, including
  unlink 87. `examples/user/lxwrite.cud` (sealed like lxtest) is launched
  with `run lxwrite` from `tests/os/lxwrite.sh`: ESP write EROFS, reserved
  names EACCES, create/write/read/append/unlink/O_EXCL (27 checks). After
  the boot, every byte outside the Incudela partition is unchanged.
  `tests/os/expected-results.txt` grows from 68 to 69 entries. The
  busybox manifest does not grant `/data` (main boots have no Incudela
  partition). Ash `>` onto `/data` is not in the gate. Syscalls 408/409
  stay `ktest_hooks` gated. The kernel unsafe cap stays 709.

- `ac41531` Linux `newfstatat` (262), `readlink` (89) and `readlinkat`
  (267), plus a read-only `/proc` (`self` and `self/exe` only; a
  `dir /proc` manifest grant is required). `lstat` and
  `newfstatat(..., AT_SYMLINK_NOFOLLOW)` do not follow those
  symlinks; `stat("/proc/self")` is a directory; write opens of
  `/proc` stay EROFS. The personality is 48 syscalls.
  `examples/user/lxproc.cud` (sealed like lxtest) is launched with
  `run lxproc` in the main OS boot (34 checks). Syscall 409 stays
  ENOSYS and `ktest_hooks` gated. The kernel unsafe cap stays 709.

- `f764d19` A still-open `/data` fd after unlink and re-create of the same
  name no longer touches the new file. Each Incudela FS inode slot has a
  generation in superblock words 7..70, snapshotted in `File.ccl` at open
  and checked on read, write, fstat and lseek. Unlink bumps the generation;
  those calls then return ESTALE (Linux 116). close and fcntl still work.
  The table lives in the superblock, and the handle's snapshot is packed
  into the kexec file record cluster word (slot in the low 8 bits,
  generation above that). `run lxwrite` covers the unlink/recreate case
  (39 checks in this commit). A kexec variant is not practical: kexec
  refuses while a sandboxed process is alive. Syscalls 408/409 stay
  `ktest_hooks` gated. The kernel unsafe cap stays 709.

- `7585432` Shrinking an Incudela FS file (Linux O_TRUNC is
  `ffs_grow(slot, 0)`) zeros the stale tail and releases unused blocks;
  an extend zeros the gap, so a sparse write after truncation never
  exposes leftover bytes. `run lxwrite` writes a 64-byte pattern, reopens
  with O_TRUNC, writes past the old start, and requires zeros in the hole
  (51 checks total). Syscalls 408/409 stay `ktest_hooks` gated. The
  kernel unsafe cap stays 709.

- `b534840` `t_errors` in `run_tests.sh` and `tools/run_tests.cud` reports
  a timeout or exit status on failure, never a bare FAIL, and the per-compile
  cap is 60s (was 20). inv259's O2 run killed the first compile
  (`tests/errors/arity.cud`) under parallel-start load and recorded a bare
  FAIL; the same binary and the O0 half both printed the expected diagnostic
  immediately. A timeout now reports `timeout 60s, exit 124`. The test is
  never skipped. No compiler change.

## 0.23.1 (open): KDF hardening, key-temporary wipes, and sysfuzz gated-list check (no git tag)

- `2146c37` `tests/sysfuzz-gates/run.sh` (wired as item 69, lane X) parses `sys_need` in
  `examples/kernel/seal.cudi` and the `gated` list in `examples/user/sysfuzz.cud` and requires
  they match for every capability the fuzzer does not declare (it holds `fs` and `ipc`; today
  that is 29 numbers). The lists already matched; no kernel change. The test does not start
  QEMU. Syscalls 408/409 stay `ktest_hooks` gated. The kernel unsafe cap stays 709.
- `5dbbda2` After unlock, `od_open` ends with `od_tmp_done`, which wipes passphrases, the KEK, `od_t`,
  the entropy pool, and the SHA-256 / HMAC / PBKDF2 working state, then counts any words still set;
  live store keys stay. `os/objstore-no-kdf-residue` requires the clean boot-log line on the create
  and reopen boots. `tests/os/expected-results.txt` grows from 67 to 68 entries. The kernel unsafe
  cap stays 709.
- `4bd6e3c` `od_kdf` now calls `sh_wipe` (new in `crypt.cudi`: zeroes `sh_h`, `sh_w`, `sh_buf`, `sh_n`
  and `sh_tot`) after copying the HMAC-SHA256 digest into `od_t`, and also clears `hm_k` and `hm_ih`.
- `9575ad6` New v2 key slots pick their PBKDF2 iteration count with `od_kdf_calibrate`: a 1000-iteration
  dummy PBKDF2 times the rate, and the count is scaled to about 500 ms, never below 20000, and at
  least 600000 when 600000 iterations are estimated to finish within 2 s (real hardware). QEMU TCG
  stays near 20000 and ~0.5 s. The chosen count is stored in the slot, so existing slots still unlock
  at their own count. `os/objstore-kdf-salted` and the upgrade/passphrase tests use the stored count
  rather than requiring exactly 20000. On-disk markers unchanged. The `9575ad6` commit subject called
  this a "600k floor", which overstated it: the floor for a new slot is 20000, calibrated to about
  500 ms, and 600000 is used only when that many iterations finish within 2 s. The pushed commit is
  left as it is.

## 0.23.0 (2026-11-25): test/debug and release kernels; parallel run_tests.sh; public CI; per-CPU run-queue locks; USB smoke image; language server; package manager; data-at-rest keys and soak/fault testing; All-Cuditor build and test drivers (no git tag)

- Known issue (0.23.0 public CI, Ubuntu 24.04 runner GNU `as` 2.42 vs box GNU `as` 2.44): four
  byte-for-byte `fas` checks fail in `run_tests.sh O2 (SKIP_OS)` by 8 bytes: `fas tests-corpus`,
  `fas self` (`fas_rc=0 gas_bytes=461624 fas_bytes=461616`), `fas build/os/boot.s` (`fas_rc=0
  gas_bytes=299440 fas_bytes=299432`), and `fas build/kernel-build.s` (`fas_rc=0
  gas_bytes=181928 fas_bytes=181920`). `docs/ci.md` carries the pinned Debian 13 container plan,
  waiting on the `workflow` token scope.
- `a450c9e` Reservation 6 closed: `build/forge-build` (`tools/build.cud`) and `build/forge-run-tests`
  (`tools/run_tests.cud`) are now the documented build and test entry points in `README.md`,
  `docs/BUILD_PLAN.md`, `docs/bootstrap.md`, `docs/ci.md`, `docs/SYSTEMS.md` and `docs/kernel-core.md`,
  with `build.sh`, `run_tests.sh` and the other ported `.sh`/`.py` originals kept as references;
  all six v1 reservations have landed work and the frontier slot stays empty (no tag).
- `3f6ad9f` Item-9 remainder: `tools/repro-mformat.cud` (built to `build/repro-mformat`) is a
  Cuditor port of `tools/repro-mformat`, which stays as the reference and is still
  what `examples/efi/build.sh`, `examples/efi/build.cud` and `tools/repro-mkrescue`
  call. When `SOURCE_DATE_EPOCH` is set and `-N` was not already passed, it adds
  `-N` with the low 32 bits of the epoch as 8 hex digits; with `-C` and `-i FILE`
  it zeroes the new image's last 512-byte sector. `tests/repro-mformat/run.sh`
  requires identical images, stdout, stderr and exit code, plus argv, last-sector
  and missing-mformat checks. Wired as item 68 (lane X). The test does not start
  QEMU. The kernel unsafe cap stays 709.
- `e29018f` Item-9 remainder: `tools/usb-image.cud` (built to `build/usb-image`) is a
  Cuditor port of `tools/usb-image.sh`, which stays as the reference. It writes
  the same USB smoke image (kernel ISO plus `incudela.smoke`, packed by
  `tools/repro-mkrescue` with `SOURCE_DATE_EPOCH` pinned) and refuses any
  `/dev` path or non-regular file. `tests/usb-image/run.sh` requires identical
  stdout, stderr, exit code and image bytes, plus the refusals. Wired as item
  67 (alone lane). The test does not start QEMU. `tests/os/usb.sh` now uses
  `build/usb-image`. The kernel unsafe cap stays 709.
- `cc2a775` Item-9 remainder: `tests/count-store-reload/count_store_reload.cud` (built
  to `build/count_store_reload`) is a Cuditor port of `tests/fs/count_store_reload.py`,
  which stays as the reference. It prints the same count of consecutive
  `mov %rN,D(%rbp)` / `mov D(%rbp),%rN` store-then-reload pairs.
  `run_tests.sh` `fs-ssa-reload-shape` now uses the Cuditor tool.
  `tests/count-store-reload/run.sh` requires identical stdout and exit code
  on synthetic assembly and on `tests/fs/ssa.cud` compiled with `--fs-temps`
  and `--fs-ssa`, plus a missing-input check. Wired as item 66 (lane S).
  The test does not start QEMU. The kernel unsafe cap stays 709.
- `1818c58` Reservation 6 batch 2: `tools/run_tests.cud` (built to `build/forge-run-tests`) is a
  Cuditor port of the repo-root `run_tests.sh`, which stays as the reference. It honours
  `SKIP_OS`, `RUN_TESTS_SERIAL`, `CUDC_FLAGS`, optional `RUN_TESTS_ONLY`, and
  `FORGE_RUN_TESTS_INNER`. `tests/forge-run-tests/run.sh` requires identical stdout, stderr
  and exit code on a short serial `SKIP_OS` subset, and the same failure when
  `tests/ci/run.sh` is replaced by a script that exits 1. Wired as item 65 (alone lane).
  `RUN_TESTS_PAR` gives a nested comparison its own per-item log dir so it cannot
  wipe the outer `build/par` (inv242: 64 false `no exit status` FAILs). The test
  also checks `run-tests/par-isolated`. The test does not start QEMU. The kernel
  unsafe cap stays 709.
- `f73b94e` Reservation 6 batch 1: `tools/build.cud` (built to `build/forge-build`) is a Cuditor port
  of the repo-root `build.sh`, which stays as the reference. `tests/forge-build/run.sh` requires
  identical stdout, stderr, exit code and bootstrap artifacts on a default run, and the same
  failure when `selfhost/runtime.cud` is hidden.
- `af6e510` Item 7 batch 4: multi-hour soak support. `syssoak` takes an optional fourth argument, a
  wall-clock budget in `sys_ticks()` units (the 100 Hz LAPIC tick, 10 ms; 0 means run every
  requested seed; 360000 ticks is one hour). When the budget expires after a completed seed, it
  prints a checkpoint and exits 0 if no seed failed so a later session can resume. `os/syssoak-long`
  boots once with `incudela.syssoaklong` (`syssoak 1 16 100 1`), requires a clean checkpoint after
  the first seed, and fails on the tree before the harness. The existing `os/syssoak` path is
  unchanged. A live multi-hour run is started from the shell and is not part of the gate.
- `f334a8c` Item 7 batch 3: ktest-gated `kmalloc` fault injection in front of sysfuzz. Syscall 408
  (still capability `ktest` and `ktest_hooks` gated; 409 unchanged) grows `b=2/3/4` to arm, query
  and probe forced allocation failures. The fail counter is in the safe `kmalloc` wrapper, so the
  kernel unsafe cap stays 709. New `examples/user/sysfault.cud` probes 1+3 failed allocations then
  a live one, records EMFILE and a denied huge mmap, and runs `sysfuzz 1 50`. `os/sysfault` boots
  once with `incudela.sysfault` and fails on the tree before the harness. The hook is not armed on
  the default boot.
- `81c56d0` Item 7 batch 2: a soak harness that runs `sysfuzz` across many seeds and records the

  results. `examples/user/syssoak.cud` (`syssoak [START [NSEEDS [N]]]`, defaults 1, 16, 100)
  fork+execs the fuzzer per seed and exits 0 only when every seed PASSes. `tools/syssoak.cud`
  writes a `syssoak-results v1` file from a serial log (`--record`, `--check`, `--self-test`).
  New `os/syssoak` boots once with `incudela.syssoak` (16 seeds x 100 calls, results in
  `build/os/syssoak-results.txt`) and fails on the tree before the harness; it skips the long
  shell and kexec sessions. Not a multi-hour soak, and no fault injection (later batches). The
  kernel unsafe cap is unchanged (709).
- `82a6560` Fix: the boot harness lost the framebuffer screendump when the kernel's 5 s wait for `q`

  expired mid-dump (inv236 `os/bootpol-config-strict`: 38 s box suspend, debug-exit 5846 ms, no ppm).
  That wait is `rdtsc` vs `tsc_per_ms * 5000`, so a host suspend can jump guest TSC. After KERNEL OK
  the harness now issues QEMU monitor `stop`, dumps, queues `q`, then `cont`. A failed screendump
  still FAILs. New `os/boot-harness-delay-after-ok` (6 s delay; FAILs on the pre-stop harness).
- `751c90b` cudc: more bounds checks elided by default (bounds-bench-overhead on slow CI runners). A local written
  once as `n = len(x)` at the top of a function, x a slice parameter it never writes, now counts as `len(x)`;
  `while v < n:` / `while v < len(x):` (v unsigned, its `addr()` never taken) drops the check on `x[v]` in that
  loop's own body until v is written; and `x[v - K]` inside `range(C, ...)` is elided for a literal K <= C. The
  bench keeps 9 of 17 checked sites instead of 13 (its sieve has none left, about 6.4M to 1M checks a round); the
  box ratio went from 1.0068 to 0.9998. CI runners near 343 ms per unchecked round gave 1.054-1.056 with the old
  code while the rest gave 1.009-1.041 (docs/ci.md); the 5% limit is unchanged. Kernel and tests/fs output is
  byte-identical. New tests/bounds/elide_alias.cud (5 positive and 12 negative functions), oob_while.cud and
  oob_addr.cud. Reseeded.
- `16f9c5d` Fix: the OS boot harness glued its box-freeze and suspension notes to the next guest serial line
  (inv235 O2 `os/kaslr` counted 4 of 5 kexecs: `[harness: box frozen 3s, not counted]kexec: new kernel
  relocatable, ...`). A note now gets its own line, or waits in the end-of-log notes when a guest line is still
  arriving; the result line still reports the freeze. New self-test check `boot-harness note-own-line`.
- `acf76a3` Fix: the ESP and ISO were not reproducible with mtools before 4.0.48 (Ubuntu 24.04 has 4.0.43; seven
  public-CI failures). `mformat -C` sizes a new image by writing its last sector, and before 4.0.48 that sector
  came from an uninitialized buffer; `tools/repro-mformat` now zeroes it, as 4.0.48 does, so box images are
  unchanged. New `efi-build/mformat-last-sector`. Images from 4.0.43 and 4.0.48 still differ in the OEM name.
- `cadc75a` Fix: `cudc -g` changed `--fs-*` code. The `-g` line markers were in the output while the `--fs-opt`,
  `--fs-live`, `--fs-temps` and `--fs-ssa` passes ran, and the passes end their windows and SSA blocks at labels,
  so the `--fs-ssa` kernel built with `-g` was 0x110 bytes larger than without it. The markers are now taken out
  around the passes and put back after; `-g` output equals non-g output apart from the debug information.
  Reseeded.
- `bb5ad6d` Fix: dwarf/image-unchanged-by-g could not fail (memimg always exits 0 and the test read only its exit
  status). It now requires memimg's `SAME` line and builds its `-g` kernel with build/kernel's flags.
- `0669f6f` docs/SYSTEMS.md "SSA stop rule": `--fs-ssa` repeats its rewrites until a round changes nothing or 12
  rounds (FS_SSRND) have run; the push/pop rewrite runs only in a round where folds and copies settled, so 45
  kernel functions are cut off (87,350 instructions at 12 rounds, 87,240 at 16). The limit is unchanged.
- `fede009` Fix: the O0 kernel kept the SSA backend. The kernel build put `--fs-ssa` before `$CUDC_FLAGS`, so the
  O0 gate (and CI's boot-o0) booted `--fs-ssa -O0` code; with `-O0` in `$CUDC_FLAGS` the kernels are now built by
  the plain freestanding code generator (exactly `cudc -O0`, every bounds check kept: 2275 of 2275). New
  `kernel-build/O0-no-fs-ssa`. User programs, modules and the EFI loader keep `--fs-ssa`.
- `89305ae` `sqrt(x)` intrinsic in freestanding code: one `sqrtsd` / `sqrtss` for an f64 / f32 (correctly rounded,
  NaN for a negative argument; an integer needs `f64(x)`; a program's own `def sqrt` wins). New tests/fs/fsqrt and
  tests/errors/sqrt_int_fs. Reseeded.
- `f6241c4` v1 reservation 5 (abi3): the CPython embed's binding layer uses only the stable ABI. Run and eval go
  through `Py_CompileString` / `PyEval_EvalCode` instead of `PyRun_*`, a one-argument call through `PyObject_Call`
  instead of `PyObject_CallOneArg`; only the PyConfig init of the embedding host (`forge_py_init`) is outside the
  stable ABI (abi3 floor 3.10). New `cpython-embed/stable-abi` check against the pinned `Misc/stable_abi.toml` and
  run/eval error-path checks. An abi3 extension module waits for PIC code and shared-object output.
- Migration (0.23.0): since `2d89c82` a store whose data key was made before `87b91fb` gets a fresh data key at
  its first open, with no request needed: the object log is re-encrypted through the crash-safe rotation of
  `e59be70`. Old disk copies and the second physical slot of each log block stay under the old key until
  overwritten.
- `2d89c82` A data key made by the pre-`87b91fb` derivation is detected at each open (`od_dk_weak`: the old
  salt-to-key relation holds for all four word pairs) and rotated unasked. A detector self-test runs first, and the
  boot log reports it and the verdict. New `os/objstore-dk-prefix-rotate` (a host-written pre-fix slot); tests/os
  expected results 62 to 63.
- `e59be70` Crash-safe data-key rotation: boot with fw_cfg `opt/forge/rotatedk` = `rotate-data-key` to re-encrypt
  every object log block under a fresh independent data key from a new RDSEED/RDRAND+TSC pool (KEK kept, fresh
  wrap salt). The rotating key slot holds both data keys and is written first through the two-copy order, so a
  crash in the middle is resumed at the next boot; `rotate-data-key:stop-after:N` simulates one. New
  `os/objstore-dk-rotate` and `os/objstore-dk-rotate-crash`; expected results 60 to 62.
- xHCI fix: the USB keyboard could go silent after the switch to MSI-X when its last polled report (the Enter
  release) was posted between draining the event ring and enabling the interrupter, which left Event Handler
  Busy set with no interrupt sent. `xh_irq_init` now enables the interrupter first and drains after. Found by the
  inv230 OS precheck (`os/drivers`, reproduced under CPU load).
- Test fix: tests/os/forgefs.sh found the two key-file copies in the disk image with a grep of the slot's first 32
  bytes, which never matches when the random wrap salt holds a newline byte; the passphrase-change crash test then
  failed. It now searches the fixed 16-byte prefix and compares all 32 bytes (`koffs`).
- Migration (0.23.0): since `93f788d` a v1 key slot is upgraded to v2 at its first unlock, and since `7e04ddb` a
  store from before inv229 gets its second key copy `objects.keyb` at its first unlock; both are written through
  the crash-safe two-copy order. Data keys made before `87b91fb` stayed until data-key rotation (`e59be70`, `2d89c82`, above).
- `93f788d` A v1 key slot (unsalted SHA-256 KEK) is upgraded at its first unlock: the same data key under PBKDF2 of
  the same passphrase with fresh salts, as the next key slot generation. `os/objstore-legacy-slot` checks the
  upgraded slot on the host and a second boot.
- `84d094d` Passphrase change: boot with the current passphrase as fw_cfg `opt/forge/userkey` and the new one as
  `opt/forge/newkey`; the data key is rewrapped under the new passphrase (fresh salts, next generation) and the
  object log is not rewritten. Once the first copy is flushed the old passphrase opens nothing. New
  `os/objstore-passphrase-change` and `os/objstore-passphrase-change-crash`; tests/os expected results 58 to 60.
- `7e04ddb` The key file has two copies, `objects.key` and `objects.keyb`, and a slot carries a generation and a
  SHA-256 of its bytes. A rewrite goes to the copy that is not current first and is flushed before the other, the
  intact copy with the higher generation is current, and a missing, damaged or older copy is rewritten from it.
  New `os/objstore-key-two-copies` and `os/objstore-key-copy-repair`; expected results 56 to 58.
- Migration (0.23.0): stores made before `2417854` keep their v1 key slot (unsalted SHA-256 passphrase key) and
  stores made before `87b91fb` keep their weaker data key; both still unlock, and the boot log names a v1 slot.
  Neither is upgraded in place by that batch; the passphrase change and the v1-to-v2 upgrade came in inv229
  (above), and data-key rotation came in inv231 (above). Making a new store gives a v2 slot and an independent data key.
- `2417854` The object store's passphrase key is PBKDF2-HMAC-SHA256 with a 128-bit salt and 20000 iterations (key
  slot v2: version, KDF salt and count in `objects.key` words 16..19; about 0.5 s on QEMU TCG), replacing one
  unsalted SHA-256. `pb_kdf` is in crypt.cudi with known-answer tests in tests/fs/crypt.cud. The raw passphrase is
  wiped after the store is opened. New `os/objstore-kdf-salted` and `os/objstore-legacy-slot`; tests/os expected
  results 54 to 56.
- `e6cbdce` The data key's entropy pool mixes up to 32 RDSEED and 32 RDRAND words (`hw_rand`, cpux.cudi) with the
  512 TSC jitter samples when CPUID reports them; a missing, 0, all-ones or repeated value is refused and counted.
  New `os/objstore-key-entropy`; expected results 53 to 54.
- `87b91fb` The data key and the plaintext wrap salt are independent PRF outputs of the entropy digest (fix: the
  salt was digest words 0..3 and the data key mixed those words with words 4..7, so reading the salt left the data
  key 128 unknown bits). New `os/objstore-data-key-independent`; expected results 52 to 53.
- `63c4d7f` Release kernel hardening (the plan's 0.23.1 items): the release kernel is booted on the BIOS path from
  its own GRUB ISO (`os/kernel-release-bios`, KERNEL OK and one kexec) and its generation prints no test/debug line
  (`os/kernel-release-quiet`); tests/os expected results 50 to 52. `page tables built: pml4 at`, `higher half:
  rip ..., rsp ...` (it gave away the image slide) and the CPU 0 irq-off watch (`i0_watch`, one `rdtsc` per tick,
  moved from apic.cudi to kdebug.cudi) are test/debug only, behind `kdbg_paging`, `kdbg_higher_half`, `kdbg_tick0`,
  `kdbg_watch_reset` and `kdbg_watch_report`. tests/kernel-release checks they are absent from the release kernel.
- `394fa68` `cuditor pkg` `build`, `stage` and `vendor` refuse a cuditor.lock whose `registry_key` differs from
  cuditor.toml's `[registry] key` before reading any index, naming both keys (fix: a mismatch was refused only
  by the final whole-lock comparison, as "edited or is stale"; the c2347c9 note that it was not compared was
  wrong). tests/pkg/run.sh 52 to 57 checks.
- Migration (0.23.0): cuditor.lock is now lock_version 2 (`b4e1b88`); `build`, `stage` and `vendor` refuse a version 1
  lock, so run `cuditor pkg lock` once per project and review the new lock. docs/SYSTEMS.md also describes the trust
  on first use of the `[registry] key` and the manual key-rotation process (`c2347c9`).
- `8a4a093` A second module-level `NAME: T` declaration is `error: line N: redeclared global NAME` in hosted and
  freestanding mode (fix): freestanding builds used to fail later in fas with `symbol redefined`, hosted mode
  accepted it silently. New tests/errors/dup_global.cud and dup_global_fs.cud; seed refreshed.
- `17cd45d` tests/user-build expects 122 build/user artifacts (sysfuzz adds .s .o .elf .raw; fix: 2961a9a left the
  count at 118).
- `2961a9a` `sysfuzz`, a seeded ring-3 syscall and capability fuzzer (the plan's item 7, batch 1): every syscall
  gated by a capability it does not declare must return EACCES, numbers outside the native table ENOSYS, then N calls
  with random arguments (huge lengths, kernel and non-canonical pointers, random path bytes) must leave its canary,
  pid and console intact. The OS suite runs `sysfuzz 7 3000` on every boot path (`sysfuzz: PASS`).
- `0d6ef27` Boot harness: box freezes inside the `FORGE_BOOT_INPUT` injection are counted and reported (fix). The
  injection loop never ran the freeze check, so inv224's os/desktop failed with no freeze noted: a box stall let the
  guest's 30 s input window run out with the last 6 of 36 commands unsent. Each command is now checked, the log says
  `[harness: box frozen Ns during input injection, not counted]` and how long the injection took, and any freeze
  shows on the result line. The result still fails. New self-test line `boot-harness input-freeze`.
- `0e763a8` `cuditor pkg vendor [DIR]` (the plan's item 6, batch 4; item 6 is done): after the same lock check as
  `build`, copies only the locked versions and their signed indexes into a new directory and checks the lock
  against the copy, so `--registry vendor` builds offline with the same binary hash. tests/pkg/run.sh 46 to 52
  checks.
- `b4e1b88` Rolled-back registry indexes are refused (the plan's item 6, batch 3): cuditor.lock (now lock_version 2)
  records per package the newest publish time and yanked count of the index it was made from; `build` and a relock
  refuse an older, still validly signed index (a stale mirror, a rolled-back yank). Version 1 locks must be
  relocked. tests/pkg/run.sh 39 to 46 checks.
- `f6b38a7` Dependency cooldowns (the plan's item 6, batch 2; no index format change): with `[registry]`
  `cooldown_days = "N"` in cuditor.toml, `cuditor pkg lock [--now UNIX]` does not newly select a version whose
  signed publish time is less than N days old; `cooldown_exempt = ["name", ...]` exempts packages. Existing locks
  keep building and the lock does not record the time. tests/pkg/run.sh 29 to 39 checks.
- `14a931a` Signed package index (the plan's item 6, batch 1): each registry package has `<name>/index` (v1: version,
  publish time, yank flag and package hash per line) and `<name>/index.sig`, an Ed25519 signature over
  `cuditor-index-v1 ` + sha256(name, newline, index); it replaces `<name>/versions`. cuditor.toml pins the registry
  key (`[registry] key`, also recorded in cuditor.lock); `lock` and `build` refuse an unsigned, edited, wrongly
  keyed or renamed index and package files that differ from the index hash. New `cuditor pkg publish` (versions
  are immutable, publish times never go back, only the current key holder appends) and `cuditor pkg yank`: a
  yanked version is never newly selected but still builds, with a warning, from a lock that has it. Fixture
  packages moved to tests/pkg/packages and are published with the test-only key tests/pkg/test-key.seed;
  tests/pkg/run.sh 12 to 29 checks.
- `25d0ecc` tools/ed25519.cud: `hexpublic`, `hexsign` and `verify PUBHEX SIGHEX MSGFILE` (the kernel's
  `ed25519_verify`, messages up to 96 bytes; exit 0 valid, 1 invalid, 2 bad input). The usage line lists the new
  verbs. tests/ed25519-tool 10 to 22 checks.
- `479ee13` Language server, last slice of the plan's item 5: references and rename take in the `.cudi` files next to a
  document, completion offers the names the includes define (functions, `extern def`s, structs, globals), and `p.f`
  resolves to a struct field when `p` is annotated with a struct or a pointer to one (definition, hover, references,
  completion after `p.`). On the kernel the first references request takes about 5 s, later ones about 0.5 s.
  tests/lsp/run.sh 78 to 88 checks.
- `4c7daf9` Fix: a struct's field names no longer count as top-level names of its file; through the include lookup
  of `ccda869`, a bare `a` resolved to a field `a`.
- `ca69031` Incremental language-server checks: an edit that changes only blank or comment lines is parsed again but
  not compiled again, and the last compile's diagnostics move to the new line numbers; any code line, or any change to
  a file the compile reaches through include or import (open buffer or disk), compiles again. On the kernel about
  90 ms per comment-only edit instead of about 290 ms. `forge/stats` reports `reused`; tests/lsp/run.sh 70 to 77 checks.
- `ccda869` Language server through include files: `cuditor lsp` resolves definitions and hover in freestanding
  sources (kernel, EFI loader, modules) through `include`, including structs, `extern def`s and globals, and a
  `.cudi` sees the names of the `.cud` that includes it. A `.cudi` is checked through that root, with the unsaved
  buffer compiled in place via hidden siblings that are removed afterwards; errors cudc reports inside an include
  appear in that file, with one diagnostic on the `include` line of the files above it, and a missing include is
  shown on the line that names it. tests/lsp/run.sh 45 to 70 checks (tests/lsp/fsproj).
- `594dfd7` USB smoke image: `tools/usb-image.sh` writes build/usb/incudela-usb.img, a reproducible BIOS+UEFI hybrid
  raw image (the kernel ISO tree with `incudela.smoke`, packed by tools/repro-mkrescue from distro GRUB, xorriso and
  mtools). Its EFI system partition holds only the removable-media `\EFI\BOOT\BOOTX64.EFI`, as forge.iso does. The
  tool only writes a regular file and refuses /dev paths; docs/usb.md covers writing it to a stick (pick the right
  device) and the first real-hardware boot. `incudela.smoke` runs only the self-tests that need no QEMU device (no
  virtio disk, drivers, modules, shell or kexec) and prints a `smoke (incudela.smoke):` line before KERNEL OK.
  tests/os/usb.sh boots the image as qemu-xhci + usb-storage under OVMF and SeaBIOS; os/result-count 45 to 50.
- `57de60c` Per-CPU run-queue locks: each run queue has its own spinlock (`rql[q]`); `rq_lock` keeps blocking,
  waking, wait queues, mutexes, condvars, channels and the process tables. No lock is held across `ctx_switch`
  any more: `Thread.on_cpu` stays set until the CPU that switched away from a thread has saved it, and a CPU
  waits for it before switching to that thread (and `thread_free` before freeing it). A running thread's timer
  or yield switch takes no `rq_lock`. Kernel unsafe report unchanged (168 functions, 659 ops). Benchmark
  (`tests/os/schedbench.sh`, TCG on the box), yields/s on 1/2/4 CPUs: about 280k/140k/53k before, 270k/395k/205k
  after; mutex/condvar ping-pongs/s about 141k/70k/24k before, 134k/155k/78k after.
- `a5dcf60` Scheduler benchmark: `incudela.schedbench` on the boot command line runs 2 yielding threads and one
  mutex/condvar ping-pong pair per CPU for 2 s and prints a `schedbench:` line; tests/os/schedbench.sh boots it
  with -smp 1, 2 and 4. A measurement only; it never gates.
- `669946e`, `3c4c48e` public CI (gated as 6020666; pushed in two commits because a git push of a workflow file
  needs the token's workflow scope, so `.github/workflows/ci.yml` came through the GitHub API in 3c4c48e, with
  the same tree as the gated one): .github/workflows/ci.yml builds from the committed seed (FIXPOINT/SEED/TOOLS OK), runs
  `SKIP_OS=1 ./run_tests.sh` at O2 and boots the -O0 kernel in QEMU to KERNEL OK (tests/os/ci-boot.sh, no retry).
  QEMU, GRUB, xorriso, mtools and OVMF come from the runner's apt packages only; no secrets, `contents: read`,
  actions pinned to full commit SHAs, a timeout on every job. tests/ci checks these rules and refuses a copy
  breaking each one. README CI badge; docs/ci.md. The full OS suite stays the dev-box gate.
- `c96256e` run_tests.sh runs its non-QEMU blocks as 62 items in lanes: lane S (the OS artifacts in build/kernel,
  build/user, build/efi, ... and their tools) in order in the foreground, the other lanes as background jobs,
  tests/bounds alone after them, and tests/os (QEMU) alone after everything. Output is printed in item order and
  is the serial output; a failed item's log is printed in place with a pointer to build/par/NN.log.
  `RUN_TESTS_SERIAL=1` keeps the serial run. Non-QEMU wall time on the box (O2): 1173 s to 589 s, same 1106
  results.
- `83256b0` The hang probe and the KASLR test/debug hooks (the `KASLR: kernel image at`/`KASLR: big heap at` lines
  and the unslid `.text` check) are test/debug only: they live in examples/kernel/kdebug.cudi, and
  `build/kernel-build --release` builds build/kernel-release/kernel.elf with the empty hooks of krelease.cudi.
  The OS tests still boot the test/debug kernel; KASLR itself and the `ktest_hooks` gate on syscalls 408/409
  are in both. Kernel instructions: test/debug 83,085 to 83,106, release 82,971. Check: tests/kernel-release.

## 0.22.0 (2026-11-19): SSA backend, Phase 12.1 steps 4d to 4ak; the pre-rename names removed

- `9d48a9d` seed: cudc, fas and fld reseeded from this tree (last reseed 51f53b3); `./build.sh` prints SEED OK and
  SEED TOOLS OK again. seed.sha256: cudc-seed `7928d08a`, fas-seed `caec69e9`, fld-seed `76b48299`.
- `bc1a85f` the old spellings kept for 0.21.x are removed, as README "Renamed from Forge" promised: `./forge`,
  `# forge:` pragmas and cudseal's `# forge: caps(...)` lines, `.forge` modules, `forge.toml`/`forge.lock`,
  `FORGEC_FLAGS`, `FORGE_GUID_SEED` and the `forge.iommu=`/`forge.desktop` boot keys now have no effect
  (tests/oldnames). The one-time `\EFI\Forge\` migration, the on-disk magics and the FS partition type GUID
  stay. Kernel instructions 83,106 to 83,085.
- `ddcedab` tests/os/forgefs.sh no longer counts box freezes against a boot's 180 s: a wall gap of 5 s or more
  between two 1 s polls is a freeze, not counted and logged as `box frozen Ns, not counted`
  (tests/os/frozen.sh); guest running time stays capped at 180 s. Check: `os/forgefs-freeze-accounting`
  (os211b: boot 0 killed by `timeout 180` after a 12-minute freeze).
- `5b81e0a` The OS boot harness (tests/os/boot.cud) keeps a read end of QEMU's stdin pipe and monitor FIFO,
  so writing `q` to a QEMU that already exited no longer kills it by SIGPIPE (exit 141, no result line, no
  log: `os/kernel-iommu` lost in os211b); writes are checked. Check: `os/boot-harness-early-exit` (a stub
  QEMU that exits before `q`; missing markers, a wrong exit code and a failed screendump still FAIL).
- `571967d` The OS boot harness reports a missing or truncated screendump as `screendump failed` (a
  framebuffer FAIL with its result line and log) instead of crashing on None.
- `f6890f1` `--fs-ssa` moves a constant index read once by a scaled address into its displacement (step 4ak,
  `mov %rdi,24(%rax)`): kernel instructions 83,521 to 83,106.
- `b449cc3` `--fs-ssa` lets `ud2` end a path, so a bounds check's pass label keeps the index register and the
  `%rcx` copy goes (step 4aj): kernel instructions 84,336 to 83,521.
- `174afe2` `--fs-ssa` folds a `lea ADDR,%rT` read only by the next mov, through `(%rT)`, into that mov
  (step 4ai, `mov (%rax,%rcx,8),%rax`, `mov %rsi,8(%rax)`): kernel instructions 86,168 to 84,336.
- `dc50329` `--fs-ssa` puts a checked index's `imul $8` scale into the address it forms (step 4ah, `lea
  (%rD,%rR,8),%rD`): kernel instructions 87,642 to 86,168.
- `1aabd27` `--fs-ssa` deletes a `jmp .LFk` whose target is among the labels straight after it (step 4ag):
  kernel instructions 89,193 to 87,642.
- `4ccc1aa` `--fs-ssa` deletes the never-run lines straight after an unconditional `jmp` with no label between
  (step 4af, `jmp; jmp` after `break` and `jmp; xor` after a loop exit): kernel instructions 90,924 to 89,193.
- `f2ffc23` Kernel irq-off watch counts CPU 0 timer gaps of 5 s or more apart as "guest not running" (a box
  freeze: the guest TSC follows host time), keeping them out of the longest gap and the over-250-ms count;
  diagnostic only (kbs-s1 stress: 126 s, 304 s and 140 s gaps were box freezes).
- `9a49dc7` Kernel stop-machine fix: a CPU parked for one round that answers the next round from its park
  loop stays parked for it instead of running again (kbs-s1 boot 30: `#UD` in `sys_getppid` while livepatch
  rewrote it). `stop_machine stress` now checks that no other CPU runs inside each of its 3000 rounds
  (without the fix 40 of 40 loaded boots failed, with it 40 of 40 passed).
- `097fd12` Kernel CPU 0 interrupts-off watch (diagnostic only): one `rdtsc` per CPU 0 timer tick keeps the
  longest gap between timer interrupts in the shell session, reported as `irq-off watch: ...` and in the hang
  probe; `os/irq-off-watch` logs it and never judges it (inv203 hypothesis H1).
- `f442570` OS hang dumps record the guest's input counters: each kernel prints a `hang probe:` line with the
  slid addresses of `kbd_irqs`, the new `ps2_rd`, the input journal and tick counters, and tests/os/boot.cud
  reads them on cpu 0 into `LOG.hangN`; `os/hang-probe-live` runs the reads at KERNEL OK (inv203: 99 IRQ1
  against 115, the tail of a typed line lost).
- `ad017f8` `--fs-ssa` folds `setCC; movzbl; test; je|jne L` through a same-sense `je|jne F` at L
  straight to F (step 4ae through-merge stop): kernel instructions 91,805 to 90,623; short-circuit
  merges that keep `setne` at L stay refused.
- `cc90ae0` `--fs-ssa` retargets `imul $N,…,%rax` and stores `%rS` straight to MEM (step 4ac) and turns
  unread-flag `add`/`sub` through `%rax` into `lea` into `%rD` (step 4ad): kernel instructions 92,421 to
  91,805.
- `e2e00c6` `--fs-ssa` folds a one-use `xor`/`mov $N,%rax` into `movq $N,MEM` or `mov $N,%rD` (step 4aa)
  and retargets a one-use `lea`/`mov MEM,%rax` copy into `%rD` (step 4ab): kernel instructions 93,068 to
  92,421; setCC chains left for a later flag-safe stop rule.
- `025419d` `--fs-ssa` drops `mov %rS,D(%rbp); mov D(%rbp),%rS` reloads (step 4y) and `add $0,%rsp`
  after calls (step 4z): kernel instructions 93,932 to 93,068.
- `f949df7` `--fs-ssa` rewrites `setCC %al; movzbl; test; je|jne L` as one `jCC` when L does not
  consume flags and neither edge reads the 0/1 (step 4x); duplicate tests are dropped even when the fold
  is refused: kernel instructions 94,731 to 93,932; short-circuit and/or merges that keep `setne` at L
  are left alone.
- `b338b9b` fas/fld write `path.tmp` then `rename(2)` onto `path`; cuditor `-o` links to `out.new` then
  `mv -f`; tests/fas snapshots each `.s` before as vs fas (inv192 O2 one-off `fas build/user/bg.s` FAIL).
- `2fb9a99` tests: `fs-ssa-mul-shape` accepts two-op or three-op `imul $N` (no `mul %rcx`) after step 4v.
- `84f8499` `--fs-ssa` rewrites `and $N,%rax` whose value only feeds setcc as `test $N,%rax` (step 4w):
  kernel instructions 94,742 to 94,731, copies into %rax 979 to 958.
- `53b86ed` `--fs-ssa` folds `mov $N,%rcx; mul %rcx` / `imul %rcx,%rax` with the multiplicand already in
  %rax into `imul $N,%rax` when the high half is unread (step 4v): kernel instructions 95,191 to 94,742,
  copies into %rax 1,035 to 979.
- `f061ac1` `--fs-ssa` folds `mov $N,%rcx; alu/cmp %rcx,%rax` when a later call only falsely counts as
  reading %rcx (step 4u, same `fs_ssa_rcx_lo` as 4t): kernel instructions 95,918 to 95,191, copies into
  %rax 1,056 to 1,035.
- `1d473c1` `--fs-ssa` folds remaining `mov $N,%rcx; shr|shl|sar %cl,%rax` via `fs_ssa_rcx_lo` and
  rewrites unread-flag `sub $N,%rax` after a copy into %rax as `lea -N(%rS),%rax` (step 4t): kernel
  instructions 96,055 to 95,918, copies into %rax 1,074 to 1,056.
- `93a1258` `--fs-ssa` drops a redundant `test %rax,%rax` after `and`/`or`/`xor` into %rax when those
  flags were unread (step 4s): kernel instructions 96,232 to 96,055.
- `4c0b68b` `--fs-ssa` folds `mov $N,%rcx; shr|shl|sar %cl,%rax` into `shr|shl|sar $N,%rax` when that
  %rcx is read once and N is in 0..63 (step 4r): kernel instructions 96,843 to 96,232, copies into %rax
  1,185 to 1,072.
- `f944491` tests: tools/fsfuzz.cud negates one generated condition in eight (`not (...)`) and joins two
  compares with `and`/`or` in another one in eight.
- `9764d45` `cudc --fs-ssa` (opt-in, implies `--fs-temps`): SSA values for the scratch and argument
  registers and the flags over each function's control-flow graph, checked by a verifier, and three
  use-count folds (a constant in %rcx into its ALU op or compare, `xor`+`cmp` into `test`, `setCC`/`movzbl`/
  `test`/`je` into one `jCC`). The first pass landed under the optimizer landing rule (optcov group, fsfuzz
  ten builds and 72 combination flag sets). Code built without the flag is byte-identical.
- `55790c5` the kernel and kernel-next are built with `--fs-ssa`: .text 508,896 to 457,536 bytes (-10.1%),
  instructions 134,600 to 120,544; `--unsafe-report` unchanged (168 functions, 659 ops).
- `70e9cf8` `--fs-ssa` also deletes register writes nothing reads (step 4e): kernel instructions 120,544 to
  119,967.
- `68836cb` `--fs-ssa` propagates register copies (step 4f): a read of %rB that holds a `mov %rA,%rB` copy
  reads %rA while %rA still has the same value; the unread copy then dies. Kernel instructions 119,967 to
  118,980.
- `f69eff8` the UEFI loader, the kernel modules and the user programs are built with `--fs-ssa` (step 4g):
  instructions -25.9%, -21.0% and -24.6%; incudelax64.efi 13,312 to 10,752 bytes.
- `ec90a5a` `--fs-ssa` tracks the callee-saved registers %rbx and %r12-%r15 (step 4h): a call preserves
  them and `ret` reads them, so copies out of them propagate too. Kernel instructions 117,427 (from 118,980),
  `mov %rbx,%rax` 2,415 to 1,957.
- `f589a68` `--fs-ssa` lets a move whose only reader is the next line's `mov %rA,%rB` write %rB itself (step
  4i, the start of SSA-based allocation of the temporaries). Kernel instructions 115,086, `mov %rax,%rdi`
  4,474 to 3,535, .text of kernel.cud 453,291 (before step 4h) to 441,355 bytes.
- `ee71af6` `--fs-ssa` finds the live phis on a worklist instead of sweeping until stable: the kernel compiles
  in 2.2 s instead of 5.5 s, with byte-identical output.
- `cb3cba0` `--fs-ssa` computes a value in its copy's register over the whole straight-line range before the
  copy (step 4j): kernel instructions 115,086 to 112,737, `mov %rax,%rbx` 805 to 394, .text of kernel.cud
  434,491 bytes.
- `8b021f5` `--fs-ssa` lets such a range start with `xor %eA,%eA`, zeroing the copy's register instead (step
  4k): kernel instructions 112,737 to 112,268, .text of kernel.cud 433,131 bytes. Temporaries whose range
  crosses a label, the planned step 4k, were measured not to occur in this code generator and are not handled.
- `9f35795` `--fs-ssa` keeps a straight-line `push`/`pop` round-trip of a nested operand in a free register
  (step 4l): kernel instructions 112,268 to 109,854, pops 3,365 to 1,349; .text of kernel.cud 433,951 bytes
  (+0.2%, a register move is longer than `push`/`pop`).
- `aa27d7b` `--fs-ssa` rounds are cheaper (scratch tables kept between rounds, a per-line cache of what each
  line reads and writes, merge sweeps that skip unchanged positions): the kernel compiles in 1.74 s instead of
  2.31 s, with byte-identical output.
- `2388c61` `--fs-ssa` gives a function eight rounds instead of four: kernel instructions 109,854 to 108,520,
  pops 1,349 to 1,049, .text of kernel.cud 431,167 bytes; compile 2.36 s.
- `684e865` `--fs-ssa` computes call arguments straight in their registers (step 4m): a call reads %rax only
  as the vector count of a variadic callee (an argument in %xmm), so `lea s(%rip),%rax; mov %rax,%rdi` becomes
  `lea s(%rip),%rdi`. The measurement before it: 5,138 of the kernel's 17,583 register moves set up a call
  argument through %rax. Kernel instructions 108,520 to 103,596, moves to 12,656, .text 416,495 bytes.
- `a8c4c9f` `--fs-ssa` propagates copies into memory operands (step 4n): the base and index registers and the
  stored register read the copy's source, so an array store `mov %rax,%rcx; mov %rdx,%rax; mov %rax,(%rcx)`
  becomes `mov %rdx,(%rax)`. Kernel instructions 103,596 to 102,244, moves to 11,296, .text 412,527 bytes.
- `51b964b` fix: the `--fs-ssa` SSA form gave every position after a loop header a phi of its own, so
  copies inside loops were never propagated (`mov %r8,%rax; cmp %rdi,%rax` stayed). A position with one
  predecessor now takes that predecessor's values. Kernel instructions 102,244 to 101,399, register moves
  11,296 to 10,447.
- `f0df4f8` `--fs-ssa` keeps step 4l's push/pop round-trips in a register across a bounds check's failure
  path, which never comes back (step 4o); the failure call's alignment pad goes with the push. Kernel
  instructions 101,399 to 99,001, pops 1,058 to 459, .text 410,143 to 404,031 bytes.
- `79944e3` `--fs-ssa` rounds cheaper again, with byte-identical output: a row cache per line so an unchanged
  line is not parsed again in the next round, a one-predecessor shortcut in the merge sweeps, and cheaper line
  checks in fs_regalloc. The kernel's `--fs-ssa` compile 3.14 to 2.30 s.
- `359c52d` `--fs-ssa` drops copies into %rax that feed an `add`, an `imul` by a constant or a `push` (step
  4p): `lea N(%rS)`, `lea (%rS,%rT)`, `imul $N,%rS,%rax`, `push %rS`; twelve rounds per function instead of
  eight. Kernel instructions 99,001 to 97,286, copies into %rax 2,276 to 1,360, .text 404,031 to 399,599
  bytes; compile 2.46 s.
- `8d9befc` fix: `--fs-ssa` no longer treats `mul` as reading %rdx (only `div`/`idiv` read the rdx:rax
  dividend). Kernel instructions 97,286 to 97,267, pops 437 to 426.
- `51f53b3` `--fs-ssa` keeps push/pop round-trips that cross a call in a callee-saved register when the call
  needs only an alignment pad, and folds unread-high-half `mul` by a constant into three-operand `imul`
  (step 4q). Kernel instructions 97,267 to 96,843, pops 426 to 410, copies into %rax 1,185, .text 397,855 bytes.

## 0.21.1 (unreleased): rename cleanup

- `e67d124` fix: tools/fsfuzz.cud generated its programs with `# forge: no-runtime` and
  `# forge: stack-protector`, which 0.22.0 would stop reading (the fuzzers would then test the hosted
  path); they write `# cuditor:`. `cuditor pkg` now really reads a project's old `forge.lock` (it checked
  and compared only `cuditor.lock`). Two compiler comments name the real old spellings again.
- `e0f1573` every old spelling kept until 0.22.0 (`# forge:` pragmas and caps lines, `.forge` modules,
  `forge.toml`/`forge.lock`, `FORGEC_FLAGS`, `FORGE_GUID_SEED`, `./forge`) prints one
  `warning: OLD is deprecated, use NEW` line on stderr; the output stays byte-identical (tests/oldnames, which clears the old names it does not test, since the O0 gate
  exports `FORGEC_FLAGS`).
- `2c242f9` tests: OS hang dumps also record interrupt delivery (`info pic`, `info irq`, `info lapic N`
  for every vCPU).
- `5e2c56d` fix(tests): the OS boot harness times guest silence on CLOCK_MONOTONIC. The box VM is
  suspended now and then and the wall clock jumps; the harness counted the jump as guest silence, which
  gave the inv167 kexec-old-to-new and inv171 bootpol2 false HANGs (each claimed more silence than the
  QEMU process had lived). Suspensions are logged and not counted; the stall limit and timeouts are
  unchanged.

## 0.21.0 (unreleased): Forge becomes Incudela (the OS) and Cuditor (the language)

The old names keep working for this release (README, "Renamed from Forge"); on-disk magics, the FS
partition type GUID and the Linux personality's `uname` strings are kept for good.
- `da81abc` the language is Cuditor: `.cud`/`.cudi` sources, the compiler `cudc` (`seed/cudc-seed`), the
  driver `./cuditor`, `# cuditor:` pragmas, `cuditor.toml`/`cuditor.lock`, `CUDC_FLAGS`,
  `INCUDELA_GUID_SEED`, and the tools cudseal, incudela-part, cud_test, cud_verify and c2cud.
- `1aec031` fix: cudseal (and cudseal.py) read `# cuditor: caps(...)` and still the old `# forge:`.
  After the rename both matched only `forge:`, so every program was sealed with caps 0 and every boot
  panicked at the `bin/cat` seal check (gate inv165).
- `81c05dd` licences: Incudela under Apache-2.0, Cuditor under MIT (LICENSE says which applies where;
  LICENSE-APACHE, LICENSE-MIT, REUSE.toml).
- `c01b041` the OS is Incudela: `incudela-kernel 0.2.6`, the Incudela UEFI loader, Incudela FS, the
  `incudela.iommu=`/`incudela.desktop` boot keys (the `forge.` keys still read).
- `36252c3` fix: tests/t3.expected and tools/incudela-part.cud follow the new name (inv165).
- `f429c5a` the ESP folder moves from `\EFI\Forge\` to `\EFI\Incudela\` with a one-time migration
  (tools/espmigrate.cud) that keeps the old folder until the new one boots.
- `0b6ceeb` fix: a disk not migrated yet may carry an older build's init.elf; the kernel accepts it only
  from `\EFI\Forge\` (kexec-old-to-new requires the alias line), and migrated disks keep the strict check.

## 0.20.1 (unreleased): self-test race fix

- `411b601` fix: the boot-time tlb_test freed its worker threads after they reported done but possibly
  before they exited; under host load the kernel panicked "thread_free: thread still alive". It reaps
  them (waits for T_DEAD), and a new boot self-test (`thread reap: 4 workers ...`) reproduces the race
  without load.
- `f334521` tests: kexec-compat builds the old 61b3e85 kernel with that one-line teardown fix ("old build
  plus the 411b601 self-test teardown fix; the handoff format is untouched").

## 0.20.0 (unreleased)

### Ownership-typed struct fields (build-plan item 2)
- `c081619` Stage 1 (designed with ChatGPT): `own[T]` fields are laid out (8 bytes, 8-aligned) but every
  access is refused until Stage 2.
- `4f9aec0` Stage 2 (designed by ChatGPT, reviewed here): direct `own[T]` fields of local structs get
  per-field move, initialisation and borrow state, joined across branches and loops.
- `05df144` fix: only the outermost assignment target takes the field-store path (double move and a write
  under a shared borrow inside targets).
- `9d057e6` Stage 3a (designed by ChatGPT, reviewed here): an `own[T]` field behind a local
  `own`/`mut`/`ref` pointer is usable as a place (`p.head.id`); moving it out waits for `take`/`replace`.
- `c2d57f3` fix: Stage 3a review fixes (named-base guard, a real runtime test, the raw-pointer message,
  seven regression tests).
- `6e19afc` fix: the Stage 3a comment block in `fs_postfix` reformatted with `build/fmt` (gate inv152
  failed fmt-repo-clean on it).
- `f0cd802` fix: pointer arithmetic on `own`/`ref`/`mut` (`q + 8`) is an unsafe operation; in safe code it
  made a second owner (or borrow) of the neighbouring memory.
- `dc44810` fix: a whole-element `p[i]` of a pointer to owners (`ptr[own[T]]`, `own[own[T]]`) is an unsafe
  operation; `a = q[0]; b = q[0]` copied one owner into two.
- `77f5e7c` Stage 3b-min (designed by ChatGPT, implemented here): `nown[T]`, an affine owner that may be
  none, for locals, parameters/returns and struct fields; use as `own[T]` needs an `if o != 0:` proof. No
  globals, arrays or `take`/`replace`/`swap` yet.
- `101c34c` tests: ChatGPT's 3b-min review probes (44 run, none wrongly accepted) pinned as 15 refusals and
  a runtime test; the loop false rejection is documented in SYSTEMS.md.
- `4fb4c9b` Stage 3c (designed with ChatGPT, implemented here): `take(place)`, `replace(place, v)` and
  `swap(a, b)` on named places (own/nown locals, Stage 2 fields, fields behind a local own/mut pointer);
  the only way an owner moves into or out of a field behind a pointer. A condition calling one of them
  proves nothing (found by the 78-program adversarial set).
- `6caae93` fix: passing a `mut[T]` as a call argument while a shared borrow of it is live
  (`r = borrow(m); bump(m)`) is refused; the callee could write what the `ref` still reads.
- `b7f75eb` fix (to 3c): `swap(a, b)` refuses two places where one is reached through the other
  (`swap(x, x.next)`), which stored an owner into its own child (a cycle, two owners).
- `1a51b4b` Stage 3d (designed with ChatGPT, implemented here): `borrow(p.head)` / `borrow_mut(p.head.next)`
  through a local own/mut/ref pointer record the borrow on the root; nested own-field paths for reads,
  writes and `take`/`replace`/`swap`; `nown` steps need a check, `ref` roots stay read-only.
- `7632ffe` `nown[T]` globals and global `nown[T][N]` arrays (designed with ChatGPT, implemented here):
  they start none; a global and each element `a[i]` are places for `take`/`replace`/`swap` (index
  evaluated once) or a test for none, nothing else.
- `5d743d2` Stage 3e, kernel run queue (designed with ChatGPT, implemented here): `rq_head`, `current`
  and `idle_thr` are `nown[Thread][8]`, linked through `Thread.rq_next: nown[Thread]`; `rq_pop` is safe
  code, `schedule_l` has one transfer point, `thread_adopt` panics on a second owner. Kernel unsafe
  report 170 / 708 -> 168 / 701.
- `0bf232a` Stage 3f, kexec handoff records (designed with ChatGPT, implemented here): `struct PsRecord`
  and `struct KxdRecord` at the documented offsets (checked at boot); each record is written through one
  `own` that `ps_seal`/`kxd_seal` consume and adopted as one owner given back before the region is
  released. Kernel unsafe report 168 / 701 -> 168 / 659.

### Optimizer: Phase 12.1 steps 4a-4c
- `be09366` step 4a, `--fs-opt` promotes scalar locals in safe functions that also take frame addresses;
  kernel frame accesses -4.0%.
- `604811f` step 4b, liveness-based register sharing under `--fs-live` (byte-identical without the flag).
- `447067b` the kernel is built with `--fs-live` (frame accesses 11,975 to 11,125).
- `3b69d8a` step 4c, stack temporaries into registers (`--fs-temps`).
- `6b43bdd` the kernel is built with `--fs-temps`.
- `e72e5d3` tools/fsfuzz, a differential fuzzer for `--fs-opt`.
- `6dd80b0` docs: the `--fs-opt` asm audit as a checked list, kept complete by tests/asm-audit.
- `6091098` bench record integrity (`bench run` records the full HEAD sha and refuses a dirty tree).

### Optimizer correctness gate (build-plan item 3)
- `f5a044b` part a, tools/optcov: block coverage of the freestanding optimizer passes (252/284).
- `d2cc610` part b, `fsfuzz --combos`: every optimizer flag combination must give the same output.
- `2324477` part c, `optcov --check`: the 2 reachable never-hit blocks get tests, the other 30 are an
  allow-list with reasons.
- `1d4e26e` part d, `optcov --registry` and the landing rule: a new pass lands only with `optcov --check`
  and `fs-opt-combos` green.
- `4985232` fix: `-O0` turns off bounds-check elision in freestanding code (the O0 pass now runs a
  different code path for kernel and user code).
- `221b90f` fix(tests): efi-build/esp-reproducible builds both ESPs with the same FORGEC_FLAGS.

### v1 reservations 1-4
- `48ec0a6` 1: AI-provenance commit trailers, checked by `forge provenance`.
- `36786ed` 2: `noalloc`/`noio`/`noreclaim` effect names reserved (grammar v1.3).
- `b56affe` 3: an address-space ID in the device-grant ABI (drv 402); only 0 exists.
- `43b38fa` 4: process-state v2 records carry a checksum next to their version.

### Test infrastructure
- `7e4cf93` fix(tests): bounds-bench-overhead takes the median of 21 pair ratios, each pair the best of 3
  interleaved rounds per variant; the 5% limit is unchanged (inv156 failed at 6.95% with identical code).
- `bd07324` fix(tests): the unsafe baseline and provenance result names carry the directory, so two results
  no longer share a name (2026-11-15 assessment).
- `94824c4` fix(tests): run_tests.sh fails closed when the OS-test toolchain (QEMU, GRUB, xorriso, mtools,
  OVMF) is missing instead of silently skipping tests/os; `SKIP_OS` is the only opt-out and is never a gate pass.

### Plan and docs
- `ce37b64` CHANGELOG.md for 0.17.2 through 0.18.0 and the start of 0.18.1.
- `e21ccf8` current execution order, the six v1 reservations and a Version 2 section.
- `e287417` working screen first, then the reviewed core order and three never-reboot tiers.
- docs for the gate's whole-repo `build/fmt --check` preflight (the commit after 9c31307; the harness lives
  outside the repo).
- `630410a` fix(docs): README states the kernel unsafe ceiling as 168 / 659 (it said 170 / 709).
- `0cd8e2c` docs(kernel-core): Appendix A names all 39 OS results (it said 35).

## 0.19.0 (unreleased)

### Working screen (build-plan item 1)
- `caf405d` step 1, framebuffer graphics and a desktop boot (gfx.fsi, `forge.desktop`).
- `cfaa6b6` step 2, a terminal window that receives console text.
- `f2c39a8` step 3, PS/2 mouse and keyboard events with an on-screen cursor.
- `e0e40cd` step 4, a windowed compositor (z-order, damage repaint, click focus, drag).
- `be48d2a` step 5, a sandboxed program gets a window through the gfx capability.
- `6f29153` step 6, a desktop shell (taskbar, launcher, minimize); the working screen is complete.

### Interrupt-driven drivers (Phase 8)
- `7a6d513` USB HID step 1: the HID boot keyboard interface and its interrupt IN endpoint are configured.
- `d6abc5d` USB HID step 2: boot reports read and decoded from an interrupt IN ring.
- `2309455` USB HID step 3: the keyboard moves to MSI-X vector 0x52 and feeds the tty.
- `4358997` NVMe I/O completions on MSI-X vector 0x53 wake sleeping readers.
- `822db56` AHCI command completions on PCI MSI vector 0x54; `hw_quiesce` clears interrupt enables
  before kexec.

### DMA policy
- `ce02f98` boot-time DMA policy switch: a sealed `\EFI\Forge\boot.cfg` sets `iommu=strict|permissive`;
  `forge.iommu=strict` on the command line can only tighten; the default is unchanged.

## 0.18.1 (cut; no tag)

### Fixes
- `01beb01` the boot harness checks the framebuffer only after two consecutive identical screendumps.
- `2829140` kbd hot-swap waits until the running input driver has entered `recv` once (inv134 hang).
- `1a04c95` the boot harness does not count time the box itself was frozen as guest silence.
- `80641f6` the fail-fast stall checks skip a clock jump over 1 s (box suspended whole).
- `3b13416` bounds-bench-overhead takes the best of 21 interleaved runs.
- `a7f2084` AP start-up waits 1 s and parks an AP that misses it before the trampoline is unmapped.
- `27aed3d` multiboot2 framebuffer byte order (red and blue swapped on GRUB boots).
- `1b4a017` more than 4096 locals in one freestanding function is a diagnostic, not an internal index error.

### Ownership checker holes
- `44d594d` arrays and slices of own/ref/mut refused as struct fields (two owners from `q.a[0]`).
- `cd512f0` `addr()` of an own/ref/mut value is an unsafe operation.
- `357500e` hosted code refuses own/ref/mut in every type position, not only parameters.
- `817848d` arrays and slices of own/ref/mut refused in every position (globals, locals, parameters,
  `slice(p, n)`), not only struct fields.
- `66edf73` `addr()` of a place reached through a `ref[T]` is an unsafe operation.

### Test and debug infrastructure
- `4e8e48b` stall dumps record QEMU's threads and the box from the host side (tests/os/hostcap.sh).
- `e7bc71f` fail-fast lost-lock and stalled-tick checks print PANIC-STALL instead of hanging.
- `f421b86` tools/ostools, the OS-test toolchain preflight that reinstalls QEMU/GRUB/xorriso/OVMF.

## 0.18.0 (cut at 1fa2883)

### c2forge (C subset to Forge)
- `515ff04` file-scope variables with integer constant initializers, wrapped as C converts them.
- `6f20a1a` integer constant expressions folded for array sizes.
- `2f75b57` `++`/`--` inside expressions.
- `8099896` string literals and char array string initializers.
- `25c273a` fix: `/` and `%` in constant expressions truncate toward zero as in C.
- `e688155` integer global initializers may be constant expressions (shifts, bitwise ops, `sizeof`, C division).
- `ab1aa5a` 1-D integer brace lists at file scope; array sizes taken from the initializer.
- `a84048e` tentative definitions and extern redeclarations merge into one definition.
- `4b8dd49` float and double global initializers (scalars and 1-D brace lists).

All of them match gcc at O2 and O0 on their tests.

### Optimizer and bench (Phase 12.1, 12.4)
- `879f794` tools/bench.forge, the Phase 12.4 tracker (self-compile and bench-vs-native numbers, regression check).
- `67b7f8f` perf(compiler): reused name buffers; self-compile 2354 ms to 1560 ms.
- `ce066fa` step 1, opt-in `--fs-opt`: leaf-function scalars in caller-saved registers, push/pop peephole.
- `e22d2c1` `--fs-opt` divides by literal constants with multiply-and-shift (fsloop 297 ms to 184 ms).
- `79e8282` fix(bench): `bench check` takes each value as its best over the newest 3 records.
- `6e764dd` step 2: functions with calls promote slots into callee-saved registers.
- `8471ed7` step 3: the kernel is built with `--fs-opt` after a SysV audit of every asm routine
  (`smep_probe` fixed; kernel code 534,272 to 495,157 bytes).
- `dd5c0d3` step 3b: the UEFI loader (-8.7%) and kernel modules (-14%) are built with `--fs-opt`.
- `b6d5906` step 3c: the user programs are built with `--fs-opt` (code -4.2%, frame accesses -20%).
- `d0e42b9` f64/f32 globals and arrays take float or integer literals, stored as IEEE bits. Reseed.

### Networking (Phase 8)
- `c969e25` ICMP echo: e1000 and virtio-net ping the QEMU gateway after ARP and check the reply.
- `1fa2883` UDP echo on port 7 (IP and UDP checksums checked, ARP answered), tested through a QEMU hostfwd port.

## 0.17.4 (fixes)

- `4ecde04` fix(kernel): no `hlt` in the post-KERNEL-OK wait, so efi-loader-gpt cannot stall 60 s.
- `f5c66be` fix(build): ESP volume serial and ISO UUID pinned, so two clean builds match.
- `43b821c` fix(kernel): TSC-bound THRE wait in `serial_putc`, so a backed-up serial pipe cannot wedge the kernel.
- `4f84fac` fix(test): QEMU stdio drained before HMP hang dumps; the 60 s stall checked every loop iteration.
- `45fd6a5` fix(kernel): Linux `rt_sigreturn` leaves by iretq and restores rcx and r11, so a resumed fault
  keeps every register.
- `0bbe40c` docs(kernel): verification-scope appendix in kernel-core.md.
- `2aba6e2` chore(unsafe): tests/unsafe baseline ratcheted from 716 to the live 709.

## 0.17.3 (security: VT-d)

- `a1c4c5b` VT-d default deny, every DRHD programmed, and a 65,536-entry context-table audit.
- `643d72e` VT-d fault recording and requester-ID aliasing, tested with edu behind a PCIe-to-PCI bridge.
- `a4dbaa6` a written DMA policy for machines without a remapping unit; strict mode refuses drv 402.
- `3f64450` VT-d interrupt remapping with queued invalidation and source-validated IRTEs.
- `385bdaf` docs(plan): BUILD_PLAN no longer lists the seven closed DMA/IOMMU gaps as open.

## 0.17.2

- `bc37abd` fix(c2forge): static locals and same-name inner-block shadowing are rejected with clear errors.
- `877f206` feat(ffi): PyConfig/PyStatus/PyMethodDef layouts generated from the pinned CPython headers; a
  non-pinned or free-threaded libpython is refused.

## 0.17.1

Base: `5b8e7af`.
