#!/usr/bin/env bash
# =============================================================================
# 04-invalid-token.sh
# Verifies that malformed, expired, and wrong-audience tokens are rejected
# with 401 by the gateway.
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/helpers.sh"
load_env

echo "Test: Invalid tokens are rejected with 401"
echo ""

SUB_KEY="$(get_subscription_key)"
BASE="$(gateway_url)"
ENDPOINT="${BASE}/crew?EmployeeNumbers=TEST001"

# ── Completely fabricated token (bad signature) ───────────────────────────────
STATUS=$(curl -s -o /tmp/apim-t4a.json -w "%{http_code}" "$ENDPOINT" \
  -H "Ocp-Apim-Subscription-Key: ${SUB_KEY}" \
  -H "Authorization: Bearer eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJmYWtlIiwicm9sZXMiOlsibm9jLmFkbWluIl19.invalidsignature")
assert_status "fabricated token (bad signature) → 401" "401" "$STATUS"

# ── Structurally valid JWT but signed with wrong key ─────────────────────────
# Header: {"alg":"RS256","typ":"JWT"}
# Payload: {"sub":"attacker","roles":["noc.admin"],"iss":"https://evil.com","aud":"api://7e000b35-50be-4c6d-9749-95549f566df2","exp":9999999999}
EVIL_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhdHRhY2tlciIsInJvbGVzIjpbIm5vYy5hZG1pbiJdLCJpc3MiOiJodHRwczovL2V2aWwuY29tIiwiYXVkIjoiYXBpOi8vN2UwMDBiMzUtNTBiZS00YzZkLTk3NDktOTU1NDlmNTY2ZGYyIiwiZXhwIjo5OTk5OTk5OTk5fQ.fakesignature"
STATUS=$(curl -s -o /tmp/apim-t4b.json -w "%{http_code}" "$ENDPOINT" \
  -H "Ocp-Apim-Subscription-Key: ${SUB_KEY}" \
  -H "Authorization: Bearer ${EVIL_TOKEN}")
assert_status "wrong issuer + fake signature → 401" "401" "$STATUS"

# ── Expired token (exp in the past, otherwise well-formed structure) ──────────
# Payload includes exp=1 (1970-01-01) — will fail expiry check
EXPIRED_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0IiwiZXhwIjoxfQ.fakesig"
STATUS=$(curl -s -o /tmp/apim-t4c.json -w "%{http_code}" "$ENDPOINT" \
  -H "Ocp-Apim-Subscription-Key: ${SUB_KEY}" \
  -H "Authorization: Bearer ${EXPIRED_TOKEN}")
assert_status "expired token → 401" "401" "$STATUS"

# ── No subscription key — APIM should reject before reaching policy ───────────
STATUS=$(curl -s -o /tmp/apim-t4d.json -w "%{http_code}" "$ENDPOINT")
# Expect 401 (no subscription key) — APIM enforces this at the product level
assert_status "missing subscription key → 401" "401" "$STATUS"

print_summary
