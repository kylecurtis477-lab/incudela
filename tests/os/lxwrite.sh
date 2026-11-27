#!/bin/bash
# Item 9: Linux writable files on /data, only on an explicitly created Incudela FS partition.
# Builds incudela-part, adds a 16 MiB Incudela partition to a copy of the GPT disk, boots the
# kernel ISO with that image as NVMe (ESP stays the read-only virtio disk), and runs `run lxwrite`
# in the compat sandbox. After the boot, every byte outside the Incudela partition must be unchanged
# (snap() hashes the image with that GPT range masked out; it is plain shell, not python3,
# and must match the former helper). After `run lxwrite` exits, the same boot kexecs with
# that NVMe disk and the ESP virtio-blk attached; the log must contain NVMe MSI-X vector
# 0x53, kexec handoff OK, "NVMe: MSI-X Enable on handoff: off", and
# "virtio-blk: MSI-X Enable on handoff: off".
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
# sha256 of the image with the Incudela partition's range (if any) masked out.
# The type GUID is D0C2E3A1-6B7F-4F0A-9E11-466F72676546 in GPT mixed-endian
# bytes. If that type is absent, lo=hi=0 and the hash covers the whole image.
# Plain shell (od, dd, sha256sum); same digest as the former python3 helper.
snap() {
  _img=$1
  _elba=$(od -An -t u8 -N 8 -j 584 "$_img" | tr -d ' \n')
  _n=$(od -An -t u4 -N 4 -j 592 "$_img" | tr -d ' \n')
  _lo=0
  _hi=0
  _i=0
  while [ "$_i" -lt "$_n" ]; do
    _off=$((_elba * 512 + _i * 128))
    _typ=$(od -An -t x1 -N 16 -j $_off "$_img" | tr -d ' \n')
    if [ "$_typ" = "a1e3c2d07f6b0a4f9e11466f72676546" ]; then
      _s=$(od -An -t u8 -N 8 -j $((_off + 32)) "$_img" | tr -d ' \n')
      _l=$(od -An -t u8 -N 8 -j $((_off + 40)) "$_img" | tr -d ' \n')
      _lo=$((_s * 512))
      _hi=$(((_l + 1) * 512))
    fi
    _i=$((_i + 1))
  done
  {
    [ "$_lo" -gt 0 ] && dd if="$_img" bs=512 count=$((_lo / 512)) status=none
    dd if="$_img" bs=512 skip=$((_hi / 512)) status=none
  } | sha256sum | awk '{print $1}'
}
S0=$(snap $T/nv.img)
FB=${FORGE_BOOT_LXWRITE_FB:-"back == front^KERNEL OK"}
MARK="Incudela FS:|linux: Linux ABI personality ready (48 syscalls)|sh: run lxwrite: 2 grants from its manifest|lxwrite: ESP write EROFS, reserved /data names, ., .., control names EACCES|lxwrite: create/write/read/append/unlink/O_EXCL on /data/lxwrite.dat|lxwrite: stale fd after unlink/recreate -> ESTALE|lxwrite: O_TRUNC sparse hole is zeros|lxwrite: MAP_SHARED /data is coherent with read/write|lxwrite: PASS (|[lxwrite exited 0 (sandboxed)]|KERNEL OK|NVMe: I/O completions on MSI-X vector 0x53|NVMe: MSI-X Enable on handoff: off|virtio-blk: MSI-X Enable on handoff: off|kexec handoff OK|debug-exit "
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
