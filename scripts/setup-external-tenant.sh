#!/usr/bin/env bash
# =============================================================================
# setup-external-tenant.sh
# Automates Entra External ID tenant app registration setup via Azure CLI.
#
# Run this AFTER manually creating the external tenant in the Azure portal
# (tenant creation isn't fully scriptable via CLI yet).
#
# Prerequisites:
#   - Azure CLI logged into the EXTERNAL tenant (az login --tenant <external-id>)
#   - .env file with required variables
#
# Usage:
#   az login --tenant <external-tenant-id>
#   ./scripts/setup-external-tenant.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$REPO_ROOT/.env"
  set +a
fi

: "${EXTERNAL_TENANT_ID:?Set EXTERNAL_TENANT_ID in .env}"
: "${APP_DISPLAY_NAME:=Contoso API}"
: "${CLIENT_APP_NAME:=Contoso SPA Client}"
: "${DAEMON_APP_NAME:=Contoso Daemon Client}"

echo "==> Working in external tenant: $EXTERNAL_TENANT_ID"
az account show --query "tenantId" -o tsv

echo ""
echo "==> Step 1: Register the API application"
API_APP_ID=$(az ad app create \
  --display-name "$APP_DISPLAY_NAME" \
  --sign-in-audience "AzureADandPersonalMicrosoftAccount" \
  --query appId -o tsv)

echo "    API App ID: $API_APP_ID"

# Set Application ID URI
az ad app update \
  --id "$API_APP_ID" \
  --identifier-uris "api://$API_APP_ID"

echo ""
echo "==> Step 2: Define app roles on the API"
READER_ROLE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
WRITER_ROLE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
ADMIN_ROLE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

az ad app update --id "$API_APP_ID" --set appRoles="[
  {
    \"id\": \"$READER_ROLE_ID\",
    \"allowedMemberTypes\": [\"User\", \"Application\"],
    \"displayName\": \"Reader\",
    \"description\": \"Can read data from the API\",
    \"value\": \"api.read\",
    \"isEnabled\": true
  },
  {
    \"id\": \"$WRITER_ROLE_ID\",
    \"allowedMemberTypes\": [\"User\", \"Application\"],
    \"displayName\": \"Writer\",
    \"description\": \"Can read and write data\",
    \"value\": \"api.write\",
    \"isEnabled\": true
  },
  {
    \"id\": \"$ADMIN_ROLE_ID\",
    \"allowedMemberTypes\": [\"User\", \"Application\"],
    \"displayName\": \"Admin\",
    \"description\": \"Full administrative access\",
    \"value\": \"api.admin\",
    \"isEnabled\": true
  }
]"

echo "    Roles created: api.read ($READER_ROLE_ID), api.write ($WRITER_ROLE_ID), api.admin ($ADMIN_ROLE_ID)"

echo ""
echo "==> Step 3: Register the SPA client application"
CLIENT_APP_ID=$(az ad app create \
  --display-name "$CLIENT_APP_NAME" \
  --sign-in-audience "AzureADandPersonalMicrosoftAccount" \
  --query appId -o tsv)

echo "    SPA Client App ID: $CLIENT_APP_ID"

# Add SPA redirect URIs
az ad app update --id "$CLIENT_APP_ID" --set spa="{
  \"redirectUris\": [\"https://jwt.ms\", \"http://localhost:3000\"]
}"

echo ""
echo "==> Step 4: Register the daemon/service client"
DAEMON_APP_ID=$(az ad app create \
  --display-name "$DAEMON_APP_NAME" \
  --sign-in-audience "AzureADMyOrg" \
  --query appId -o tsv)

echo "    Daemon App ID: $DAEMON_APP_ID"

# Create a client secret for the daemon
DAEMON_SECRET=$(az ad app credential reset \
  --id "$DAEMON_APP_ID" \
  --append \
  --query password -o tsv)

echo "    Daemon client secret: $DAEMON_SECRET  (SAVE THIS — shown only once)"

echo ""
echo "==========================================================="
echo "  SETUP COMPLETE — Save these values to your .env file"
echo "==========================================================="
echo ""
echo "EXTERNAL_TENANT_ID=$EXTERNAL_TENANT_ID"
echo "API_APP_ID=$API_APP_ID"
echo "CLIENT_APP_ID=$CLIENT_APP_ID"
echo "DAEMON_APP_ID=$DAEMON_APP_ID"
echo "DAEMON_CLIENT_SECRET=$DAEMON_SECRET"
echo "READER_ROLE_ID=$READER_ROLE_ID"
echo "WRITER_ROLE_ID=$WRITER_ROLE_ID"
echo "ADMIN_ROLE_ID=$ADMIN_ROLE_ID"
echo ""
echo "Next steps:"
echo "  1. Configure user flows in the Azure portal (External Identities → User flows)"
echo "  2. Assign roles to test users (Enterprise Applications → $APP_DISPLAY_NAME → Users and groups)"
echo "  3. Update Named Values in APIM with API_APP_ID and EXTERNAL_TENANT_ID"
echo "  4. See docs/02-apim-setup.md"
