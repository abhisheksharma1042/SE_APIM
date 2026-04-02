#!/usr/bin/env bash
# =============================================================================
# 01-no-token.sh
# Verifies that calls without an Authorization header are rejected with 401.
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/helpers.sh"
load_env

echo "Test: Unauthenticated request → 401"
echo ""

SUB_KEY="$(get_subscription_key)"
BASE="$(gateway_url)"

# ── No Authorization header at all ───────────────────────────────────────────
STATUS=$(curl -s -o /tmp/apim-t1a.json -w "%{http_code}" \
  "${BASE}/crew?EmployeeNumbers=TEST001" \
  -H "Ocp-Apim-Subscription-Key: ${SUB_KEY}")
BODY=$(cat /tmp/apim-t1a.json)

assert_status "no Authorization header → 401" "401" "$STATUS"
assert_contains "body contains our error message" "valid Bearer token" "$BODY"

# ── Authorization header present but empty value ──────────────────────────────
STATUS=$(curl -s -o /tmp/apim-t1b.json -w "%{http_code}" \
  "${BASE}/crew?EmployeeNumbers=TEST001" \
  -H "Ocp-Apim-Subscription-Key: ${SUB_KEY}" \
  -H "Authorization: ")
assert_status "empty Authorization header → 401" "401" "$STATUS"

# ── Wrong scheme (Basic instead of Bearer) ───────────────────────────────────
STATUS=$(curl -s -o /tmp/apim-t1c.json -w "%{http_code}" \
  "${BASE}/crew?EmployeeNumbers=TEST001" \
  -H "Ocp-Apim-Subscription-Key: ${SUB_KEY}" \
  -H "Authorization: Basic dXNlcjpwYXNz")
assert_status "Basic scheme instead of Bearer → 401" "401" "$STATUS"

print_summary
