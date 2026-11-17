#!/bin/sh
# Build the test kernel modules as relocatable ELF64 objects (.ko = plain assembler (tools/fas) output, ET_REL).
set -e
cd "$(dirname "$0")"
B=../../build/modules; mkdir -p $B
# the sealer: tools/cudseal.cud (tools/cudseal.py is kept as the reference; tests/cudseal)
S=../../build/cudseal
../../build/cudc ../../tools/cudseal.cud $S.s && ../../build/fas -o $S.o $S.s && ../../build/fld --base 0x100000000000 -o $S $S.o
for m in hello badabi unresolved newer tty1 tty2 getpid2; do
  ../../build/cudc $m.cud $B/$m.s --fs-ssa $CUDC_FLAGS
  ../../build/fas -o $B/$m.ko $B/$m.s
  cp $B/$m.ko $B/$m.raw
  $S --module $m.cud $B/$m.ko ../../build/user/seal.key ../../tests/unsafe/baseline.txt >/dev/null
done
# negative modules: unsealed, one code byte flipped after sealing, a sealed user program
cp $B/hello.raw $B/unsealed.ko
cp $B/tty1.raw $B/tty1u.ko
python3 -c "import sys; d=bytearray(open(sys.argv[1],'rb').read()); d[0x50]^=1; open(sys.argv[2],'wb').write(d)" $B/hello.ko $B/tampered.ko
cp ../../build/user/hello.elf $B/userimg.ko
