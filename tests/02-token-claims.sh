#!/usr/bin/env bash
# =============================================================================
# 02-token-claims.sh
# Fetches a client credentials token from the CIAM daemon app and verifies
# the JWT claims are correct before using it to call the gateway.
# =============================================================================

set -euo pipefail
source "$(dirname "$0")/helpers.sh"
load_env

echo "Test: Daemon token claims"
echo ""

TOKEN="$(get_daemon_token)"

if [[ -z "$TOKEN" ]]; then
  echo "  FAIL  could not obtain token — check DAEMON_APP_ID / DAEMON_CLIENT_SECRET in .env"
  exit 1
fi

# Decode claims (no signature verification — just payload inspection)
CLAIMS=$(echo "$TOKEN" | python3 -c "
import sys, base64, json
token = sys.stdin.read().strip()
payload = token.split('.')[1]
payload += '=' * (4 - len(payload) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(payload)), indent=2))
")

ISS=$(echo "$CLAIMS"  | python3 -c "import sys,json; print(json.load(sys.stdin).get('iss',''))")
AUD=$(echo "$CLAIMS"  | python3 -c "import sys,json; print(json.load(sys.stdin).get('aud',''))")
ROLES=$(echo "$CLAIMS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('roles',''))")
APP_ID=$(echo "$CLAIMS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('appid', json.load(open('/dev/stdin')) if False else json.loads(open('/dev/null').read() or '{}').get('azp','')) or json.load(sys.stdin).get('azp',''))" 2>/dev/null || \
         echo "$CLAIMS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('appid', d.get('azp','')))")

echo "  Token summary:"
echo "    iss:   $ISS"
echo "    aud:   $AUD"
echo "    roles: $ROLES"
echo ""

assert_contains "issuer contains external tenant ID" "$EXTERNAL_TENANT_ID" "$ISS"
assert_contains "audience matches API app ID"        "$API_APP_ID"          "$AUD"
assert_contains "roles claim contains noc.operations" "noc.operations"     "$ROLES"

print_summary
