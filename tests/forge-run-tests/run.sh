#!/bin/sh
# tests/forge-run-tests/run.sh: compare tools/run_tests.cud (build/forge-run-tests)
# against the repo-root run_tests.sh, which stays as the reference.
# Reservation 6, batch 2. tests/build/ is gitignored by the build/ rule, so this
# test lives here. Never starts QEMU (SKIP_OS=1).
# usage: tests/forge-run-tests/run.sh
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"; rm -f build/par/outer-sentinel; [ -f tests/ci/run.sh.bak ] && mv -f tests/ci/run.sh.bak tests/ci/run.sh' EXIT
fail=0
./cuditor tools/run_tests.cud -o build/forge-run-tests >/dev/null || { echo "FAIL forge-run-tests build"; exit 1; }

# A short serial non-QEMU subset: driver + inline items + a script item, not a
# second full suite. FORGE_RUN_TESTS_INNER omits t_forge_run_tests if present.
# RUN_TESTS_PAR is a private scratch dir: a nested run_tests.sh does rm -rf on
# its par dir, and must not wipe the outer run's build/par (inv242: 64 false
# "no exit status" FAILs when item 65 used the outer par).
ONLY="t_diag_input t_input_missing t_ci t_asm_audit t_cdiv t_float_global"
export FORGE_RUN_TESTS_INNER=1 SKIP_OS=1 RUN_TESTS_SERIAL=1 RUN_TESTS_ONLY="$ONLY"
export RUN_TESTS_PAR="$T/par"
mkdir -p "$RUN_TESTS_PAR" build/par
echo isolated > build/par/outer-sentinel

sh ./run_tests.sh >$T/s.out 2>$T/s.err; rs=$?
./build/forge-run-tests >$T/f.out 2>$T/f.err; rf=$?
if [ $rs = $rf ] && cmp -s $T/s.out $T/f.out && cmp -s $T/s.err $T/f.err \
   && grep -q '^PASS diag-json-input-missing' $T/f.out \
   && grep -q '^PASS include-missing' $T/f.out \
   && grep -q '^PASS input-missing' $T/f.out \
   && grep -q '^PASS fs-opt-cdiv-shape' $T/f.out \
   && grep -q '^PASS fs-float-global-literal-only' $T/f.out \
   && grep -q '^SKIP tests/os (SKIP_OS set:' $T/f.out; then
  echo "PASS run-tests/default"
else
  echo "FAIL run-tests/default (rc $rs/$rf)"
  echo "---- stdout ----"
  diff -u $T/s.out $T/f.out | head -50
  echo "---- stderr ----"
  diff -u $T/s.err $T/f.err | head -20
  fail=1
fi

# Same failure when tests/ci/run.sh is replaced by a script that exits 1.
mv tests/ci/run.sh tests/ci/run.sh.bak
printf '%s\n' '#!/bin/sh' 'echo "FAIL tests/ci (planted)"' 'exit 1' > tests/ci/run.sh
chmod +x tests/ci/run.sh
export RUN_TESTS_ONLY="t_ci"
sh ./run_tests.sh >$T/ms.out 2>$T/ms.err; mrs=$?
./build/forge-run-tests >$T/mf.out 2>$T/mf.err; mrf=$?
mv tests/ci/run.sh.bak tests/ci/run.sh
if [ $mrs = $mrf ] && [ $mrs != 0 ] && cmp -s $T/ms.out $T/mf.out && cmp -s $T/ms.err $T/mf.err \
   && grep -q '^FAIL tests/ci (planted)' $T/mf.out; then
  echo "PASS run-tests/missing-item"
else
  echo "FAIL run-tests/missing-item (rc $mrs/$mrf)"
  echo "---- stdout ----"
  diff -u $T/ms.out $T/mf.out | head -40
  echo "---- stderr ----"
  diff -u $T/ms.err $T/mf.err | head -20
  fail=1
fi

# The nested run must leave the outer build/par alone.
if [ -f build/par/outer-sentinel ] && grep -q isolated build/par/outer-sentinel; then
  echo "PASS run-tests/par-isolated"
else
  echo "FAIL run-tests/par-isolated (nested run wiped or changed build/par)"
  fail=1
fi
rm -f build/par/outer-sentinel

[ $fail = 0 ]
exit $fail
