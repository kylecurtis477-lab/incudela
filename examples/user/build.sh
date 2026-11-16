#!/bin/sh
# Build the Incudela user programs as static ELF64 executables (ring 3, loaded by the kernel's ELF loader),
# with --fs-opt (fs-mode register allocation; Phase 12.1 step 3c) and then $CUDC_FLAGS.
set -e
cd "$(dirname "$0")"
B=../../build/user; mkdir -p $B
# Sealing key: an Ed25519 seed generated once per build tree, never committed and never embedded;
# the kernel embeds only the public key (seal.pub)
# the sealer: tools/cudseal.cud (tools/cudseal.py is kept as the reference; tests/cudseal)
S=../../build/cudseal
../../build/cudc ../../tools/cudseal.cud $S.s && ../../build/fas -o $S.o $S.s && ../../build/fld --base 0x100000000000 -o $S $S.o
K=$B/seal.key
[ -s $K ] || head -c 32 /dev/urandom > $K
# a second, unrelated key: cat carries two signatures (seal v3 has room for several)
[ -s $B/seal2.key ] || head -c 32 /dev/urandom > $B/seal2.key
$S --pub $K > $B/seal.pub
for p in hello fault sh cat forktest blkd crash sum bg captest chantest sbtest grtest wxtest capdeny badptr kbdd kbdd2 nvmed nvmed2 gfxapp gfxdeny; do
  ../../build/cudc $p.cud $B/$p.s --fs-opt $CUDC_FLAGS
  ../../build/fas -o $B/$p.o $B/$p.s
  ../../build/fld -o $B/$p.elf $B/$p.o
  cp $B/$p.elf $B/$p.raw
  x=""; [ $p = cat ] && x="--extra-key $B/seal2.key"
  $S $x $p.cud $B/$p.elf $K ../../tests/unsafe/baseline.txt >/dev/null
done
# seal v3 checks: hello sealed in the old v2 format (still accepted), and two correctly signed v3
# negatives: an unknown signature algorithm ID, a filled (reserved) proof slot
cp $B/hello.raw $B/hellov2.elf; $S --v2 hello.cud $B/hellov2.elf $K ../../tests/unsafe/baseline.txt >/dev/null
cp $B/hello.raw $B/algbad.elf; $S --alg-id 2 hello.cud $B/algbad.elf $K ../../tests/unsafe/baseline.txt >/dev/null
cp $B/hello.raw $B/proofset.elf; $S --proof-byte hello.cud $B/proofset.elf $K ../../tests/unsafe/baseline.txt >/dev/null
# 6.3 negative images: an unsealed copy and a sealed copy with one code byte flipped
cp $B/hello.raw $B/unsealed.elf
python3 -c "import sys; d=bytearray(open(sys.argv[1],'rb').read()); d[0x1010]^=1; open(sys.argv[2],'wb').write(d)" $B/hello.elf $B/tampered.elf
# ... and a sealed copy whose manifest claims every capability (signature no longer matches)
python3 -c "import sys; d=bytearray(open(sys.argv[1],'rb').read()); d[-384+32]=0x7f; open(sys.argv[2],'wb').write(d)" $B/hello.elf $B/forged.elf
# 6.4: hello re-tagged as a Linux ABI binary (EI_OSABI = 3) and properly sealed: still refused
python3 -c "import sys; d=bytearray(open(sys.argv[1],'rb').read()); d[7]=3; open(sys.argv[2],'wb').write(d)" $B/hello.raw $B/linuxabi.elf
$S hello.cud $B/linuxabi.elf $K ../../tests/unsafe/baseline.txt >/dev/null
# 11.1: lxtest, a raw-syscall Linux x86-64 program: tagged EI_OSABI = 3 *before* sealing, so its seal
# covers the tag; the kernel runs it only through a sandboxed launch (sh `run lxtest`, docs/linux-compat.md)
../../build/cudc lxtest.cud $B/lxtest.s --fs-opt $CUDC_FLAGS
../../build/fas -o $B/lxtest.o $B/lxtest.s
../../build/fld -o $B/lxtest.raw $B/lxtest.o
python3 -c "import sys; d=bytearray(open(sys.argv[1],'rb').read()); d[7]=3; open(sys.argv[2],'wb').write(d)" $B/lxtest.raw $B/lxtest.elf
$S lxtest.cud $B/lxtest.elf $K ../../tests/unsafe/baseline.txt >/dev/null
# 11.1b: lxthreads (clone threads, futex, TLS), built and tagged the same way
../../build/cudc lxthreads.cud $B/lxthreads.s --fs-opt $CUDC_FLAGS
../../build/fas -o $B/lxthreads.o $B/lxthreads.s
../../build/fld -o $B/lxthreads.raw $B/lxthreads.o
python3 -c "import sys; d=bytearray(open(sys.argv[1],'rb').read()); d[7]=3; open(sys.argv[2],'wb').write(d)" $B/lxthreads.raw $B/lxthreads.elf
$S lxthreads.cud $B/lxthreads.elf $K ../../tests/unsafe/baseline.txt >/dev/null
# 11.1c: lxfs (openat, fstat, getdents64), built and tagged the same way
../../build/cudc lxfs.cud $B/lxfs.s --fs-opt $CUDC_FLAGS
../../build/fas -o $B/lxfs.o $B/lxfs.s
../../build/fld -o $B/lxfs.raw $B/lxfs.o
python3 -c "import sys; d=bytearray(open(sys.argv[1],'rb').read()); d[7]=3; open(sys.argv[2],'wb').write(d)" $B/lxfs.raw $B/lxfs.elf
$S lxfs.cud $B/lxfs.elf $K ../../tests/unsafe/baseline.txt >/dev/null
# 11.1d: lxexec (execve, execveat), built and tagged the same way
../../build/cudc lxexec.cud $B/lxexec.s --fs-opt $CUDC_FLAGS
../../build/fas -o $B/lxexec.o $B/lxexec.s
../../build/fld -o $B/lxexec.raw $B/lxexec.o
python3 -c "import sys; d=bytearray(open(sys.argv[1],'rb').read()); d[7]=3; open(sys.argv[2],'wb').write(d)" $B/lxexec.raw $B/lxexec.elf
$S lxexec.cud $B/lxexec.elf $K ../../tests/unsafe/baseline.txt >/dev/null
# 11.1d: lxsig part 2 (signals), built and tagged the same way
../../build/cudc lxsig.cud $B/lxsig.s --fs-opt $CUDC_FLAGS
../../build/fas -o $B/lxsig.o $B/lxsig.s
../../build/fld -o $B/lxsig.raw $B/lxsig.o
python3 -c "import sys; d=bytearray(open(sys.argv[1],'rb').read()); d[7]=3; open(sys.argv[2],'wb').write(d)" $B/lxsig.raw $B/lxsig.elf
$S lxsig.cud $B/lxsig.elf $K ../../tests/unsafe/baseline.txt >/dev/null
# 11.1e: BusyBox from verified source (tools/busybox), only when the source tarballs are on the box
if [ -f ${BB_SRC:-/workspace/bb}/busybox-1.38.0.tar.bz2 ]; then
    sh ../../tools/busybox/build.sh $B/busybox.elf $K
fi
