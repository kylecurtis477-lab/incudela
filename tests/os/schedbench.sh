#!/bin/bash
# tests/os/schedbench.sh: the scheduler benchmark (examples/kernel/kernel.cud sched_bench), not a test: timing never
# gates and tests/os/run.sh does not call it. The kernel ISO from build/kernel/iso (tests/os/run.sh or
# examples/kernel/build.cud) is rebuilt with `incudela.schedbench` on the multiboot2 command line and booted headless
# in QEMU (BIOS, multi-threaded TCG, or KVM when /dev/kvm is usable) once per CPU count (default 1 2 4, or the
# arguments). Right after the scheduler self-test the kernel runs 2 yielding threads and one mutex/condvar ping-pong
# pair per CPU for 200 LAPIC ticks (2 s) and prints one `schedbench:` line; QEMU is stopped once it appears. Prints
# that line per run (BENCH lines), exit 1 when a run gives no line within TIMEOUT seconds (default 300).
cd "$(dirname "$0")/../.."
T=$(mktemp -d /tmp/forge-schedbench.XXXXXX)
trap 'rm -rf $T' EXIT
TO=${TIMEOUT:-300}
[ -f build/kernel/iso/boot/grub/grub.cfg ] || { echo "schedbench: needs build/kernel/iso (build the kernel first)"; exit 1; }
cp -r build/kernel/iso $T/iso
sed -i 's|multiboot2 /boot/kernel.elf$|multiboot2 /boot/kernel.elf incudela.schedbench|' $T/iso/boot/grub/grub.cfg
grep -q 'incudela.schedbench' $T/iso/boot/grub/grub.cfg || { echo "schedbench: grub.cfg edit failed"; exit 1; }
env -u SOURCE_DATE_EPOCH grub-mkrescue -o $T/sb.iso $T/iso >/dev/null 2>&1 || { echo "schedbench: grub-mkrescue failed"; exit 1; }
ACC="-accel tcg,thread=multi"
[ -r /dev/kvm ] && [ -w /dev/kvm ] && ACC="-accel kvm"
rc=0
for n in ${@:-1 2 4}; do
  log=$T/sb$n.log
  qemu-system-x86_64 $ACC -cpu max -display none -no-reboot -net none -m 256 -smp $n -serial file:$log \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 -boot d -cdrom $T/sb.iso >/dev/null 2>&1 &
  qp=$!
  s=0
  while [ $s -lt $TO ] && kill -0 $qp 2>/dev/null && ! grep -qa '^schedbench: ' $log 2>/dev/null; do sleep 1; s=$((s + 1)); done
  kill $qp 2>/dev/null; wait $qp 2>/dev/null
  line=$(grep -a '^schedbench: ' $log 2>/dev/null | tr -d '\r')
  if [ -n "$line" ]; then echo "BENCH smp=$n ${ACC#-accel } $line"; else echo "schedbench: no result with -smp $n (last serial lines below)"; tail -n 5 $log; rc=1; fi
done
exit $rc
