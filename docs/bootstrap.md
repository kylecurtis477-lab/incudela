# Bootstrap: seed compiler, assembler and linker

Files: `tools/build.cud` (`build/forge-build`, documented entry point; `build.sh` kept as the reference),
`tools/run_tests.cud` (`build/forge-run-tests`; `run_tests.sh` kept as the reference), `seed/cudc-seed`,
`seed/fas-seed`, `seed/fld-seed`, `seed/seed.sha256`, `tools/reseed.cud` (`tools/reseed.sh` reference),
`tools/fas.cud`, `tools/fld.cud`, `tools/embed.cud`, and `selfhost/cudc.cud`
(the self-hosted compiler, generated from `selfhost/compiler.cud`).

## What it does
The build needs no Rust and no GNU binutils. Three checked-in x86-64 Linux binaries start it:
- `cudc-seed` is a build of the Forge compiler.
- `fas-seed` is Forge's assembler. It reads GNU-as syntax and writes ELF64 relocatable objects.
- `fld-seed` is Forge's static linker.

`seed/seed.sha256` pins all three. `build/forge-build` (and `build.sh`) exit if a hash doesn't match.

## Stages
1. The seed compiles `tools/embed.cud` and `selfhost/cudc.cud` into stage2. The seed fas and fld assemble and link it.
2. stage2 builds `fas` and `fld` from `tools/`.
3. stage2 compiles the compiler into stage3, and stage3 compiles it again into stage4. The new fas and fld assemble and link both.
4. **FIXPOINT OK**: `stage2.s == stage3.s == stage4.s`. stage3 becomes `build/cudc`.
5. **SEED OK**: `build/cudc` and stage2 are byte-identical to `cudc-seed`. If they differ, `build/forge-build`
   prints `SEED NOTE`, which means the compiler source changed since the last reseed.
6. **TOOLS OK**: the self-built fas and fld reproduce stage3's object and binary exactly. **SEED TOOLS OK**: they
   are byte-identical to the seed's fas and fld.

`FORGE_RUST_CHECK=1` also builds the old Rust bootstrap (`src/main.rs`) as an optional cross-check.

## Reseeding
Any commit that changes the compiler, fas or fld has to reseed:
1. Run `build/forge-build` (or `./build.sh`) and check that FIXPOINT is green.
2. Run `./cuditor reseed` (tools/reseed.cud, built to build/reseed). It requires `stage2.s == stage4.s`,
   copies build/cudc, fas and fld into `seed/` (mode 755), and rewrites `seed.sha256` with its own
   SHA-256. `tools/reseed.sh` is kept as the reference; tests/reseed/run.sh checks both give the same
   output, exit code and seed files. Neither works for a prelude change, where stage2 still carries the
   seed's old prelude: then check `stage3.s == stage4.s`, copy the three files and rewrite seed.sha256 by hand.
3. Run `build/forge-build` (or `./build.sh`) again. It must print SEED OK and SEED TOOLS OK.
4. Commit the seed files with the source change.

## Testing
Run the invariant check from a clean copy with `as`, `ld`, `cargo` and `rustc` blocked on PATH by stub scripts.
`build/forge-build` (after compiling `tools/build.cud` from the seed on a clean tree, or `./build.sh`) must print FIXPOINT OK, SEED OK, TOOLS OK and SEED TOOLS OK. `build/forge-run-tests` (`./run_tests.sh` reference) then
runs the full suite at O2, and `CUDC_FLAGS=-O0` runs it again at O0. GNU as and ld appear only as
reference oracles in `tests/fas` and `tests/fld`.

## Known limits
- The seeds are opaque binaries. Trust comes from the pinned hashes plus the fixpoint and the
  optional Rust cross-check (diverse double-compiling), not from source alone.
- The seeds run only on x86-64 Linux hosts.
