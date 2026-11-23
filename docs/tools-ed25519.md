# ed25519 (tools/ed25519.cud)

This is the Cuditor port of the signing side of `tools/ed25519.py` (RFC 8032 Ed25519).

    ed25519 public SEEDFILE          32-byte public key on stdout   (= ed25519.public(seed))
    ed25519 sign SEEDFILE MSGFILE    64-byte signature on stdout    (= ed25519.sign(seed, msg))
    ed25519 hexpublic SEEDFILE       the public key as 64 lowercase hex digits and a newline
    ed25519 hexsign SEEDFILE MSGFILE the signature as 128 lowercase hex digits and a newline
    ed25519 verify PUBHEX SIGHEX MSGFILE
                                     exit 0 if valid, 1 if not (message at most 96 bytes)

- The seed file is hashed as-is, so any length works, as in the Python version. A standard key is 32 bytes.
- The message file is streamed twice: once for r and once for the challenge. Its size has no limit.
- Exit codes: 2 with a usage line on stderr for bad arguments, 1 when a file can't be read.
- `verify` runs `ed25519_verify` from `examples/kernel/ed25519.cudi`, the same code the kernel uses for sealed
  images, so it takes at most 96 message bytes (that function's limit). It exits 0 for a valid signature, 1 for
  an invalid one, and 2 for bad usage, hex that is not exactly 64/128 lowercase digits, a message over 96 bytes,
  or an unreadable message file. `cuditor pkg` uses `hexsign` and `verify` for registry index signatures.

## How it works

It's a freestanding (`# cuditor: no-runtime`) Linux program with its own `_start` and raw syscalls. It includes
`examples/kernel/ed25519.cudi`, the kernel's verifier (a TweetNaCl port), and reuses that file's SHA-512,
GF(2^255-19) and point code. On top of that it adds:

- key clamping
- `sc_muladd`, which computes S = (r + h·a) mod L

The only `@unsafe` code reads argv, parses and prints hex, and makes the syscalls.

## Status and tests

`tools/ed25519.py` stays as the reference. The keypair step (`ed_key`) and `sc_muladd` live in `tools/ed25519sign.cudi`,
shared with `tools/cudseal.cud`, which signs seal trailers with the same code.

tests/ed25519-tool/run.sh compares the output byte for byte with the Python version on 26 vectors and checks the
RFC 8032 known answers. It also checks that `hexpublic`/`hexsign` print the same bytes as hex on all 26 vectors, and
that `verify` accepts the RFC 8032 test 1 signature, round-trips our signatures at 8 message lengths up to 96
bytes, and rejects another message, a changed signature, the wrong key (exit 1), a 97-byte message, 5 malformed
hex forms and a missing file (exit 2). tests/ed25519 still checks the kernel verifier against `cryptography`.
