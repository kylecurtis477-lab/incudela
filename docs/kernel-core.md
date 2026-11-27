# Kernel core interface spec (scheduler, IPC, capabilities)

Status: **spec v1** (plan v1.3 item 8). This document states the interface the rest of the kernel and
user programs may rely on for the three core services, as implemented today in
`examples/kernel/sched.cudi`, `chan.cudi`, `proc.cudi` (handle rights) and `seal.cudi` (syscall
capabilities). It is a description of the contract, not new code: nothing in the kernel changed with it.
Anything not written here is an implementation detail and may change without notice. A change to
anything written here bumps the spec version and must update this file in the same commit, with tests.
Appendix A records the verification scope for this contract and for the kernel properties the boot
tests pin, including the known DMA/IOMMU gaps. It does not change the interface in §§0–5.

Related formats that are specified elsewhere and referenced, not repeated: process-state v1 and the
kexec handoff (SYSTEMS.md "Process-state format", `pstate.cudi`), the nondeterminism hook
(SYSTEMS.md, `nondet.cudi`), the seal / proof manifest (SYSTEMS.md "Proof manifests", "Seal v3").

## 0. Conventions
- Errors are returned as negative values in a u64 (`EPERM`, `EBADF`, `EFAULT`, `EINVAL`, `EMFILE`,
  `EACCES`, `EPIPE` = -32). Argument and permission errors are reported before any side effect.
- Locking: the global spinlock `rq_lock` guards thread state changes for blocking and waking, every
  wait queue, mutex, condvar and channel, and the process tables. Each CPU's run queue has its own
  spinlock `rql[q]` (0.23.0), taken only inside `rq_push`/`rq_pop`. Functions ending in `_l` require
  `rq_lock` held **and interrupts off**; all others take and release it themselves and may be called
  with interrupts on. Lock order: `rq_lock`, then at most one `rql[q]`, innermost; no other lock may be
  taken while holding `rq_lock`, and `rq_lock` never while holding an `rql`.
- "Blocks" means the caller may be descheduled; it must not hold `rq_lock` (non-`_l` API) or any
  spinlock other than `rq_lock` (the `_l` API, which releases it while parked).

## 1. Scheduler (`sched.cudi`)
### Model
- Kernel threads (`Thread`), preemptive, round-robin on the 100 Hz LAPIC timer; one run queue per
  CPU (up to 8) with stealing; a per-CPU idle thread. A user process runs on one or more threads; the
  thread carries the address space (`cr3`), FPU area, user FS base and the syscall in progress.
- States: `T_READY` 0, `T_RUNNING` 1, `T_DEAD` 2, `T_IDLE` 3, `T_BLOCKED` 4.
  Transitions: new -> READY (`thread_start_ready`); READY -> RUNNING (picked); RUNNING -> READY
  (preempted / yield); RUNNING -> BLOCKED (`wq_block_l`); BLOCKED -> READY (`wake_l`);
  RUNNING -> DEAD (`thread_exit`). No other transition is legal.
- No lock is held across the stack switch (0.23.0; before, `rq_lock` was held across it and released by
  the resumed thread). `Thread.on_cpu` is 1 from the moment a CPU picks the thread until the CPU that
  switched away from it has saved it: the resumed side (`sched_finish`, after `ctx_switch` or in a new
  thread's `sched_tail`) clears it for `sw_prev[cpu]`. A CPU that took a thread from a run queue waits
  for `on_cpu == 0` before switching to it, and does so before its own old thread goes back on a queue, so
  the waits cannot form a cycle; `thread_free` waits for it too. A blocking thread keeps `rq_lock` until
  its owner is given up, so no waker can adopt it earlier.
- Every pick passes the nondeterminism hook (`nd_hook(ND_SCHED, cpu, thread)`).
- Ownership (Stage 3e): each thread has at most one owner at a time. The run queue owns its READY threads
  (`rq_head[q]: nown[Thread]`, then `Thread.rq_next`; `rq_tail[q]` is a non-owning view), `current[cpu]`
  owns the running thread and `idle_thr[cpu]` the idle thread while it is not running. The owner is
  created once by `thread_adopt` (`thread_start_ready`, `wake_l`, `sched_cpu_init`), which panics on a
  thread that already has one, and is given up in `schedule_l` when the thread blocks (its raw wait-queue
  link holds it until `wake_l`) or dies (`thread_reap` frees it through its handle). `schedule_l` has one
  transfer point, `replace(current[cpu], nxt)`; `cur_thread()` is a non-owning view of `current[cpu]`.
- kexec handoff records (Stage 3f): process records are `own[PsRecord]` while written (consumed by `ps_seal`)
  and while adopted (given back by `ps_done` before the region is released); the driver-state record likewise
  (`KxdRecord`, `kxd_seal` / `kxd_done`). Their layouts are checked against the format at boot.
- Each thread has a 16 KiB kernel stack with a guard page; overflowing it ends the thread
  (`thread_overflow_exit`), not the kernel.

### Calls
| call | contract |
|---|---|
| `thread_spawn(fn, arg) -> ptr[Thread]` | create and make READY; `fn(arg)` runs, returning from it = `thread_exit` |
| `thread_new` / `thread_start_ready` | the same in two steps (set fields such as `pin`, `proc` in between) |
| `yield_cpu()` | give up the CPU; returns READY->RUNNING later |
| `thread_exit()` | never returns; the thread is reaped by `thread_reap` (its stack and FPU area freed) |
| `sleep_ticks(n)` | block for at least n timer ticks (10 ms each) |
| `schedule(exiting)` / `schedule_l` | internal: irqs off; `_l` returns with `rq_lock` released; a running thread's `schedule(0)` (timer, yield) takes no `rq_lock` |

### Wait queues and sleeping locks
| call | contract |
|---|---|
| `wq_wait(q)` / `wq_block_l(q)` | park the caller on q; `_l` returns with `rq_lock` re-held |
| `wq_wake_one_l(q) -> 0/1`, `wq_wake_all[_l](q) -> n` | FIFO wake; woken threads become READY |
| `mutex_lock` / `mutex_unlock` | sleeping, non-recursive (recursive lock panics), owner-checked unlock (panics otherwise) |
| `cond_wait(c, m)` / `cond_signal` / `cond_broadcast` | release m and park atomically; m re-held on return; callers re-check their condition (wake-ups may be spurious) |

There is no priority and no fairness guarantee beyond FIFO wait queues and round-robin run queues.

### Benchmark
`incudela.schedbench` on the boot command line runs `sched_bench` (kernel.cud) right after the scheduler
self-test: for 200 LAPIC ticks (2 s) 2 yielding threads and one mutex/condvar ping-pong pair per CPU, all
unpinned, then one line `schedbench: N cpus, 2000 ms: yields Y (Y/s), ping-pongs P (P/s), switches S,
steals K`. `tests/os/schedbench.sh [CPUS...]` boots it in QEMU with `-smp 1`, `2` and `4` (multi-threaded
TCG, KVM when usable) and prints one `BENCH` line per run. It is a measurement, not a test: tests/os/run.sh
does not call it and its numbers never gate.

## 2. Capabilities
Two independent layers; a call must pass both.

### 2a. Process capabilities (syscall classes, `seal.cudi`)
- Bits: `fs` 1, `spawn` 2, `ipc` 4, `drv` 8, `kexec` 16, `probe` 32, `ktest` 64, `grant` 128.
- Source: the sealed manifest of the executable (`# cuditor: caps(...)`). exec sets
  `caps = held & declared` (never more than the parent); fork copies; kexec hands them over in the
  process-state record (flags word).
- Check: `sys_need(nr)` at the top of `syscall_dispatch`, before anything else the syscall does.
  Missing bit -> `EPERM` and a `cap:` log line. Classes: fs = open, stat, getdents, openat;
  spawn = fork, exec, wait, exec_sandboxed; ipc = chan, send, recv; drv = 400-407 (402 dma_alloc(npages, asid): address-space ID, only 0 exists, others EINVAL; 407 a=6 reports the count), 411-418;
  ktest = 408; kexec = 409; probe = 200; grant = 428-430. All other native syscalls need none.
- Linux-personality processes never reach this table (they see only the Linux syscall table).

### 2b. Handle rights (per fd, `proc.cudi`)
- An fd is a handle: `Proc.fds[i]` (a `File`, refcounted) plus `Proc.fdr[i]` rights:
  `READ` 1, `WRITE` 2, `LOOKUP` 4, `DUP` 8, `XFER` 16 (`CAP_ALL` 31). 16 fds per process.
- **Rights only shrink.** `dup(fd, r)` needs DUP and `r ⊆ rights(fd)`; `restrict(fd, r)` narrows in
  place; `openat` gives the directory's rights minus WRITE; a handle received over a channel keeps the
  rights it was sent with. No call widens a right.
- Ambient authority is fd 3 only (the root directory with LOOKUP, `CAP_ROOT_FD`); a sandboxed
  process loses it at exec, a driver process never gets it.
- Grants (Phase 10.2): a handle installed by a manifest launch carries a grant id, inherited by every
  handle derived from it; once revoked every use returns `EACCES` at the next syscall.

## 3. IPC channels (`chan.cudi`)
- A channel is two endpoint handles (File type `F_CHAN`), created together with READ|WRITE|DUP|XFER.
  At most 16 channels exist at once.
- Message: 1..64 bytes plus at most one handle. Each direction is a 16-slot FIFO ring; order is
  preserved per direction, nothing is reordered or merged.
- Syscalls (class `ipc`):
  - 423 `chan(u64[2]* fds) -> 0`: `EFAULT`, `EMFILE` (needs two free fds).
  - 424 `send(fd, buf, n, h) -> 0`: needs WRITE on fd; n in 1..64 else `EINVAL`; h is `NO_HANDLE`
    (~0) or an fd with XFER that is not fd itself; the handle is **moved** (gone from the sender
    when send succeeds); blocks while the ring is full; `EPIPE` if the peer is closed.
  - 425 `recv(fd, buf, n, &h) -> length`: needs READ; blocks while empty; returns 0 once the peer is
    closed and the ring is drained; `h` gets the received fd or `NO_HANDLE`. A free fd is reserved
    and both destinations are written once **before** dequeueing, so `EMFILE` (no free fd) and
    `EFAULT` (bad buffer) leave the message queued. Bytes beyond n are discarded (no partial reads).
- Close: when an endpoint's last reference goes, the peer's blocked senders/receivers wake; when
  both ends are gone, queued handles are released and the slot freed.
- kexec is refused while any channel is open (`chan_live != 0`); channels are not part of
  process-state v1.

## 4. Guarantees the rest of the system may rely on
1. No syscall widens a handle right or a process capability.
2. Capability checks happen before any side effect of a syscall.
3. A blocked thread is on exactly one wait queue; a READY thread on exactly one run queue (the queue
   owns it, so pushing a thread that already has an owner panics in `thread_adopt`).
4. Moved handles exist in exactly one place (sender table, channel slot, or receiver table).
5. Scheduler choices, timer ticks, syscall results and random values all pass `nd_hook`.

## 5. Not yet specified (future items)
Priorities / real-time scheduling, channel select/poll across endpoints, capability-typed effects
(`uses` clauses, reserved: GRAMMAR v1.2 / E0106), and channels in the kexec handoff.

Tests that pin this contract: `examples/user/captest.cud`, `chantest.cud`, the kernel sync /
sched / TLB self-tests and the grant and sandbox checks in `tests/os/run.sh`.

## Appendix A. Verification scope

This appendix is a statement of what the executable tests actually check, what they do not, and
under which assumptions. "Verified" here means a named test in `run_tests.sh` (including
`tests/os/run.sh`) has passed on the CI configuration, at both -O2 and -O0 unless a note says
otherwise. It is not a machine-checked proof, and it is not a claim about hardware or firmware
outside that configuration. The interface in §§0–5 is unchanged.

### A.1 What is verified, and by which tests

Markers in this section are exact serial (or framebuffer) substrings required by `tests/os/run.sh`
or a kernel self-test. A result name is one of the 69 entries in `tests/os/expected-results.txt`
(`os/result-count` fails if any is missing). The framebuffer check on the BIOS, UEFI, EFI-loader
and IOMMU boots requires `back == front` and a row that decodes as `KERNEL OK`.

**Boot and memory.** `os/kernel-bios`, `os/kernel-bios-smp1`, `os/kernel-uefi` and
`os/efi-loader-gpt` each reach `KERNEL OK` through GRUB BIOS, GRUB UEFI, or the Incudela UEFI loader.
After `KERNEL OK` the kernel prints `debug-exit N ms after KERNEL OK` (TSC-bounded 5 s wait for the
harness screenshot); `os/efi-loader-gpt-post-ok` requires N < 8000, so a 60 s stall after `KERNEL OK`
fails the suite.
`os/kernel-wx` requires that `kernel.elf` has no RWX `PT_LOAD`. Identity mapping of low RAM is
dropped (`identity 0x0000000000100000 -> unmapped`). Image and heap/stack KASLR are pinned by
`os/kaslr` (`KASLR: big heap at`, `KASLR: kernel image at`, `link-address alias unmapped`,
`unslid .text` unmapped, loader and kexec relocatable counts). The buddy allocator, vmalloc reuse
and demand paging print `buddy allocator OK`, `vmalloc VA reuse OK` and `demand paging: 3 faults`.
SMEP/SMAP and `copy_user` are checked by the uaccess self-test (`SMAP blocks kernel read`,
`SMEP blocks kernel exec`, `uaccess:`) and by `examples/user/badptr.cud` (every pointer-taking
syscall, four bad addresses, all `EFAULT`).
`examples/user/sysfuzz.cud` (the plan's item 7) is a seeded syscall and capability fuzzer run as
`sysfuzz 7 3000` on every boot path: each syscall gated by a capability it does not declare must return
`EACCES`, numbers outside the native table (including the Linux-only 15, 56, 158 and 322) `ENOSYS`, and then
3000 calls with random arguments (huge lengths, kernel, non-canonical and straddling pointers, random path
bytes) must leave its canary, pid and console intact (`sysfuzz: PASS`).
`tests/sysfuzz-gates/run.sh` (wired as item 69, lane X; no QEMU) parses `sys_need` in `seal.cudi` and the
`gated` list in `sysfuzz.cud` and requires they match for every capability the fuzzer does not declare
(today: spawn, drv, ktest, kexec, probe, grant, gfx; it holds `fs` and `ipc`). Syscalls 408/409 stay
`ktest_hooks` gated. The kernel unsafe cap is unchanged (709).
The item 7 batch 2 soak harness (`examples/user/syssoak.cud`, `tools/syssoak.cud`) runs that fuzzer
across many seeds and records the results (`syssoak-results v1`). `os/syssoak` boots once with
`incudela.syssoak` (16 seeds x 100 calls, results in `build/os/syssoak-results.txt`) and fails on
the tree before the harness; it skips the long shell and kexec sessions so the gated test stays
short. The item 7 batch 3 fault injector extends ktest-gated syscall 408 (`b=2/3/4`) so
`kmalloc()` can be forced to return 0; `os/sysfault` boots once with `incudela.sysfault`,
probes 1+3 failed allocations then a live one, records EMFILE and a denied huge mmap, and
runs `sysfuzz 1 50`. 408/409 stay `ktest_hooks` gated. The kernel unsafe cap is unchanged
(709). Item 7 batch 4 adds an optional tick budget to `syssoak` (100 Hz LAPIC ticks;
0 means no limit; 360000 ticks is one hour). When the budget expires after a completed
seed, the program prints a checkpoint and exits 0 so a later session can resume.
`os/syssoak-long` boots once with `incudela.syssoaklong` and `syssoak 1 16 100 1`, which
must checkpoint after the first seed; `tools/syssoak.cud` has `--check-checkpoint` and
`--resume`. The existing `os/syssoak` path is unchanged. A live multi-hour run is
started from the shell and is not part of the gate.

**Scheduler, IPC and capabilities (§§1–4).** The legal thread states, wait queues, mutexes and
condvars are exercised by the kernel sync self-test (`wait queues + sleeping mutexes + condvars OK`,
`6 threads x 2000 increments = 12000`). Preemption and stealing: `preemptive SMP scheduler OK`,
`per-CPU run queues:`, `SMP: 4 cpus online` (and `SMP: 1 cpus online` with zero IPIs on
`os/kernel-bios-smp1`). Overflow into a kernel stack guard and a smashed canary kill the thread,
not the kernel (`kernel stack guard pages:`, `stack canaries:`). A thread that has reported back is not yet
dead: `thread reap: 4 workers reported done while 4 still ran; all reaped after T_DEAD` checks that the
parent reaps (waits for `T_DEAD`) instead of freeing. Stop-machine rendezvous:
`stop_machine stress OK: 3000 rounds`, and inside every round the three lock hammers on the other CPUs must
not advance (`no CPU ran while parked`; a parked CPU that answered the next round from its park loop used to
run again, kbs-s1 boot 30). Handle rights that only shrink, and the syscall-class
gate, are pinned by `examples/user/captest.cud` (`captest: PASS`) and `capdeny` (`capability
gate: undeclared spawn and probe denied at the syscall boundary`). Channel move, XFER, EOF on
peer close, and `EFAULT` leaving a message queued are pinned by `chantest.cud` (`chantest: PASS`)
and `badptr`. Grants and revocation: `sbtest: PASS`, `grtest:` mid-read cut-off, `audit: ledger
check`. W^X in user space: `wxtest: PASS`. Sealed images: boot lines `verify: /efi/incudela/bin/unsealed
refused: no proof manifest`, `tampered` / `forged` / `linuxabi` refusals, and `osabi0` when that image is on the ESP; `os/seal-private-key-not-shipped`;
`tests/ed25519/run.sh` and `tests/cudseal/run.sh`.

**Drivers, isolation and VT-d.** `PCI + virtio-blk + FAT32 (read-only) OK` and a byte-identical
`init.elf` read through `blkd` (`blkd: read`, `through the user-mode driver, identical`) plus
`isolated driver service OK` and `supervised driver restart OK` pin the Phase 2.2 virtio-blk
service. `os/kernel-iommu` boots q35 with `-device intel-iommu,intremap=on` and a modern
virtio-blk (`disable-legacy=on,iommu_platform=on`) and requires `VT-d: 1 remapping unit`,
`haw `, `bits, flags 0x`, `base 0x`, `translation on`, `drv 403 returns IOVA`,
`slpt maps only the grant`, and `KERNEL OK`. Default deny and table coverage (A.2 gaps 1, 3, 6, closed): `translation on, 1 of 1 remapping unit programmed (default deny`, `VT-d: default deny: `, `scanned device(s) and every unscanned requester ID blocked`, `context audit: 65536 requester IDs, `, `0 stray, 0 missing`, and the negative case `context audit catches a stray pass-through entry`. Observed faults and aliasing (A.2 gaps 4, 5, closed): the same boot adds QEMU's `edu` device behind a root port and a PCIe-to-PCI bridge; `(alias via PCIe-to-PCI bridge `, `denied edu DMA faulted: source ` (an unclaimed device's DMA is recorded by the hardware model with the alias as source), `requester-ID context(s): 64 bytes into edu and back`, `identical, 0 faults` (DMA through the alias context arrives intact), and `out-of-grant edu DMA faulted at IOVA 0x0000000000810000: source ` (DMA outside the mapping faults at that address). DMA policy (A.2 gap 7, closed): `VT-d policy: remapping active (deny by default, grants confined)` on `os/kernel-iommu`; `VT-d policy: no remapping unit, DMA unconfined (permissive default` and the negative case `strict mode refuses drv 402 without a remapping unit: EPERM` on `os/kernel-bios`, `os/kernel-uefi` and `os/efi-loader-gpt`. Interrupt remapping (A.2 gap 2, closed): `VT-d: interrupt remapping on (256-entry table`, `vector 0x50 -> IRTE 0 (source ` (virtio-blk MSI-X through a source-validated IRTE; blkd keeps serving the disk), `VT-d IR: edu MSI via IRTE 1 (source `, `delivered 1; via an IRTE validated for `, and `blocked; via a not-present IRTE blocked`. The IOVA in that report is not the host PA
(`iommu_grant_ok` refuses an identity grant). Without a remapping unit the existing BIOS/UEFI
boots still reach `KERNEL OK` and 403 still returns a host PA. Input and NVMe services,
Incudela FS and the object store have their own result names (`os/drivers`, `os/forgefs-*`,
`os/objstore-*`, `os/objfs-*`, `os/nvme-service-swap-restart-boot1` / `boot2`).

**Other result names (count corrected 2026-11-15).** The list grew from 35 to 39 without this appendix
following. Also required: `os/boot-harness-self-test` (the harness's own stall and drain checks, no QEMU),
`os/drivers-no-disk-write` (the driver boot leaves its disk image byte-identical), the boot-policy boots
`os/bootpol-cmdline-strict`, `os/bootpol-config-strict` and `os/bootpol-iommu-kexec` (tests/os/bootpol.sh: the
sealed `\EFI\Incudela\boot.cfg` and `incudela.iommu=strict` only tighten the DMA policy, also across kexec),
`dwarf/image-unchanged-by-g`, `dwarf/line-table` and `dwarf/gdb-schedule` (`-g` debug info leaves the loaded
image unchanged, memimg must print `SAME`, and gdb resolves kernel lines), and `os/desktop` (tests/os/desktop.sh: colour bars, window
drag, the app canvas, taskbar and launcher checked from a screendump).

**Kexec and process-state.** `kexec handoff OK`, `kexec: handoff format v5`, `process-state: format
v2 (adopts v1..v2), header and checksum checks OK (64 of 64 flipped bits caught)`, `TLB IPI: 1 stale shootdown IPI(s) from the previous kernel
handled before SMP`, and `driver state carried across kexec OK`. `os/kexec-no-disk-write` requires
the GPT image to be byte-identical after the loader boot. The bios suite repeats the handoff
(`kexec: generation 3 kernel adopted`). Those handoffs are between kernels built from the same tree,
so a record layout change on both sides would still agree with itself; tests/os/kexec-compat.sh closes that
gap. `os/kexec-compat-build` builds an older commit (`KXC_OLD`, default 61b3e85, the last one before the
Stage 3e/3f conversions) from `git archive` with this tree's seal key and requires its `kernel.elf` to differ
(old build plus the 411b601 self-test teardown fix; the handoff format is untouched: its tlb_test reaps its
workers instead of freeing them while they may still run, which panicked under host load);
`os/kexec-old-to-new` boots that old ISO and `kexec next`s into this tree's `kernel-next.elf` and then once more
into itself (`kexec: generation 1 kernel adopted`, `kexec: generation 2 kernel adopted`), with the shell, its fd
and the input service state carried across. The old ISO's disk still has the pre-rename `\EFI\Forge\` layout,
so the new kernel reads it through the alias and its init.elf identity check accepts the old build's init.elf
(`from the build that wrote the old \EFI\Forge\ (not migrated yet), not this build`); on a disk with
`\EFI\Incudela\` a differing init.elf still panics (`init.elf contents differ`). The user-mode block driver's read of init.elf is then compared with the in-kernel driver's read instead of
the build output.

**Linux personality, modules, live patch, nondeterminism.** `lxtest: PASS`, `lxthreads: PASS`,
`lxfs: PASS`, `lxexec: PASS`, `lxipc: PASS`, `lxsig: PASS`, and BusyBox ash (`hello from ash, forge`,
`script done: ok`) run only in the compat sandbox; a plain exec of a Linux image is refused.
The Linux personality has 48 syscalls after item 9 batch 4 (pipe, fork/wait4, vfork as an eager-copy fork, file-backed mmap, an ash pipeline in the gate, writable files on `/data` with unlink, newfstatat, readlink, and a read-only `/proc`).
Modules: `module ABI OK: 1002 loads, 1002 unloads, 7 rejected`. Live patch:
`live patching OK`. The nondeterminism hook: `nondet: recording off by default`, `nondet hook OK`.

**Unsafe surface.** `tests/unsafe/run.sh` (in `run_tests.sh`) compiles the allow/deny cases,
checks `cudc --provenance-lint`, and fails if any program's function/block/op/asm count in
`tests/unsafe/baseline.txt` grows. `cudc --unsafe-report` on `examples/kernel/kernel.cud`
is part of that baseline. Counts may shrink; they must not rise.

### A.2 What is not verified

The tests do not prove the kernel correct on every machine, under every interleaving, or against
a formal model of x86, ACPI, PCI or VT-d. In particular they do not cover: timing or
cache/side-channel behaviour (IBPB, VERW and retpoline are not implemented; see
[spec-exec.md](spec-exec.md)); AArch64 or physical hardware; Secure Boot; multiple outstanding
virtio requests; packed virtqueues; IOAPIC interrupt remapping; DMA under translation from devices other
than the granted virtio-blk and the edu test device; or more than one remapping unit.
Commentary in SYSTEMS.md or BUILD_PLAN.md that is not pinned by a
named test or marker in A.1 is not a verification claim.

**Known DMA/IOMMU gaps** (these are deliberate current limits, not omitted test bugs):

1. **Closed: deny is the default.** The root table starts empty. Only a device the kernel drives
   itself (claimed through `pci_busmaster`, pass-through, domain 1) or a device with a DMA grant
   (translate-and-confine, domain 2) has a context entry; every other requester ID is blocked.
   Remaining limit: a kernel-driven device is trusted with host physical addresses (no per-device
   kernel DMA domains). Pinned in A.1.
2. **Closed: interrupt remapping.** With IR and QI on every unit, the kernel enables queued
   invalidation, a 256-entry remapping table, CFI and IRE; virtio-blk's MSI-X is routed through a
   source-validated IRTE, and edu's MSI is delivered only through an IRTE validated for its
   requester ID. Remaining limits: compatibility-format interrupts stay allowed (CFI) because the
   IOAPIC is not remapped, so a device that can rewrite its own MSI address could still send a
   compatibility-format interrupt; x2APIC destinations above 255 (EIME) are not used; interrupt
   remapping faults are printed if recorded but not required.
3. **Closed: every DRHD is programmed.** All units the probe records (up to `IOMMU_MAX` = 4) get the
   shared root table, are invalidated together, and have translation enabled; the second-level
   width is one every unit supports. Remaining limit: the test topology has one unit (QEMU
   presents one), so the multi-unit path is not exercised by a boot, and device-scope entries are
   not parsed (sharing one root table is correct for any scope).
4. **Closed: DMAR faults are read and tested.** `iommu_fault_drain` reads FSTS and every
   fault-recording register, prints each fault (unit, source ID, reason, address) and clears it.
   The edu self-test injects DMA from a denied device and DMA outside a mapping and requires the
   matching fault records. Remaining limit: faults are polled by the self-test, not taken as an
   interrupt, and nothing polls them in normal operation.
5. **Closed: requester-ID aliasing.** `iommu_aliases` follows the bridges above a device (PCIe-to-PCI:
   secondary bus, devfn 0; conventional PCI bridge: the bridge's ID); claims and grants install a
   context entry for every alias. Pinned by the edu device behind a PCIe-to-PCI bridge. Remaining
   limit: quirky devices that use other requester IDs (DMA-alias quirks) are not modelled.
6. **Closed: context-table coverage is checked.** Context tables are allocated per bus on demand
   (up to 8 buses). `iommu_audit` walks all 65536 requester IDs and requires that exactly the
   claimed and granted ones are present, with the right translation type and domain, and that
   nothing else is (unused entries are not present, never pass-through). A planted stray entry
   must be caught. Pinned in A.1.
7. **Closed: written policy for a machine with no remapping unit.** If the DMAR table is missing,
   has no DRHD, or `iommu_enable` fails, translation stays off and the policy is permissive by
   default: drivers keep working with host physical addresses (drv 403 returns the host PA) and
   the boot log states that DMA is unconfined. The strict policy (`iommu_strict`) refuses drv 402
   with `EPERM` in that case. Since 2026-11-12 the policy is chosen at boot (bootpol.cudi): the build
   default (permissive), then a sealed `\EFI\Incudela\boot.cfg` (`cudseal --config`, either way), then
   the command line, which can only tighten (`incudela.iommu=strict`; `incudela.iommu=permissive` is refused).
   The command line lives in `BootInfo.cmdline` and survives kexec. Remaining limit: strict gates
   user-mode driver grants only, not kernel-driven devices.

QEMU's transitional virtio-blk bypasses the IOMMU unless `VIRTIO_F_ACCESS_PLATFORM` is negotiated.
The IOMMU boot therefore uses a modern (non-transitional) device; a pass of `os/kernel-bios` does
not imply that device DMA was translated.

### A.3 Assumptions

- The host is QEMU running the command lines in `tests/os/run.sh` (256 MiB RAM; 4 VCPUs, or 1 on
  `os/kernel-bios-smp1`; SeaBIOS or OVMF; a read-only virtio-blk ESP, plus the extra disks only
  on the driver/Forge-FS/object-store tests).
- For A.1's VT-d claims: `-machine q35 -device intel-iommu,intremap=on` and
  `virtio-blk-pci,disable-legacy=on,iommu_platform=on`, plus `pcie-root-port` -> `pcie-pci-bridge` -> `edu`
  for the fault and aliasing claims. The firmware DMAR describes at least one
  DRHD whose register base the kernel can map, and the granted device is on bus 0 in that unit's
  scope.
- ACPI tables, PCI configuration, and the IOMMU's register interface are those QEMU presents.
  The tests do not attack the firmware or the emulator.
- The kernel under test is the one built by `examples/kernel/build.cud` / `examples/efi/build.cud`
  with the self-hosted compiler (`build/forge-build` / `build.sh` `FIXPOINT OK`, `SEED OK`, `TOOLS OK`, `SEED TOOLS OK`).
- The kernel the tests boot is the test/debug build (`examples/kernel/kdebug.cudi` included): it prints the
  `hang probe:` line the boot harness reads at a HANG and the KASLR layout lines (`KASLR: kernel image at`,
  `KASLR: big heap at`) and checks the unslid `.text` alias is unmapped. `build/kernel-build --release` builds
  the release kernel with `krelease.cudi` instead, whose `kdbg_*` hooks are empty; image and region KASLR
  themselves are identical in both. The release kernel is checked by `tests/kernel-release/run.sh` (no probe or
  layout strings, empty hooks, `kaslr_pick`/`kaslr_unmap` and every `ktest_hooks` reference kept), and since
  0.23.1 it is also booted: `os/kernel-release-bios` boots it from its own GRUB ISO on the BIOS path to
  `KERNEL OK` (through one kexec into the test/debug `kernel-next.elf`), and `os/kernel-release-quiet` checks
  that the release generation's serial output has none of the test/debug lines. Also test/debug only since
  0.23.1: `page tables built: pml4 at` (`kdbg_paging`), `higher half: rip ..., rsp ...` (`kdbg_higher_half`;
  it gives away the image slide) and the CPU 0 interrupts-off watch (`i0_watch` and its per-tick `rdtsc`,
  moved from apic.cudi into kdebug.cudi behind `kdbg_tick0`, `kdbg_watch_reset` and `kdbg_watch_report`).
- `ktest_hooks` (syscalls 408/409) is armed only for the boot self-test session. Recording in the
  nondeterminism hook is off by default.
- Claims are about the functional behaviour those tests observe (including "0 frames leaked" and
  "0 heap leaked" where a marker says so), not about worst-case latency, throughput, or
  resistance to a concurrent attacker with a second DMA-capable device.

### A.4 Verifier-ready conventions

These conventions are how a later verifier, or a human discharging a claim, should read this
spec and the tests. They fit on one page; they are not themselves a proof system.

1. **A claim is a sentence plus a pin.** The pin is a result name (`os/kernel-iommu`), a test
   program (`examples/user/captest.cud`), and/or an exact marker substring. Text without a pin
   is commentary.
2. **Markers are literal.** Matching is substring inclusion of the text in A.1, as
   `tests/os/run.sh` does. Do not normalise whitespace, case or punctuation when discharging a
   marker claim.
3. **Name the configuration** when the claim depends on hardware or QEMU flags (machine type,
   IOMMU, virtio mode, CPU count). A pass on `-machine pc` does not discharge a q35+VT-d claim.
4. **Negative claims need a rejected case.** "Refused", `EPERM`, `EACCES`, `EFAULT`, `EPIPE` and
   seal reason lines are the evidence. The absence of a crash is not evidence that a path is
   forbidden.
5. **Rights and capabilities only shrink**, and **argument/permission errors occur before any
   side effect** (§4). A verifier may treat a counterexample (a widened right, or a mutation
   before `EFAULT`) as a failed claim even if some other test still passes.
6. **Software table walks are not hardware observations.** `slpt maps only the grant` confirms
   the page table the kernel wrote. It does not, by itself, confirm that the IOMMU walked that
   table or that an out-of-grant transaction faulted. The edu fault markers (A.1, A.2.4) are the
   hardware-model observations.
7. **Default behaviour is stated, not inferred.** Under VT-d the default is deny (A.2.1): a
   requester ID with no claim and no grant has no context entry. Kernel-driven devices are
   pass-through, so do not read "DMA is confined" as applying to them; only a granted device is
   confined to its grant.
8. **The unsafe baseline is a budget, not a memory-safety proof.** `tests/unsafe/baseline.txt`
   and `--unsafe-report` bound the counted surface. They do not prove that every `@unsafe`
   function is correct, or that unmarked code is free of other undefined behaviour.
9. **Spec and tests change together.** A change to anything in §§0–5 bumps the spec version and
   updates this file and the pins in the same commit (page 1). A new kernel guarantee is not
   "verified" until it has a pin in A.1. Closing a gap in A.2 is a new pin, not a silent
   deletion of the gap.
10. **Stable identifiers.** Prefer the result name, the source path, and the marker text over
    line numbers or commit hashes. Line numbers move; markers and result names are the
    interface of the test suite.
