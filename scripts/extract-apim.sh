#!/usr/bin/env bash
# =============================================================================
# extract-apim.sh
# Downloads the APIOps extractor binary and pulls the current APIM
# configuration into apim-artifacts/ for Git tracking.
#
# Authentication (in priority order):
#   1. Service principal — set AZURE_CLIENT_ID + AZURE_CLIENT_SECRET in .env
#   2. Active az CLI session — if no SP creds, uses your current `az login`
#
# Prerequisites:
#   - Azure CLI (az) installed and logged in (or SP creds in .env)
#   - .env file with required variables
#
# Usage:
#   ./scripts/extract-apim.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/.tools"
APIOPS_VERSION="v6.0.2"

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

OUTPUT_DIR="$REPO_ROOT/apim-artifacts"

# ── Download extractor binary if not cached ───────────────────────────────────
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

if [[ "$OS" == "darwin" && "$ARCH" == "arm64" ]]; then
  ASSET="extractor-osx-arm64.zip"
elif [[ "$OS" == "darwin" ]]; then
  ASSET="extractor-osx-x64.zip"
elif [[ "$ARCH" == "arm64" ]]; then
  ASSET="extractor-linux-arm64.zip"
else
  ASSET="extractor-linux-x64.zip"
fi

EXTRACTOR_BIN="$TOOLS_DIR/extractor"

if [[ ! -f "$EXTRACTOR_BIN" ]]; then
  echo "==> Downloading APIOps extractor $APIOPS_VERSION ($ASSET)..."
  mkdir -p "$TOOLS_DIR"
  DOWNLOAD_URL="https://github.com/Azure/apiops/releases/download/$APIOPS_VERSION/$ASSET"
  curl -sL "$DOWNLOAD_URL" -o "$TOOLS_DIR/extractor.zip"
  unzip -q -o "$TOOLS_DIR/extractor.zip" -d "$TOOLS_DIR"
  chmod +x "$EXTRACTOR_BIN"
  rm "$TOOLS_DIR/extractor.zip"
  echo "    Extractor ready at $EXTRACTOR_BIN"
else
  echo "==> Extractor binary already cached ($EXTRACTOR_BIN)"
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
  # Unset SP vars so extractor uses bearer token path
  unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET
fi

# ── Run extraction ────────────────────────────────────────────────────────────
echo "==> Extracting APIM configuration to $OUTPUT_DIR ..."
mkdir -p "$OUTPUT_DIR"

AZURE_RESOURCE_GROUP_NAME="$APIM_RESOURCE_GROUP" \
API_MANAGEMENT_SERVICE_NAME="$APIM_SERVICE_NAME" \
API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH="$OUTPUT_DIR" \
"$EXTRACTOR_BIN"

echo ""
echo "==> Extraction complete. Artifacts in: $OUTPUT_DIR"
echo ""
echo "Review : git diff apim-artifacts/"
echo "Commit : git add apim-artifacts/ && git commit -m 'chore: sync APIM config from Azure'"
