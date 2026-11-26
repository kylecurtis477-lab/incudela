#!/bin/bash
# Item 9: Linux writable files on /data, only on an explicitly created Incudela FS partition.
# Builds incudela-part, adds a 16 MiB Incudela partition to a copy of the GPT disk, boots the
# kernel ISO with that image as NVMe (ESP stays the read-only virtio disk), and runs `run lxwrite`
# in the compat sandbox. After the boot, every byte outside the Incudela partition must be unchanged.
# Invoked from tests/os/run.sh after the ISO and vdisk exist:
#   bash tests/os/lxwrite.sh $B $L $Q $VD
B=$1; L=$2; shift 2
ISO=build/kernel/forge.iso
[ -x "$B" ] && [ -f "$ISO" ] || { echo "FAIL os/lxwrite (need boot harness and $ISO)"; exit 0; }
[ -f build/efi/disk.img ] || { echo "FAIL os/lxwrite (need build/efi/disk.img)"; exit 0; }
T=$(mktemp -d /tmp/forge-lxwrite.XXXXXX)
trap 'rm -rf $T' EXIT
# the Forge build of the partition tool (byte-identical to incudela-part.py per tests/incudela-part)
if ! build/cudc tools/incudela-part.cud $T/fp.s >/dev/null 2>$L/lxwrite-tool.err \
   || ! build/fas -o $T/fp.o $T/fp.s >/dev/null 2>>$L/lxwrite-tool.err \
   || ! build/fld --base 0x100000000000 -o $T/incudela-part $T/fp.o >/dev/null 2>>$L/lxwrite-tool.err; then
  echo "FAIL os/lxwrite (incudela-part build failed)"
  exit 0
fi
cp build/efi/disk.img $T/nv.img
$T/incudela-part create $T/nv.img 16 --yes-add-incudela-partition >$T/tool.out
# sha256 of the image with the Incudela partition's range (if any) masked out
snap() { python3 - "$1" <<'P'
import sys,struct,hashlib,uuid
f=open(sys.argv[1],'rb'); d=f.read(); h=d[512:604]; elba,n=struct.unpack_from('<QI',h,72)
F=uuid.UUID('D0C2E3A1-6B7F-4F0A-9E11-466F72676546').bytes_le; lo=hi=0
for i in range(n):
    e=d[elba*512+i*128:elba*512+i*128+128]
    if e[:16]==b'\0'*16: continue
    s,l=struct.unpack_from('<QQ',e,32)
    if e[:16]==F: lo,hi=s*512,(l+1)*512
print(hashlib.sha256(d[:lo]+d[hi:]).hexdigest())
P
}
S0=$(snap $T/nv.img)
FB=${FORGE_BOOT_LXWRITE_FB:-"back == front^KERNEL OK"}
MARK="Incudela FS:|linux: Linux ABI personality ready (48 syscalls)|sh: run lxwrite: 2 grants from its manifest|lxwrite: ESP write EROFS, reserved /data names EACCES|lxwrite: create/write/read/append/unlink/O_EXCL on /data/lxwrite.dat|lxwrite: PASS (|[lxwrite exited 0 (sandboxed)]|KERNEL OK|debug-exit "
# no user key: objstore stays locked; ffs_test still formats and writes persist.dat / hello.txt
out=$(FORGE_BOOT_LXWRITE=1 $B lxwrite-boot $L/lxwrite.log 360 "$MARK" "$FB" -- "$@" \
  -drive file=$T/nv.img,format=raw,if=none,id=nv,cache=writethrough -device nvme,drive=nv,serial=forge-nv0 \
  -boot d -cdrom $ISO 2>&1) || true
echo "$out" >$L/lxwrite-boot.out
if ! echo "$out" | grep -q "^PASS os/lxwrite-boot "; then
  ts=$(date '+%Y%m%d-%H%M%S')
  cp -a $L/lxwrite.log /workspace/forge-logs/lxwrite-$ts.fail.log 2>/dev/null || true
  cp -a $L/lxwrite-boot.out /workspace/forge-logs/lxwrite-$ts.fail-boot.out 2>/dev/null || true
  echo "FAIL os/lxwrite (boot [$out])"
  exit 0
fi
S1=$(snap $T/nv.img)
if [ "$S1" != "$S0" ]; then
  echo "FAIL os/lxwrite (bytes outside the Incudela partition changed)"
  exit 0
fi
echo "PASS os/lxwrite"
exit 0
