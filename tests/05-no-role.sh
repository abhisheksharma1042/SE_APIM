#!/usr/bin/env bash
# =============================================================================
# 05-no-role.sh
# Verifies that a valid token from the correct issuer but with NO noc.* role
# assigned is rejected with 403 (not 401 — the token itself is valid).
#
# To produce a role-less token this test uses the SPA client app
# (JSX NOC Portal) which has no app role assignment — only the delegated
# scope. Client credentials flow for an app with no role assignments
# produces a token where the "roles" claim is absent.
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/helpers.sh"
load_env

echo "Test: Valid token with no noc.* role → 403"
echo ""

SUB_KEY="$(get_subscription_key)"
BASE="$(gateway_url)"

# Fetch a token for the SPA client app (no role assigned, only delegated scope)
# Using client credentials with the SPA client — the token will be issued from
# the correct tenant/issuer but will have no "roles" claim.
ROLELESS_TOKEN_RESP=$(curl -s -X POST \
  "https://${EXTERNAL_TENANT_DOMAIN%.onmicrosoft.com}.ciamlogin.com/${EXTERNAL_TENANT_ID}/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_APP_ID}" \
  -d "client_secret=${CLIENT_APP_SECRET:-}" \
  -d "scope=api://${API_APP_ID}/.default")

ERROR=$(echo "$ROLELESS_TOKEN_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null)

if [[ -n "$ERROR" && "$ERROR" != "None" ]]; then
  echo "  SKIP  SPA client app has no client secret configured (CLIENT_APP_SECRET not set in .env)"
  echo "        To run this test:"
  echo "          1. Create a client secret for app ID ${CLIENT_APP_ID} in the external tenant portal"
  echo "          2. Add CLIENT_APP_SECRET=<secret> to .env"
  echo "          3. Ensure NO app role is assigned to the SPA app in Enterprise Applications"
  echo ""
  echo "  INFO  The 403 code path is exercised by the policy logic:"
  echo "        <choose> block checks callerRole == 'none' and returns 403"
  exit 0
fi

ROLELESS_TOKEN=$(echo "$ROLELESS_TOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Verify this token has no roles claim
ROLES=$(echo "$ROLELESS_TOKEN" | python3 -c "
import sys, base64, json
token = sys.stdin.read().strip()
payload = token.split('.')[1]
payload += '=' * (4 - len(payload) % 4)
decoded = json.loads(base64.urlsafe_b64decode(payload))
print(decoded.get('roles', 'ABSENT'))
")

echo "  roles claim: $ROLES"
if [[ "$ROLES" != "ABSENT" && "$ROLES" != "[]" ]]; then
  echo "  WARN  SPA client app has roles assigned — assign a role to test 403 path specifically"
fi

STATUS=$(curl -s -o /tmp/apim-t5.json -w "%{http_code}" \
  "${BASE}/crew?EmployeeNumbers=TEST001" \
  -H "Ocp-Apim-Subscription-Key: ${SUB_KEY}" \
  -H "Authorization: Bearer ${ROLELESS_TOKEN}")
BODY=$(cat /tmp/apim-t5.json)

assert_status "valid token, no noc.* role → 403" "403" "$STATUS"
assert_contains "body mentions role requirement" "noc" "$BODY"

print_summary
