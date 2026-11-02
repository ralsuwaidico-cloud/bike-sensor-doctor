#!/usr/bin/env bash
# The required check before every commit (ios/CI_PROCESS.md):
#   1. swiftc -parse on every changed Swift file
#   2. the Linux engine harness — the suites that cover the changed files (full run when unsure or with --full)
#   3. actionlint + bash -n when CI files changed
# Usage: tools/precommit.sh [--full] [--base <commit>] [paths...]
#   default paths = staged + unstaged changes (plus commits since --base when given). Exit 0 only when everything passed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
FULL=0; BASE=""; PATHS=()
while [ $# -gt 0 ]; do case "$1" in --full) FULL=1;; --base) BASE="$2"; shift;; *) PATHS+=("$1");; esac; shift; done
if [ ${#PATHS[@]} -eq 0 ]; then
  while IFS= read -r l; do [ -n "$l" ] && PATHS+=("$l"); done < <( { git diff --name-only; git diff --name-only --cached; [ -n "$BASE" ] && git diff --name-only "$BASE..HEAD"; } | sort -u )
fi
echo "precommit: ${#PATHS[@]} changed path(s)"
FAIL=0
# Swift toolchain (the harness env.sh adds /opt/swiftx when present)
[ -f tools/coach-harness/env.sh ] && source tools/coach-harness/env.sh
if ! command -v swiftc >/dev/null; then echo "precommit: swiftc not found (source tools/coach-harness/env.sh)"; exit 2; fi

# 1 ---- parse every changed Swift file
for p in "${PATHS[@]}"; do
  case "$p" in *.swift) [ -f "$p" ] || continue
    if ! swiftc -parse "$p" >/tmp/precommit-parse.txt 2>&1; then echo "PARSE FAIL $p"; head -5 /tmp/precommit-parse.txt; FAIL=1; fi;;
  esac
done
echo "precommit: parse $([ $FAIL -eq 0 ] && echo ok || echo FAILED)"

# 2 ---- Linux harness, filtered to the suites that cover the change (a clean copy, as CI runs it)
SUITES=$(python3 tools/ci-targets.py --harness "${PATHS[@]}")
[ $FULL -eq 1 ] && SUITES=ALL
HAS_CODE=0; for p in "${PATHS[@]}"; do case "$p" in ios/BikeComputer/*|ios/BikeComputerTests/*|ios/Shared/*|tools/coach-harness/*) HAS_CODE=1;; esac; done
if [ $HAS_CODE -eq 1 ] || [ $FULL -eq 1 ]; then
  H=$(mktemp -d)/harness; cp -r tools/coach-harness "$H"; rm -rf "$H/testws"
  if [ "$SUITES" = ALL ] || [ -z "$SUITES" ]; then echo "precommit: harness (all suites)"; (cd "$H" && ./test.sh "$ROOT" > "$H/out.txt" 2>&1); R=$?
  else
    echo "precommit: harness suites: $SUITES"
    # TESTS limits which test files are compiled in; the filter runs only those suites
    FILTER=$(echo "$SUITES" | tr ' ' '|')
    (cd "$H" && TESTS="TestScreenSupport $SUITES" ./test.sh "$ROOT" "$FILTER" > "$H/out.txt" 2>&1); R=$?
  fi
  grep -E "error:|failed \(|Executed [0-9]+ tests" "$H/out.txt" | tail -8
  if [ $R -ne 0 ]; then echo "precommit: harness FAILED (full log: $H/out.txt, build log: $H/testws/build.log)"; FAIL=1; else echo "precommit: harness ok"; fi
else echo "precommit: no engine/test sources changed — harness skipped (use --full to force)"; fi

# 3 ---- CI files
for p in "${PATHS[@]}"; do
  case "$p" in
    .github/workflows/*.yml) if command -v actionlint >/dev/null; then actionlint -shellcheck= "$p" || FAIL=1; else echo "precommit: actionlint not installed — pip install actionlint-py"; FAIL=1; fi;;
    *.sh) bash -n "$p" || { echo "BASH SYNTAX $p"; FAIL=1; };;
    *.py) python3 -m py_compile "$p" || FAIL=1;;
  esac
done
echo "precommit: $([ $FAIL -eq 0 ] && echo ALL OK || echo FAILED)"
exit $FAIL
