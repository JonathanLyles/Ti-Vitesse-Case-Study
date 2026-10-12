#!/usr/bin/env bash
# Runs every verification gate. Prints "GATE <name>: PASS|FAIL" for each.
# Usage: check.sh [org-alias]    (defaults to the project's target org)
# Base branch for the diff check can be overridden: BASE=develop check.sh

# Git Bash on Windows: calling sf.cmd directly exits 1 even when the command
# succeeded, which makes every gate that runs sf report FAIL. Going through
# cmd.exe returns the real exit code.
case "$OSTYPE" in
  msys*|cygwin*) sf() { cmd //c sf "$@"; } ;;
esac

ORG_ARGS=()
[ -n "$1" ] && ORG_ARGS=(--target-org "$1")
BASE="${BASE:-main}"
fail=0

gate() {
  local name="$1"; shift
  echo "=== $name ==="
  if "$@"; then echo "GATE $name: PASS"; else echo "GATE $name: FAIL"; fail=1; fi
}

apex_tests() {
  sf apex run test --test-level RunLocalTests --code-coverage \
    --result-format human --wait 30 "${ORG_ARGS[@]}"
}

lwc_tests() {
  # Skip cleanly if the project has no Jest setup
  grep -q '"test:unit"' package.json 2>/dev/null || { echo "no LWC tests configured"; return 0; }
  npm run test:unit --silent
}

static_analysis() {
  # Fails on any violation of severity 2 (High) or worse
  sf code-analyzer run --workspace force-app --severity-threshold 2
}

tests_not_weakened() {
  local diff findings
  diff=$(git diff "$BASE" --unified=0 -- '*Test.cls' '*.test.js')
  findings=$(
    echo "$diff" | grep -E '^-[^-]' | grep -Ei 'assert|expect\(' | sed 's/^/removed assertion: /'
    echo "$diff" | grep -E '^\+[^+]' | grep -i 'SeeAllData=true' | sed 's/^/added: /'
  )
  if [ -n "$findings" ]; then echo "$findings"; return 1; fi
  echo "no assertions removed, no SeeAllData=true added"
}

gate apex-tests         apex_tests
gate lwc-tests          lwc_tests
gate static-analysis    static_analysis
gate tests-not-weakened tests_not_weakened

exit $fail
