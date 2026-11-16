# fsfuzz (tools/fsfuzz.cud)

Differential fuzzer for the freestanding backend's `--fs-opt` pass (Phase 12.1). It is the gate before any further
step 4 work on the register allocator.

    fsfuzz [--seed N] [--n COUNT] [--keep] [--combos]       (defaults: seed 1, 20 programs; 50 with --combos)

## What it checks

It writes COUNT random programs to build/fsfuzz/pK.cud and builds each one ten ways with build/cudc, build/fas
and build/fld:

| config | flags |
|---|---|
| 0 | default (O2) |
| 1 | `-O0` |
| 2 | `--fs-opt` |
| 3 | `-O0 --fs-opt` |
| 4 | `--fs-live` (step 4b, liveness-based register sharing) |
| 5 | `-O0 --fs-live` |
| 6 | `--fs-temps` (step 4c, stack temporaries and call arguments in registers) |
| 7 | `-O0 --fs-temps` |
| 8 | `--fs-ssa` (step 4d, SSA values of the scratch registers: constant, compare and branch folds) |
| 9 | `-O0 --fs-ssa` |

Each binary runs under `/usr/bin/timeout 10`. The result is the exit status plus stdout. All ten must be equal. Any
difference (or a build failure) counts as a diff and prints the ten results, truncated to 300 characters.

It ends with `fsfuzz: seed N, COUNT programs (L lines), 10 builds each (...): A agree, D differ` and exits 1 when D > 0.
Without `--keep` it deletes each program's .s, .o and binaries after the comparison.

## --combos: every optimizer flag combination (build-plan item 3, part b)

With `--combos` each program is built under every combination of the switches that change freestanding code
generation, instead of the ten fixed builds:

- optimizer level, 9 spellings: none, `--fs-opt`, `--fs-live`, `--fs-temps`, `--fs-ssa` (since step 4d), and the
  redundant `--fs-opt --fs-live`, `--fs-live --fs-temps`, `--fs-opt --fs-live --fs-temps`, `--fs-temps --fs-ssa`
  (each flag implies the ones before it, so the redundant spellings must give the same code);
- `-O0` or not;
- `--no-bounds` or not (bounds checks removed, so `fs_bsafe` elision and the check code both change);
- `-g` or not (debug line info; `.loc` lines sit between the instructions the peepholes and the allocator match).

That is 72 flag sets (56 before step 4d). Each program is also built from a second source, the same program with
`# cuditor: stack-protector` plus a `stack_canary` word and a `stack_smashed` handler, so every frame that holds an
array gets a canary store in the prologue and a check before `leave` (code the allocator must work around):
144 builds per program. A build whose assembly is byte-identical to an earlier build of the same source is not
assembled or run again; every distinct assembly is linked, run under `timeout 10`, and must print the same output
and exit code as the plain default build of that source. Any difference, or a build that fails, prints the flag
set and its result and fails the run. The summary is

    fsfuzz --combos: seed S, N programs x 2 sources (plain, stack-protector) x 72 flag sets = B builds, D distinct assemblies run: A agree, F differ

Results on 2026-11-13, 25 programs per seed (2800 builds each): seed 1 ran 744 distinct assemblies, seed 2 760 and
seed 3 748 (about 15 per source); all agreed. At that point `-O0` never produced a distinct
assembly (see docs/tools-optcov.md), and neither did the redundant spellings. Since the -O0 fix (2026-11-13) a
`-O0` build keeps every bounds check, so it is a distinct assembly whenever a program has an elided check. A deliberately broken compiler
(a wrapper that turns the first `imul` into `add` when `--fs-live` and `-g` are both given) is caught on the first
program, with the three affected flag sets listed.

Results on 2026-11-16 with `--fs-ssa` (step 4d), 25 programs per seed (3600 builds each, the step 4d programs of
the new generator): seed 1 ran 1440 distinct assemblies, seed 2 1410 and seed 3 1386 (about 28 per source); all
agreed. The ten-way form, seeds 1-6 x 80 programs (97,267 lines): 0 differ. (One earlier seed 1 run reported a
differ while build/cudc was being rebuilt under it; the rerun on a quiet tree agreed.)

run_tests.sh runs a bounded form, `build/fsfuzz-tool --combos --seed 7 --n 3` (`PASS fs-opt-combos`, 432 builds
and 168 distinct assemblies since step 4d (336 and 126 before it; 84 before the -O0 fix), about 40 s; 2 programs
until build-plan item 3 part d). Together with `optcov --check` it is
the landing gate for optimizer passes (docs/tools-optcov.md, "Landing rule").

## The programs

The generator is an LCG (`seed * 1103515245 + 12345` mod 2^31), so a seed always gives the same programs. Each
program has several functions `fK(p0..pN-1: i64 [, w: i64[4]]) -> i64` and a `main` that calls them and prints the
results. A function can have:

- up to 8 parameters (stack arguments), and more scalar locals than the pass has free registers;
- a `w: i64[4]` array parameter (copied with `rep movsb`), a frame array `t: i64[8]`, and `addr()` of a local (that
  local must stay in memory: step 4a pinning);
- a call to an earlier function, so values live across calls (callee-saved promotion);
- `if`/`else` blocks and nested `while` loops with constant bounds. Loop counters are read-only inside the loop, so
  every program ends.
- wrapping `+ - *`, `& | ^`, shifts by masked counts, unsigned shifts, narrow casts (u8, i8, u16, i32, u32), signed
  and unsigned compares (since 2026-11-16 one condition in eight is negated with `not (...)` and one in eight joins
  two compares with `and`/`or`, so 0/1 comparison values and short-circuit jumps are exercised), division and
  modulo by constants (the magic-number path) and by variables forced positive (`(b & 1023) + 1`), and array
  reads and writes with masked indices.

None of this is undefined: ints wrap, divisors are positive, shift counts and indices are masked. The programs are
safe code, so step 4a's promotion next to frame aggregates applies.

## Tests

run_tests.sh builds the tool and runs `build/fsfuzz-tool --seed 1 --n 20` (`PASS fs-opt-fuzz`) at both O2 and
CUDC_FLAGS=-O0. The tool itself is built with those flags, but every program is always built in all ten configs.
