#!/bin/sh
# Ed25519 verifier (examples/kernel/ed25519.cudi) against vectors from tests/ed25519/gen.cud (signed by
# tools/ed25519.cud). The generated program must equal the committed edtest.cud byte for byte.
# FORGE_ED25519_PY=1 also runs gen.py (signatures from `cryptography`, independent of the Forge signer)
# and requires the same program and expectations.
cd "$(dirname "$0")"
B=../../build/ed25519; mkdir -p $B
../../build/cudc ../../tools/ed25519.cud $B/sign.s && ../../build/fas -o $B/sign.o $B/sign.s && ../../build/fld -o $B/sign $B/sign.o || { echo "FAIL ed25519/signer-build"; exit 1; }
../../cuditor gen.cud -o $B/gen >/dev/null || { echo "FAIL ed25519/gen-build"; exit 1; }
want=$($B/gen $B/edtest.cud $B/sign) || { echo "FAIL ed25519/gen"; exit 1; }
cmp -s $B/edtest.cud edtest.cud && echo "PASS ed25519/gen-matches-committed" || { echo "FAIL ed25519/gen-matches-committed"; exit 1; }
if [ "$FORGE_ED25519_PY" = 1 ]; then
  pw=$(python3 gen.py $B/edtest_py.cud) && [ "$pw" = "$want" ] && cmp -s $B/edtest_py.cud edtest.cud && echo "PASS ed25519/gen-matches-py" || { echo "FAIL ed25519/gen-matches-py"; exit 1; }
fi
../../build/cudc edtest.cud $B/edtest.s $CUDC_FLAGS && ../../build/fas -o $B/edtest.o $B/edtest.s && ../../build/fld -o $B/edtest $B/edtest.o || { echo "FAIL ed25519/build"; exit 1; }
got=$($B/edtest)
if [ "$got" = "$want" ]; then echo "PASS ed25519/verify ($want)"; else echo "FAIL ed25519/verify want $want got $got"; exit 1; fi
