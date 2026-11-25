#!/bin/sh
# tests/*.cud: stdout must match .expected
# tests/runtime/*.cud: stdout+stderr+exit code must match .expected (line-numbered runtime errors)
# tests/errors/*.cud: compiler must fail with "error: line N: ..."
# tests/os/run.sh: QEMU boot tests (kernel via multiboot2 on BIOS and OVMF, native PE32+ EFI app on a GPT disk)
# tests/fs/*.cud: freestanding (--freestanding / no-runtime pragma) programs linked with plain ld, no runtime
#   (each one again with --fs-opt, which must not change its output)
# tests/ast/*.sh: --emit=ast-json / --emit=pretty round trips (AST equal, pretty fixpoint, same behaviour, self-host)
# tests/grammar/: docs/GRAMMAR.md conformance (valid/ parse, invalid/ rejected) + grammar-based fuzzer
# tests/diag/*.cud: --diagnostics=json output must match the golden .json (one object per error, schema v1)
# tests/typeerrors/*.cud: static type errors; full diagnostic (line, col, source, caret) must match .expected
# tests/bench/: tools/bench.cud regression-check logic on fixed records (bench timing never gates)
# Parallel (default): the blocks below are items; each lane of the table runs as one background job,
#   its items in order, lane S (builds or reads the shared OS artifacts) in the foreground, lane alone
#   (bounds timing) after every lane has finished; each item writes build/par/NN.log, printed in item order,
#   so the output is the serial output. RUN_TESTS_SERIAL=1: every item in order, streaming, nothing in
#   parallel. RUN_TESTS_ONLY (space-separated item names) runs only those
#   items; FORGE_RUN_TESTS_INNER=1 omits t_forge_run_tests. RUN_TESTS_PAR is the per-item log dir (default build/par; a nested run must set it, or INNER defaults to build/par-inner, so the outer logs are not wiped). tests/os (QEMU) always runs after all items, alone (README.md, Tests)
cd "$(dirname "$0")"; fail=0; mkdir -p build
t_cases() {
fail=0
for t in tests/*.cud; do
  case "$t" in tests/mod_*) continue;; esac
  ./cuditor "$t" -o build/t_bin && build/t_bin a b | diff -q - "${t%.cud}.expected" >/dev/null && echo "PASS $t" || { echo "FAIL $t"; fail=1; }
done
return $fail
}
t_runtime() {
fail=0
for t in tests/runtime/*.cud; do
  ./cuditor "$t" -o build/t_bin && (build/t_bin 2>&1; echo "exit $?") | diff -q - "${t%.cud}.expected" >/dev/null && echo "PASS $t" || { echo "FAIL $t"; fail=1; }
done
return $fail
}
t_errors() {
fail=0
for t in tests/errors/*.cud; do
  m=$(timeout 20 build/cudc "$t" build/t_err.s 2>&1) && { echo "FAIL $t (no error)"; fail=1; } || { echo "$m" | grep -q "error: line" && echo "PASS $t: $m" || { echo "FAIL $t"; fail=1; }; }
done
return $fail
}
t_typeerrors() {
fail=0
for t in tests/typeerrors/*.cud; do
  build/cudc "$t" build/t_err.s > build/t_err.txt 2>&1 && { echo "FAIL $t (no error)"; fail=1; } || { diff -q build/t_err.txt "${t%.cud}.expected" >/dev/null && echo "PASS $t: $(head -1 build/t_err.txt)" || { echo "FAIL $t"; fail=1; }; }
done
return $fail
}
t_diag() {
fail=0
for t in tests/diag/*.cud; do
  build/cudc "$t" build/t_err.s --diagnostics=json > build/t_diag.json 2>&1 && { echo "FAIL $t (no error)"; fail=1; } || { diff -q build/t_diag.json "${t%.cud}.json" >/dev/null && echo "PASS $t" || { echo "FAIL $t"; fail=1; }; }
done
return $fail
}
t_diag_schema() {
fail=0
if command -v python3 >/dev/null; then
  python3 -c 'import json,sys,glob
for f in glob.glob("tests/diag/*.json"):
    for l in open(f):
        d=json.loads(l); assert d["version"]==1 and d["code"][0]=="E" and d["line"]>0 and d["col"]>0 and isinstance(d["fixits"],list), f' && echo "PASS diag-json-schema" || { echo "FAIL diag-json-schema"; fail=1; }
fi
return $fail
}
t_diag_input() {
fail=0
build/cudc build/no_such_input.cud build/t_inc.s --diagnostics=json 2>&1 | grep -q '"code":"E0001"' && echo "PASS diag-json-input-missing" || { echo "FAIL diag-json-input-missing"; fail=1; }
return $fail
}
t_ast_roundtrip() {
fail=0
tests/ast/roundtrip.sh selfhost/compiler.cud selfhost/prelude.cud tools/*.cud tests/*.cud tests/runtime/*.cud tests/fs/*.cud tests/unit/*.cud tests/testblocks/*.cud tests/bounds/*.cud tests/nonnull/*.cud tests/unsafe/*.cud tests/own/*.cud tests/defer/*.cud tests/generic/*.cud tests/atomic/*.cud std/*.cudi examples/*/*.cud examples/*/*.cudi || fail=1
return $fail
}
t_ast_semantic() {
fail=0
tests/ast/semantic.sh || fail=1
return $fail
}
t_grammar() {
fail=0
tests/grammar/run.sh || fail=1
return $fail
}
t_fmt() {
fail=0
tests/fmt/run.sh || fail=1
return $fail
}
t_os_artifacts() {
fail=0
# tests/fas and tests/fld check every OS artifact (user programs, modules, EFI loader, kernel); build them
# first so a clean tree (e.g. straight from the seed) runs the same checks instead of skipping them
{ ./cuditor examples/kernel/build.cud -o build/kernel-build && build/kernel-build && ./cuditor examples/efi/build.cud -o build/efi-build && build/efi-build; } >/dev/null 2>&1 || { echo "FAIL os-artifacts-build (fas/fld artifact checks would be skipped)"; fail=1; }
# the boot harness asm is one of the fas artifacts; build it here so every run checks the same file set
# (before, build/os/boot.s existed only after an earlier OS run, so O2 and O0 counted 638 vs 639)
mkdir -p build/os && build/cudc tests/os/boot.cud build/os/boot.s || { echo "FAIL os-boot-harness-asm"; fail=1; }
return $fail
}
t_fas() {
fail=0
tests/fas/run.sh || fail=1
return $fail
}
t_fld() {
fail=0
tests/fld/run.sh || fail=1
return $fail
}
t_krel() {
fail=0
tests/krel/run.sh || fail=1
return $fail
}
t_incudela_part() {
fail=0
tests/incudela-part/run.sh || fail=1
return $fail
}
t_mkgpt() {
fail=0
tests/mkgpt/run.sh || fail=1
return $fail
}
t_espmigrate() {
fail=0
tests/espmigrate/run.sh || fail=1
return $fail
}
t_ed25519_tool() {
fail=0
tests/ed25519-tool/run.sh || fail=1
return $fail
}
t_grammar_fuzz() {
fail=0
tests/grammar-fuzz/run.sh || fail=1
return $fail
}
t_mkfont() {
fail=0
tests/mkfont/run.sh || fail=1
return $fail
}
t_c2cud() {
fail=0
tests/c2cud/run.sh || fail=1
return $fail
}
t_cudseal() {
fail=0
tests/cudseal/run.sh || fail=1
return $fail
}
t_modules_build() {
fail=0
tests/modules-build/run.sh || fail=1
return $fail
}
t_user_build() {
fail=0
tests/user-build/run.sh || fail=1
return $fail
}
t_busybox_build() {
fail=0
tests/busybox-build/run.sh || fail=1
return $fail
}
t_bzip2() {
fail=0
tests/bzip2/run.sh || fail=1
return $fail
}
t_cpython_build() {
fail=0
tests/cpython-build/run.sh || fail=1
return $fail
}
t_cpython_embed() {
fail=0
tests/cpython-embed/run.sh || fail=1
return $fail
}
t_efi_build() {
fail=0
tests/efi-build/run.sh || fail=1
return $fail
}
t_kernel_build() {
fail=0
tests/kernel-build/run.sh || fail=1
return $fail
}
t_kernel_release() {
fail=0
tests/kernel-release/run.sh || fail=1
return $fail
}
t_rtport() {
fail=0
tests/rtport/run.sh || fail=1
return $fail
}
t_forge_build() {
fail=0
tests/forge-build/run.sh || fail=1
return $fail
}
t_forge_run_tests() {
fail=0
tests/forge-run-tests/run.sh || fail=1
return $fail
}
t_pecheck() {
fail=0
tests/pecheck/run.sh || fail=1
return $fail
}
t_memimg() {
fail=0
tests/memimg/run.sh || fail=1
return $fail
}
t_count_store_reload() {
fail=0
tests/count-store-reload/run.sh || fail=1
return $fail
}
t_oslib() {
fail=0
tests/oslib/run.sh || fail=1
return $fail
}
t_reseed() {
fail=0
tests/reseed/run.sh || fail=1
return $fail
}
t_pkg() {
fail=0
tests/pkg/run.sh || fail=1
return $fail
}
t_oldnames() {
fail=0
# tests/oldnames: the pre-rename spellings removed in 0.22.0 have no effect any more
tests/oldnames/run.sh || fail=1
return $fail
}
t_lsp() {
fail=0
tests/lsp/run.sh || fail=1
return $fail
}
t_provenance() {
fail=0
# tests/provenance: AI-provenance commit trailers (tools/provenance.cud, docs/PROVENANCE.md)
tests/provenance/run.sh || fail=1
return $fail
}
t_testblocks() {
fail=0
tests/testblocks/run.sh || fail=1
return $fail
}
t_bounds() {
fail=0
tests/bounds/run.sh || fail=1
return $fail
}
t_nonnull() {
fail=0
tests/nonnull/run.sh || fail=1
return $fail
}
t_unsafe() {
fail=0
tests/unsafe/run.sh || fail=1
return $fail
}
t_own() {
fail=0
tests/own/run.sh || fail=1
return $fail
}
t_limits() {
fail=0
# tests/limits: compiler table limits end in a diagnostic (4096 locals per fs function)
tests/limits/run.sh || fail=1
return $fail
}
t_defer() {
fail=0
tests/defer/run.sh || fail=1
return $fail
}
t_generic() {
fail=0
tests/generic/run.sh || fail=1
return $fail
}
t_ed25519() {
fail=0
tests/ed25519/run.sh || fail=1
return $fail
}
t_atomic() {
fail=0
tests/atomic/run.sh || fail=1
return $fail
}
t_ast_selfpp() {
fail=0
tests/ast/selfpp.sh || fail=1
return $fail
}
t_bench() {
fail=0
# tests/bench: tools/bench.cud record parser and regression logic on fixed records (timing itself never gates)
./cuditor tools/bench.cud -o build/bench >/dev/null 2>&1 || { echo "FAIL bench-build"; fail=1; }
for c in ok slow ratio window; do
  (build/bench check --history tests/bench/$c.tsv --baseline tests/bench/base.tsv; echo "exit $?") | diff -q - tests/bench/$c.expected >/dev/null && echo "PASS bench-check-$c" || { echo "FAIL bench-check-$c"; fail=1; }
done
(build/bench check --history tests/bench/window.tsv --baseline tests/bench/base.tsv --window 1; echo "exit $?") | diff -q - tests/bench/window1.expected >/dev/null && echo "PASS bench-check-window1" || { echo "FAIL bench-check-window1"; fail=1; }
# record integrity: full sha, dirty-tree refusal (scratch git repo, no timing)
tests/bench/tree.sh build/bench || fail=1
return $fail
}
t_asm_audit() {
fail=0
# --fs-opt asm discipline: every asm routine in examples/ must be checked off in docs/SYSTEMS.md (no build, no QEMU)
tests/asm-audit/run.sh || fail=1
return $fail
}
t_ci() {
fail=0
# tests/ci: the public CI workflow keeps its rules (pinned actions, read-only token, no secrets, timeouts; docs/ci.md)
tests/ci/run.sh || fail=1
return $fail
}
t_ast_json() {
fail=0
build/cudc tests/tuples.cud build/t_ast.json --emit=ast-json && python3 -c 'import json;d=json.load(open("build/t_ast.json"));assert d["forge_ast"]==1 and d["root"]["k"]=="Module"' && echo "PASS ast-json-schema" || { echo "FAIL ast-json-schema"; fail=1; }
return $fail
}
t_fs_shapes() {
fail=0
for t in tests/fs/*.cud; do
  c=""; [ -f "${t%.cud}.c" ] && gcc -O1 -ffreestanding -fno-pic -fno-stack-protector -c -o build/t_fsc.o "${t%.cud}.c" && c=build/t_fsc.o
  build/cudc "$t" build/t_fs.s $CUDC_FLAGS && build/fas -o build/t_fs.o build/t_fs.s && build/fld -o build/t_fs build/t_fs.o $c && build/t_fs | diff -q - "${t%.cud}.expected" >/dev/null && echo "PASS $t" || { echo "FAIL $t"; fail=1; }
done
# --fs-opt (Phase 12.1 step 1, opt-in): every freestanding program must print the same with the flag, and
# tests/fs/regalloc.cud must come out with ra_leaf fully in registers, ra_calls using a callee-saved register
# and ra_addr (address taken) untouched; step 4a: ra_arr (frame array), ra_cpy (rep movsb) and ra_mix (addr() of
# one local) still promote their other scalars
for t in tests/fs/*.cud; do
  c=""; [ -f "${t%.cud}.c" ] && gcc -O1 -ffreestanding -fno-pic -fno-stack-protector -c -o build/t_fsc.o "${t%.cud}.c" && c=build/t_fsc.o
  build/cudc "$t" build/t_fs.s $CUDC_FLAGS --fs-opt && build/fas -o build/t_fs.o build/t_fs.s && build/fld -o build/t_fs build/t_fs.o $c && build/t_fs | diff -q - "${t%.cud}.expected" >/dev/null && echo "PASS fs-opt $t" || { echo "FAIL fs-opt $t"; fail=1; }
done
build/cudc tests/fs/regalloc.cud build/t_ra.s $CUDC_FLAGS --fs-opt && [ "$(awk '/^ra_leaf:/,/ret$/' build/t_ra.s | grep -c '(%rbp)')" = 0 ] && [ "$(awk '/^ra_addr:/,/ret$/' build/t_ra.s | grep -c '(%rbp)')" -gt 0 ] && awk '/^ra_calls:/,/ret$/' build/t_ra.s | grep -q 'mov %rax,%rbx' && awk '/^ra_arr:/,/ret$/' build/t_ra.s | grep -q '%rbx' && awk '/^ra_cpy:/,/ret$/' build/t_ra.s | grep -q 'rep movsb' && awk '/^ra_cpy:/,/ret$/' build/t_ra.s | grep -q '%rbx' && awk '/^ra_mix:/,/ret$/' build/t_ra.s | grep -q 'lea -[0-9]*(%rbp)' && awk '/^ra_mix:/,/ret$/' build/t_ra.s | grep -q '%r8' && echo "PASS fs-opt-shape" || { echo "FAIL fs-opt-shape"; fail=1; }
# --fs-live (Phase 12.1 step 4b, opt-in): every freestanding program must print the same with it, and
# tests/fs/regalloc.cud's ra_seq (14 phase-local scalars plus 2 long-lived ones, 16 slots for 11 registers) keeps
# frame slots under --fs-opt and none under --fs-live
for t in tests/fs/*.cud; do
  c=""; [ -f "${t%.cud}.c" ] && gcc -O1 -ffreestanding -fno-pic -fno-stack-protector -c -o build/t_fsc.o "${t%.cud}.c" && c=build/t_fsc.o
  build/cudc "$t" build/t_fs.s $CUDC_FLAGS --fs-live && build/fas -o build/t_fs.o build/t_fs.s && build/fld -o build/t_fs build/t_fs.o $c && build/t_fs | diff -q - "${t%.cud}.expected" >/dev/null && echo "PASS fs-live $t" || { echo "FAIL fs-live $t"; fail=1; }
done
build/cudc tests/fs/regalloc.cud build/t_ra.s $CUDC_FLAGS --fs-opt && [ "$(awk '/^ra_seq:/,/ret$/' build/t_ra.s | grep -c '(%rbp)')" -gt 0 ] && build/cudc tests/fs/regalloc.cud build/t_ra.s $CUDC_FLAGS --fs-live && [ "$(awk '/^ra_seq:/,/ret$/' build/t_ra.s | grep -c '(%rbp)')" = 0 ] && echo "PASS fs-live-shape" || { echo "FAIL fs-live-shape"; fail=1; }
# --fs-temps (Phase 12.1 step 4c, opt-in, implies --fs-live): call arguments go straight to their registers and
# constant loads skip the stack; every freestanding program must print the same, and ra_rec keeps (%rsp)
# operands under --fs-live and none under --fs-temps
for t in tests/fs/*.cud; do
  c=""; [ -f "${t%.cud}.c" ] && gcc -O1 -ffreestanding -fno-pic -fno-stack-protector -c -o build/t_fsc.o "${t%.cud}.c" && c=build/t_fsc.o
  build/cudc "$t" build/t_fs.s $CUDC_FLAGS --fs-temps && build/fas -o build/t_fs.o build/t_fs.s && build/fld -o build/t_fs build/t_fs.o $c && build/t_fs | diff -q - "${t%.cud}.expected" >/dev/null && echo "PASS fs-temps $t" || { echo "FAIL fs-temps $t"; fail=1; }
done
build/cudc tests/fs/regalloc.cud build/t_ra.s $CUDC_FLAGS --fs-live && [ "$(awk '/^ra_rec:/,/ret$/' build/t_ra.s | grep -c '(%rsp)')" -gt 0 ] && build/cudc tests/fs/regalloc.cud build/t_ra.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ra_rec:/,/ret$/' build/t_ra.s | grep -c '(%rsp)')" = 0 ] && echo "PASS fs-temps-shape" || { echo "FAIL fs-temps-shape"; fail=1; }
# --fs-ssa (Phase 12.1 step 4d, opt-in, implies --fs-temps): SSA values for the scratch registers fold a constant
# into its one use and a 0/1 test into its branch; every freestanding program must print the same, and
# tests/fs/ssa.cud's ssa_cmp keeps its setcc/movzbl/test chains under --fs-temps and has none under --fs-ssa
for t in tests/fs/*.cud; do
  c=""; [ -f "${t%.cud}.c" ] && gcc -O1 -ffreestanding -fno-pic -fno-stack-protector -c -o build/t_fsc.o "${t%.cud}.c" && c=build/t_fsc.o
  build/cudc "$t" build/t_fs.s $CUDC_FLAGS --fs-ssa && build/fas -o build/t_fs.o build/t_fs.s && build/fld -o build/t_fs build/t_fs.o $c && build/t_fs | diff -q - "${t%.cud}.expected" >/dev/null && echo "PASS fs-ssa $t" || { echo "FAIL fs-ssa $t"; fail=1; }
done
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_cmp:/,/ret$/' build/t_ssa.s | grep -c 'movzbl %al,%eax')" -gt 0 ] && [ "$(awk '/^ssa_cmp:/,/ret$/' build/t_ssa.s | grep -c 'mov \$[0-9-]*,%rcx')" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_cmp:/,/ret$/' build/t_ssa.s | grep -c 'movzbl %al,%eax')" = 0 ] && [ "$(awk '/^ssa_cmp:/,/ret$/' build/t_ssa.s | grep -c 'mov \$[0-9-]*,%rcx')" = 0 ] && echo "PASS fs-ssa-shape" || { echo "FAIL fs-ssa-shape"; fail=1; }
# step 4e: ssa_drop's dropped call result (xor %eax,%eax) is overwritten by the implicit return before any read:
# two xor lines under --fs-temps, one under --fs-ssa
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_drop:/,/ret$/' build/t_ssa.s | grep -c 'xor %eax,%eax')" = 2 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_drop:/,/ret$/' build/t_ssa.s | grep -c 'xor %eax,%eax')" = 1 ] && echo "PASS fs-ssa-dead-shape" || { echo "FAIL fs-ssa-dead-shape"; fail=1; }
# step 4f: ssa_copy keeps its parameters in %r8-%r10 copies under --fs-temps; copy propagation reads %rdi/%rsi/%rdx
# directly and the copies die, so no %r8/%r9/%r10 is left under --fs-ssa
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_copy:/,/ret$/' build/t_ssa.s | grep -c '%r8\|%r9\|%r10')" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_copy:/,/ret$/' build/t_ssa.s | grep -c '%r8\|%r9\|%r10')" = 0 ] && echo "PASS fs-ssa-copy-shape" || { echo "FAIL fs-ssa-copy-shape"; fail=1; }
# step 4h: ssa_keep holds x, y and z in %r12/%r13/%rbx across its calls; --fs-temps copies them into %rcx for the
# adds, and with the callee-saved registers tracked (a call leaves them alone) --fs-ssa reads them directly
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_keep:/,/ret$/' build/t_ssa.s | grep -c 'mov %\(rbx\|r12\|r13\),%rcx')" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_keep:/,/ret$/' build/t_ssa.s | grep -c 'mov %\(rbx\|r12\|r13\),%rcx')" = 0 ] && echo "PASS fs-ssa-callee-shape" || { echo "FAIL fs-ssa-callee-shape"; fail=1; }
# step 4i: in ssa_move, a move into %rax directly followed by `mov %rax,%rN` (its only reader) under --fs-temps;
# under --fs-ssa the move writes %rN itself, so no such pair is left
mvpair='/^ssa_move:/ {f=1} f && prev ~ /^    (mov|movq|movl|lea|movzbl) [^,]*,%[re]ax$/ && $0 ~ /^    mov %rax,%r/ {c++} f {prev=$0} f && /ret$/ {f=0} END {print c+0}'
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk "$mvpair" build/t_ssa.s)" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk "$mvpair" build/t_ssa.s)" = 0 ] && echo "PASS fs-ssa-retarget-shape" || { echo "FAIL fs-ssa-retarget-shape"; fail=1; }
# step 4j: ssa_range's loop counter lives in %rbx; --fs-temps increments it through %rax and copies it back, under
# --fs-ssa it stays in %rbx: one increment written straight into %rbx (`add $1,%rbx`, or `lea 1(%rbx),%rbx` since
# step 4p) and no copy through %rax in either direction
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_range:/,/ret$/' build/t_ssa.s | grep -c 'mov %rax,%rbx$')" -gt 0 ] && [ "$(awk '/^ssa_range:/,/ret$/' build/t_ssa.s | grep -c 'add \$1,%rbx$')" = 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_range:/,/ret$/' build/t_ssa.s | grep -c '^    \(add \$1,%rbx\|lea 1(%rbx),%rbx\)$')" = 1 ] && [ "$(awk '/^ssa_range:/,/ret$/' build/t_ssa.s | grep -c 'mov %rax,%rbx$\|mov %rbx,%rax$')" = 0 ] && echo "PASS fs-ssa-range-shape" || { echo "FAIL fs-ssa-range-shape"; fail=1; }
# step 4k: ssa_range zeroes s and i; under --fs-temps through `xor %eax,%eax` and a copy, under --fs-ssa in the
# copies' registers (`xor %ebx,%ebx`), so no zero-then-copy pair is left
zpair='/^ssa_range:/ {f=1} f && prev == "    xor %eax,%eax" && $0 ~ /^    mov %rax,%r/ {c++} f {prev=$0} f && /ret$/ {f=0} END {print c+0}'
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk "$zpair" build/t_ssa.s)" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk "$zpair" build/t_ssa.s)" = 0 ] && echo "PASS fs-ssa-zero-shape" || { echo "FAIL fs-ssa-zero-shape"; fail=1; }
# step 4l: ssa_push's nested operands go through push/pop under --fs-temps; under --fs-ssa fewer pops are left (the
# straight-line round-trips keep the value in a free register)
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && npop=$(awk '/^ssa_push:/,/ret$/' build/t_ssa.s | grep -c '^    pop %r') && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_push:/,/ret$/' build/t_ssa.s | grep -c '^    pop %r')" -lt "$npop" ] && echo "PASS fs-ssa-pushpop-shape" || { echo "FAIL fs-ssa-pushpop-shape"; fail=1; }
# step 4m: ssa_args sets up its call arguments in %rax and copies them to %rdi under --fs-temps; under --fs-ssa a
# call reads %rax only as the vector count, so the loads write %rdi themselves; cabi_float keeps its three
# `mov $n,%eax` vector counts right before their calls
apair='/^ssa_args:/ {f=1} f && prev ~ /^    (mov|lea) [^,]*,%rax$/ && $0 == "    mov %rax,%rdi" {c++} f {prev=$0} f && /ret$/ {f=0} END {print c+0}'
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk "$apair" build/t_ssa.s)" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk "$apair" build/t_ssa.s)" = 0 ] && build/cudc tests/fs/cabi_float.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(grep -A1 -E '^    mov \$[0-9]+,%eax$' build/t_ssa.s | grep -c '^    call')" = 3 ] && echo "PASS fs-ssa-args-shape" || { echo "FAIL fs-ssa-args-shape"; fail=1; }
# step 4n: ssa_move's array stores copy the address to %rcx and the value to %rax first under --fs-temps
# (`mov %rax,(%rcx)`); under --fs-ssa the store reads the copies' sources (`mov %rdx,(%rXX)` — address may
# be %rax or another tracked register after step 4ad's add→lea, `(%rB,%rI,8)` once step 4ai folds that lea
# into the store, or `N(%rB)` once step 4ak moves the constant index into the displacement). --no-bounds: at
# -O0 the kept bounds checks put a label between the value's push and pop
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --no-bounds --fs-temps && [ "$(awk '/^ssa_move:/,/ret$/' build/t_ssa.s | grep -c '^    mov %rax,(%rcx)$')" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --no-bounds --fs-ssa && [ "$(awk '/^ssa_move:/,/ret$/' build/t_ssa.s | grep -c '^    mov %rax,(%rcx)$')" = 0 ] && [ "$(awk '/^ssa_move:/,/ret$/' build/t_ssa.s | grep -cE '^    mov %rdx,(-?[0-9]+)?\(%r[a-z0-9]+(,%r[a-z0-9]+,[1248])?\)$')" = 2 ] && echo "PASS fs-ssa-mem-shape" || { echo "FAIL fs-ssa-mem-shape"; fail=1; }
# fix (SSA form): ssa_lcopy's loop counters are copied to %rax for each compare under --fs-temps; a position inside
# a loop has no phi of its own any more, so under --fs-ssa the copies propagate and each compare reads its counter
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_lcopy:/,/ret$/' build/t_ssa.s | grep -c '^    cmp .*,%rax$')" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_lcopy:/,/ret$/' build/t_ssa.s | grep -c '^    cmp .*,%rax$')" = 0 ] && echo "PASS fs-ssa-loop-copy-shape" || { echo "FAIL fs-ssa-loop-copy-shape"; fail=1; }
# step 4o: ssa_cold's stored and multiplied values cross the bounds checks of w[i] and w[j] on the stack under
# --fs-temps (the failure call then needs `sub $8,%rsp` to stay aligned); under --fs-ssa they stay in registers, so
# no pad is left and only the pop around the `and` (a real join) remains
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_cold:/,/ret$/' build/t_ssa.s | grep -c '^    sub \$8,%rsp$')" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_cold:/,/ret$/' build/t_ssa.s | grep -c '^    sub \$8,%rsp$')" = 0 ] && [ "$(awk '/^ssa_cold:/,/ret$/' build/t_ssa.s | grep -c '^    pop %r')" = 1 ] && echo "PASS fs-ssa-cold-shape" || { echo "FAIL fs-ssa-cold-shape"; fail=1; }
# step 4p: under --fs-temps ssa_rax copies its operands into %rax for each add and imul by a constant; under
# --fs-ssa no copy into %rax is left there, and the adds and multiplies are lea and three-operand imul
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_rax:/,/ret$/' build/t_ssa.s | grep -c '^    mov %r[a-z0-9]*,%rax$')" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_rax:/,/ret$/' build/t_ssa.s | grep -c '^    mov %r[a-z0-9]*,%rax$')" = 0 ] && [ "$(awk '/^ssa_rax:/,/ret$/' build/t_ssa.s | grep -c '^    lea -*[0-9]*(%r[a-z0-9]*\(,%r[a-z0-9]*\)*),%r')" -ge 3 ] && [ "$(awk '/^ssa_rax:/,/ret$/' build/t_ssa.s | grep -c '^    lea -[0-9]*(%r')" -ge 1 ] && [ "$(awk '/^ssa_rax:/,/ret$/' build/t_ssa.s | grep -c '^    imul \$[0-9]*,%r[a-z0-9]*,%r')" -ge 2 ] && echo "PASS fs-ssa-rax-shape" || { echo "FAIL fs-ssa-rax-shape"; fail=1; }
# and ssa_rpush's operands pushed across its calls go straight from their registers (`push %rbx`, `push %r12`)
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_rpush:/,/ret$/' build/t_ssa.s | grep -c '^    push %r\(bx\|12\)$')" = 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_rpush:/,/ret$/' build/t_ssa.s | grep -c '^    push %r\(bx\|12\)$')" = 2 ] && echo "PASS fs-ssa-rpush-shape" || { echo "FAIL fs-ssa-rpush-shape"; fail=1; }
# step 4q/4v: ssa_mul's unsigned mul by a constant with an unread high half is imul $N (two-op into %rax or three-op); no mul %rcx
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_mul:/,/ret$/' build/t_ssa.s | grep -c '^    mul %rcx$')" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_mul:/,/ret$/' build/t_ssa.s | grep -c '^    mul %rcx$')" = 0 ] && [ "$(awk '/^ssa_mul:/,/ret$/' build/t_ssa.s | grep -cE '^    imul \$[0-9]*,(%r[a-z0-9]*,)?%r[a-z0-9]*$')" -ge 1 ] && echo "PASS fs-ssa-mul-shape" || { echo "FAIL fs-ssa-mul-shape"; fail=1; }
# step 4r: ssa_shift's constant shifts become immediate counts (no mov $N,%rcx / sh* %cl)
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_shift:/,/ret$/' build/t_ssa.s | grep -c '^    mov \$[0-9]*,%rcx$')" -ge 3 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_shift:/,/ret$/' build/t_ssa.s | grep -c '^    \(shr\|shl\|sar\) %cl,')" = 0 ] && [ "$(awk '/^ssa_shift:/,/ret$/' build/t_ssa.s | grep -c '^    \(shr\|shl\|sar\) \$[0-9]*,')" -ge 3 ] && echo "PASS fs-ssa-shift-shape" || { echo "FAIL fs-ssa-shift-shape"; fail=1; }
# step 4t: ssa_sar's arithmetic shifts by a constant use sar $N (no mov $N,%rcx / sar %cl)
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_sar:/,/ret$/' build/t_ssa.s | grep -c '^    sar %cl,')" -ge 2 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_sar:/,/ret$/' build/t_ssa.s | grep -c '^    sar %cl,')" = 0 ] && [ "$(awk '/^ssa_sar:/,/ret$/' build/t_ssa.s | grep -c '^    sar \$[0-9]*,')" -ge 2 ] && echo "PASS fs-ssa-sar-shape" || { echo "FAIL fs-ssa-sar-shape"; fail=1; }
# step 4s: ssa_andtest's and into %rax that only feeds a zero-test keeps the and's flags (no test %rax,%rax)
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_andtest:/,/ret$/' build/t_ssa.s | grep -c '^    test %rax,%rax$')" -gt 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_andtest:/,/ret$/' build/t_ssa.s | grep -c '^    test %rax,%rax$')" = 0 ] && [ "$(awk '/^ssa_andtest:/,/ret$/' build/t_ssa.s | grep -c '^    and \$')" -ge 1 ] && echo "PASS fs-ssa-andtest-shape" || { echo "FAIL fs-ssa-andtest-shape"; fail=1; }
# step 4u: ssa_aluimm's add/and/or by a constant fold to immediates even when a later call inflates %rcx use counts
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_aluimm:/,/ret$/' build/t_ssa.s | grep -c '^    mov \$[0-9]*,%rcx$')" -ge 2 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_aluimm:/,/ret$/' build/t_ssa.s | grep -c '^    mov \$[0-9]*,%rcx$')" = 0 ] && [ "$(awk '/^ssa_aluimm:/,/ret$/' build/t_ssa.s | grep -cE '^    (add|and|or|lea) ')" -ge 3 ] && echo "PASS fs-ssa-aluimm-shape" || { echo "FAIL fs-ssa-aluimm-shape"; fail=1; }
# step 4v: ssa_mulrax's mul by a constant with the multiplicand already in %rax becomes imul $N,%rax
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_mulrax:/,/ret$/' build/t_ssa.s | grep -c '^    mul %rcx$')" -ge 1 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_mulrax:/,/ret$/' build/t_ssa.s | grep -c '^    mul %rcx$')" = 0 ] && [ "$(awk '/^ssa_mulrax:/,/ret$/' build/t_ssa.s | grep -c '^    imul \$[0-9]*,%rax$')" = 1 ] && echo "PASS fs-ssa-mulrax-shape" || { echo "FAIL fs-ssa-mulrax-shape"; fail=1; }
# step 4w: ssa_andset's and by a constant that only feeds setcc becomes test $N (value unread)
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_andset:/,/ret$/' build/t_ssa.s | grep -cE '^    and ')" -ge 1 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_andset:/,/ret$/' build/t_ssa.s | grep -cE '^    and ')" = 0 ] && [ "$(awk '/^ssa_andset:/,/ret$/' build/t_ssa.s | grep -c '^    test \$')" -ge 1 ] && echo "PASS fs-ssa-andset-shape" || { echo "FAIL fs-ssa-andset-shape"; fail=1; }
# step 4x: ssa_cold's short-circuit and keeps setne at the merge (fold refuses flag-consuming targets);
# a safe setCC/movzbl/test/je (kernel serial_putc tries loop) becomes jCC — covered by kernel build in the os gate
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_cold:/,/^ssa_rax:/' build/t_ssa.s | grep -c 'setne %al')" -ge 1 ] && [ "$(awk '/^ssa_cold:/,/^ssa_rax:/' build/t_ssa.s | grep -cE '^    setl %al$')" -ge 1 ] && echo "PASS fs-ssa-jcc-shape" || { echo "FAIL fs-ssa-jcc-shape"; fail=1; }
# step 4y: store then reload of the same register from the same %rbp slot drops under --fs-ssa
build/cudc tests/count-store-reload/count_store_reload.cud build/count_store_reload.s && build/fas -o build/count_store_reload.o build/count_store_reload.s && build/fld --base 0x100000000000 -o build/count_store_reload build/count_store_reload.o && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(build/count_store_reload build/t_ssa.s)" -ge 1 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(build/count_store_reload build/t_ssa.s)" = 0 ] && echo "PASS fs-ssa-reload-shape" || { echo "FAIL fs-ssa-reload-shape"; fail=1; }
# step 4z: add $0,%rsp is dropped under --fs-ssa
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(grep -cE '^    add \$0,%rsp$' build/t_ssa.s)" -ge 1 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(grep -cE '^    add \$0,%rsp$' build/t_ssa.s)" = 0 ] && echo "PASS fs-ssa-add0-shape" || { echo "FAIL fs-ssa-add0-shape"; fail=1; }
# step 4aa: ssa_zstore's xor;store of 0 becomes movq $0,MEM under --fs-ssa
zstore_xor='/^ssa_zstore:/ {f=1} f && prev ~ /^    xor %e?ax,%e?ax$/ && $0 ~ /^    mov %rax,/ && $0 !~ /^    mov %rax,%/ {c++} f {prev=$0} /^ssa_leamov:/ {f=0} END {print c+0}'
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk "$zstore_xor" build/t_ssa.s)" -ge 1 ] && [ "$(awk '/^ssa_zstore:/,/^ssa_leamov:/' build/t_ssa.s | grep -cE '^    movq \$0,')" = 0 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk "$zstore_xor" build/t_ssa.s)" = 0 ] && [ "$(awk '/^ssa_zstore:/,/^ssa_leamov:/' build/t_ssa.s | grep -cE '^    movq \$0,')" -ge 1 ] && echo "PASS fs-ssa-zstore-shape" || { echo "FAIL fs-ssa-zstore-shape"; fail=1; }
# step 4ab: lea ADDR,%rax; mov %rax,%rD becomes lea ADDR,%rD under --fs-ssa
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(python3 -c "import re;L=open('build/t_ssa.s').read().splitlines();print(sum(1 for i in range(len(L)-1) if re.match(r'    lea .*,%rax$',L[i]) and re.match(r'    mov %rax,%r(?!ax)',L[i+1])))")" -ge 1 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(python3 -c "import re;L=open('build/t_ssa.s').read().splitlines();print(sum(1 for i in range(len(L)-1) if re.match(r'    lea .*,%rax$',L[i]) and re.match(r'    mov %rax,%r(?!ax)',L[i+1])))")" = 0 ] && echo "PASS fs-ssa-leamov-shape" || { echo "FAIL fs-ssa-leamov-shape"; fail=1; }
# step 4ac: imul $N,%rS,%rax; mov %rax,%rD becomes imul into %rD under --fs-ssa
imulpair='/^    imul \$[0-9-]+,%r[a-z0-9]+,%rax$/ {a=$0; getline; if ($0 ~ /^    mov %rax,%r/ && $0 !~ /^    mov %rax,%rax/) c++} END {print c+0}'
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk "$imulpair" build/t_ssa.s)" -ge 1 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk "$imulpair" build/t_ssa.s)" = 0 ] && echo "PASS fs-ssa-imuldest-shape" || { echo "FAIL fs-ssa-imuldest-shape"; fail=1; }
# step 4ad: add %rS,%rax; mov %rax,%rD becomes lea (%rax,%rS),%rD under --fs-ssa
addpair='/^    add %r[a-z0-9]+,%rax$/ {a=$0; getline; if ($0 ~ /^    mov %rax,%r/ && $0 !~ /^    mov %rax,%rax/) c++} END {print c+0}'
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk "$addpair" build/t_ssa.s)" -ge 1 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk "$addpair" build/t_ssa.s)" = 0 ] && echo "PASS fs-ssa-addlea-shape" || { echo "FAIL fs-ssa-addlea-shape"; fail=1; }
# step 4ae: ssa_andmerge's first arm becomes a direct jCC to the false target (through-merge stop)
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_andmerge:/,/^ssa_leamov:/' build/t_ssa.s | grep -cE '^    setl %al$')" -ge 1 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_andmerge:/,/^ssa_leamov:/' build/t_ssa.s | grep -cE '^    j(ge|l|le|g|e|ne) ')" -ge 1 ] && [ "$(awk '/^ssa_andmerge:/,/^ssa_leamov:/' build/t_ssa.s | grep -cE '^    setl %al$')" -le 1 ] && echo "PASS fs-ssa-through-shape" || { echo "FAIL fs-ssa-through-shape"; fail=1; }
# step 4af: ssa_brk's `jmp; jmp` (break) and `jmp; xor` (loop exit) lose the never-run second line under --fs-ssa
unr='p ~ /^    jmp / && $0 ~ /^    [a-z]/ {c++} {p=$0} END {print c+0}'
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_brk:/,/^ssa_leamov:/' build/t_ssa.s | awk "$unr")" -ge 2 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_brk:/,/^ssa_leamov:/' build/t_ssa.s | awk "$unr")" = 0 ] && echo "PASS fs-ssa-unreach-shape" || { echo "FAIL fs-ssa-unreach-shape"; fail=1; }
# step 4ag: ssa_brk's loop exit jumps to the return label right after it under --fs-temps; under --fs-ssa that jmp is gone
retj='{a[NR]=$0} END {for (i=2;i<=NR;i++) if (a[i]=="    leave" && a[i-1] ~ /^\.LF[0-9]+:$/) r=substr(a[i-1],1,length(a[i-1])-1); for (i=1;i<=NR;i++) if (a[i]=="    jmp " r) c++; print c+0}'
jnx='/^    jmp \.LF/ {t=$2; while ((getline n) > 0 && n ~ /^\.LF[0-9]+:$/) { if (n == t ":") {c++; break} } } END {print c+0}'
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_brk:/,/^ssa_leamov:/' build/t_ssa.s | awk "$retj")" -ge 1 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_brk:/,/^ssa_leamov:/' build/t_ssa.s | awk "$retj")" = 0 ] && [ "$(awk "$jnx" build/t_ssa.s)" = 0 ] && echo "PASS fs-ssa-jnext-shape" || { echo "FAIL fs-ssa-jnext-shape"; fail=1; }
# step 4ah: ssa_idx's three checked indexes scale with `imul $8,%rcx,%rcx` under --fs-temps; under --fs-ssa each
# imul is gone and the scale sits in the address as (%rB,%rI,8) (%rI the index itself since step 4aj)
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_idx:/,/^ssa_cidx:/' build/t_ssa.s | grep -c '^    imul \$8,%rcx,%rcx$')" -ge 3 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_idx:/,/^ssa_cidx:/' build/t_ssa.s | grep -c '^    imul ')" = 0 ] && [ "$(awk '/^ssa_idx:/,/^ssa_cidx:/' build/t_ssa.s | grep -cE '\(%r[a-z0-9]+,%r[a-z0-9]+,8\)')" -ge 3 ] && echo "PASS fs-ssa-scale-shape" || { echo "FAIL fs-ssa-scale-shape"; fail=1; }
# step 4ai: ssa_idx's element addresses (lea (%rB,%rcx,8),%rT after step 4ah) fold into the loads and the store
# that go through (%rT): under --fs-ssa no lea is left in ssa_idx and the movs address (%rB,%rI,8) themselves
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_idx:/,/^ssa_cidx:/' build/t_ssa.s | grep -cE '^    lea \(.*,8\),')" = 0 ] && [ "$(awk '/^ssa_idx:/,/^ssa_cidx:/' build/t_ssa.s | grep -cE '^    mov \(%r[a-z0-9]+,%r[a-z0-9]+,8\),%r')" -ge 2 ] && [ "$(awk '/^ssa_idx:/,/^ssa_cidx:/' build/t_ssa.s | grep -cE '^    mov %r[a-z0-9]+,\(%r[a-z0-9]+,%r[a-z0-9]+,8\)$')" -ge 1 ] && echo "PASS fs-ssa-memfold-shape" || { echo "FAIL fs-ssa-memfold-shape"; fail=1; }
# step 4aj: ud2 never falls through, so each bounds check's pass label keeps the index's register: under --fs-ssa
# ssa_idx copies no index into %rcx before its compare (`mov %rdi,%rcx; cmp $8,%rdi` before) and addresses
# (%rax,%rdi,8) directly; under --fs-temps the copies are there
ixcp='p ~ /^    mov %r[a-z0-9]+,%rcx$/ && $0 ~ /^    cmp \$[0-9]+,%r[a-z0-9]+$/ {split(p,a,/[ ,]+/); split($0,b,/[ ,]+/); if (a[3] == b[4]) c++} {p=$0} END {print c+0}'
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-temps && [ "$(awk '/^ssa_idx:/,/^ssa_cidx:/' build/t_ssa.s | grep -c '^    mov %rbx,%rcx$')" -ge 2 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --fs-ssa && [ "$(awk '/^ssa_idx:/,/^ssa_cidx:/' build/t_ssa.s | awk "$ixcp")" = 0 ] && [ "$(awk '/^ssa_idx:/,/^ssa_cidx:/' build/t_ssa.s | grep -cE '\(%rax,%rdi,8\)')" -ge 2 ] && echo "PASS fs-ssa-trapend-shape" || { echo "FAIL fs-ssa-trapend-shape"; fail=1; }
# step 4ak: ssa_cidx's constant indexes (`mov $3,%rcx`, `xor %ecx,%ecx`, read once by the scaled address) go into
# the displacement under --fs-ssa: no index register is loaded, no scaled address is left, and the store and the
# load of element 3 address 24(%rax). --no-bounds: at -O0 the kept bounds checks also compare the constant
# index, a second read that keeps it in %rcx
build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --no-bounds --fs-temps && [ "$(awk '/^ssa_cidx:/,/^show:/' build/t_ssa.s | grep -cE '^    (mov \$3,%rcx|xor %ecx,%ecx)$')" -ge 2 ] && build/cudc tests/fs/ssa.cud build/t_ssa.s $CUDC_FLAGS --no-bounds --fs-ssa && [ "$(awk '/^ssa_cidx:/,/^show:/' build/t_ssa.s | grep -cE '^    (mov \$[0-9]+,%rcx|xor %ecx,%ecx)$')" = 0 ] && [ "$(awk '/^ssa_cidx:/,/^show:/' build/t_ssa.s | grep -cE ',[1248]\)')" = 0 ] && [ "$(awk '/^ssa_cidx:/,/^show:/' build/t_ssa.s | grep -c '24(%rax)')" = 2 ] && echo "PASS fs-ssa-cidx-shape" || { echo "FAIL fs-ssa-cidx-shape"; fail=1; }
return $fail
}
t_fsfuzz() {
fail=0
# --fs-opt differential fuzz: 20 random programs (fixed seed), each built O2 / -O0 / --fs-opt / -O0 --fs-opt / --fs-live / -O0 --fs-live / --fs-temps / -O0 --fs-temps / --fs-ssa / -O0 --fs-ssa; any output diff fails
./cuditor tools/fsfuzz.cud -o build/fsfuzz-tool >/dev/null 2>&1 && build/fsfuzz-tool --seed 1 --n 20 > build/t_fsfuzz.log 2>&1 && echo "PASS fs-opt-fuzz" || { echo "FAIL fs-opt-fuzz"; cat build/t_fsfuzz.log; fail=1; }
# build-plan item 3 (b, d): every optimizer flag combination (56 flag sets x plain/stack-protector), 3 programs
build/fsfuzz-tool --combos --seed 7 --n 3 > build/t_fscombos.log 2>&1 && echo "PASS fs-opt-combos" || { echo "FAIL fs-opt-combos"; cat build/t_fscombos.log; fail=1; }
return $fail
}
t_optgate() {
fail=0
# build-plan item 3 (c): optimizer-gate programs (tests/optgate) give the same output under every fs optimizer level
for t in tests/optgate/*.cud; do
  for f in "" --fs-opt --fs-live --fs-temps --fs-ssa; do
    build/cudc "$t" build/t_og.s $CUDC_FLAGS $f && build/fas -o build/t_og.o build/t_og.s && build/fld -o build/t_og build/t_og.o && build/t_og | diff -q - "${t%.cud}.expected" >/dev/null && echo "PASS optgate$f $t" || { echo "FAIL optgate$f $t"; fail=1; }
  done
done
return $fail
}
t_optcov() {
fail=0
# build-plan item 3 (a, c): block coverage of the fs optimizer passes; --check fails on any never-hit block not in
# tools/optcov-allow.txt and on any stale allow-list entry (docs/tools-optcov.md, ~45 s)
./cuditor tools/optcov.cud -o build/optcov-tool >/dev/null 2>&1 && build/optcov-tool --check > build/t_optcov.log 2>&1 && echo "PASS optimizer-coverage" || { echo "FAIL optimizer-coverage"; cat build/t_optcov.log; fail=1; }
return $fail
}
t_cdiv() {
fail=0
# constant division: in c_i64_7 and c_u64_641 only the three divisions by a variable keep div/idiv
build/cudc tests/fs/cdiv.cud build/t_cd.s $CUDC_FLAGS --fs-opt && [ "$(awk '/^c_i64_7:/,/ret$/' build/t_cd.s | grep -c '    idiv ')" = 3 ] && [ "$(awk '/^c_u64_641:/,/ret$/' build/t_cd.s | grep -c '    div ')" = 3 ] && echo "PASS fs-opt-cdiv-shape" || { echo "FAIL fs-opt-cdiv-shape"; fail=1; }
return $fail
}
t_float_global() {
fail=0
# float globals take float or integer literals only (tests/fs/fglobals.cud checks the bits)
printf '# cuditor: no-runtime\nK = 3\nx: f64 = K\n' > build/t_fgk.cud
build/cudc build/t_fgk.cud build/t_fgk.s 2>&1 | grep -q "a float global's initializer must be a float or integer literal" && echo "PASS fs-float-global-literal-only" || { echo "FAIL fs-float-global-literal-only"; fail=1; }
return $fail
}
t_input_missing() {
fail=0
# missing input / include files: clean diagnostic, exit 1, no crash
printf 'include "no_such_file.cudi"\n' > build/t_inc.cud
build/cudc build/t_inc.cud build/t_inc.s --freestanding > build/t_inc.txt 2>&1; rc=$?
[ $rc = 1 ] && grep -q "^error: cannot read include file .*no_such_file.cudi" build/t_inc.txt && echo "PASS include-missing" || { echo "FAIL include-missing (rc=$rc)"; fail=1; }
build/cudc build/no_such_input.cud build/t_inc.s > build/t_inc.txt 2>&1; rc=$?
[ $rc = 1 ] && grep -q "^error: cannot read input file" build/t_inc.txt && echo "PASS input-missing" || { echo "FAIL input-missing (rc=$rc)"; fail=1; }
return $fail
}
# NN lane item, in serial order. Lanes: S = everything that writes or reads build/kernel, build/user,
# build/efi, build/modules, build/fas or the busybox/cpython trees (one at a time, in this order); alone =
# timing-sensitive (tests/bounds compares run times); the others only touch their own scratch files, and
# items sharing a scratch file or a lazily rebuilt tool (build/t_bin, build/t_err.s, build/grammar-fuzz,
# build/fmt, build/pkg, ...) share a lane
ITEMS='01 A t_cases
02 A t_runtime
03 E t_errors
04 E t_typeerrors
05 E t_diag
06 E t_diag_schema
07 E t_diag_input
08 R t_ast_roundtrip
09 M t_ast_semantic
10 G t_grammar
11 F t_fmt
12 S t_os_artifacts
13 S t_fas
14 S t_fld
15 S t_krel
16 X t_incudela_part
17 X t_mkgpt
18 S t_espmigrate
19 X t_ed25519_tool
20 G t_grammar_fuzz
21 X t_mkfont
22 X t_c2cud
23 X t_cudseal
24 S t_modules_build
25 S t_user_build
26 S t_busybox_build
27 S t_bzip2
28 S t_cpython_build
29 S t_cpython_embed
30 S t_efi_build
31 S t_kernel_build
32 S t_kernel_release
33 S t_rtport
34 S t_pecheck
35 S t_memimg
36 S t_oslib
37 S t_reseed
38 S t_pkg
39 S t_oldnames
40 B t_lsp
41 B t_provenance
42 F t_testblocks
43 alone t_bounds
44 X t_nonnull
45 M t_unsafe
46 M t_own
47 X t_limits
48 X t_defer
49 X t_generic
50 X t_ed25519
51 X t_atomic
52 M t_ast_selfpp
53 B t_bench
54 B t_asm_audit
55 B t_ci
56 E t_ast_json
57 FS t_fs_shapes
58 Z t_fsfuzz
59 Z t_optgate
60 C t_optcov
61 E t_cdiv
62 E t_float_global
63 E t_input_missing
64 S t_forge_build
65 alone t_forge_run_tests
66 S t_count_store_reload'
# RUN_TESTS_ONLY: optional space-separated item names (the Cuditor port honours the same).
# FORGE_RUN_TESTS_INNER=1 omits t_forge_run_tests so a comparison can run inside the suite.
# RUN_TESTS_PAR: per-item log dir (default build/par). If unset and INNER is set, build/par-inner.
if [ -n "$FORGE_RUN_TESTS_INNER" ]; then
  ITEMS=$(printf '%s\n' "$ITEMS" | while read n l f; do [ "$f" != "t_forge_run_tests" ] && echo "$n $l $f"; done)
fi
if [ -n "$RUN_TESTS_ONLY" ]; then
  ITEMS=$(printf '%s\n' "$ITEMS" | while read n l f; do
    case " $RUN_TESTS_ONLY " in
      *" $f "*) echo "$n $l $f" ;;
    esac
  done)
fi
if [ -n "$RUN_TESTS_PAR" ]; then
  P=$RUN_TESTS_PAR
elif [ -n "$FORGE_RUN_TESTS_INNER" ]; then
  P=build/par-inner
else
  P=build/par
fi
rm -rf "$P"; mkdir -p "$P"
if [ -n "$RUN_TESTS_SERIAL" ]; then
  echo "$ITEMS" | while read n l f; do ( $f ) < /dev/null || : > $P/fail; done
else
  # one lane's items in order, each item's output and exit status in build/par
  run_lane() { echo "$ITEMS" | while read n l f; do [ "$l" = "$1" ] && { ( $f ) > $P/$n.log 2>&1 < /dev/null; echo $? > $P/$n.rc; }; done; }
  for l in $(echo "$ITEMS" | awk '$2 != "S" && $2 != "alone" {print $2}' | sort -u); do run_lane $l & done
  run_lane S
  wait
  run_lane alone
  # every item's output in item order; a failed item keeps its whole log in place plus a pointer to the file,
  # and an item with no exit status (killed, never run) is a FAIL of its own
  echo "$ITEMS" | while read n l f; do
    cat $P/$n.log 2>/dev/null; rc=$(cat $P/$n.rc 2>/dev/null)
    if [ -z "$rc" ]; then echo "FAIL run-tests/$f (no exit status; log: $P/$n.log)"; : > $P/fail
    elif [ "$rc" != 0 ]; then echo "# $f (lane $l) exited $rc, log: $P/$n.log"; : > $P/fail; fi
  done
fi
[ -f $P/fail ] && fail=1
# tests/os: boot the Incudela kernel (BIOS + UEFI via GRUB multiboot2) and the native EFI app in headless QEMU
if [ -z "$SKIP_OS" ] && command -v qemu-system-x86_64 >/dev/null && command -v grub-mkrescue >/dev/null; then
  # capture through a regular file, not $(...): a child that sets O_NONBLOCK on the shared pipe made later
  # writes fail with EAGAIN, silently dropping result lines (inv83: 14 os/dwarf results missing at O0)
  tests/os/run.sh > build/os-results.txt 2>&1; r=$(cat build/os-results.txt); echo "$r"; echo "$r" | grep -q "^FAIL" && fail=1
  miss=""
  for n in $(grep -v '^#' tests/os/expected-results.txt); do
    echo "$r" | grep -qE "^(PASS|FAIL) $n( |$)" || miss="$miss $n"
  done
  [ -z "$miss" ] && echo "PASS os/result-count ($(grep -vc '^#' tests/os/expected-results.txt) results reported)" || { echo "FAIL os/result-count (missing:$miss)"; fail=1; }
elif [ -n "$SKIP_OS" ]; then
  # an explicit, visible opt-out (quick non-QEMU runs while a gate holds QEMU); never a gate result
  echo "SKIP tests/os (SKIP_OS set: the $(grep -vc '^#' tests/os/expected-results.txt) OS results were not run, so this run is not a gate pass)"
else
  # fail closed: a run without the OS-test toolchain must not look like a full pass (the gate harness reinstalls
  # the tools with tools/ostools.cud before it starts; 2026-11-15 assessment)
  echo "FAIL tests/os (qemu-system-x86_64 or grub-mkrescue missing: build/ostools reinstalls them; SKIP_OS=1 skips on purpose)"; fail=1
fi
exit $fail
