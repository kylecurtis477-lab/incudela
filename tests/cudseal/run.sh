#!/bin/sh
# tests/cudseal: tools/cudseal.cud must seal byte-identically to tools/cudseal.py (the reference):
# same sealed image, stdout, stderr and exit status for v3 (default), --extra-key (two slots, and an
# empty key file = no extra slot), --v2, --alg-id, --proof-byte, --module, caps lines, an EI_OSABI = 3
# image, --foreign, --pub (seeds of several lengths) and the error paths with a Python message
# (already sealed, not in the baseline, unknown capability, unknown option, verifier rejection,
# --foreign on a non-Linux ELF). Unreadable inputs: Python dies with a traceback, Forge with
# "cudseal: PATH: cannot read ..."; both must exit 1.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf $T' EXIT
S=build/cudseal.t   # must sit directly in build/: the repo root is dirname(dirname(/proc/self/exe))
build/cudc tools/cudseal.cud $T/s.s && build/fas -o $T/s.o $T/s.s && build/fld --base 0x100000000000 -o $S $T/s.o || { echo "FAIL cudseal build"; exit 1; }
trap 'rm -rf $T $S' EXIT
fail=0
BL=tests/unsafe/baseline.txt
python3 -c "import random; r=random.Random(7); [open('$T/k%d'%n,'wb').write(bytes(r.randrange(256) for _ in range(n))) for n in (0,1,32,100)]"
mkdir -p $T/u
for p in hello cat captest lxtest; do
  build/cudc examples/user/$p.cud $T/u/$p.s && build/fas -o $T/u/$p.o $T/u/$p.s && build/fld -o $T/u/$p.raw $T/u/$p.o || { echo "FAIL cudseal build $p"; fail=1; }
done
python3 -c "import sys; d=bytearray(open(sys.argv[1],'rb').read()); d[7]=3; open(sys.argv[2],'wb').write(d)" $T/u/lxtest.raw $T/u/lxtest.lx
build/cudc examples/modules/hello.cud $T/u/mod.s && build/fas -o $T/u/mod.raw $T/u/mod.s || fail=1
printf 'print(1)\n' > $T/plain.cud
# scratch copies of hello with other caps lines (the user .cudi files alongside, for its include)
cp examples/user/*.cudi $T/
{ printf '# cuditor: caps(fs, bogus)\n'; grep -v 'caps()' examples/user/hello.cud; } > $T/badcap.cud
{ printf '#forge:  caps( ipc ,, grant)  # note\n# cuditor: caps()\n#   forge:caps(spawn)\n'; grep -v 'caps()' examples/user/hello.cud; } > $T/caps.cud
printf 'def f(:\n' > $T/syntax.cud
: > $T/empty.txt
# an audited baseline for the scratch sources (relpath from the repo root, as cudseal computes it)
R=$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], os.getcwd()))" $T)
for f in caps badcap; do echo "$R $f.cud 999 999 999 999"; done > $T/bl.txt
printf '# comment\n%s caps.cud 1 2\n' "$R" >> $T/bl.txt
# chk NAME IMAGE-OR-- ARGS...: run both on fresh copies of IMAGE (named alike), compare everything
chk() {
  n=$1; img=$2; shift 2
  rm -rf $T/p $T/f; mkdir $T/p $T/f
  if [ "$img" != - ]; then cp $img $T/p/img; cp $img $T/f/img; fi
  a=$(echo "$*" | sed "s|@|$T/p/img|g"); b=$(echo "$*" | sed "s|@|$T/f/img|g")
  python3 tools/cudseal.py $a >$T/p.out 2>$T/p.err; pr=$?
  $S $b >$T/f.out 2>$T/f.err; fr=$?
  sed -i "s|$T/p/|X/|g" $T/p.err $T/p.out; sed -i "s|$T/f/|X/|g" $T/f.err $T/f.out
  if [ $pr = $fr ] && cmp -s $T/p.out $T/f.out && cmp -s $T/p.err $T/f.err && { [ "$img" = - ] || cmp -s $T/p/img $T/f/img; }; then
    echo "PASS cudseal $n (rc=$fr)"
  else echo "FAIL cudseal $n (rc py=$pr forge=$fr)"; head -3 $T/p.err $T/f.err; fail=1; fi
}
U=examples/user
chk "v3 hello" $T/u/hello.raw $U/hello.cud @ $T/k32 $BL
chk "v3 cat --extra-key" $T/u/cat.raw --extra-key $T/k100 $U/cat.cud @ $T/k32 $BL
chk "empty --extra-key" $T/u/cat.raw --extra-key $T/k0 $U/cat.cud @ $T/k32 $BL
chk "v3 captest caps" $T/u/captest.raw $U/captest.cud @ $T/k1 $BL
# the caps line is read, not only compared: cat.cud says `# cuditor: caps(fs)` (the new spelling) and a scratch copy
# with the pre-rename `# forge: caps(fs)` must give the same mask (inv165: both tools read only `forge:`, so cat
# was sealed with caps 0 and every boot panicked at its seal check)
cp $T/u/cat.raw $T/cat1.img; python3 tools/cudseal.py $U/cat.cud $T/cat1.img $T/k32 $BL > $T/c1.out 2>&1
cp $T/u/cat.raw $T/cat2.img; $S $U/cat.cud $T/cat2.img $T/k32 $BL > $T/c2.out 2>&1
{ sed 's/^# cuditor: caps(/# forge: caps(/' $U/cat.cud > $T/catold.cud; } && grep -q '^# forge: caps(fs)' $T/catold.cud
echo "$R catold.cud $(grep "^examples/user cat.cud " $BL | cut -d' ' -f3-)" >> $T/bl.txt
cp $T/u/cat.raw $T/cat3.img; $S $T/catold.cud $T/cat3.img $T/k32 $T/bl.txt > $T/c3.out 2>&1
if grep -q "caps 0x1$" $T/c1.out && grep -q "caps 0x1$" $T/c2.out && grep -q "caps 0x1$" $T/c3.out; then echo "PASS cudseal caps-spellings (cuditor: and forge: both give caps 0x1)"
else echo "FAIL cudseal caps-spellings"; cat $T/c1.out $T/c2.out $T/c3.out | head -6; fail=1; fi
chk "--v2" $T/u/hello.raw --v2 $U/hello.cud @ $T/k32 $BL
chk "--alg-id 2" $T/u/hello.raw --alg-id 2 $U/hello.cud @ $T/k32 $BL
chk "--proof-byte" $T/u/hello.raw --proof-byte $U/hello.cud @ $T/k32 $BL
chk "all options" $T/u/hello.raw --module --proof-byte --alg-id 7 --extra-key $T/k1 $U/hello.cud @ $T/k100 $BL
chk "--v2 --module" $T/u/mod.raw --v2 --module examples/modules/hello.cud @ $T/k32 $BL
chk "--module" $T/u/mod.raw --module examples/modules/hello.cud @ $T/k32 $BL
chk "EI_OSABI=3 lxtest" $T/u/lxtest.lx $U/lxtest.cud @ $T/k32 $BL
chk "caps parse, own baseline" $T/u/hello.raw $T/caps.cud @ $T/k32 $T/bl.txt
chk "relative src" $T/u/hello.raw ./examples/user/../user/hello.cud @ $T/k32 $BL
chk "--foreign" $T/u/lxtest.lx --foreign @ $T/k32
for k in 0 1 32 100; do chk "--pub ${k}B seed" - --pub $T/k$k; done
# error paths
python3 tools/cudseal.py $U/hello.cud $T/u/hello.raw.s $T/k32 $BL >/dev/null 2>&1
cp $T/u/hello.raw $T/sealed; python3 tools/cudseal.py $U/hello.cud $T/sealed $T/k32 $BL >/dev/null
cp $T/u/hello.raw $T/sealed2; python3 tools/cudseal.py --v2 $U/hello.cud $T/sealed2 $T/k32 $BL >/dev/null
chk "already sealed v3" $T/sealed $U/hello.cud @ $T/k32 $BL
chk "already sealed v2" $T/sealed2 $U/hello.cud @ $T/k32 $BL
chk "foreign already sealed" $T/sealed --foreign @ $T/k32
chk "foreign not Linux ABI" $T/u/hello.raw --foreign @ $T/k32
chk "not in baseline" $T/u/hello.raw $U/hello.cud @ $T/k32 $T/empty.txt
chk "not in baseline (scratch)" $T/u/hello.raw $T/plain.cud @ $T/k32 $BL
chk "unknown capability" $T/u/hello.raw $T/badcap.cud @ $T/k32 $T/bl.txt
sed -i "1s/.*/# cuditor: caps(fs, ipc) x)/" $T/badcap.cud
chk "greedy caps group" $T/u/hello.raw $T/badcap.cud @ $T/k32 $T/bl.txt
chk "unknown option" $T/u/hello.raw --bogus $U/hello.cud @ $T/k32 $BL
chk "verifier rejected" $T/u/hello.raw $T/syntax.cud @ $T/k32 $BL
for c in "$U/hello.cud $T/nope $T/k32 $BL" "$U/hello.cud $T/u/hello.raw $T/nope $BL" "$U/hello.cud $T/u/hello.raw $T/k32 $T/nope" "--foreign $T/nope $T/k32" "--pub $T/nope"; do
  cp $T/u/hello.raw $T/u/h.bak
  $S $c >/dev/null 2>$T/e; r=$?
  cp $T/u/h.bak $T/u/hello.raw
  if [ $r = 1 ] && grep -q "^cudseal: .*cannot read" $T/e; then echo "PASS cudseal missing input ($c)"; else echo "FAIL cudseal missing input ($c) rc=$r"; fail=1; fi
done
exit $fail
