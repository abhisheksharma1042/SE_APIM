#!/usr/bin/env bash
# =============================================================================
# run-all.sh — Run all APIM gateway tests in sequence
#
# Usage:
#   cd tests && ./run-all.sh
#   ./tests/run-all.sh
# =============================================================================

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
SKIPPED=()

run_test() {
  local file="$1"
  local name
  name="$(basename "$file")"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if bash "$file"; then
    # Parse PASS/FAIL counts from output
    OUTPUT=$(bash "$file" 2>&1)
    PASSES=$(echo "$OUTPUT" | grep -c "  PASS" || true)
    FAILS=$(echo "$OUTPUT"  | grep -c "  FAIL" || true)
    TOTAL_PASS=$(( TOTAL_PASS + PASSES ))
    TOTAL_FAIL=$(( TOTAL_FAIL + FAILS ))
  else
    EXIT=$?
    if [[ $EXIT -eq 0 ]]; then
      SKIPPED+=("$name")
    else
      TOTAL_FAIL=$(( TOTAL_FAIL + 1 ))
    fi
  fi
}

for test_file in "$TESTS_DIR"/0*.sh; do
  run_test "$test_file"
done

echo ""
echo "═══════════════════════════════════════════════"
echo "  TOTAL: ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"
[[ ${#SKIPPED[@]} -gt 0 ]] && echo "  SKIPPED: ${SKIPPED[*]}"
echo "═══════════════════════════════════════════════"

[[ $TOTAL_FAIL -eq 0 ]]
