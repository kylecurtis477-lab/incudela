#!/bin/bash
# tests/os/boot-ok-stop.sh B L [qemu args...]: boot the kernel ISO with the framebuffer check, and
# delay 6 s after KERNEL OK (FORGE_BOOT_DELAY_AFTER_OK) before the screendump. The kernel bounds its
# wait for 'q' with rdtsc (tsc_per_ms * 5000, examples/kernel/kernel.cud). A 6 s delay with the
# vCPUs still running lets that wait expire and qemu_exit before the dump — the inv236
# bootpol-config-strict failure (there a 38 s box suspend jumped guest TSC; a plain delay is the
# deterministic equivalent, because SIGSTOP of QEMU does not jump TSC). The new harness issues
# QEMU monitor `stop` first, so the same delay cannot expire the wait. Fails on the pre-stop
# harness; passes on the new one. A failed screendump still FAILs (tests/os/boot-early-exit.sh).
B=$1; L=$2; shift 2
FB=${FORGE_BOOT_OK_STOP_FB:-"back == front^KERNEL OK"}
ISO=build/kernel/forge.iso
[ -x "$B" ] && [ -f "$ISO" ] || { echo "FAIL os/boot-harness-delay-after-ok (need boot harness and $ISO)"; exit 0; }
out=$(FORGE_BOOT_DELAY_AFTER_OK=6 FORGE_BOOT_NO_RETRY=1 $B ok-screendump-stop $L/ok-screendump-stop.log 200 "KERNEL OK" "$FB" -- "$@" 2>&1) || true
echo "$out" | grep -q "^PASS os/ok-screendump-stop " && grep -q "delayed 6s after KERNEL OK" $L/ok-screendump-stop.log && grep -qE "^debug-exit [0-9]+ ms after KERNEL OK" $L/ok-screendump-stop.log && echo "PASS os/boot-harness-delay-after-ok" || echo "FAIL os/boot-harness-delay-after-ok ([$out])"
