#!/bin/sh
# tests/c2cud: the C-to-Forge translator (tools/c2cud.cud, plan item 11.4).
# Step 1: the lexer's token dump of lex.c must match lex.expected; a bad character is a clean error (exit 1).
# Step 2+: each program in PROGS is translated to @unsafe freestanding Forge, built at -O2 and -O0, and its
# output must equal the gcc build of the same C (with shim.c providing put_i64/put_u64/nl via printf).
# Step 4: ptrs.c (pointers, arrays, structs); ptr-int-error: `int *p = 5;` is rejected (no implicit int->pointer).
# Step 5: floats.c (float/double, conversions, casts, void *); union-error and float-mod-error are clean errors.
# Step 6: pp.c (object-like #define/#undef, standard headers); fnmacro-error, if-error, header-error and
# typedef-without-header are clean errors.
# Step 7: lib.c, a first small real C library (zlib-style CRC-32 and Adler-32, the XTEA reference cipher),
# translated and run against the gcc build, including the standard check values for "123456789".
# 0.15.2: ints.c uses file-scope variables; pointer globals, non-constant global initializers and a local
# named like a global are clean errors. Array sizes may be integer constant expressions (arrconst.c);
# ++/-- works in expressions (incdec.c). String literals are values (strlit.c). Integer global initializers
# may be constant expressions (cinit.c), with clean errors for unsigned-and-negative, /0 and bad shifts.
# File-scope 1-D integer arrays take brace lists and T a[] = {...} takes its size from the list (braces.c);
# float and double globals take literal or constant initializers (fglobals.c); a non-constant float element,
# multi-dimensional file-scope brace lists and too many elements are clean errors. Tentative and
# extern redeclarations of a global merge (tentative.c); a second initializer or another type is an error. Remaining named errors
# are other rejected C, plus static locals and same-name inner-block shadowing. Listed in docs/BUILD_PLAN.md item 4.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf $T' EXIT
fail=0
PROGS="ints flow ptrs floats pp lib arrconst incdec strlit cinit braces tentative fglobals"
build/cudc tools/c2cud.cud $T/c2.s && build/fas -o $T/c2.o $T/c2.s && build/fld --base 0x100000000000 -o $T/c2cud $T/c2.o || { echo "FAIL c2cud build"; exit 1; }
$T/c2cud --tokens tests/c2cud/lex.c | cmp -s - tests/c2cud/lex.expected && echo "PASS c2cud lex" || { echo "FAIL c2cud lex"; fail=1; }
printf 'int x = @;\n' > $T/bad.c
out=$($T/c2cud --tokens $T/bad.c); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: unexpected character '@'" ] && echo "PASS c2cud lex-error" || { echo "FAIL c2cud lex-error (rc=$rc)"; fail=1; }
cp tests/fs/linux.cudi $T/linux.cudi
for p in $PROGS; do
  ok=1
  $T/c2cud tests/c2cud/$p.c $T/$p.cud || ok=0
  gcc -O1 -o $T/$p.ref tests/c2cud/$p.c tests/c2cud/shim.c 2>/dev/null && $T/$p.ref > $T/$p.want || ok=0
  for o in -O2 -O0; do
    [ $ok = 1 ] && build/cudc $T/$p.cud $T/$p.s $o && build/fas -o $T/$p.o $T/$p.s && build/fld -o $T/$p $T/$p.o && $T/$p > $T/$p.got && cmp -s $T/$p.got $T/$p.want || ok=0
  done
  [ $ok = 1 ] && echo "PASS c2cud $p (O2 and O0 output == gcc)" || { echo "FAIL c2cud $p"; fail=1; }
done
printf 'int main(void) { int x = 0; int y = ++(x + 1); return 0; }\n' > $T/inc.c
out=$($T/c2cud $T/inc.c $T/inc.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: ++/-- needs an lvalue (at ';')" ] && echo "PASS c2cud incdec-lvalue-error" || { echo "FAIL c2cud incdec-lvalue-error (rc=$rc out=$out)"; fail=1; }
printf 'int *gp; int main(void) { return 0; }\n' > $T/gv.c
out=$($T/c2cud $T/gv.c $T/gv.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: pointer global variables are not supported yet (at 'gp')" ] && echo "PASS c2cud global-pointer-error" || { echo "FAIL c2cud global-pointer-error (rc=$rc out=$out)"; fail=1; }
printf 'int g = 1; int main(void) { int g = 2; return g; }\n' > $T/gs.c
out=$($T/c2cud $T/gs.c $T/gs.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: local g shadows a global variable (not supported yet) (at 'g')" ] && echo "PASS c2cud global-shadow-error" || { echo "FAIL c2cud global-shadow-error (rc=$rc out=$out)"; fail=1; }
printf 'int n = 2; int g = n; int main(void) { return g; }\n' > $T/gi.c
out=$($T/c2cud $T/gi.c $T/gi.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: global initializer must be an integer constant (at 'n')" ] && echo "PASS c2cud global-init-error" || { echo "FAIL c2cud global-init-error (rc=$rc out=$out)"; fail=1; }
for c in "uns|unsigned g = -1 / 2u;|unsigned operand with a negative value in global initializer is not supported yet (at '-')" "div0|int g = 1 / (2 - 2);|division by zero in global initializer (at ';')" "shift|long g = 1L << 64;|shift count out of range in global initializer (at ';')"; do
  n=${c%%|*}; r=${c#*|}; src=${r%%|*}; want=${r#*|}
  printf '%s int main(void) { return 0; }\n' "$src" > $T/ce.c
  out=$($T/c2cud $T/ce.c $T/ce.cud); rc=$?
  [ $rc = 1 ] && [ "$out" = "c2cud: line 1: $want" ] && echo "PASS c2cud cinit-$n-error" || { echo "FAIL c2cud cinit-$n-error (rc=$rc out=$out)"; fail=1; }
done
for c in "many|int t[2] = {1, 2, 3};|too many initializers (at '3')" "float|double d[2] = {1.5, x};|a float global initializer must be a constant (at 'x')" "2d|int m[2][2] = {{1, 2}, {3, 4}};|a file-scope brace initializer needs a 1-D integer array (not supported yet) (at '{')"; do
  n=${c%%|*}; r=${c#*|}; src=${r%%|*}; want=${r#*|}
  printf '%s int main(void) { return 0; }\n' "$src" > $T/be.c
  out=$($T/c2cud $T/be.c $T/be.cud); rc=$?
  [ $rc = 1 ] && [ "$out" = "c2cud: line 1: $want" ] && echo "PASS c2cud braces-$n-error" || { echo "FAIL c2cud braces-$n-error (rc=$rc out=$out)"; fail=1; }
done
for c in "twice|int w = 1; int w = 2;|redefinition of w (at 'w')" "types|int v; long v;|conflicting types for v (at 'v')"; do
  n=${c%%|*}; r=${c#*|}; src=${r%%|*}; want=${r#*|}
  printf '%s int main(void) { return 0; }\n' "$src" > $T/te.c
  out=$($T/c2cud $T/te.c $T/te.cud); rc=$?
  [ $rc = 1 ] && [ "$out" = "c2cud: line 1: $want" ] && echo "PASS c2cud tentative-$n-error" || { echo "FAIL c2cud tentative-$n-error (rc=$rc out=$out)"; fail=1; }
done
printf 'int main(void) { char s[1] = "hi"; return 0; }\n' > $T/sl.c
out=$($T/c2cud $T/sl.c $T/sl.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: too many initializers (at ';')" ] && echo "PASS c2cud strlit-too-many-error" || { echo "FAIL c2cud strlit-too-many-error (rc=$rc out=$out)"; fail=1; }
printf 'int main(void) { int a[]; return 0; }\n' > $T/sa.c
out=$($T/c2cud $T/sa.c $T/sa.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: array needs a positive size (at ';')" ] && echo "PASS c2cud arrsize-unsized-error" || { echo "FAIL c2cud arrsize-unsized-error (rc=$rc out=$out)"; fail=1; }
printf 'int main(void) { int n = 4; int a[n]; return 0; }\n' > $T/ae.c
out=$($T/c2cud $T/ae.c $T/ae.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: array size must be an integer constant (at 'n')" ] && echo "PASS c2cud arrsize-vla-error" || { echo "FAIL c2cud arrsize-vla-error (rc=$rc out=$out)"; fail=1; }
printf 'int main(void) { int *p = 5; return 0; }\n' > $T/pi.c
out=$($T/c2cud $T/pi.c $T/pi.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: cannot convert i32 to ptr[i32] without a cast (at ';')" ] && echo "PASS c2cud ptr-int-error" || { echo "FAIL c2cud ptr-int-error (rc=$rc)"; fail=1; }
printf 'union u { int a; };\n' > $T/un.c
out=$($T/c2cud $T/un.c $T/un.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: unions are not supported (Forge has no unions) (at 'union')" ] && echo "PASS c2cud union-error" || { echo "FAIL c2cud union-error (rc=$rc)"; fail=1; }
printf 'int main(void) { double d = 1.0; int x = d %% 2; return 0; }\n' > $T/fm.c
out=$($T/c2cud $T/fm.c $T/fm.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: invalid float operands to % (at ';')" ] && echo "PASS c2cud float-mod-error" || { echo "FAIL c2cud float-mod-error (rc=$rc)"; fail=1; }
printf '#define SQ(x) ((x) * (x))\nint main(void) { return 0; }\n' > $T/fn.c
out=$($T/c2cud $T/fn.c $T/fn.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: function-like macro SQ is not supported (only object-like #define)" ] && echo "PASS c2cud fnmacro-error" || { echo "FAIL c2cud fnmacro-error (rc=$rc)"; fail=1; }
printf 'int x;\n#ifdef X\n#endif\n' > $T/if.c
out=$($T/c2cud $T/if.c $T/if.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 2: #ifdef is not supported (only #define, #undef, #include <standard header>)" ] && echo "PASS c2cud if-error" || { echo "FAIL c2cud if-error (rc=$rc)"; fail=1; }
printf '#include <stdio.h>\n' > $T/hd.c
out=$($T/c2cud $T/hd.c $T/hd.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: #include <stdio.h>: unsupported header (supported: <stdint.h> <stddef.h> <sys/types.h> <limits.h>)" ] && echo "PASS c2cud header-error" || { echo "FAIL c2cud header-error (rc=$rc)"; fail=1; }
printf 'uint32_t f(void) { return 1; }\n' > $T/td.c
$T/c2cud $T/td.c $T/td.cud >/dev/null; rc=$?
[ $rc = 1 ] && echo "PASS c2cud typedef-without-header" || { echo "FAIL c2cud typedef-without-header (rc=$rc)"; fail=1; }
printf 'int main(void) { static int x = 0; return x; }\n' > $T/st.c
out=$($T/c2cud $T/st.c $T/st.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: static local variables are not supported yet (at 'static')" ] && echo "PASS c2cud static-local-error" || { echo "FAIL c2cud static-local-error (rc=$rc out=$out)"; fail=1; }
printf 'int main(void) { int x = 1; { int x = 2; } return x; }\n' > $T/sh.c
out=$($T/c2cud $T/sh.c $T/sh.cud); rc=$?
[ $rc = 1 ] && [ "$out" = "c2cud: line 1: inner-block declaration of x shadows an outer variable (block scoping is not supported yet) (at 'x')" ] && echo "PASS c2cud shadow-error" || { echo "FAIL c2cud shadow-error (rc=$rc out=$out)"; fail=1; }
exit $fail
