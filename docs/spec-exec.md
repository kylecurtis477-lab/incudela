# Speculative-execution policy

This is a statement of what the tree does today. It is not a hardware proof, not a claim that
Incudela is safe against Spectre, Meltdown, MDS or related attacks, and not a promise that a
named mitigation will be added later. Appendix A.2 of [kernel-core.md](kernel-core.md) already
says the tests do not cover timing or cache/side-channel behaviour.

## Named mitigations that are not implemented

**IBPB, VERW (MD_CLEAR) and retpoline are not present in this tree.** In particular:

- The kernel never writes `IA32_PRED_CMD` (MSR 0x49), so it never issues IBPB on a context
  switch, a syscall, a kexec, or anywhere else. It also never writes `IA32_SPEC_CTRL`
  (MSR 0x48), so IBRS, STIBP and SSBD are not enabled.
- There is no `verw` (MD_CLEAR) buffer flush, including on a return to user mode.
- The Cuditor freestanding backend does not emit retpoline thunks for indirect calls, indirect
  jumps or returns. The assembler (`tools/fas.cud`) accepts `lfence`, but a search of
  `examples/kernel` finds no `lfence` and no `verw`. `syscall_entry` in `examples/kernel/user.cudi`
  uses `swapgs` with no serialising instruction after it, and returns with `sysretq` or `iretq`.
- There is no kernel-page-table isolation. `as_new` copies every kernel-half PML4 entry from
  `kernel_pml4` into each process table (`user.cudi`), so the higher-half kernel remains mapped
  while user code runs.

A later change that added any of these would be a kernel or compiler change, with its own tests,
not a documentation-only edit.

## Hardening that is implemented

These are already documented and pinned by tests. They are not substitutes for the mitigations
above.

- SMEP and SMAP, with `copy_user` / `copy_str_user` and #PF fixups (uaccess self-test, `badptr`).
- W^X for the kernel image and for user ELF (no RWX `PT_LOAD`; `os/kernel-wx`, `wxtest`).
- Per-thread kernel stack guard pages and stack canaries (`# cuditor: stack-protector` on the
  kernel).
- Image and region KASLR (`os/kaslr`).
- Capability and sandbox checks before syscall side effects (`captest`, `sysfuzz`, grant and
  sandbox boot markers).

DMA policy (Intel VT-d, the permissive default when no remapping unit is present, and
`incudela.iommu=strict`) is a separate matter; it is described in [SYSTEMS.md](SYSTEMS.md) and
[kernel-core.md](kernel-core.md) Appendix A, and this note does not change it.

## Policy

Do not describe IBPB, VERW, retpoline, IBRS, STIBP, SSBD or kernel-page-table isolation as
present, in comments, CHANGELOG entries, or other docs, unless a later commit actually adds
them. This file is the place that records the current stance.
