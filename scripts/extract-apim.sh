#!/usr/bin/env bash
# =============================================================================
# extract-apim.sh
# Runs the APIOps extractor to pull the current APIM configuration into
# apim-artifacts/ — committed to Git so changes are tracked and reviewed.
#
# Prerequisites:
#   - Azure CLI (az) installed and logged in
#   - Docker (to run the APIOps extractor container)
#   - .env file with required variables (see .env.example)
#
# Usage:
#   ./scripts/extract-apim.sh
#   ./scripts/extract-apim.sh --api example-api        # extract single API
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment variables
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$REPO_ROOT/.env"
  set +a
else
  echo "ERROR: .env file not found. Copy .env.example to .env and fill in values."
  exit 1
fi

# Required variables
: "${APIM_SERVICE_NAME:?Set APIM_SERVICE_NAME in .env}"
: "${APIM_RESOURCE_GROUP:?Set APIM_RESOURCE_GROUP in .env}"
: "${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID in .env}"

OUTPUT_DIR="$REPO_ROOT/apim-artifacts"

echo "==> Logging in to Azure (device code flow if not already logged in)"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

echo "==> Verifying APIM instance: $APIM_SERVICE_NAME in $APIM_RESOURCE_GROUP"
az apim show \
  --name "$APIM_SERVICE_NAME" \
  --resource-group "$APIM_RESOURCE_GROUP" \
  --query "name" -o tsv > /dev/null

echo "==> Running APIOps extractor via Docker"
# APIOps extractor Docker image
EXTRACTOR_IMAGE="mcr.microsoft.com/apiops/extractor:latest"

docker run --rm \
  -e AZURE_CLIENT_ID \
  -e AZURE_CLIENT_SECRET \
  -e AZURE_TENANT_ID \
  -e AZURE_SUBSCRIPTION_ID \
  -e API_MANAGEMENT_SERVICE_NAME="$APIM_SERVICE_NAME" \
  -e AZURE_RESOURCE_GROUP_NAME="$APIM_RESOURCE_GROUP" \
  -e API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH="/output" \
  -v "$OUTPUT_DIR:/output" \
  "$EXTRACTOR_IMAGE"

echo ""
echo "==> Extraction complete. Artifacts written to: $OUTPUT_DIR"
echo ""
echo "Review changes with: git diff apim-artifacts/"
echo "Stage changes with:  git add apim-artifacts/ && git commit -m 'chore: sync APIM config'"
