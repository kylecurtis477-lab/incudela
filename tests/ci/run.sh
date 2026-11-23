#!/bin/bash
# tests/ci: the public CI workflow (.github/workflows/ci.yml, docs/ci.md) keeps its rules: every action pinned to a
# full 40-hex commit SHA, a read-only token (top-level `permissions: contents: read`, nothing else granted), no
# secrets, a timeout on every job, no download or cache steps (the build starts from the committed seed; tools
# come from apt on the runner only), and the three jobs (build.sh, run_tests.sh, the O0 boot). Each rule is also
# checked against a copy of the workflow that breaks it. No network, no QEMU.
cd "$(dirname "$0")/../.."
W=.github/workflows/ci.yml; T=$(mktemp -d); trap 'rm -rf $T' EXIT; fail=0
# check FILE: prints the first broken rule and returns 1, or returns 0
check() {
  local f=$1 n
  grep -E '^\s*-?\s*uses:' $f | grep -vqE 'uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}( #.*)?$' && { echo "unpinned action"; return 1; }
  grep -qE '^permissions:$' $f && grep -A1 -E '^permissions:$' $f | tail -1 | grep -qE '^  contents: read$' || { echo "no top-level contents: read"; return 1; }
  grep -qiE ':\s*write\b|write-all|permissions:\s*\S' $f && { echo "write permission"; return 1; }
  grep -qE 'secrets\.|GITHUB_TOKEN' $f && { echo "secret used"; return 1; }
  grep -qiE '\b(curl|wget)\b|actions/cache|setup-[a-z]+|releases/download|docker' $f && { echo "download or cache step"; return 1; }
  n=$(grep -cE '^  [a-z0-9-]+:$' <(sed -n '/^jobs:$/,$p' $f)); [ "$n" -ge 1 ] && [ "$(grep -cE '^    timeout-minutes: [0-9]+$' $f)" = "$n" ] || { echo "job without timeout"; return 1; }
  grep -qE '^      - uses: actions/checkout@' $f && [ "$(grep -c 'persist-credentials: false' $f)" = "$(grep -c 'uses: actions/checkout@' $f)" ] || { echo "checkout keeps credentials"; return 1; }
  grep -qE '^\s+run: \./build\.sh' $f && grep -q 'FIXPOINT OK' $f && grep -q 'SEED TOOLS OK' $f || { echo "no seed build check"; return 1; }
  grep -q 'SKIP_OS=1 ./run_tests.sh' $f && grep -q 'run: tests/os/ci-boot.sh' $f || { echo "missing job"; return 1; }
  return 0
}
r=$(check $W) && echo "PASS ci/workflow-rules" || { echo "FAIL ci/workflow-rules ($r)"; fail=1; }
# each broken copy must be refused, for the rule it breaks
mut() { sed -E "$2" $W > $T/w.yml; r=$(check $T/w.yml) && { echo "FAIL ci/refuses-$1 (accepted)"; fail=1; } || { [ "$r" = "$3" ] && echo "PASS ci/refuses-$1 ($r)" || { echo "FAIL ci/refuses-$1 (got: $r)"; fail=1; }; }; }
mut tag-pin '0,/checkout@[0-9a-f]{40}/s//checkout@v7/' "unpinned action"
mut short-sha '0,/checkout@([0-9a-f]{12})[0-9a-f]{28}/s//checkout@\1/' "unpinned action"
mut write-token 's/^  contents: read$/  contents: write/' "no top-level contents: read"
mut extra-write '/^  contents: read$/a\  packages: write' "write permission"
mut secret '0,/run: \.\/build\.sh$/s//run: .\/build.sh ${{ secrets.X }}/' "secret used"
mut download '0,/run: \.\/build\.sh$/s//run: curl -sLO https:\/\/example.invalid\/cudc \&\& .\/build.sh/' "download or cache step"
mut no-timeout '0,/^    timeout-minutes: [0-9]+$/{//d}' "job without timeout"
mut credentials '0,/persist-credentials: false/s//persist-credentials: true/' "checkout keeps credentials"
mut no-boot 's#run: tests/os/ci-boot.sh#run: true#' "missing job"
# the O0 boot script: -O0 build, no retry on a hang, KERNEL OK on serial and framebuffer
B=tests/os/ci-boot.sh
grep -q 'CUDC_FLAGS=-O0 build/kernel-build' $B && grep -q 'FORGE_BOOT_NO_RETRY=1 \$B kernel-bios-O0' $B && grep -q '"multiboot2 (BIOS)|KERNEL OK" "back == front^KERNEL OK"' $B && echo "PASS ci/boot-script" || { echo "FAIL ci/boot-script"; fail=1; }
# README shows the workflow's badge
grep -qF '(https://github.com/kylecurtis477-lab/incudela/actions/workflows/ci.yml/badge.svg?branch=master)' README.md && echo "PASS ci/readme-badge" || { echo "FAIL ci/readme-badge"; fail=1; }
exit $fail
