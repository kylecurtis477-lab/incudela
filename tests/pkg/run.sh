#!/bin/bash
# Phase 7.4: forge pkg (tools/pkg.cud). Fixture packages tests/pkg/packages are published into a signed
# temporary registry with the test-only key tests/pkg/test-key.seed (its public key is pinned in
# tests/pkg/app/cuditor.toml) at fixed publish times; project tests/pkg/app.
D="$(cd "$(dirname "$0")/../.." && pwd)"
F="$D/cuditor"; S="$D/tests/pkg/packages"; K="$D/tests/pkg/test-key.seed"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
ok() { echo "PASS pkg/$1"; }; bad() { echo "FAIL pkg/$1"; fail=1; }
fail=0
R=$T/reg; mkdir $R
for p in "mathx/1.0.0 1700000000" "strutil/1.0.0 1700000100" "clash/1.0.0 1700000200" "mathx/1.2.0 1700100000" "strutil/1.1.0 1700100100" "mathx/2.0.0 1700200000"; do
  set -- $p; "$F" pkg --registry $R publish --key $K --time $2 "$S/$1" > $T/p 2>&1 || { cat $T/p; echo "FAIL pkg/publish-fixture $1"; exit 1; }
done
ED="$D/build/edsig"; PK=$("$ED" hexpublic $K)
cp -r "$D/tests/pkg/app" $T/a && cd $T/a || exit 1
grep -q "^key = \"$PK\"$" cuditor.toml && ok pinned-key-is-test-key || bad pinned-key-is-test-key
# the index: one v1 line per version with its publish time, yank flag and package hash, signed over
# "cuditor-index-v1 " + sha256(name LF index) (checked here with sha256sum and the CLI verifier)
printf 'cuditor-index-v1 %s' "$({ printf 'mathx\n'; cat $R/mathx/index; } | sha256sum | cut -d' ' -f1)" > $T/im
[ "$(sed 's/ [0-9a-f]*$//' $R/mathx/index)" = "$(printf '# cuditor index v1: version published yanked sha256\n1.0.0 1700000000 0\n1.2.0 1700100000 0\n2.0.0 1700200000 0')" ] && "$ED" verify $PK "$(cat $R/mathx/index.sig)" $T/im && ok index-signed-with-times || bad index-signed-with-times
[ "$(sed -n 's/^1.2.0 [0-9]* 0 //p' $R/mathx/index)" = "$(cd $R/mathx/1.2.0 && { printf 'cuditor.toml\0%s\0' $(wc -c < cuditor.toml); cat cuditor.toml; printf 'mathx.cud\0%s\0' $(wc -c < mathx.cud); cat mathx.cud; } | sha256sum | cut -d' ' -f1)" ] && ok index-hash-is-package-hash || bad index-hash-is-package-hash
# our SHA-256 agrees with sha256sum, including bytes >= 0x80 and an empty file
printf '\xc3\xa9t\xe9\n' > $T/h1; : > $T/h2; cp "$D/tools/pkg.cud" $T/h3
[ "$("$F" pkg sha256 $T/h1 $T/h2 $T/h3)" = "$(sha256sum $T/h1 $T/h2 $T/h3)" ] && ok sha256-matches-sha256sum || bad sha256-matches-sha256sum
# resolution: highest compatible versions (strutil 1.1.0 needs mathx ^1.1; mathx 2.0.0 excluded by ^1)
"$F" pkg --registry $R lock > $T/l1 2>&1
grep -q "^locked mathx 1.2.0$" $T/l1 && grep -q "^locked strutil 1.1.0$" $T/l1 && ok resolve-highest-compatible || bad resolve-highest-compatible
# the recorded package hash is SHA-256 over cuditor.toml + files as documented (independent check)
python3 - "$R/strutil/1.1.0" cuditor.lock <<'PY' && ok package-hash-independent || bad package-hash-independent
import hashlib, sys, re
d = sys.argv[1]
s = b""
for f in ["cuditor.toml", "strutil.cud"]:
    t = open(d + "/" + f, "rb").read()
    s += f.encode() + b"\0" + str(len(t)).encode() + b"\0" + t
lock = open(sys.argv[2]).read()
m = re.search(r'name = "strutil"\nversion = "1.1.0"\nsha256 = "([0-9a-f]{64})"', lock)
sys.exit(0 if m and m.group(1) == hashlib.sha256(s).hexdigest() else 1)
PY
cp cuditor.lock $T/lock1; "$F" pkg --registry $R lock > /dev/null 2>&1
cmp -s cuditor.lock $T/lock1 && ok lock-deterministic || bad lock-deterministic
# reproducible build: two clean builds, and a build of a copy in another directory, give the same hash
h1=$("$F" pkg --registry $R build 2>&1 | sed -n 's/.*sha256 //p'); out=$(./target/app)
rm -rf target; h2=$("$F" pkg --registry $R build 2>&1 | sed -n 's/.*sha256 //p')
cp -r $T/a $T/b; rm -rf $T/b/target; h3=$(cd $T/b && "$F" pkg --registry $R build 2>&1 | sed -n 's/.*sha256 //p')
[ -n "$h1" ] && [ "$h1" = "$h2" ] && [ "$h1" = "$h3" ] && ok "reproducible-build ($h1)" || bad "reproducible-build ($h1 $h2 $h3)"
[ "$out" = "$(printf '[hello pkg]\n[0, 1, 8, 27]\n49 1.2.0')" ] && ok program-runs || bad "program-runs ($out)"
# a tampered registry package is refused
cp -r $R $T/r; echo "# changed" >> $T/r/mathx/1.2.0/mathx.cud
"$F" pkg --registry $T/r build > $T/e 2>&1; [ $? != 0 ] && grep -q "hash mismatch for mathx 1.2.0" $T/e && ok tamper-detected || bad tamper-detected
# an edited lock is refused
sed 's/version = "1.2.0"/version = "1.0.0"/' $T/lock1 > cuditor.lock
"$F" pkg --registry $R build > $T/e 2>&1; [ $? != 0 ] && grep -q "hash mismatch\|cuditor.lock" $T/e && ok edited-lock-refused || bad edited-lock-refused
cp $T/lock1 cuditor.lock
# a registry whose files changed after publishing is refused by a fresh lock (the signed index pins the hash)
cp -r $R $T/r2; echo "# changed" >> $T/r2/mathx/1.2.0/mathx.cud
"$F" pkg --registry $T/r2 lock > $T/e 2>&1; [ $? != 0 ] && grep -q "mathx 1.2.0 in the registry does not match its signed index" $T/e && ok changed-files-refused || bad changed-files-refused
cmp -s cuditor.lock $T/lock1 || { cp $T/lock1 cuditor.lock; bad changed-files-lock-untouched; }
# an index edited without re-signing (a flipped yank flag, a moved publish time) is refused
cp -r $R $T/r3; sed -i 's/^1.2.0 1700100000 0/1.2.0 1700100000 1/' $T/r3/mathx/index
"$F" pkg --registry $T/r3 lock > $T/e 2>&1; [ $? != 0 ] && grep -q "the index of mathx is not signed by the registry key" $T/e && ok edited-index-refused || bad edited-index-refused
cp -r $R $T/r4; sed -i 's/^2.0.0 1700200000/2.0.0 1700200001/' $T/r4/mathx/index
"$F" pkg --registry $T/r4 build > $T/e 2>&1; [ $? != 0 ] && grep -q "the index of mathx is not signed by the registry key" $T/e && ok edited-time-refused || bad edited-time-refused
# an index moved to another package name does not verify, nor does a missing signature
cp -r $R $T/r5; cp $T/r5/strutil/index $T/r5/mathx/index; cp $T/r5/strutil/index.sig $T/r5/mathx/index.sig
"$F" pkg --registry $T/r5 lock > $T/e 2>&1; [ $? != 0 ] && grep -q "the index of mathx is not signed" $T/e && ok index-bound-to-name || bad index-bound-to-name
cp -r $R $T/r6; rm $T/r6/strutil/index.sig
"$F" pkg --registry $T/r6 lock > $T/e 2>&1; [ $? != 0 ] && grep -q "the index of strutil is not signed (no " $T/e && ok unsigned-index-refused || bad unsigned-index-refused
# the pinned key decides: another key's registry, or no [registry] key at all, is refused
printf 'another key\n' > $T/k2; mkdir $T/r7
"$F" pkg --registry $T/r7 publish --key $T/k2 --time 1 "$S/mathx/1.0.0" > /dev/null 2>&1 && "$F" pkg --registry $T/r7 publish --key $T/k2 --time 1 "$S/strutil/1.0.0" > /dev/null 2>&1
"$F" pkg --registry $T/r7 lock > $T/e 2>&1; [ $? != 0 ] && grep -q "is not signed by the registry key $(echo $PK | cut -c1-16)" $T/e && ok foreign-registry-refused || bad foreign-registry-refused
sed '/^\[registry\]$/d; /^key = /d' "$D/tests/pkg/app/cuditor.toml" > cuditor.toml
"$F" pkg --registry $R lock > $T/e 2>&1; [ $? != 0 ] && grep -q "cuditor.toml has no \[registry\] key" $T/e && ok no-key-refused || bad no-key-refused
cp "$D/tests/pkg/app/cuditor.toml" cuditor.toml
# publishing: versions are immutable, only the key holder appends, and publish times never go back
"$F" pkg --registry $R publish --key $K --time 1800000000 "$S/mathx/1.2.0" > $T/e 2>&1; [ $? != 0 ] && grep -q "mathx 1.2.0 is already published" $T/e && ok republish-refused || bad republish-refused
cp -r $S/mathx/2.0.0 $T/m3; sed -i 's/2.0.0/3.0.0/' $T/m3/cuditor.toml
"$F" pkg --registry $R publish --key $T/k2 --time 1800000000 $T/m3 > $T/e 2>&1; [ $? != 0 ] && grep -q "the index of mathx is not signed by the registry key" $T/e && [ ! -e $R/mathx/3.0.0 ] && ok foreign-publisher-refused || bad foreign-publisher-refused
"$F" pkg --registry $R publish --key $K --time 1700000000 $T/m3 > $T/e 2>&1; [ $? != 0 ] && grep -q "publish time 1700000000 is before the last publish of mathx" $T/e && [ ! -e $R/mathx/3.0.0 ] && ok publish-time-monotonic || bad publish-time-monotonic
# yank: never newly selected (strutil 1.1.0 needs mathx ^1.1, so both fall back to 1.0.0) ...
cp -r $R $T/ry; "$F" pkg --registry $T/ry yank --key $K mathx 1.2.0 > $T/y 2>&1 && grep -q "^yanked mathx 1.2.0$" $T/y && grep -q "^1.2.0 1700100000 1 " $T/ry/mathx/index && ok yank-sets-flag || bad yank-sets-flag
"$F" pkg --registry $T/ry lock > $T/l3 2>&1 && grep -q "^locked mathx 1.0.0$" $T/l3 && grep -q "^locked strutil 1.0.0$" $T/l3 && ok yanked-not-newly-selected || bad yanked-not-newly-selected
# ... but still stages, with a warning, for a cuditor.lock that already selects it (same binary)
cp $T/lock1 cuditor.lock; rm -rf target
hy=$("$F" pkg --registry $T/ry build 2> $T/w | sed -n 's/.*sha256 //p')
[ "$hy" = "$h1" ] && grep -q "warning: mathx 1.2.0 is yanked; staged because cuditor.lock selects it" $T/w && ok yanked-kept-for-existing-lock || bad "yanked-kept-for-existing-lock ($hy)"
sed -i 's/^mathx = "\^1"/mathx = "1.2.0"/' cuditor.toml
"$F" pkg --registry $T/ry lock > $T/e 2>&1; [ $? != 0 ] && grep -q "no version of mathx satisfies 1.2.0 (root) (1 matching version(s) yanked)" $T/e && ok yanked-pin-reported || bad yanked-pin-reported
cp "$D/tests/pkg/app/cuditor.toml" cuditor.toml; cp $T/lock1 cuditor.lock
# cooldown: [registry] cooldown_days = "3" skips versions published less than 3 days before `lock --now`.
# Two days after mathx 1.2.0 / strutil 1.1.0 were published, both fall back to 1.0.0 ...
cool() { cp "$D/tests/pkg/app/cuditor.toml" cuditor.toml; sed -i "/^key = /a $1" cuditor.toml; }
cool 'cooldown_days = "3"'
"$F" pkg --registry $R lock --now 1700272800 > $T/c1 2>&1 && grep -q "^locked mathx 1.0.0$" $T/c1 && grep -q "^locked strutil 1.0.0$" $T/c1 && ok cooldown-skips-young || bad cooldown-skips-young
# ... exactly 3 days after strutil 1.1.0 it is old enough, one second earlier it is not (mathx 1.2.0 is 100 s older)
"$F" pkg --registry $R lock --now 1700359300 > $T/c2 2>&1 && grep -q "^locked mathx 1.2.0$" $T/c2 && grep -q "^locked strutil 1.1.0$" $T/c2 && cmp -s cuditor.lock $T/lock1 && ok "cooldown-boundary (same lock as without a cooldown)" || bad cooldown-boundary
"$F" pkg --registry $R lock --now 1700359299 > $T/c3 2>&1 && grep -q "^locked mathx 1.2.0$" $T/c3 && grep -q "^locked strutil 1.0.0$" $T/c3 && ok cooldown-boundary-minus-1s || bad cooldown-boundary-minus-1s
# an existing lock with versions inside the cooldown still builds (the cooldown only limits new selection)
cp $T/lock1 cuditor.lock; rm -rf target; hc=$("$F" pkg --registry $R build 2>&1 | sed -n 's/.*sha256 //p')
[ "$hc" = "$h1" ] && ok cooldown-keeps-existing-lock || bad "cooldown-keeps-existing-lock ($hc)"
# exempt packages ignore it; a pin inside it is reported; a malformed value is refused
cool 'cooldown_days = "3"\ncooldown_exempt = ["mathx", "strutil"]'
"$F" pkg --registry $R lock --now 1700272800 > $T/c4 2>&1 && grep -q "^locked mathx 1.2.0$" $T/c4 && grep -q "^locked strutil 1.1.0$" $T/c4 && ok cooldown-exempt || bad cooldown-exempt
cool 'cooldown_days = "3"\ncooldown_exempt = ["strutil"]'
"$F" pkg --registry $R lock --now 1700272800 > $T/c5 2>&1 && grep -q "^locked mathx 1.0.0$" $T/c5 && grep -q "^locked strutil 1.0.0$" $T/c5 && ok cooldown-exempt-only-named || bad cooldown-exempt-only-named
cool 'cooldown_days = "3"'; sed -i 's/^mathx = "\^1"/mathx = "1.2.0"/' cuditor.toml
"$F" pkg --registry $R lock --now 1700272800 > $T/e 2>&1; [ $? != 0 ] && grep -q "no version of mathx satisfies 1.2.0 (root) (1 matching version(s) inside the 3-day cooldown)" $T/e && ok cooldown-pin-reported || bad cooldown-pin-reported
n=0; for v in '"-1"' '"3d"' '""' '"123456"' '["3"]'; do
  cool "cooldown_days = $v"; "$F" pkg --registry $R lock --now 1700272800 > $T/e 2>&1; [ $? != 0 ] && grep -q "cooldown_days must be a whole number of days" $T/e && n=$((n + 1))
done
[ $n = 5 ] && ok "bad-cooldown-refused (5 forms)" || bad "bad-cooldown-refused ($n/5)"
cool 'cooldown_exempt = "mathx"'; "$F" pkg --registry $R lock --now 1700272800 > $T/e 2>&1; [ $? != 0 ] && grep -q "cooldown_exempt must be a list" $T/e && ok bad-exempt-refused || bad bad-exempt-refused
cp "$D/tests/pkg/app/cuditor.toml" cuditor.toml; "$F" pkg --registry $R lock --now soon > $T/e 2>&1; [ $? != 0 ] && grep -q "lock needs the current time in Unix seconds" $T/e && ok bad-now-refused || bad bad-now-refused
cp "$D/tests/pkg/app/cuditor.toml" cuditor.toml; cp $T/lock1 cuditor.lock
# cuditor.toml changed without relocking
sed -i 's/mathx = "\^1"/mathx = "^1.2"/' cuditor.toml
"$F" pkg --registry $R build > $T/e 2>&1; [ $? != 0 ] && grep -q "out of date" $T/e && ok stale-lock-refused || bad stale-lock-refused
# an exact pin to 1.0.0 conflicts with strutil 1.1.0's mathx ^1.1 -> falls back to strutil 1.0.0
sed -i 's/mathx = "\^1.2"/mathx = "1.0.0"/' cuditor.toml
"$F" pkg --registry $R lock > $T/l2 2>&1 && grep -q "^locked strutil 1.0.0$" $T/l2 && grep -q "^locked mathx 1.0.0$" $T/l2 && ok "backtrack-to-compatible" || bad backtrack-to-compatible
# unsatisfiable requirement
sed -i 's/mathx = "1.0.0"/mathx = "^3"/' cuditor.toml
"$F" pkg --registry $R lock > $T/e 2>&1; [ $? != 0 ] && grep -q "no version of mathx satisfies" $T/e && ok unsatisfiable-reported || bad unsatisfiable-reported
# two packages providing the same module
cp "$D/tests/pkg/app/cuditor.toml" cuditor.toml; printf 'clash = "1.0.0"\n' >> cuditor.toml; sed -i 's/"greet.cud"/"greet.cud", "clash.cud"/' cuditor.toml; cp greet.cud clash.cud
"$F" pkg --registry $R lock > /dev/null 2>&1; "$F" pkg --registry $R build > $T/e 2>&1; [ $? != 0 ] && grep -q "module clash.cud is provided by both" $T/e && ok module-clash-refused || bad module-clash-refused
exit $fail
