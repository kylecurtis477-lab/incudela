#!/bin/sh
# Pretty-printed tests/*.cud must compile and produce the same .expected output.
cd "$(dirname "$0")/../.."; fail=0; n=0
for t in tests/*.cud; do
  case "$t" in tests/mod_*) continue;; esac
  n=$((n+1)); b=$(basename "$t")
  o="$(dirname "$t")/.pp_$b"; build/cudc "$t" "$o" --emit=pretty && ./cuditor "$o" -o build/pp_bin 2>/dev/null && build/pp_bin a b | diff -q - "${t%.cud}.expected" >/dev/null || { echo "FAIL ast-pretty-semantic $t"; fail=1; }
  rm -f "$o"
done
[ $fail = 0 ] && echo "PASS ast-pretty-semantic ($n programs)"
exit $fail
