#!/usr/bin/env bash
# =============================================================================
# publish-apim.sh
# Downloads the APIOps publisher binary and pushes apim-artifacts/ to the
# target APIM instance, applying configuration overrides.
#
# Authentication (in priority order):
#   1. Service principal — set AZURE_CLIENT_ID + AZURE_CLIENT_SECRET in .env
#   2. Active az CLI session — if no SP creds, uses your current `az login`
#
# Prerequisites:
#   - Azure CLI logged in to the WORKFORCE tenant (where APIM lives)
#   - .env file with required variables
#
# Usage:
#   az login --tenant 497d5e45-e7a5-4d05-a37f-b104b15d68b8
#   ./scripts/publish-apim.sh                          # uses configuration.dev.yaml
#   ./scripts/publish-apim.sh configuration.qa.yaml    # explicit config file
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/.tools"
APIOPS_VERSION="v6.0.2"
CONFIGURATION_FILE="${1:-$REPO_ROOT/configuration.dev.yaml}"

# Load environment variables (strip inline comments)
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

: "${APIM_SERVICE_NAME:?Set APIM_SERVICE_NAME in .env}"
: "${APIM_RESOURCE_GROUP:?Set APIM_RESOURCE_GROUP in .env}"
: "${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID in .env}"
: "${AZURE_TENANT_ID:?Set AZURE_TENANT_ID in .env}"

ARTIFACTS_DIR="$REPO_ROOT/apim-artifacts"

# ── Download publisher binary if not cached ───────────────────────────────────
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

if [[ "$OS" == "darwin" && "$ARCH" == "arm64" ]]; then
  ASSET="publisher-osx-arm64.zip"
elif [[ "$OS" == "darwin" ]]; then
  ASSET="publisher-osx-x64.zip"
elif [[ "$ARCH" == "arm64" ]]; then
  ASSET="publisher-linux-arm64.zip"
else
  ASSET="publisher-linux-x64.zip"
fi

PUBLISHER_BIN="$TOOLS_DIR/publisher"

if [[ ! -f "$PUBLISHER_BIN" ]]; then
  echo "==> Downloading APIOps publisher $APIOPS_VERSION ($ASSET)..."
  mkdir -p "$TOOLS_DIR"
  curl -sL "https://github.com/Azure/apiops/releases/download/$APIOPS_VERSION/$ASSET" \
    -o "$TOOLS_DIR/publisher.zip"
  unzip -q -o "$TOOLS_DIR/publisher.zip" -d "$TOOLS_DIR"
  chmod +x "$PUBLISHER_BIN"
  rm "$TOOLS_DIR/publisher.zip"
  echo "    Publisher ready at $PUBLISHER_BIN"
else
  echo "==> Publisher binary already cached ($PUBLISHER_BIN)"
fi

# ── Verify APIM instance ──────────────────────────────────────────────────────
echo "==> Setting active subscription: $AZURE_SUBSCRIPTION_ID"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

echo "==> Verifying APIM instance: $APIM_SERVICE_NAME in $APIM_RESOURCE_GROUP"
az apim show \
  --name "$APIM_SERVICE_NAME" \
  --resource-group "$APIM_RESOURCE_GROUP" \
  --query "name" -o tsv > /dev/null
echo "    Found."

echo "==> Configuration file: $CONFIGURATION_FILE"
[[ -f "$CONFIGURATION_FILE" ]] || { echo "ERROR: config file not found"; exit 1; }

# ── Determine auth method ─────────────────────────────────────────────────────
if [[ -n "${AZURE_CLIENT_ID:-}" && "${AZURE_CLIENT_ID}" != "00000000-0000-0000-0000-000000000000" && \
      -n "${AZURE_CLIENT_SECRET:-}" && "${AZURE_CLIENT_SECRET}" != "your-client-secret-here" ]]; then
  echo "==> Auth: service principal ($AZURE_CLIENT_ID)"
else
  echo "==> Auth: using active az CLI session"
  export AZURE_BEARER_TOKEN
  AZURE_BEARER_TOKEN=$(az account get-access-token \
    --resource "https://management.azure.com/" \
    --query accessToken -o tsv)
  unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET 2>/dev/null || true
fi

# ── Run publisher ─────────────────────────────────────────────────────────────
echo "==> Publishing $ARTIFACTS_DIR → $APIM_SERVICE_NAME ..."

AZURE_RESOURCE_GROUP_NAME="$APIM_RESOURCE_GROUP" \
API_MANAGEMENT_SERVICE_NAME="$APIM_SERVICE_NAME" \
API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH="$ARTIFACTS_DIR" \
CONFIGURATION_YAML_PATH="$CONFIGURATION_FILE" \
"$PUBLISHER_BIN"

echo ""
echo "==> Publish complete."
echo ""
echo "Verify policy: az apim api policy show --api-id noc-service \\"
echo "                 --service-name $APIM_SERVICE_NAME --resource-group $APIM_RESOURCE_GROUP"
