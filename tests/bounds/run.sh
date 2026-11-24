#!/bin/bash
# Phase 4.1: slices + bounds checks — traps with precise diagnostics, compile-time errors, elision count, overhead
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); fail=0
ok() { echo "PASS $1"; }; no() { echo "FAIL $1"; fail=1; }
trap_case() { # name, expected diagnostic
    ./cuditor tests/bounds/$1.cud -o $T/$1 >/dev/null 2>&1 || { no bounds-$1; return; }
    $T/$1 > $T/$1.out 2>&1; rc=$?
    [ $rc = 134 ] && grep -qF "$2" $T/$1.out && ok bounds-$1 || { no bounds-$1; cat $T/$1.out; }
}
trap_case oob_slice "bounds check failed: tests/bounds/oob_slice.cud:5: index 3 out of range for length 3"
trap_case oob_array "bounds check failed: tests/bounds/oob_array.cud:7: index 18446744073709551615 out of range for length 5"
trap_case oob_sub "bounds check failed: tests/bounds/oob_sub.cud:7: index 6 out of range for length 5"
trap_case oob_while "bounds check failed: tests/bounds/oob_while.cud:11: index 4 out of range for length 4"
trap_case oob_addr "bounds check failed: tests/bounds/oob_addr.cud:15: index 4 out of range for length 4"
# the in-range call before the trap still ran
grep -qx 0 $T/oob_slice.out && ok bounds-before-trap || no bounds-before-trap
cf_case() { # name, expected error
    ./cuditor tests/bounds/$1.cud -o $T/$1 > $T/$1.err 2>&1 && { no bounds-$1; return; }
    grep -qF "$2" $T/$1.err && ok bounds-$1 || { no bounds-$1; cat $T/$1.err; }
}
cf_case cf_const "index 5 is out of bounds for an array of length 5"
cf_case cf_mismatch "slice type mismatch"
# without a forge_bounds_fail handler the check is a bare ud2 (SIGILL)
printf '# cuditor: no-runtime\n@export\ndef _start():\n    a: u8[2]\n    i: u64 = 2\n    a[i] = 0\n' > $T/bare.cud
build/cudc $T/bare.cud $T/bare.s && grep -q ud2 $T/bare.s && ok bounds-bare-ud2 || no bounds-bare-ud2
# elision: loops over range(len(x)) / range(K<=N) drop the check; assigning the loop var keeps it
build/cudc tests/bounds/elide.cud $T/e.s --bounds-stats 2> $T/e.st
grep -qx "bounds: 8 sites, 5 checked, 3 elided" $T/e.st && ok bounds-elide-count || { no bounds-elide-count; cat $T/e.st; }
./cuditor tests/bounds/elide.cud -o $T/e && [ "$($T/e)" = 197 ] && ok bounds-elide-run || no bounds-elide-run
# elision through n = len(s) aliases, while v < n: / while v < len(s): guards and range(C, ...) lower bounds
# (X[v - K], K <= C): each pos_* function has no check left, each neg_* keeps its own (a reassigned or
# conditionally defined alias, a write to v before the index, an index in a nested loop, K > C, <=, a written
# slice parameter, addr() of v, an alias also written by for or addr(), len() of a local array, a K that wraps)
# (in range(C, ...), stored negative); -O0 keeps all 29
fchk() { awk '/^[a-z_]+:$/{f=substr($1,1,length($1)-1)} /call forge_bounds_fail/{c[f]++} /^(pos|neg)_[a-z_]+:$/{n[++k]=substr($1,1,length($1)-1)} END{for(i=1;i<=k;i++) printf "%s=%d ", n[i], c[n[i]]+0}' $1; }
build/cudc tests/bounds/elide_alias.cud $T/a.s --bounds-stats 2> $T/a.st
[ "$(fchk $T/a.s)" = "pos_range_alias=0 pos_while=0 pos_while_len=0 pos_nested_while=0 pos_lo=0 neg_reassign=1 neg_cond_def=1 neg_write_before=1 neg_nested=1 neg_lo=1 neg_le=1 neg_param_write=2 neg_addr=1 neg_alias_for=1 neg_alias_addr=1 neg_while_array=1 neg_big=1 " ] && grep -qx "bounds: 29 sites, 23 checked, 6 elided" $T/a.st && ok bounds-elide-alias || { no bounds-elide-alias; fchk $T/a.s; cat $T/a.st; }
build/cudc tests/bounds/elide_alias.cud $T/a0.s -O0 --bounds-stats 2> $T/a0.st
grep -qx "bounds: 29 sites, 29 checked, 0 elided" $T/a0.st && ok bounds-elide-alias-O0 || { no bounds-elide-alias-O0; cat $T/a0.st; }
./cuditor tests/bounds/elide_alias.cud -o $T/a && [ "$($T/a)" = 4732 ] && CUDC_FLAGS=-O0 ./cuditor tests/bounds/elide_alias.cud -o $T/a0 && [ "$($T/a0)" = 4732 ] && ok bounds-elide-alias-run || no bounds-elide-alias-run
# -O0 turns elision off: every site keeps its check (also for in-range constant indices), same output
build/cudc tests/bounds/elide.cud $T/e0.s -O0 --bounds-stats 2> $T/e0.st
grep -qx "bounds: 8 sites, 8 checked, 0 elided" $T/e0.st && ok bounds-elide-off-O0 || { no bounds-elide-off-O0; cat $T/e0.st; }
build/fas -o $T/e0.o $T/e0.s && build/fld -o $T/e0 $T/e0.o && [ "$($T/e0)" = 197 ] && ok bounds-elide-off-O0-run || no bounds-elide-off-O0-run
# --no-bounds and the pragma drop every check
build/cudc tests/bounds/oob_sub.cud $T/n.s --no-bounds --bounds-stats 2> $T/n.st
grep -q " 0 checked" $T/n.st && ok bounds-off-flag || no bounds-off-flag
sed '1a # cuditor: no-bounds-checks' tests/bounds/oob_array.cud > tests/bounds/.p.cud
build/cudc tests/bounds/.p.cud $T/p.s --bounds-stats 2> $T/p.st; rm -f tests/bounds/.p.cud
grep -q " 0 checked" $T/p.st && ok bounds-off-pragma || no bounds-off-pragma
# overhead: checked vs --no-bounds, must be <= 5% slower. 21 pairs; a pair is 3 interleaved checked/unchecked
# rounds (the order alternates every round so drift and warm-up favour neither) and its ratio is best checked /
# best unchecked of those 3, in basis points; the test takes the median of the 21 pair ratios. Comparing the best
# checked run with the best unchecked run of the whole series failed twice under gate load with byte-identical
# code: inv138 O2 (best of 7, 6.7%; three re-runs gave 5.7%, -3.3% and 4.3%) and inv156 O2 (best of 21, 6.95%:
# one lucky fast unchecked run, 286 ms against 287-334 ms in the ten gates before). Single-run pairs were too
# noisy on the box (pair ratios 0.63-2.66, medians of 21 from 0.997 to 1.067 with identical code); best of 3 per
# pair keeps the pair ratios near 0.9-1.17 and the median of 21 at 1.009-1.023 (measured 2026-11-13).
./cuditor tests/bounds/bench.cud -o $T/bc && CUDC_FLAGS=--no-bounds ./cuditor tests/bounds/bench.cud -o $T/bn
[ "$($T/bc)" = "$($T/bn)" ] && ok bounds-bench-same || no bounds-bench-same
tm() { s=$(date +%s%N); $1 >/dev/null; echo $(( ($(date +%s%N)-s)/1000 )); }
: > $T/ratios
for k in $(seq 1 21); do
  c=999999999; n=999999999
  for j in 1 2 3; do
    if [ $(((k + j) % 2)) = 1 ]; then d=$(tm $T/bc); [ $d -lt $c ] && c=$d; d=$(tm $T/bn); [ $d -lt $n ] && n=$d
    else d=$(tm $T/bn); [ $d -lt $n ] && n=$d; d=$(tm $T/bc); [ $d -lt $c ] && c=$d; fi
  done
  [ $n -gt 0 ] || n=1
  echo $((c * 10000 / n)) >> $T/ratios
done
med=$(sort -n $T/ratios | sed -n 11p); lo=$(sort -n $T/ratios | head -1); hi=$(sort -n $T/ratios | tail -1)
build/cudc tests/bounds/bench.cud $T/b.s --bounds-stats 2> $T/b.st
r4() { echo "$(($1 / 10000)).$(printf %04d $(($1 % 10000)))"; }
echo "bounds bench: median checked/unchecked $(r4 $med) over 21 pairs of best-of-3 (min $(r4 $lo), max $(r4 $hi)," \
  "limit 1.0500), last pair checked ${c}us unchecked ${n}us, $(cat $T/b.st)"
[ $med -le 10500 ] && ok bounds-bench-overhead || no bounds-bench-overhead
rm -rf $T; exit $fail
