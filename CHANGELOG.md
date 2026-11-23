<!-- CHANGELOG.md: release notes for Incudela (the OS) and Cuditor (the language), both named Forge until
     2026-11-16, from 0.17.1 (5b8e7af) on. Each entry names its commit; the
     version-to-commit mapping comes from the project plan. There are no git tags: the versions are
     groupings of commits, not contiguous ranges of history (for example the 0.17.4 fixes 0bbe40c, 4ecde04,
     f5c66be and 2aba6e2 come before the 0.17.2 commits in the log). Newest version first. 0.18.1 is cut as
     a grouping only; 0.19.0, 0.20.0 and 0.23.0 are open; 0.22.0 is closed (2026-11-19). Entries before 0.21.0 use
     the names of their time (Forge, forgec, c2forge, `\EFI\Forge\`). -->
# Incudela and Cuditor changelog

## 0.23.0 (open): test/debug and release kernels; parallel run_tests.sh; public CI; per-CPU run-queue locks; USB smoke image; language server through include files; incremental LSP checks; LSP references, completion and struct fields

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
