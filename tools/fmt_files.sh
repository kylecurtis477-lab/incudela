#!/bin/sh
# Reference for `fmt --list` (tools/fmt.cud, which tests/fmt/run.sh checks against this). Sources kept
# canonically formatted by `cuditor fmt`. Excluded: the
# generated selfhost/cudc.cud and the intentionally malformed / column-sensitive
# error fixtures (tests/diag, tests/errors, tests/typeerrors, tests/grammar/invalid).
cd "$(dirname "$0")/.."
find selfhost tools tests examples -name '*.cud' -o -name '*.cudi' | grep -v -e '^selfhost/cudc.cud$' -e '^tests/diag/' -e '^tests/errors/' -e '^tests/typeerrors/' -e '^tests/grammar/invalid/' -e '^tests/fmt/' -e '/\.pp_' | LC_ALL=C sort
