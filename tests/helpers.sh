#!/usr/bin/env bash
# =============================================================================
# helpers.sh — shared utilities sourced by each test file
# =============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Load .env ────────────────────────────────────────────────────────────────
load_env() {
  if [[ ! -f "$REPO_ROOT/.env" ]]; then
    echo "ERROR: .env not found at $REPO_ROOT/.env" >&2
    exit 1
  fi
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    clean="${line%%#*}"
    clean="${clean%"${clean##*[![:space:]]}"}"
    [[ -n "$clean" ]] && export "$clean" 2>/dev/null || true
  done < "$REPO_ROOT/.env"
}

# ── Fetch APIM master subscription key via ARM REST API ──────────────────────
get_subscription_key() {
  az rest --method POST \
    --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${APIM_RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_SERVICE_NAME}/subscriptions/master/listSecrets?api-version=2023-09-01-preview" \
    --query primaryKey -o tsv 2>/dev/null
}

# ── Fetch a client credentials token from the CIAM daemon app ────────────────
get_daemon_token() {
  curl -s -X POST \
    "https://${EXTERNAL_TENANT_DOMAIN%.onmicrosoft.com}.ciamlogin.com/${EXTERNAL_TENANT_ID}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_id=${DAEMON_APP_ID}" \
    -d "client_secret=${DAEMON_CLIENT_SECRET}" \
    -d "scope=api://${API_APP_ID}/.default" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['access_token'])" 2>/dev/null
}

# ── Gateway base URL (derived from APIM service name) ────────────────────────
gateway_url() {
  local name_lower
  name_lower=$(echo "$APIM_SERVICE_NAME" | tr '[:upper:]' '[:lower:]')
  echo "https://${name_lower}.azure-api.net/integration-noc/v1/nocrestapi/v1"
}

# ── Assert helpers ────────────────────────────────────────────────────────────
PASS=0
FAIL=0

assert_status() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS  $test_name (HTTP $actual)"
    (( PASS++ )) || true
  else
    echo "  FAIL  $test_name — expected HTTP $expected, got HTTP $actual"
    (( FAIL++ )) || true
  fi
}

assert_contains() {
  local test_name="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS  $test_name (found: $needle)"
    (( PASS++ )) || true
  else
    echo "  FAIL  $test_name — expected to contain '$needle'"
    echo "        got: $(echo "$haystack" | head -c 200)"
    (( FAIL++ )) || true
  fi
}

print_summary() {
  echo ""
  echo "──────────────────────────────────"
  echo "  Results: ${PASS} passed, ${FAIL} failed"
  echo "──────────────────────────────────"
  [[ $FAIL -eq 0 ]]
}
