#!/bin/sh
# tools/ed25519.cud must produce byte-identical public keys and signatures to tools/ed25519.py
# (the reference), over RFC 8032 vectors, random seeds of several lengths and message sizes that
# cross SHA-512 block and the tool's 64 KiB read-buffer boundaries; plus usage/IO errors.
cd "$(dirname "$0")/../.." || exit 1
B=build/ed25519-tool; T=$(mktemp -d); trap 'rm -rf $T' EXIT; mkdir -p $B
build/cudc tools/ed25519.cud $B/ed.s && build/fas -o $B/ed.o $B/ed.s && build/fld -o $B/ed25519 $B/ed.o || { echo "FAIL ed25519-tool/build"; exit 1; }
fail=0
python3 - "$T" <<'P' || fail=1
import os, sys, random
d = sys.argv[1]; random.seed(25519)
c = []
# RFC 8032 7.1 test 1 (empty message) and test 2 (one byte)
c.append(bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')); c.append(b'')
c.append(bytes.fromhex('4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb')); c.append(bytes([0x72]))
for n in [0, 1, 31, 32, 33, 100]:
    c.append(bytes(random.randrange(256) for _ in range(n))); c.append(b'abc')
for m in [55, 63, 64, 95, 96, 97, 111, 112, 127, 128, 129, 1000, 65536 - 64, 65536, 65537, 200003]:
    c.append(bytes(random.randrange(256) for _ in range(32))); c.append(os.urandom(m))
c.append(bytes(32)); c.append(b'\xff' * 300)
c.append(b'\xff' * 32); c.append(b'')
for i in range(0, len(c), 2):
    open('%s/s%d' % (d, i // 2), 'wb').write(c[i]); open('%s/m%d' % (d, i // 2), 'wb').write(c[i + 1])
open(d + '/n', 'w').write(str(len(c) // 2))
P
n=$(cat $T/n); i=0; ok=0
while [ $i -lt $n ]; do
  $B/ed25519 public $T/s$i > $T/gp; r1=$?
  $B/ed25519 sign $T/s$i $T/m$i > $T/gs; r2=$?
  python3 -c "import sys; sys.path.insert(0, 'tools'); import ed25519 as e
s = open('$T/s$i', 'rb').read(); m = open('$T/m$i', 'rb').read()
open('$T/wp', 'wb').write(e.public(s)); open('$T/ws', 'wb').write(e.sign(s, m))"
  if [ $r1 = 0 ] && [ $r2 = 0 ] && cmp -s $T/gp $T/wp && cmp -s $T/gs $T/ws; then ok=$((ok + 1)); else echo "FAIL ed25519-tool/vector $i (seed $(wc -c < $T/s$i)B, msg $(wc -c < $T/m$i)B)"; fail=1; fi
  i=$((i + 1))
done
echo "PASS ed25519-tool/identical public+sign: $ok/$n vectors"
[ $ok = $n ] || fail=1
# RFC 8032 known answers (independent of the Python reference)
want=e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b
got=$($B/ed25519 sign $T/s0 $T/m0 | od -An -tx1 | tr -d ' \n')
[ "$got" = "$want" ] && echo "PASS ed25519-tool/rfc8032 test 1 signature" || { echo "FAIL ed25519-tool/rfc8032 test 1 got $got"; fail=1; }
want=3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c
got=$($B/ed25519 public $T/s1 | od -An -tx1 | tr -d ' \n')
[ "$got" = "$want" ] && echo "PASS ed25519-tool/rfc8032 test 2 public key" || { echo "FAIL ed25519-tool/rfc8032 test 2 got $got"; fail=1; }
# errors
for args in "" "public" "sign $T/s0" "bogus $T/s0" "public $T/s0 extra" "hexpublic" "hexsign $T/s0" "verify a b" "verify a b c d"; do
  $B/ed25519 $args > $T/o 2> $T/e; r=$?
  if [ $r = 2 ] && [ ! -s $T/o ] && grep -q '^usage: ed25519 public|hexpublic SEEDFILE | ed25519 sign|hexsign SEEDFILE MSGFILE | ed25519 verify PUBHEX SIGHEX MSGFILE$' $T/e; then echo "PASS ed25519-tool/usage '$args' rc=2"; else echo "FAIL ed25519-tool/usage '$args' rc=$r"; fail=1; fi
done
$B/ed25519 public $T/nope > $T/o 2> $T/e; r=$?
[ $r = 1 ] && [ ! -s $T/o ] && grep -q 'cannot read seed file' $T/e && echo "PASS ed25519-tool/missing seed rc=1" || { echo "FAIL ed25519-tool/missing seed rc=$r"; fail=1; }
$B/ed25519 sign $T/s0 $T/nope > $T/o 2> $T/e; r=$?
[ $r = 1 ] && [ ! -s $T/o ] && grep -q 'cannot read message file' $T/e && echo "PASS ed25519-tool/missing message rc=1" || { echo "FAIL ed25519-tool/missing message rc=$r"; fail=1; }
# hex verbs: the same key and signature as public/sign, as lowercase hex and a newline
ok=0; i=0
while [ $i -lt $n ]; do
  [ "$($B/ed25519 hexpublic $T/s$i)" = "$($B/ed25519 public $T/s$i | od -An -tx1 -v | tr -d ' \n')" ] && [ "$($B/ed25519 hexsign $T/s$i $T/m$i)" = "$($B/ed25519 sign $T/s$i $T/m$i | od -An -tx1 -v | tr -d ' \n')" ] && [ "$($B/ed25519 hexpublic $T/s$i | wc -l)" = 1 ] && ok=$((ok + 1)) || { echo "FAIL ed25519-tool/hex vector $i"; fail=1; }
  i=$((i + 1))
done
echo "PASS ed25519-tool/hexpublic+hexsign match public+sign: $ok/$n vectors"
# verify: the kernel verifier (examples/kernel/ed25519.cudi) behind a CLI, for messages of at most 96 bytes
vf() { $B/ed25519 verify "$@" > $T/o 2> $T/e; echo $?; }
# RFC 8032 test 1: known public key and signature, independent of our signer
p1=d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a
s1=e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b
[ "$(vf $p1 $s1 $T/m0)" = 0 ] && echo "PASS ed25519-tool/verify rfc8032 test 1 rc=0" || { echo "FAIL ed25519-tool/verify rfc8032 test 1"; fail=1; }
printf x > $T/mx
[ "$(vf $p1 $s1 $T/mx)" = 1 ] && [ ! -s $T/o ] && echo "PASS ed25519-tool/verify other message rc=1" || { echo "FAIL ed25519-tool/verify other message"; fail=1; }
s1b=$(echo $s1 | sed 's/0b$/0c/')
[ "$(vf $p1 $s1b $T/m0)" = 1 ] && echo "PASS ed25519-tool/verify changed signature rc=1" || { echo "FAIL ed25519-tool/verify changed signature"; fail=1; }
# every message length up to the 96-byte limit, signed by our signer, and a wrong key
ok=0; for len in 0 1 17 63 64 81 95 96; do
  head -c $len /dev/urandom > $T/ml; pk=$($B/ed25519 hexpublic $T/s3); sg=$($B/ed25519 hexsign $T/s3 $T/ml)
  [ "$(vf $pk $sg $T/ml)" = 0 ] && [ "$(vf $($B/ed25519 hexpublic $T/s4) $sg $T/ml)" = 1 ] && ok=$((ok + 1)) || { echo "FAIL ed25519-tool/verify roundtrip ${len}B"; fail=1; }
done
echo "PASS ed25519-tool/verify roundtrip and wrong key: $ok/8 lengths"
head -c 97 /dev/zero > $T/m97
[ "$(vf $p1 $s1 $T/m97)" = 2 ] && grep -q 'message longer than 96 bytes' $T/e && echo "PASS ed25519-tool/verify 97-byte message rc=2" || { echo "FAIL ed25519-tool/verify 97-byte message"; fail=1; }
ok=0; for bad in "${p1}0 $s1" "$(echo $p1 | tr a-f A-F) $s1" "$p1 ${s1%?}" "$p1 ${s1}0" "$p1 $(echo $s1 | sed 's/^e/g/')"; do
  [ "$(vf $bad $T/m0)" = 2 ] && grep -q 'PUBHEX must be 64 and SIGHEX 128 lowercase hex digits' $T/e && ok=$((ok + 1)) || { echo "FAIL ed25519-tool/verify bad hex '$bad'"; fail=1; }
done
echo "PASS ed25519-tool/verify bad hex rc=2: $ok/5 forms"
[ "$(vf $p1 $s1 $T/nope)" = 2 ] && grep -q 'cannot read message file' $T/e && echo "PASS ed25519-tool/verify missing message rc=2" || { echo "FAIL ed25519-tool/verify missing message"; fail=1; }
exit $fail
