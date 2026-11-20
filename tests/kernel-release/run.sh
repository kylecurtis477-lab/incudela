#!/bin/sh
# tests/kernel-release (inv213): the release kernel omits the test/debug boot diagnostics and the test/debug
# kernel keeps them. `build/kernel-build --release` (and the reference examples/kernel/build.sh --release, which
# must give the same output, exit code and build/kernel-release bytes) compiles kernel.cud with krelease.cudi in
# place of kdebug.cudi. Checked in the assembly and the linked ELF:
#   release: no hang probe (kdbg_hang_probe's "hang probe:" line, probe_put), no "KASLR: kernel image at",
#            "KASLR: big heap at" or "unslid .text"; still relocatable (.krel, image KASLR itself stays on) and
#            ktest_hooks still gates syscalls 408/409 (the sys_kexec / drv checks are in both builds)
#   test/debug (build/kernel, what the OS tests boot): all of them present
# Needs build/ (cudc, fas, fld) and build/kernel from the default kernel build (run_tests.sh builds it first).
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
./cuditor examples/kernel/build.cud -o build/kernel-build >/dev/null || { echo "FAIL kernel-release/build"; exit 1; }
rm -rf build/kernel-release; sh examples/kernel/build.sh --release >$T/s.out 2>$T/s.err; rs=$?
rm -rf $T/sh; cp -a build/kernel-release $T/sh 2>/dev/null
rm -rf build/kernel-release; (cd / && "$OLDPWD/build/kernel-build" --release >$T/f.out 2>$T/f.err); rf=$?
man() { (cd $1 2>/dev/null && find . -type f | sort | xargs stat -c '%a %n' && find . -type f | sort | xargs sha256sum); }
man $T/sh >$T/m1; man build/kernel-release >$T/m2
if [ $rs = 0 ] && [ $rf = 0 ] && cmp -s $T/s.out $T/f.out && cmp -s $T/s.err $T/f.err && cmp -s $T/m1 $T/m2 && [ "$(wc -l <$T/m2)" = 6 ]; then
  echo "PASS kernel-release/build-matches-script ($(sha256sum < build/kernel-release/kernel.elf | cut -c1-16))"
else
  echo "FAIL kernel-release/build-matches-script (rc $rs/$rf)"; diff $T/m1 $T/m2 | head -5; head -3 $T/f.err; fail=1
fi
R=build/kernel-release; D=build/kernel
# debug-only code: the strings must be absent from the release .elf and present in the test/debug one (cudc emits
# string literals as bytes, so they are looked for in the ELF), the functions absent from the release .s
for pat in "hang probe:" "KASLR: kernel image at" "KASLR: big heap at" "unslid .text"; do
  nr=$(grep -ac -- "$pat" $R/kernel.elf 2>/dev/null); nd=$(grep -ac -- "$pat" $D/kernel.elf 2>/dev/null)
  [ "${nr:-x}" = 0 ] && [ "${nd:-0}" -gt 0 ] || { echo "FAIL kernel-release/debug-only-omitted (string '$pat': release ${nr:-none}, test/debug ${nd:-none})"; fail=1; bad=1; }
done
for fn in kdbg_hang_probe probe_put kdbg_kaslr_image kdbg_kaslr_dyn kdbg_kaslr_unslid; do
  # release keeps the kdbg_* hook names as empty stubs: their bodies must not call or print anything
  nr=$(awk -v f="$fn:" '$0 == f {on = 1; next} /^[A-Za-z_.][A-Za-z0-9_.]*:$/ && on {exit} on && /call|lea .*\.LS|lea .*rip/ {n++} END {print n + 0}' $R/kernel.s 2>/dev/null)
  hd=$(grep -c "^$fn:$" $D/kernel.s 2>/dev/null)
  [ "$fn" = probe_put ] && nr=$(grep -c "^$fn:$" $R/kernel.s 2>/dev/null)
  [ "${nr:-x}" = 0 ] && [ "${hd:-0}" = 1 ] || { echo "FAIL kernel-release/debug-only-omitted ($fn: release ${nr:-none}, test/debug ${hd:-none})"; fail=1; bad=1; }
done
[ -z "$bad" ] && echo "PASS kernel-release/debug-only-omitted (hang probe and KASLR layout lines: absent from the release kernel, present in build/kernel)"
# what stays in release: image KASLR (relocation table, slide pick, alias unmap) and the ktest_hooks gate
if grep -aq "^kaslr_pick:" $R/kernel.s && grep -aq "^kaslr_unmap:" $R/kernel.s && grep -aq "ktest_hooks" $R/kernel.s \
   && [ "$(grep -ac 'ktest_hooks' $R/kernel.s)" = "$(grep -ac 'ktest_hooks' $D/kernel.s)" ]; then
  echo "PASS kernel-release/kaslr-and-gates-kept (kaslr_pick, kaslr_unmap; ktest_hooks references $(grep -ac 'ktest_hooks' $R/kernel.s) in both)"
else
  echo "FAIL kernel-release/kaslr-and-gates-kept"; fail=1
fi
rm -rf build/kernel-release
exit $fail
