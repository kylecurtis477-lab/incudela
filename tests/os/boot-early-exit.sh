#!/bin/bash
# tests/os/boot-early-exit.sh B L: the boot harness against a stub "QEMU" that drops its stdin (every fd but
# stdout/stderr) and exits before the harness sends 'q' after KERNEL OK (inv211). Before the fix the harness's
# write of 'q' to a pipe with no reader raised SIGPIPE and killed it silently (exit 141): no result line, no
# log, so os/kernel-iommu went missing in os211b. Now the result line must appear, the log must be written,
# and the boot is still judged from the serial log: a missing marker or a wrong exit code still FAILs.
# No QEMU runs here.
B=$1; L=$2
S=$L/early-exit-stub
rm -rf $S; mkdir -p $S
cat > $S/qemu-system-x86_64 <<'STUB'
#!/bin/bash
# no reader left on the harness's stdin pipe from here on, like a QEMU that already exited
exec 0<&-
for fd in $(seq 3 63); do eval "exec $fd<&-" 2>/dev/null; done
echo "stub up"
echo "KERNEL OK"
# stay alive (unreaped) long enough for the harness to write 'q' into the readerless pipe
sleep 2
exit ${STUB_RC:-33}
STUB
chmod +x $S/qemu-system-x86_64
bad=""
run() { # name rc markers [fbtext] -> sets out, ec
    out=$(STUB_RC=$2 PATH=$S:$PATH FORGE_BOOT_NO_RETRY=1 $B $1 $L/$1.log 30 "$3" "$4" -- -stub 2>&1); ec=$?
}
run early-exit 33 "stub up|KERNEL OK"
[ $ec = 0 ] || bad="$bad; harness exit $ec on an early exit (141 = killed by SIGPIPE)"
echo "$out" | grep -q "^PASS os/early-exit " || bad="$bad; no PASS line for a good log: [$out]"
grep -q "^rc=33$" $L/early-exit.log 2>/dev/null && grep -q "^\[harness\] " $L/early-exit.log || bad="$bad; early-exit log not written"
run early-exit-missing 33 "stub up|KERNEL OK|never printed"
[ $ec = 0 ] || bad="$bad; harness exit $ec (missing marker)"
echo "$out" | grep -q "^FAIL os/early-exit-missing (missing: never printed, qemu rc=33;" || bad="$bad; a missing marker did not FAIL: [$out]"
grep -q "^rc=33$" $L/early-exit-missing.log 2>/dev/null || bad="$bad; early-exit-missing log not written"
run early-exit-rc 1 "stub up|KERNEL OK"
[ $ec = 0 ] || bad="$bad; harness exit $ec (rc 1)"
echo "$out" | grep -q "^FAIL os/early-exit-rc (qemu rc=1;" || bad="$bad; a wrong exit code did not FAIL: [$out]"
# framebuffer check on: the screendump goes to the monitor FIFO of a QEMU that is gone, so it fails (and FAILs)
run early-exit-fb 33 "stub up|KERNEL OK" "KERNEL OK"
[ $ec = 0 ] || bad="$bad; harness exit $ec (framebuffer check)"
echo "$out" | grep -q "^FAIL os/early-exit-fb (framebuffer: screendump failed" || bad="$bad; a failed screendump did not FAIL: [$out]"
if [ -z "$bad" ]; then
    echo "PASS os/boot-harness-early-exit (result line and log after QEMU exits before 'q'; missing marker, rc 1 and a failed screendump still FAIL)"
else
    echo "FAIL os/boot-harness-early-exit (${bad#; })"
fi
