#!/bin/sh
# tests/count-store-reload: tests/count-store-reload/count_store_reload.cud must agree with
# tests/fs/count_store_reload.py (kept as the reference): identical stdout and exit code on
# synthetic assembly and on tests/fs/ssa.cud compiled with --fs-temps and --fs-ssa.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf $T' EXIT
fail=0
build/cudc tests/count-store-reload/count_store_reload.cud $T/c.s && build/fas -o $T/c.o $T/c.s && build/fld --base 0x100000000000 -o $T/count_store_reload $T/c.o || { echo "FAIL count-store-reload build"; exit 1; }
command -v python3 >/dev/null || { echo "SKIP count-store-reload (needs python3 for the reference)"; exit 0; }

# write FILE from stdin (no extra newline beyond what the payload has)
put() { cat > "$T/$1.s"; }

put empty </dev/null

put one-pair <<'S'
    mov %rax,-8(%rbp)
    mov -8(%rbp),%rax
S

put two-pairs <<'S'
    mov %rax,-8(%rbp)
    mov -8(%rbp),%rax
    mov %rbx,-16(%rbp)
    mov -16(%rbp),%rbx
S

put diff-reg <<'S'
    mov %rax,-8(%rbp)
    mov -8(%rbp),%rbx
S

put diff-off <<'S'
    mov %rax,-8(%rbp)
    mov -16(%rbp),%rax
S

put pos-off <<'S'
    mov %r12,16(%rbp)
    mov 16(%rbp),%r12
S

put ws <<'S'
    mov %rax,-8(%rbp)   
    mov -8(%rbp),%rax	
S

put gap <<'S'
    mov %rax,-8(%rbp)
    nop
    mov -8(%rbp),%rax
S

put eax <<'S'
    mov %eax,-8(%rbp)
    mov -8(%rbp),%eax
S

put rcx <<'S'
    mov %rcx,-8(%rbp)
    mov -8(%rbp),%rcx
S

put junk <<'S'
    mov %rax,-8(%rbp); nop
    mov -8(%rbp),%rax
S

put r8 <<'S'
    mov %r8,-24(%rbp)
    mov -24(%rbp),%r8
S

compare() {
  python3 tests/fs/count_store_reload.py "$1" >$T/py.out 2>/dev/null; pr=$?
  $T/count_store_reload "$1" >$T/fo.out 2>/dev/null; fr=$?
  if [ $pr = $fr ] && cmp -s $T/py.out $T/fo.out; then
    echo "PASS count-store-reload $2 (out=$(cat $T/fo.out) rc=$fr)"
  else
    echo "FAIL count-store-reload $2 (py rc=$pr out=$(cat $T/py.out), forge rc=$fr out=$(cat $T/fo.out))"
    fail=1
  fi
}

for n in empty one-pair two-pairs diff-reg diff-off pos-off ws gap eax rcx junk r8; do
  compare "$T/$n.s" "$n"
done

# Real compiler output: --fs-temps has at least one pair; --fs-ssa has none.
build/cudc tests/fs/ssa.cud $T/t_ssa.s --fs-temps || { echo "FAIL count-store-reload compile-temps"; exit 1; }
compare "$T/t_ssa.s" temps
temps_n=$(cat $T/fo.out)
[ "$temps_n" -ge 1 ] || { echo "FAIL count-store-reload temps-nonzero"; fail=1; }
build/cudc tests/fs/ssa.cud $T/t_ssa.s --fs-ssa || { echo "FAIL count-store-reload compile-ssa"; exit 1; }
compare "$T/t_ssa.s" ssa
[ "$(cat $T/fo.out)" = 0 ] || { echo "FAIL count-store-reload ssa-zero"; fail=1; }

$T/count_store_reload $T/missing.s 2>$T/e; r=$?
[ $r = 1 ] && grep -q "count_store_reload: cannot read" $T/e && echo "PASS count-store-reload missing-input" || { echo "FAIL count-store-reload missing-input"; fail=1; }

exit $fail
