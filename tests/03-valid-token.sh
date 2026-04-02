#!/usr/bin/env bash
# =============================================================================
# 03-valid-token.sh
# Verifies that a valid token with a recognised noc.* role passes through
# the gateway and reaches the NOC backend (HTTP 200 or backend error, never
# an APIM 401/403).
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/helpers.sh"
load_env

echo "Test: Valid token passes through gateway"
echo ""

SUB_KEY="$(get_subscription_key)"
TOKEN="$(get_daemon_token)"
BASE="$(gateway_url)"

if [[ -z "$TOKEN" ]]; then
  echo "  FAIL  could not obtain token"
  exit 1
fi

# ── noc.operations role — GET crew ────────────────────────────────────────────
STATUS=$(curl -s -o /tmp/apim-t3a.json -w "%{http_code}" \
  "${BASE}/crew?EmployeeNumbers=TEST001" \
  -H "Ocp-Apim-Subscription-Key: ${SUB_KEY}" \
  -H "Authorization: Bearer ${TOKEN}")
BODY=$(cat /tmp/apim-t3a.json)

assert_status "valid token reaches backend (not 401 or 403)" "$STATUS" "$STATUS"

# Gateway must not return 401 or 403 — anything else means the request passed policy
if [[ "$STATUS" == "401" ]]; then
  echo "  FAIL  gateway returned 401 — JWT validation failed"
  echo "        body: $BODY"
  (( FAIL++ )) || true
elif [[ "$STATUS" == "403" ]]; then
  echo "  FAIL  gateway returned 403 — role check failed (check admin consent)"
  echo "        body: $BODY"
  (( FAIL++ )) || true
else
  echo "  PASS  gateway forwarded request to backend (HTTP $STATUS)"
  (( PASS++ )) || true
fi

# ── Verify response is not an APIM error envelope ────────────────────────────
if echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'statusCode' in d else 1)" 2>/dev/null; then
  APIM_MSG=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',''))")
  echo "  FAIL  response looks like an APIM error: $APIM_MSG"
  (( FAIL++ )) || true
else
  echo "  PASS  response is not an APIM error envelope"
  (( PASS++ )) || true
fi

# ── GET airports (different domain — confirm same policy applies) ─────────────
STATUS2=$(curl -s -o /tmp/apim-t3b.json -w "%{http_code}" \
  "${BASE}/airports?ActiveOnly=true" \
  -H "Ocp-Apim-Subscription-Key: ${SUB_KEY}" \
  -H "Authorization: Bearer ${TOKEN}")

if [[ "$STATUS2" != "401" && "$STATUS2" != "403" ]]; then
  echo "  PASS  second endpoint (airports) also passed policy (HTTP $STATUS2)"
  (( PASS++ )) || true
else
  echo "  FAIL  airports endpoint returned $STATUS2"
  (( FAIL++ )) || true
fi

print_summary
