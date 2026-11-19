#!/bin/sh
# tests/oldnames: the pre-rename spellings (# forge: pragmas, .forge modules, forge.toml / forge.lock,
# FORGEC_FLAGS, FORGE_GUID_SEED, ./forge, cudseal's forge: caps lines, the forge.iommu= / forge.desktop boot
# keys) were read, with a warning, until 0.22.0, which removed them. Each check shows the old spelling has no
# effect: the output is the same as without it, nothing on stderr names it, and a control with the new spelling
# differs, so a spelling still honoured (even silently) could not pass.
cd "$(dirname "$0")/../.." || exit 1
# The O0 gate exports FORGEC_FLAGS=-O0 next to CUDC_FLAGS=-O0 (forge-harness/inv.sh); each check sets the old
# names it tests itself.
unset FORGEC_FLAGS FORGE_GUID_SEED
D=$(pwd)
T=$(mktemp -d); trap 'rm -rf $T' EXIT
fail=0
ok() { echo "PASS oldnames $1"; }
bad() { echo "FAIL oldnames $1"; fail=1; }
# quiet FILE: no deprecation warning and no mention of an old name on stderr
quiet() { ! grep -q -i -e deprecated -e forge $1; }
# 1. # forge: pragmas are plain comments now: the same code as the line renamed to another comment, unlike # cuditor:
mkdir $T/fs; cp tests/fs/linux.cudi $T/fs/
sed '2s/.*/# cuditor: checked-ints/' tests/fs/basic.cud > $T/fs/new.cud
sed '2s/.*/# forge: checked-ints/' tests/fs/basic.cud > $T/fs/old.cud
sed '2s/.*/# old: checked-ints/' tests/fs/basic.cud > $T/fs/ctl.cud
for f in new old ctl; do build/cudc $T/fs/$f.cud $T/fs/$f.s 2>$T/fs/$f.err; done
if [ -s $T/fs/old.s ] && cmp -s $T/fs/old.s $T/fs/ctl.s && ! cmp -s $T/fs/new.s $T/fs/old.s && quiet $T/fs/old.err
then ok "pragma (# forge: is a comment, same code as without it)"; else bad "pragma"; head -3 $T/fs/old.err; fi
# 2. a .forge module is not found by import (helper.cud is)
mkdir $T/mn $T/mo
printf 'import helper\nprint(helper.f(6))\n' > $T/mn/main.cud; cp $T/mn/main.cud $T/mo/main.cud
printf 'def f(n):\n    return n * 7\n' > $T/mn/helper.cud; cp $T/mn/helper.cud $T/mo/helper.forge
(cd $T/mn && $D/build/cudc main.cud main.s 2>err); (cd $T/mo && $D/build/cudc main.cud main.s 2>err); mo=$?
if [ -s $T/mn/main.s ] && [ ! -s $T/mn/err ] && ! cmp -s $T/mn/main.s $T/mo/main.s 2>/dev/null && quiet $T/mo/err
then ok "forge-module (helper.forge is not imported)"; else bad "forge-module (rc $mo)"; head -3 $T/mo/err; fi
# 3. FORGEC_FLAGS is not read by ./cuditor (--fs-opt changes the freestanding code), and ./forge is gone
F=$T/fs/new.cud
CUDC_FLAGS=--fs-opt ./cuditor $F -o $T/fnew 2>/dev/null && env -u CUDC_FLAGS FORGEC_FLAGS=--fs-opt ./cuditor $F -o $T/fold 2>$T/fold.err \
  && env -u CUDC_FLAGS ./cuditor $F -o $T/fnone 2>/dev/null
if [ -s $T/fold ] && cmp -s $T/fnone $T/fold && ! cmp -s $T/fnew $T/fold && quiet $T/fold.err
then ok "FORGEC_FLAGS (ignored: same binary as no flags)"; else bad "FORGEC_FLAGS"; head -3 $T/fold.err; fi
if [ ! -e ./forge ] && [ "$(git ls-files forge)" = "" ]; then ok "./forge (removed)"; else bad "./forge (still present)"; fi
# 4. FORGE_GUID_SEED is not read: mkgpt and incudela-part, Cuditor and Python, give random GUIDs, not the seeded image
build/cudc examples/efi/mkgpt.cud $T/m.s && build/fas -o $T/m.o $T/m.s && build/fld --base 0x100000000000 -o $T/mkgpt $T/m.o
build/cudc tools/incudela-part.cud $T/p.s && build/fas -o $T/p.o $T/p.s && build/fld --base 0x100000000000 -o $T/part $T/p.o
head -c 1048576 /dev/zero | tr '\0' 'E' > $T/esp.fat
for impl in cud py; do
  if [ $impl = cud ]; then M=$T/mkgpt; P=$T/part; else M="python3 examples/efi/mkgpt.py"; P="python3 tools/incudela-part.py"; fi
  env -u FORGE_GUID_SEED INCUDELA_GUID_SEED=77 $M $T/gnew.img $T/esp.fat 64 >/dev/null 2>/dev/null
  env -u FORGE_GUID_SEED INCUDELA_GUID_SEED=77 $M $T/gnew2.img $T/esp.fat 64 >/dev/null 2>/dev/null
  env -u INCUDELA_GUID_SEED FORGE_GUID_SEED=77 $M $T/gold.img $T/esp.fat 64 >/dev/null 2>$T/gold.err
  if [ -s $T/gold.img ] && cmp -s $T/gnew.img $T/gnew2.img && ! cmp -s $T/gnew.img $T/gold.img && quiet $T/gold.err
  then ok "FORGE_GUID_SEED mkgpt-$impl (ignored)"; else bad "FORGE_GUID_SEED mkgpt-$impl"; head -3 $T/gold.err; fi
  cp $T/gnew.img $T/pnew.img; cp $T/gnew.img $T/pold.img
  env -u FORGE_GUID_SEED INCUDELA_GUID_SEED=5 $P create $T/pnew.img 16 --yes-add-incudela-partition >/dev/null 2>/dev/null
  env -u INCUDELA_GUID_SEED FORGE_GUID_SEED=5 $P create $T/pold.img 16 --yes-add-incudela-partition >/dev/null 2>$T/pold.err
  if [ -s $T/pold.img ] && ! cmp -s $T/pnew.img $T/pold.img && ! cmp -s $T/gnew.img $T/pold.img && quiet $T/pold.err
  then ok "FORGE_GUID_SEED incudela-part-$impl (ignored)"; else bad "FORGE_GUID_SEED incudela-part-$impl"; head -3 $T/pold.err; fi
done
# 5. ./cuditor pkg reads only cuditor.toml / cuditor.lock
R=$D/tests/pkg/registry
cp -r tests/pkg/app $T/an; cp -r tests/pkg/app $T/ao; mv $T/ao/cuditor.toml $T/ao/forge.toml
(cd $T/an && $D/cuditor pkg --registry $R lock > out 2>err); (cd $T/ao && $D/cuditor pkg --registry $R lock > out 2>err); ao=$?
if [ -s $T/an/cuditor.lock ] && [ $ao != 0 ] && [ ! -e $T/ao/cuditor.lock ] && grep -q "missing file cuditor.toml" $T/ao/err && ! grep -q deprecated $T/ao/err
then ok "forge.toml (not read: missing cuditor.toml)"; else bad "forge.toml (rc $ao)"; head -3 $T/ao/err; fi
cp $T/an/cuditor.toml $T/ao/cuditor.toml; cp $T/an/cuditor.lock $T/ao/forge.lock
(cd $T/ao && $D/cuditor pkg --registry $R build -o $T/ao/app > out 2>err); ab=$?
if [ $ab != 0 ] && [ ! -e $T/ao/app ] && grep -q "no cuditor.lock" $T/ao/err && ! grep -q deprecated $T/ao/err
then ok "forge.lock (not read: no cuditor.lock)"; else bad "forge.lock (rc $ab)"; head -3 $T/ao/err; fi
# 6. the kernel reads only the incudela. boot keys: the built kernel has no forge.iommu= / forge.desktop key
K=build/kernel/kernel.elf
if [ -s $K ] && grep -q -a 'incudela\.iommu=' $K && grep -q -a 'incudela\.desktop' $K && ! grep -q -a -e 'forge\.iommu=' -e 'forge\.desktop' $K \
  && ! grep -q -e '"forge\.iommu="' -e '"forge\.desktop"' examples/kernel/*.cud examples/kernel/*.cudi
then ok "boot keys (only incudela.iommu= and incudela.desktop in kernel.elf)"; else bad "boot keys"; fi
exit $fail
