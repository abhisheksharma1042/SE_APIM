#!/usr/bin/env bash
# =============================================================================
# setup-external-tenant.sh
# Registers the JSX Integration API enterprise applications in the Entra
# External ID (CIAM) tenant for APIM RBAC.
#
# Creates:
#   1. API resource app   — "JSX Integration API" (defines app roles)
#   2. SPA client app     — "JSX NOC Portal" (user-facing, Auth Code + PKCE)
#   3. Daemon client app  — "JSX Integration Service" (service-to-service)
#
# The script is IDEMPOTENT — if an app with the same display name already
# exists it reuses it rather than creating a duplicate.
#
# Prerequisites:
#   - Azure CLI logged into the EXTERNAL tenant
#     Run: az login --tenant <external-tenant-id> --allow-no-subscriptions
#   - .env file present with at least EXTERNAL_TENANT_ID set
#
# Usage:
#   az login --tenant 44557ddd-5eb1-45ca-8f8f-b939e0b59c88 --allow-no-subscriptions
#   ./scripts/setup-external-tenant.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Load .env (strip inline comments so lines like KEY=value  # comment work) ─
if [[ -f "$REPO_ROOT/.env" ]]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    clean="${line%%#*}"
    clean="${clean%"${clean##*[![:space:]]}"}"
    [[ -n "$clean" ]] && export "$clean" 2>/dev/null || true
  done < "$REPO_ROOT/.env"
else
  echo "ERROR: .env file not found."
  exit 1
fi

: "${EXTERNAL_TENANT_ID:?Set EXTERNAL_TENANT_ID in .env}"

# Derived project-specific names from the live APIM extraction
API_APP_NAME="${APP_DISPLAY_NAME:-JSX Integration API}"
SPA_APP_NAME="JSX NOC Portal"
DAEMON_APP_NAME="JSX Integration Service"

# APIM developer portal URL (from extracted policy.xml global CORS config)
APIM_DEV_PORTAL="https://intergration-api-gateway-test.developer.azure-api.net"

# ── Verify we are logged into the correct (external) tenant ──────────────────
echo "==> Verifying Azure CLI session..."
CURRENT_TENANT=$(az account show --query "tenantId" -o tsv 2>/dev/null || echo "none")

if [[ "$CURRENT_TENANT" != "$EXTERNAL_TENANT_ID" ]]; then
  echo ""
  echo "  ERROR: Azure CLI is signed into tenant: $CURRENT_TENANT"
  echo "         Expected external tenant:         $EXTERNAL_TENANT_ID ($EXTERNAL_TENANT_DOMAIN)"
  echo ""
  echo "  Run this first, then re-run this script:"
  echo "    az login --tenant $EXTERNAL_TENANT_ID --allow-no-subscriptions"
  echo ""
  exit 1
fi

echo "    Confirmed — logged into external tenant: $EXTERNAL_TENANT_DOMAIN ($EXTERNAL_TENANT_ID)"

# ── Helper: find existing app by display name, or return empty ────────────────
find_app() {
  az ad app list --display-name "$1" --query "[0].appId" -o tsv 2>/dev/null || echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: API resource application — "JSX Integration API"
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "==> Step 1: API resource app — '$API_APP_NAME'"

EXISTING=$(find_app "$API_APP_NAME")
if [[ -n "$EXISTING" && "$EXISTING" != "None" ]]; then
  API_APP_ID="$EXISTING"
  echo "    Existing app found: $API_APP_ID (reusing)"
else
  # External (CIAM) tenant — single-tenant audience scoped to this external tenant
  API_APP_ID=$(az ad app create \
    --display-name "$API_APP_NAME" \
    --sign-in-audience "AzureADMyOrg" \
    --query appId -o tsv)
  echo "    Created: $API_APP_ID"

  # Set the Application ID URI (used as `audience` value in validate-jwt policy)
  az ad app update \
    --id "$API_APP_ID" \
    --identifier-uris "api://$API_APP_ID"
  echo "    Application ID URI set: api://$API_APP_ID"
fi

# ── Step 1a: Define app roles on the API ─────────────────────────────────────
# Roles reflect the NOC.Service domain — Crew, Flight, Roster, Airport, etc.
# Three tiers: readonly (GET), operations (GET+write), admin (all + user mgmt)
echo ""
echo "==> Step 1a: Defining app roles (noc.readonly / noc.operations / noc.admin)"

READER_ROLE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
WRITER_ROLE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
ADMIN_ROLE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

az ad app update --id "$API_APP_ID" --set appRoles="[
  {
    \"id\": \"$READER_ROLE_ID\",
    \"allowedMemberTypes\": [\"User\", \"Application\"],
    \"displayName\": \"NOC Read Only\",
    \"description\": \"Read-only access to NOC data: flights, rosters, crew, airports, aircraft, hotel bookings, pairings, schedules\",
    \"value\": \"noc.readonly\",
    \"isEnabled\": true
  },
  {
    \"id\": \"$WRITER_ROLE_ID\",
    \"allowedMemberTypes\": [\"User\", \"Application\"],
    \"displayName\": \"NOC Operations\",
    \"description\": \"Read and write access to NOC operations data: update flights, rosters, crew data, maintenance, hotel bookings\",
    \"value\": \"noc.operations\",
    \"isEnabled\": true
  },
  {
    \"id\": \"$ADMIN_ROLE_ID\",
    \"allowedMemberTypes\": [\"User\", \"Application\"],
    \"displayName\": \"NOC Admin\",
    \"description\": \"Full administrative access including user management, configuration data, and all NOC operations\",
    \"value\": \"noc.admin\",
    \"isEnabled\": true
  }
]"
echo "    Roles set: noc.readonly / noc.operations / noc.admin"

# ── Step 1b: Expose a delegated scope ────────────────────────────────────────
echo ""
echo "==> Step 1b: Exposing delegated scope 'access_as_user'"
SCOPE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

az ad app update --id "$API_APP_ID" --set api="{
  \"oauth2PermissionScopes\": [
    {
      \"id\": \"$SCOPE_ID\",
      \"adminConsentDescription\": \"Access the JSX Integration API on behalf of the signed-in user\",
      \"adminConsentDisplayName\": \"Access JSX Integration API\",
      \"isEnabled\": true,
      \"type\": \"User\",
      \"userConsentDescription\": \"Access the JSX NOC API on your behalf\",
      \"userConsentDisplayName\": \"Access JSX NOC API\",
      \"value\": \"access_as_user\"
    }
  ]
}"
echo "    Scope set: access_as_user ($SCOPE_ID)"

# ── Step 1c: Create service principal so roles can be assigned ────────────────
echo ""
echo "==> Step 1c: Ensuring service principal exists for '$API_APP_NAME'"
SP_EXISTS=$(az ad sp show --id "$API_APP_ID" --query "appId" -o tsv 2>/dev/null || echo "")
if [[ -z "$SP_EXISTS" ]]; then
  az ad sp create --id "$API_APP_ID" > /dev/null
  echo "    Service principal created."
else
  echo "    Service principal already exists."
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: SPA client app — "JSX NOC Portal"
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "==> Step 2: SPA client app — '$SPA_APP_NAME'"

EXISTING=$(find_app "$SPA_APP_NAME")
if [[ -n "$EXISTING" && "$EXISTING" != "None" ]]; then
  CLIENT_APP_ID="$EXISTING"
  echo "    Existing app found: $CLIENT_APP_ID (reusing)"
else
  CLIENT_APP_ID=$(az ad app create \
    --display-name "$SPA_APP_NAME" \
    --sign-in-audience "AzureADMyOrg" \
    --query appId -o tsv)
  echo "    Created: $CLIENT_APP_ID"
fi

# Redirect URIs — APIM dev portal + local dev
az ad app update --id "$CLIENT_APP_ID" --set spa="{
  \"redirectUris\": [
    \"$APIM_DEV_PORTAL\",
    \"$APIM_DEV_PORTAL/\",
    \"https://jwt.ms\",
    \"http://localhost:3000\",
    \"http://localhost:3000/\"
  ]
}"
echo "    Redirect URIs: $APIM_DEV_PORTAL, http://localhost:3000"

# Grant delegated permission to the API
az ad app permission add \
  --id "$CLIENT_APP_ID" \
  --api "$API_APP_ID" \
  --api-permissions "$SCOPE_ID=Scope" 2>/dev/null || true

echo "    Delegated API permission granted (access_as_user)"

# Ensure SP exists for the client
SP_EXISTS=$(az ad sp show --id "$CLIENT_APP_ID" --query "appId" -o tsv 2>/dev/null || echo "")
if [[ -z "$SP_EXISTS" ]]; then
  az ad sp create --id "$CLIENT_APP_ID" > /dev/null
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Daemon/service client — "JSX Integration Service"
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "==> Step 3: Daemon client app — '$DAEMON_APP_NAME'"

EXISTING=$(find_app "$DAEMON_APP_NAME")
if [[ -n "$EXISTING" && "$EXISTING" != "None" ]]; then
  DAEMON_APP_ID="$EXISTING"
  echo "    Existing app found: $DAEMON_APP_ID (reusing)"
else
  DAEMON_APP_ID=$(az ad app create \
    --display-name "$DAEMON_APP_NAME" \
    --sign-in-audience "AzureADMyOrg" \
    --query appId -o tsv)
  echo "    Created: $DAEMON_APP_ID"
fi

# Grant application role permission (noc.operations by default for service clients)
az ad app permission add \
  --id "$DAEMON_APP_ID" \
  --api "$API_APP_ID" \
  --api-permissions "$WRITER_ROLE_ID=Role" 2>/dev/null || true
echo "    Application role permission added (noc.operations)"

# Create client secret
echo "==> Generating client secret for daemon app..."
DAEMON_SECRET=$(az ad app credential reset \
  --id "$DAEMON_APP_ID" \
  --display-name "apim-setup-$(date +%Y%m%d)" \
  --years 1 \
  --append \
  --query password -o tsv)

# Ensure SP exists
SP_EXISTS=$(az ad sp show --id "$DAEMON_APP_ID" --query "appId" -o tsv 2>/dev/null || echo "")
if [[ -z "$SP_EXISTS" ]]; then
  az ad sp create --id "$DAEMON_APP_ID" > /dev/null
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=================================================================="
echo "  SETUP COMPLETE"
echo "=================================================================="
echo ""
echo "Paste these values into your .env file:"
echo ""
echo "AZURE_SUBSCRIPTION_ID=3870d1e4-c958-479f-a241-97b2d2fb1716"
echo "API_APP_ID=$API_APP_ID"
echo "CLIENT_APP_ID=$CLIENT_APP_ID"
echo "DAEMON_APP_ID=$DAEMON_APP_ID"
echo "DAEMON_CLIENT_SECRET=$DAEMON_SECRET"
echo "READER_ROLE_ID=$READER_ROLE_ID"
echo "WRITER_ROLE_ID=$WRITER_ROLE_ID"
echo "ADMIN_ROLE_ID=$ADMIN_ROLE_ID"
echo ""
echo "=================================================================="
echo ""
echo "Next steps:"
echo ""
echo "  1. Add Named Values to APIM (docs/02-apim-setup.md):"
echo "     az apim nv create ... --named-value-id api-app-id --value $API_APP_ID"
echo "     az apim nv create ... --named-value-id external-tenant-id --value $EXTERNAL_TENANT_ID"
echo "     az apim nv create ... --named-value-id external-tenant-domain --value jsxdev"
echo ""
echo "  2. Grant admin consent for daemon app roles in the external tenant portal:"
echo "     Portal → Enterprise Applications → $DAEMON_APP_NAME → Permissions → Grant admin consent"
echo ""
echo "  3. Assign roles to users:"
echo "     Portal → Enterprise Applications → $API_APP_NAME → Users and groups"
echo "     (noc.readonly / noc.operations / noc.admin)"
echo ""
echo "  4. Review APIM policy templates in:"
echo "     apim-artifacts/apis/noc-service/policy.xml"
echo "     (current policy uses hardcoded Basic auth — replace with validate-jwt)"
echo "     See: policies/apis/example-api/api-policy.xml for the JWT template"
