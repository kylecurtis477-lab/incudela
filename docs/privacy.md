# Private by design (Phase 10)

## 10.1 Per-user keys, objects encrypted at rest
Everything the object store puts on disk (`objects.log`, so every object, version and blob, including objfs
file names and contents) is encrypted and authenticated. The code is in `examples/kernel/crypt.cudi`
(primitives) and `examples/kernel/objd.cudi` (keys and the on-disk format). Both are safe Forge: no new
`@unsafe` code.

### Primitives (crypt.cudi)
- ChaCha20 block function (RFC 8439): `cc_key` (8 x 32-bit words), `cc_block(ctr, n0, n1, n2)`, `cc_word(i)`.
- SHA-256 (FIPS 180-4): `sh_init`, `sh_byte`, `sh_u64`, `sh_fin` (result in `sh_h`).
- HMAC-SHA256 (RFC 2104): `hm_setkey32` (or `hm_setkey_digest` for a hashed long key), `hm_begin`, feed the
  message with `sh_byte`/`sh_u64`, `hm_end` (MAC in `sh_h`). This is the real two-pass HMAC with the 0x36/0x5c
  padded key blocks, not SHA-256(key || message), which would be open to length extension. The first
  10.1 commit (2473aed) used that prefix-keyed form with 64-bit tags; it was replaced before 10.2.
- `ct_eq4(a, b)`: constant-time 256-bit compare (ORs the XOR of every word, then one branch-free reduction),
  used for every tag and the key check value.
- Known-answer tests, tests/fs/crypt.cud, at O2 and O0, every output word compared: RFC 8439 2.3.2
  (block function, all 16 words) and 2.4.2 (the 114-byte "Ladies and Gentlemen" encryption); SHA-256 of
  "abc", the 448-bit two-block FIPS message, "" and 1M x "a"; RFC 4231 HMAC-SHA256 cases 1, 2 and 6 (131-byte
  key, hashed first); `ct_eq4` equal and one-bit-different.

### Keys
- **User key (KEK).** The platform key (`od_tpm_present` is a placeholder for TPM sealing and always
  returns 0; see Limits): PBKDF2-HMAC-SHA256(passphrase, 128-bit salt, 20000 iterations) since inv228 (key slot
  v2, `pb_kdf` in crypt.cudi; known-answer vectors from RFC 7914 section 11 and openssl in tests/fs/crypt.cud). The passphrase (8..64 bytes) arrives as
  the QEMU fw_cfg file `opt/forge/userkey` (I/O ports 0x510/0x511, read through the `pio_add`/`pio_rd`/`pio_wr` safe
  wrappers) and is wiped from kernel memory once the store is opened. The KDF salt is a fourth independent PRF output
  of the entropy digest (HMAC(digest, "ksalt")), stored with the iteration count in `objects.key` words 16..19
  (version 2, salt, iterations), so a later, higher count leaves old slots readable. A **v1 slot** (made before
  inv228: those words are 0) still unlocks with the old KEK, SHA-256("frge-kek" || passphrase), and the boot log
  says so; any other version, or a count of 0 or above 2^24, is refused as a damaged slot. Slots are not upgraded in
  place: rewriting the only key block is not crash-safe, so v1-to-v2 rotation is planned with key rotation (inv229).
  The user key itself is never written anywhere.
- **Data key (DK).** Made at first mount from a SHA-256 pool of 512 TSC jitter samples and, since inv228, up to 32
  RDSEED and 32 RDRAND words when CPUID reports them (`hw_rand` in cpux.cudi; a missing, 0, all-ones or repeated
  value is refused and counted, never mixed; the boot log says how many of each went in); the digest is only a
  PRF key: DK = HMAC(digest, "dkey") and the wrap salt = HMAC(digest, "wsalt"), so the plaintext salt says nothing
  about DK (fix, inv228: the salt used to be digest words 0..3 and DK mixed those words with words 4..7, which left
  DK 128 unknown bits once the salt was read from the disk). It is stored only
  wrapped: `objects.key` (one Incudela FS block) holds magic `FORGEKEY`, uid 1000, a 128-bit salt,
  DK XOR HMAC(KEK, "wrap" || salt) and a 256-bit check value HMAC(KEK, "chk" || salt), compared in constant time,
  then the v2 KDF parameters above.
- **Two copies of the key file (inv229).** `objects.keyb` holds a second copy of the slot (made at first mount;
  on a store from before inv229 it is written from `objects.key` at the first unlock). A slot written since inv229
  also carries a generation (word 20) and the SHA-256 of its bytes 0..191 (words 24..27), which detects a torn or
  corrupted copy; it is not a MAC, the check value authenticates the key. Every rewrite goes first to the copy that
  is not current and is flushed before the other copy is written, so a crash leaves at least one intact copy of the
  old or the new slot. At unlock the intact copy with the higher generation is current, its key is the only one
  tried, and a missing, damaged or older other copy is rewritten from it (the boot log names the current copy and
  any rewrite). The slot fits in the first 512-byte sector of its block.
- **Passphrase change (inv229).** Boot with the current passphrase as `opt/forge/userkey` and the new one (8..64
  bytes) as fw_cfg file `opt/forge/newkey`, for example `-fw_cfg name=opt/forge/newkey,string=NEW`. After the
  unlock, the same data key is wrapped under PBKDF2 of the new passphrase with fresh wrap and KDF salts (from a new
  entropy pool) as the next generation, through the two-copy write; the data itself is not rewritten. Once the
  first copy is flushed the old passphrase opens nothing, even if the boot stops before the second copy is
  written: the newer intact copy supersedes the older one. Both passphrases are wiped after the open. Pass
  `newkey` for one boot only: a second boot with the old `userkey` is locked.
- **Working keys, separate for each job.** K_enc = HMAC(DK, "enc") is the ChaCha20 key and K_mac = HMAC(DK, "mac")
  the HMAC key; neither is stored, and they are independent PRF outputs, so the cipher and the MAC never share a key.
- **No key** (no TPM and no fw_cfg file): the store stays locked. Nothing is read, created or written, and
  the boot continues. **Wrong key** (the check value doesn't match): the mount is refused the same way, and the
  on-disk bytes are left untouched.

### On-disk format
- `objects.log` has `OD_NB` = 65 logical blocks (507 payload words each, enough for `OB_NL` = 32768 log words).
  Each logical block has two physical 4 KiB slots, A and B, so the file is 130 blocks.
- A slot holds words 0..506 of ciphertext, word 507 the write counter `wc`, and words 508..511 the full
  256-bit tag HMAC(K_mac, block || wc || ciphertext): **encrypt-then-MAC**. A slot is decrypted only after its
  tag verifies, so unauthenticated ciphertext is never processed.
- ChaCha20 nonce = (wc low 32 bits, wc high 32 bits, logical block); the ChaCha block counter runs over the 64
  keystream blocks of a slot. Every slot write takes a fresh `wc`, so a (K_enc, nonce) pair is never reused.
- **Counters are never reused**, including across reboots, torn writes, rewinds and tampering:
  - `objects.ctr` (two slots, each HMAC-tagged) holds a high-water mark. Before any counter above it is used,
    a new mark `wc + 4096` is written to the other slot and flushed; at mount the higher verified slot wins.
  - At mount `wc` resumes from the maximum of that mark and every counter word found in any log slot,
    verified or not, so even a torn or tampered slot's counter is skipped.
  - A rewind (Phase 9.4) or an objfs rewrite appends new log records, which go out in new slot writes with
    new counters; nothing is ever rewritten under an old counter.
- A write goes to the slot that is *not* current, so a torn write can never destroy the previous contents.
  At mount, each block uses the slot with a valid tag and the higher `wc`. If neither slot verifies, the block
  reads as zeros, and the log replay then truncates there exactly as for a torn tail (Phase 9.2).

### Threat model
Protected against: someone who gets the disk (or the image) while Forge is not running and does not know the
user key. They learn no object contents, file names inside the object store, or key material, and any change
they make to a log slot, the counter file or the key slot is detected (HMAC / check value) instead of being
decrypted or trusted: a changed slot is treated like a torn one, a changed key slot locks the store.
Not protected against:
- **Rollback.** Each slot is authenticated on its own, so an attacker can put back an older copy of the
  whole image, or destroy the newer slot of a block so the older authentic one is used. Detecting that needs
  a monotonic counter outside the disk (a TPM NV counter), which the test setup does not have.
- **Weak passphrases.** Since inv228 the KEK is salted (no precomputed tables, and the same passphrase on two disks
  gives two KEKs) and costs 20000 HMAC-SHA256 iterations per guess (about 0.5 s on QEMU TCG). That slows offline
  guessing on a stolen disk but does not stop it for a weak passphrase: PBKDF2 is not memory-hard, so GPUs guess
  fast. A v1 (pre-inv228) slot still has the unsalted single SHA-256 until it is rotated. A TPM-sealed key or a
  memory-hard KDF would fix this.
- **A running, compromised kernel**, physical memory attacks (keys live in kernel memory while mounted), and
  side channels other than tag comparison timing.
- **Denial of service.** Corrupting the disk can always make data unreadable; it cannot make forged data be accepted.

### Tests (tests/os/forgefs.sh, QEMU)
- **os/objstore-key-wrap:** boot 1 creates and wraps the data key; boot 3 unwraps it with the platform key.
- **os/objstore-no-plaintext:** the Incudela partition contains no object plaintext (`motd\0`, `notes\0`),
  and not the passphrase either. The written log slots do not compress with zlib.
- **os/objstore-wrong-key-locked:** a boot with a wrong passphrase and a boot with no key both report the
  store locked, and `objects.log`/`objects.key` are byte-identical afterwards.
- **os/objstore-key-entropy:** boot 1 reports 32 RDSEED and 32 RDRAND words mixed into the new data key (QEMU
  `-cpu max` has both) and none refused.
- **os/objstore-kdf-salted:** `objects.key` is a v2 slot with 20000 iterations and a nonzero KDF salt that is not
  the wrap salt; the host derives the KEK with `openssl kdf ... PBKDF2`, which gives the stored check value, and the
  old unsalted KEK does not; boots 1 and 3 report the v2 KDF.
- **os/objstore-data-key-independent:** the host unwraps DK from `objects.key` with the KEK (openssl), checks the
  key check value, and checks the old salt-to-DK relation holds for none of the four word pairs (on the old
  derivation it held for all four).
- **os/objstore-nonce-unique:** every written slot in the image has a distinct counter, and the durable
  high-water mark in `objects.ctr` is at least the highest of them.
- **os/objstore-tamper-rejected:** boot 6 runs on a copy of the image with one bit of the newest slot's
  ciphertext flipped; the HMAC rejects exactly one more slot than on the clean boot.
- **os/objstore-legacy-slot:** the host rewrites `objects.key` as the v1 slot for the same data key (wrapped and
  checked under the unsalted KEK, words 16..19 zero); boot 7 reports the legacy slot, unlocks it and reads the
  persisted store, and the slot is still v1 afterwards. `objects.keyb` is zeroed in the same image (a damaged
  copy), and the boot rewrites it from `objects.key`.
- **os/objstore-key-two-copies:** after boots 1-3, `objects.key` and `objects.keyb` hold the same generation-1
  slot whose bytes 192..223 are the SHA-256 of bytes 0..191, and no boot rewrote a copy.
- **os/objstore-key-copy-repair:** boot 8 runs with one byte of `objects.key`'s wrapped data key flipped; it
  unlocks from `objects.keyb`, reads the persisted store and rewrites `objects.key`, so both copies are the
  original slot again.
- **os/objstore-passphrase-change:** boot 9 changes the passphrase. Both copies become one generation-2 slot with
  new salts whose check value is the host's PBKDF2 of the new passphrase and which unwraps to the same data key;
  boot 10 with the old passphrase is locked and writes nothing, boot 11 with the new one reads the persisted store.
- **os/objstore-passphrase-change-crash:** the host rebuilds the state of a crash between the two writes
  (`objects.keyb` new, `objects.key` old); the old passphrase stays locked and writes nothing, the new one unlocks
  from `objects.keyb` and rewrites `objects.key`. With the generation comparison removed from the kernel, the old
  passphrase unlocks the stale copy and this test fails.
- The Phase 9 crash-recovery, rewind and /obj tests all run on the encrypted store.

### Limits
- **TPM sealing is not implemented.** No TPM device exists in the test setup (no swtpm), so `od_tpm_present`
  returns 0 and the fw_cfg platform key is used. Without a TPM, the passphrase protects the data.
- **No swap.** Cuditor has no swap, so there are no swap pages to encrypt.
- **One user per store.** Each store has one user key (uid 1000); there are no separate per-user stores yet.
- **Plaintext metadata.** Incudela FS metadata (file names, sizes, extents, and the plaintext `hello.txt`/`persist.dat`
  Incudela FS self-test files) is not encrypted. Only the object store is.
- **DK entropy.** RDSEED and RDRAND are mixed in when the CPU has them (inv228); on a CPU with neither, the data
  key rests on TSC jitter alone, which is weak. The CPU RNG is trusted only as one input of the pool.
- **No data-key rotation.** The passphrase can be changed (inv229), but the data key itself cannot be rotated
  yet, and v1 slots are not upgraded to v2 yet. Stores made before inv228's data-key fix keep their weaker data key
  until data-key rotation re-encrypts the object log. A passphrase change does not help against someone who
  already copied the disk while the old passphrase was in use: the old slot opens that copy.
- **Rollback and weak-passphrase guessing** are possible, see the threat model.
- **Key wrap.** The wrapped DK is XORed with a PRF output and checked through the KEK check value, not a
  standard AEAD key wrap; tampering with it only makes every tag fail (the store reads as empty / locked).

## 10.2 The grant ledger: revocable permissions on open handles

Phase 5.3 sandboxes an app launched with `run app`: sh opens the handles that `/efi/incudela/apps/app.mf`
lists (`read PATH`, `dir PATH`), restricts their rights, and calls `sys_exec_sandboxed`, which drops the
root capability. 10.2 turns each of those handles into a **grant** that the user can list and revoke while
the app runs.

### How it works (examples/kernel/grant.cudi)
- **Ledger.** `sandbox_enter` creates one entry per handle the launcher installed (fd > 2): id, app name,
  rights (`read`, or `dir` with LOOKUP), the path the handle was opened by, pid, state (active, revoked,
  ended), number of uses, and number of denied uses. There are 64 entries. Ids are never reused. A new
  grant takes a free entry or the oldest inactive one, so an active grant is never evicted. If all 64 are
  active, the handle is closed instead of being handed over untracked (fail closed).
- **The grant follows the object, not the fd.** The grant id is stored in the `File` object (`File.gid`), and
  the path it was opened by in `File.lab`. Every handle that shares that File (a `dup`, a forked child's
  copy, a handle passed over a channel) has the same grant. A file opened with `openat` through a granted
  directory gets the directory's grant id, so revoking the directory also cuts off files already opened
  through it.
- **Checked on every use.** `read`, `write`, `getdents`, `openat` (on the directory handle) and `dup` call
  `gr_use`. While the grant is active, the use is counted. Once it is revoked, the call returns EACCES. The
  first denial per grant is logged. A zero-length read is also checked, so an app can poll its handle.
  Revocation takes effect at the app's next syscall on any handle derived from the grant, mid-file, with no
  cooperation from the app.
- **Syscalls.** 428 `grant_revoke(app)` revokes every active grant of that app and returns how many it
  revoked (ENOENT if there were none). 429 `grant_list()` prints the ledger. Both need the new `grant`
  capability (CAPB_GRANT = 128, `# cuditor: caps(..., grant)`). Only sh declares it. An app cannot list or
  revoke grants.
- **sh.** `run app &` starts a sandboxed app in the background. `grants` prints the ledger. `revoke app`
  revokes the app's grants.
- When the app exits, its active grants become `ended` and stay in the ledger as history.
- Ledger messages are printed whole under the console lock, so they never interleave with app output.

### Tests (tests/os/run.sh, QEMU, BIOS and UEFI boots)
`run grtest &` holds one grant, `/efi/incudela/docs/big.bin` (96 KiB). grtest makes a dup of the handle and
reads the first 48 KiB, checking every byte. It prints `halfway`, then polls the handle with zero-length
reads. sh then runs `grants` (the entry is active), `revoke grtest` (sent only after `halfway` has
appeared), `wait` and `grants` again. Required log lines:
- `grants: grant 3 (grtest: read /efi/incudela/docs/big.bin) active for pid N`
- `grtest: halfway, 49152 of 98304 bytes read through grant fd 4`
- `grants: revoked grant 3 (...) from pid N after K uses` and `sh: revoked 1 grant(s) of grtest`
- the kernel's denial line `grant 3 (...): revoked; pid N read denied (EACCES)`
- `grtest: cut off mid-read at byte 49152: read, read on the earlier dup, and dup all return EACCES`
- the final ledger, showing sbtest's two grants `ended` and grtest's grant `revoked`

### Limits
- Revocation applies to **handles**. Data the app has already read stays in its memory. Revocation stops
  further access; it does not take back what was already read.
- The grant check runs at the syscall boundary. A read that is already in progress finishes; the next one
  is refused.
- Revocation is all-or-nothing per app (`revoke app`). There is no per-grant id revoke and no re-grant yet;
  to get access back, the app has to be relaunched.
- The ledger is in memory and is not carried across kexec (the handoff does not serialise `File.gid`, so
  carried handles are no longer granted). The 10.3 audit log is in memory too (see below).
- Grants cover the handles sh installs from a manifest. Handles that unsandboxed programs open are not
  ledgered: they hold the root capability anyway.

## 10.3 The audit log: every grant and every use

### How it works (`examples/kernel/audit.cudi`)
grant.cudi appends a record for each event on a granted handle: `granted` (when sh's sandbox launch
creates the grant), each **use** (read, write, getdents, openat through a granted directory, dup;
a zero-length read is logged as `poll`), each **denial** after revocation, `revoked by pid N` (the
revoking process) and `ended` (the app exited). A record holds the sequence number, grant id, pid,
event, operation, count, bytes moved and the LAPIC tick.

Consecutive uses of the same grant by the same pid with the same operation are merged into one record
with a count, and successful reads add their byte counts to it. Every use is still counted, in order,
but a polling loop does not flood the log. Records live in a 256-entry ring; the sequence counter counts
every record ever written, so the dump states how many were evicted.

Syscall 430 `audit_dump` (capability `grant`, which only sh declares; sh builtin `audit`) prints the log
under the console lock, then cross-checks it: for every grant in the ledger, the logged uses and denials
must equal the ledger's counters. If records were evicted, the check is skipped and the dump says so.

### Tests (tests/os/run.sh)
After the 10.2 revocation, the boot script runs `audit`. Required log lines include
`audit: N records, 0 evicted`, sbtest's `granted` / `openat x1` / `ended (app exited)` records, grtest's
`granted to grtest, /efi/incudela/docs/big.bin`, `read x12, 49152 bytes`, `revoked by pid N`,
`poll denied x1`, `read denied x2`, `dup denied x1`, and
`audit: ledger check: uses and denials match the ledger for all 3 grants`.

### Limits
- The log is in **kernel memory only**: it is lost at reboot, not carried across kexec, and not
  written to the object store.
- It is not signed or hash-chained. It is accurate against a confined app, but a compromised kernel
  can rewrite it.
- Only granted handles are audited. Unsandboxed programs hold the root capability and are not logged.
- Bytes are counted for reads (file and object handles); writes, getdents and openat count uses only.
- With more than 256 records, the oldest are evicted (counted) and the ledger cross-check is skipped.

