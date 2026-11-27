#!/usr/bin/env python3
"""Phase 6.1 proof manifest: seal a Forge user ELF with a verifier-produced trailer.

usage: cudseal.py [--module] [--v2] [--extra-key KEY2] [--alg-id N] [--proof-byte] SRC.cud IMAGE KEYFILE BASELINE
       cudseal.py --foreign IMAGE KEYFILE   (11.1e: a foreign Linux-ABI program, e.g. BusyBox)

Runs `cudc --unsafe-report` on SRC (the verifier: type/unsafe checking happens there) and refuses
to seal unless the unsafe counts are zero or within the audited entry in BASELINE. Declared
capabilities come from a `# cuditor: caps(a, b, ...)` line in SRC. KEYFILE is the 32-byte Ed25519
private seed (build-only; the kernel embeds just the public key).

Seal v3 (default, plan v1.3) appends a 384-byte trailer:
  +0..+64 as v2 below, with version 3
  +64  SHA-256(ELF bytes)   +96 proof slot (32 bytes, reserved: must be zero)
  +128 signature count (1..3)   +136 reserved (0)
  +144 three 80-byte signature slots: algorithm ID (u64; 1 = Ed25519, the only one implemented),
       key ID (first 8 bytes of the public key), signature (64 bytes)
  Every slot signs M = trailer[0:64] || SHA-256(trailer[64:144]) (96 bytes).
  --extra-key adds a second signature (slot 0) by another key; --alg-id / --proof-byte make
  negative test images (signed correctly, but an unknown algorithm ID / a filled proof slot).
--v2 writes the previous 160-byte trailer, which the kernel still reads:
  +0  "FORGEPRF"   +8 version (2)   +16 safety level   +24 unsafe ops (whole program)
  +32 caps mask    +40 ELF length   +48 main-file unsafe ops   +56 kind (0 user program, 1 kernel module: --module)
  +64 SHA-256(ELF bytes)            +96 Ed25519 signature (R || S) over trailer[0:96]
--foreign: level 3, no unsafe counts (the Forge verifier never saw the program), caps 0; refused
unless the ELF is a Linux ABI image (EI_OSABI = 3, or EI_OSABI = 0 with a PT_GNU_RELRO program
header, as in most static musl builds). Incudela fld images are OSABI 0 without GNU_RELRO and stay
refused. The kernel re-checks the same rule.
Safety level: 2 = no unsafe code at all in the program's own file (only the audited ulib),
1 = unsafe counts match the audited baseline. 0 is reserved for "no unsafe anywhere"."""
import hashlib, os, re, struct, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ed25519

SEAL3 = 384

def v3(head, digest, keys, alg=1, proof=False):
    """head: the 7 u64 fields after the magic (version included); keys: Ed25519 seeds in slot order"""
    t = MAGIC + struct.pack('<7Q', *head) + digest
    t += (b'\x01' if proof else b'\x00') + bytes(31)
    t += struct.pack('<2Q', len(keys), 0)
    m = t[0:64] + hashlib.sha256(t[64:144]).digest()
    for k in keys:
        t += struct.pack('<Q', alg) + ed25519.public(k)[:8] + ed25519.sign(k, m)
    t += bytes(SEAL3 - len(t))
    assert len(t) == SEAL3
    return t

def sealed(elf):
    return elf[-160:-152] == MAGIC or elf[-SEAL3:-SEAL3 + 8] == MAGIC

CAPS = {'fs': 1, 'spawn': 2, 'ipc': 4, 'drv': 8, 'kexec': 16, 'probe': 32, 'ktest': 64, 'grant': 128, 'gfx': 256}
MAGIC = b'FORGEPRF'

PT_GNU_RELRO = 0x6474e552

def is_linux_elf(elf):
    # EI_OSABI = 3, or EI_OSABI = 0 (System V / most static musl builds) with PT_GNU_RELRO.
    # Incudela fld images are also OSABI 0 but do not emit GNU_RELRO.
    if elf[:4] != b'\x7fELF' or len(elf) < 64:
        return False
    if elf[7] == 3:
        return True
    if elf[7] != 0 or elf[4] != 2:
        return False
    phoff = struct.unpack_from('<Q', elf, 32)[0]
    phentsz, phnum = struct.unpack_from('<HH', elf, 54)
    if phentsz != 56:
        return False
    for i in range(phnum):
        o = phoff + i * phentsz
        if o + 4 > len(elf):
            return False
        if struct.unpack_from('<I', elf, o)[0] == PT_GNU_RELRO:
            return True
    return False

def foreign(img, keyf):
    elf = open(img, 'rb').read()
    if not is_linux_elf(elf):
        sys.exit(f'cudseal: {img}: --foreign needs a Linux ABI ELF (EI_OSABI = 3, or OSABI 0 with PT_GNU_RELRO)')
    if sealed(elf):
        sys.exit(f'cudseal: {img}: already sealed')
    t = v3((3, 3, 0, 0, len(elf), 0, 0), hashlib.sha256(elf).digest(), [open(keyf, 'rb').read()])
    open(img, 'wb').write(elf + t)
    print(f'sealed {os.path.basename(img)}: level 3 (foreign), caps 0x0')

def main():
    kind = 0
    ver, extra, alg, proof = 3, None, 1, False
    while sys.argv[1].startswith('--'):
        o = sys.argv.pop(1)
        if o == '--module':
            kind = 1
        elif o == '--v2':
            ver = 2
        elif o == '--extra-key':
            extra = open(sys.argv.pop(1), 'rb').read()
        elif o == '--alg-id':
            alg = int(sys.argv.pop(1))
        elif o == '--proof-byte':
            proof = True
        else:
            sys.exit(f'cudseal: unknown option {o}')
    src, img, keyf, base = sys.argv[1:5]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    fc = os.path.join(root, 'build/cudc')
    d, f = os.path.dirname(os.path.abspath(src)), os.path.basename(src)
    r = subprocess.run([fc, f, '/dev/null', '--unsafe-report'], cwd=d, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f'cudseal: {src}: verifier rejected the program:\n{r.stderr}')
    lines = (r.stdout + r.stderr).splitlines()
    m = [re.match(r'unsafe: (\d+) functions, (\d+) blocks, (\d+) ops, (\d+) top-level', l) for l in lines]
    m = [x for x in m if x]
    if not m:
        sys.exit(f'cudseal: {src}: no unsafe report')
    cnt = tuple(int(x) for x in m[-1].groups())
    own = sum(int(x.group(1)) for x in (re.match(rf'unsafe: \S*{re.escape(f)}:\d+ .*ops=(\d+)', l) for l in lines) if x)
    rel = os.path.relpath(d, root)
    audited = None
    for l in open(base):
        p = l.split()
        if len(p) == 6 and p[0] == rel and p[1] == f:
            audited = tuple(int(x) for x in p[2:])
    if cnt == (0, 0, 0, 0):
        level = 0
    elif audited and all(a <= b for a, b in zip(cnt, audited)):
        level = 2 if own == 0 else 1
    else:
        sys.exit(f'cudseal: {src}: unsafe counts {cnt} are not in the audited baseline; refusing to seal')
    caps = 0
    for l in open(src):
        mm = re.match(r'#\s*cuditor:\s*caps\((.*)\)', l)  # the pre-rename forge: was read until 0.22.0
        if mm:
            for c in filter(None, (x.strip() for x in mm.group(1).split(','))):
                if c not in CAPS:
                    sys.exit(f'cudseal: {src}: unknown capability {c!r}')
                caps |= CAPS[c]
    elf = open(img, 'rb').read()
    if sealed(elf):
        sys.exit(f'cudseal: {img}: already sealed')
    key = open(keyf, 'rb').read()
    head = (ver, level, cnt[2], caps, len(elf), own, kind)
    if ver == 2:
        t = MAGIC + struct.pack('<7Q', *head) + hashlib.sha256(elf).digest()
        t += ed25519.sign(key, t)
        assert len(t) == 160
    else:
        t = v3(head, hashlib.sha256(elf).digest(), ([extra] if extra else []) + [key], alg, proof)
    open(img, 'wb').write(elf + t)
    print(f'sealed {os.path.basename(img)} (v{ver}): level {level}, {cnt[2]} unsafe ops, caps 0x{caps:x}')

if len(sys.argv) == 3 and sys.argv[1] == '--pub':
    sys.stdout.buffer.write(ed25519.public(open(sys.argv[2], 'rb').read()))
elif len(sys.argv) == 4 and sys.argv[1] == '--foreign':
    foreign(sys.argv[2], sys.argv[3])
else:
    main()
