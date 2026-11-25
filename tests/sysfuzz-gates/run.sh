#!/bin/sh
# tests/sysfuzz-gates/run.sh: sysfuzz's gated-syscall list must match sys_need
# in examples/kernel/seal.cudi for every capability the fuzzer does not declare.
# sysfuzz (examples/user/sysfuzz.cud) declares caps(fs, ipc) and, in phase 1,
# calls every other capability-gated number expecting EACCES. This host test
# parses both sources (no QEMU) so a new syscall in sys_need cannot drift out
# of the list, and a stale list entry cannot linger after a cap change.
# Syscalls 408/409 stay ktest_hooks gated in the kernel; this test only checks
# the capability table. The kernel unsafe cap is unchanged (709).
# usage: tests/sysfuzz-gates/run.sh
cd "$(dirname "$0")/../.." || exit 1
SEAL=examples/kernel/seal.cudi
FUZZ=examples/user/sysfuzz.cud
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

HELD=$(sed -n 's/^# cuditor: caps(\(.*\))/\1/p' "$FUZZ" | tr -d ' ')
if [ -z "$HELD" ]; then
  echo "FAIL sysfuzz-gates/pragma (no caps() pragma in $FUZZ)"
  exit 1
fi

# gated: u64[N] = [ ... ] may wrap across lines
awk '
  BEGIN { inarr=0 }
  $0 ~ /^gated: u64\[[0-9]+\] = \[/ {
    line=$0
    sub(/^gated: u64\[[0-9]+\] = \[/, "", line)
    if (line ~ /\]/) { sub(/\].*/, "", line); print line; exit }
    buf=line; inarr=1; next
  }
  inarr {
    line=$0
    if (line ~ /\]/) { sub(/\].*/, "", line); print buf line; exit }
    buf=buf line
  }
' "$FUZZ" | tr ',' ' ' | tr -s ' \t' '\n' | grep -E '^[0-9]+$' | sort -n > "$T/gated"
if [ ! -s "$T/gated" ]; then
  echo "FAIL sysfuzz-gates/gated (no numbers in $FUZZ gated list)"
  exit 1
fi

# sys_need body through the next top-level def
awk '
  BEGIN { infn=0 }
  /^def sys_need\(/ { infn=1; next }
  infn && /^def / { exit }
  infn { print }
' "$SEAL" > "$T/need.body"
if ! grep -q "return CAPB_" "$T/need.body"; then
  echo "FAIL sysfuzz-gates/sys_need (could not find sys_need in $SEAL)"
  exit 1
fi

# Expand if-conditions + return CAPB_* into "nr cap" lines.
# Supports: nr == N; nr >= A and nr <= B; combined with or; optional parens.
awk '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  function emit(lo, hi, cap,    n) {
    for (n = lo; n <= hi; n++) print n, cap
  }
  function capname(s) {
    sub(/^CAPB_/, "", s)
    return tolower(s)
  }
  function expand(cond, cap,    parts, np, i, t, a, b) {
    gsub(/[()]/, "", cond)
    np = split(cond, parts, /[ \t]+or[ \t]+/)
    for (i = 1; i <= np; i++) {
      t = trim(parts[i])
      if (t ~ /^nr == [0-9]+$/) {
        split(t, a, / == /)
        emit(a[2]+0, a[2]+0, cap)
      } else if (t ~ /^nr >= [0-9]+[ \t]+and[ \t]+nr <= [0-9]+$/) {
        split(t, a, / >= /)
        split(a[2], b, /[ \t]+and[ \t]+nr <=[ \t]+/)
        emit(b[1]+0, b[2]+0, cap)
      } else if (t != "") {
        print "PARSE_ERROR: " t > "/dev/stderr"
        exit 1
      }
    }
  }
  /^[ \t]*if / {
    cond=$0
    sub(/^[ \t]*if[ \t]+/, "", cond)
    sub(/:[ \t]*$/, "", cond)
    pending=cond
    next
  }
  pending != "" && /return CAPB_/ {
    cap=$0
    sub(/^.*return CAPB_/, "", cap)
    sub(/[ \t]*$/, "", cap)
    expand(pending, capname(cap))
    pending=""
    next
  }
  pending != "" && NF && $1 != "#" {
    print "PARSE_ERROR: expected return CAPB_ after: " pending > "/dev/stderr"
    exit 1
  }
' "$T/need.body" > "$T/need.pairs"
if [ $? != 0 ] || [ ! -s "$T/need.pairs" ]; then
  echo "FAIL sysfuzz-gates/parse (could not expand sys_need in $SEAL)"
  exit 1
fi

# Numbers sysfuzz must deny: sys_need caps it does not hold
awk -v held="$HELD" '
  BEGIN { n=split(held, h, ","); for (i=1;i<=n;i++) have[h[i]]=1 }
  !have[$2] { print $1 }
' "$T/need.pairs" | sort -n | uniq > "$T/need"
need_caps=$(awk -v held="$HELD" '
  BEGIN { n=split(held, h, ","); for (i=1;i<=n;i++) have[h[i]]=1 }
  !have[$2] { c[$2]=1 }
  END { for (k in c) print k }
' "$T/need.pairs" | sort | tr "\n" "," | sed "s/,$//")
need_n=$(wc -l < "$T/need" | tr -d ' ')
gated_n=$(wc -l < "$T/gated" | tr -d ' ')
if [ "$need_n" = 0 ]; then
  echo "FAIL sysfuzz-gates/empty (sys_need produced no numbers to deny)"
  exit 1
fi

miss=$(comm -23 "$T/need" "$T/gated" | tr "\n" " " | sed "s/[ ]*$//")
extra=$(comm -13 "$T/need" "$T/gated" | tr "\n" " " | sed "s/[ ]*$//")
if [ -n "$miss" ] || [ -n "$extra" ]; then
  echo "FAIL sysfuzz-gates/mismatch (missing from gated: [${miss:-none}]; extra in gated: [${extra:-none}]; sysfuzz holds $HELD, sys_need denies $need_caps)"
  exit 1
fi
echo "PASS sysfuzz-gates (sysfuzz holds $HELD; $need_n gated numbers match sys_need for $need_caps)"
exit 0
