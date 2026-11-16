#!/bin/sh
# tests/oldnames: every pre-rename spelling kept until 0.22.0 (# forge: pragmas, .forge modules, forge.toml /
# forge.lock, FORGEC_FLAGS, FORGE_GUID_SEED, ./forge, cudseal's forge: caps lines) still works, prints one
# "warning: ... is deprecated, use ..." line on stderr, and gives byte-for-byte the same output as the new
# spelling, which prints no warning. A control run without the setting must differ, so a spelling that was
# silently ignored could not pass.
cd "$(dirname "$0")/../.." || exit 1
# The O0 gate exports FORGEC_FLAGS=-O0 next to CUDC_FLAGS=-O0 (forge-harness/inv.sh), so an old spelling
# inherited from the environment would add its own warning; each check below sets the old names it tests itself.
unset FORGEC_FLAGS FORGE_GUID_SEED
D=$(pwd)
T=$(mktemp -d); trap 'rm -rf $T' EXIT
fail=0
ok() { echo "PASS oldnames $1"; }
bad() { echo "FAIL oldnames $1"; fail=1; }
# warned FILE OLD: exactly one deprecation line for OLD, and nothing else on stderr
warned() { [ "$(grep -c "deprecated" $1)" = 1 ] && grep -qF -- "$2 is deprecated" $1 && [ "$(wc -l < $1)" = 1 ]; }
# 1. # forge: pragmas, in a freestanding program (checked-ints changes its code, so the control differs)
mkdir $T/fs; cp tests/fs/linux.cudi $T/fs/
sed '2s/.*/# cuditor: checked-ints/' tests/fs/basic.cud > $T/fs/new.cud
sed 's/^# cuditor:/# forge:/' $T/fs/new.cud > $T/fs/old.cud
sed '2s/.*/# checked-ints off/' tests/fs/basic.cud > $T/fs/ctl.cud
for f in new old ctl; do build/cudc $T/fs/$f.cud $T/fs/$f.s 2>$T/fs/$f.err; done
if [ -s $T/fs/new.s ] && cmp -s $T/fs/new.s $T/fs/old.s && ! cmp -s $T/fs/new.s $T/fs/ctl.s && [ ! -s $T/fs/new.err ] \
  && [ "$(wc -l < $T/fs/old.err)" = 2 ] && grep -qF '`# forge: no-runtime` is deprecated, use `# cuditor: no-runtime`' $T/fs/old.err \
  && grep -qF '`# forge: checked-ints` is deprecated, use `# cuditor: checked-ints`' $T/fs/old.err
then ok "pragma (same code as # cuditor:, one warning per pragma)"; else bad "pragma"; head -3 $T/fs/old.err; fi
# 2. a .forge module found by import
mkdir $T/mn $T/mo
printf 'import helper\nprint(helper.f(6))\n' > $T/mn/main.cud; cp $T/mn/main.cud $T/mo/main.cud
printf 'def f(n):\n    return n * 7\n' > $T/mn/helper.cud; cp $T/mn/helper.cud $T/mo/helper.forge
(cd $T/mn && $D/build/cudc main.cud main.s 2>err) && (cd $T/mo && $D/build/cudc main.cud main.s 2>err)
if [ -s $T/mo/main.s ] && cmp -s $T/mn/main.s $T/mo/main.s && [ ! -s $T/mn/err ] && warned $T/mo/err 'module file helper.forge'
then ok "forge-module (same code as helper.cud, one warning)"; else bad "forge-module"; head -3 $T/mo/err; fi
# 3. FORGEC_FLAGS through ./cuditor (--fs-opt changes the freestanding code), and ./forge for the driver itself
F=$T/fs/new.cud
CUDC_FLAGS=--fs-opt ./cuditor $F -o $T/fnew 2>$T/fnew.err && env -u CUDC_FLAGS FORGEC_FLAGS=--fs-opt ./cuditor $F -o $T/fold 2>$T/fold.err \
  && env -u CUDC_FLAGS ./cuditor $F -o $T/fnone 2>/dev/null
if [ -s $T/fnew ] && cmp -s $T/fnew $T/fold && ! cmp -s $T/fnew $T/fnone && [ ! -s $T/fnew.err ] && warned $T/fold.err FORGEC_FLAGS
then ok "FORGEC_FLAGS (same binary as CUDC_FLAGS, one warning)"; else bad "FORGEC_FLAGS"; head -3 $T/fold.err; fi
env -u CUDC_FLAGS ./forge $F -o $T/dold 2>$T/dold.err
if cmp -s $T/fnone $T/dold && warned $T/dold.err ./forge; then ok "./forge (same binary as ./cuditor, one warning)"; else bad "./forge"; head -3 $T/dold.err; fi
# 4. FORGE_GUID_SEED: mkgpt and incudela-part, Cuditor and Python, same image as INCUDELA_GUID_SEED
build/cudc examples/efi/mkgpt.cud $T/m.s && build/fas -o $T/m.o $T/m.s && build/fld --base 0x100000000000 -o $T/mkgpt $T/m.o
build/cudc tools/incudela-part.cud $T/p.s && build/fas -o $T/p.o $T/p.s && build/fld --base 0x100000000000 -o $T/part $T/p.o
head -c 1048576 /dev/zero | tr '\0' 'E' > $T/esp.fat
for impl in cud py; do
  if [ $impl = cud ]; then M=$T/mkgpt; P=$T/part; else M="python3 examples/efi/mkgpt.py"; P="python3 tools/incudela-part.py"; fi
  env -u FORGE_GUID_SEED INCUDELA_GUID_SEED=77 $M $T/gnew.img $T/esp.fat 64 >/dev/null 2>$T/gnew.err
  env -u INCUDELA_GUID_SEED FORGE_GUID_SEED=77 $M $T/gold.img $T/esp.fat 64 >/dev/null 2>$T/gold.err
  env -u INCUDELA_GUID_SEED FORGE_GUID_SEED=78 $M $T/gctl.img $T/esp.fat 64 >/dev/null 2>/dev/null
  if cmp -s $T/gnew.img $T/gold.img && ! cmp -s $T/gnew.img $T/gctl.img && [ ! -s $T/gnew.err ] && warned $T/gold.err FORGE_GUID_SEED
  then ok "FORGE_GUID_SEED mkgpt-$impl"; else bad "FORGE_GUID_SEED mkgpt-$impl"; head -3 $T/gold.err; fi
  cp $T/gnew.img $T/pnew.img; cp $T/gnew.img $T/pold.img
  env -u FORGE_GUID_SEED INCUDELA_GUID_SEED=5 $P create $T/pnew.img 16 --yes-add-incudela-partition >$T/pnew.out 2>$T/pnew.err
  env -u INCUDELA_GUID_SEED FORGE_GUID_SEED=5 $P create $T/pold.img 16 --yes-add-incudela-partition >$T/pold.out 2>$T/pold.err
  if cmp -s $T/pnew.img $T/pold.img && cmp -s $T/pnew.out $T/pold.out && [ ! -s $T/pnew.err ] && warned $T/pold.err FORGE_GUID_SEED
  then ok "FORGE_GUID_SEED incudela-part-$impl"; else bad "FORGE_GUID_SEED incudela-part-$impl"; head -3 $T/pold.err; fi
done
# 5. forge.toml / forge.lock read by ./cuditor pkg
R=$D/tests/pkg/registry
cp -r tests/pkg/app $T/an; cp -r tests/pkg/app $T/ao; mv $T/ao/cuditor.toml $T/ao/forge.toml
(cd $T/an && $D/cuditor pkg --registry $R lock > out 2>err) && (cd $T/ao && $D/cuditor pkg --registry $R lock > out 2>err)
if [ -s $T/an/cuditor.lock ] && cmp -s $T/an/cuditor.lock $T/ao/cuditor.lock && cmp -s $T/an/out $T/ao/out && [ ! -s $T/an/err ] && warned $T/ao/err forge.toml
then ok "forge.toml (same lock as cuditor.toml, one warning)"; else bad "forge.toml"; head -3 $T/ao/err; fi
mv $T/ao/cuditor.lock $T/ao/forge.lock
(cd $T/an && $D/cuditor pkg --registry $R build -o $T/an/app > out 2>err) && (cd $T/ao && $D/cuditor pkg --registry $R build -o $T/an/app2 > out 2>err)
if cmp -s $T/an/app $T/an/app2 && [ ! -s $T/an/err ] && grep -q "forge.lock is deprecated" $T/ao/err && grep -q "forge.toml is deprecated" $T/ao/err && [ "$(grep -c deprecated $T/ao/err)" = 2 ]
then ok "forge.lock (same build as cuditor.lock, one warning each)"; else bad "forge.lock"; head -3 $T/ao/err; fi
exit $fail
