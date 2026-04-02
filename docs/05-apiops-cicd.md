# 05 — APIOps CI/CD Pipeline

> The APIM built-in Git repository was **retired March 15, 2025**.
> APIOps with your own Git repo is the replacement.

---

## What is APIOps?

APIOps applies **GitOps** principles to API Management:

- All APIM configuration lives in Git as artifacts
- An **extractor** pulls current state from APIM → files in your repo
- A **publisher** pushes artifact changes from your repo → APIM
- Changes go through **PR review** before deploying
- Environment promotion: `dev` → `qa` → `prod` via branch strategy

```
Developer's machine
     │
     │  1. ./scripts/extract-apim.sh
     │     (pulls current APIM state to apim-artifacts/)
     ▼
  Git repo  ──── PR Review ────▶  GitHub Actions
     │                                   │
     │  2. Edit policies, APIs,           │  3. publisher runs
     │     named values, products         │     on PR merge
     │                                   ▼
     └──────────────────────────▶  Azure APIM
                                  (dev / qa / prod)
```

---

## Repository Setup

### 1. Add APIOps as a GitHub Action tool

The APIOps toolkit is distributed as GitHub Actions. No local binary install needed for CI — for local extraction, use the Azure CLI approach in `scripts/extract-apim.sh`.

### 2. Set GitHub Secrets

In your GitHub repo → **Settings** → **Secrets and variables** → **Actions**:

| Secret name | Value |
|-------------|-------|
| `AZURE_CLIENT_ID` | Service principal or federated identity client ID |
| `AZURE_CLIENT_SECRET` | SP secret (or use OIDC — see below) |
| `AZURE_TENANT_ID` | Your **workforce** tenant ID (where APIM lives) |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `APIM_SERVICE_NAME` | e.g. `contoso-apim` |
| `APIM_RESOURCE_GROUP` | e.g. `rg-apim-prod` |

### 3. Create a Service Principal with least privilege

```bash
# Create SP with Contributor on just the APIM resource group
SP=$(az ad sp create-for-rbac \
  --name "apim-github-actions" \
  --role "API Management Service Contributor" \
  --scopes "/subscriptions/<sub-id>/resourceGroups/rg-apim-prod" \
  --sdk-auth)

echo $SP
# Copy the clientId, clientSecret, tenantId, subscriptionId to GitHub secrets
```

---

## GitHub Actions Workflows

### Extract Workflow

`.github/workflows/extract.yml` — runs on a schedule or manually. Pulls APIM config to `apim-artifacts/` and opens a PR if anything changed.

```yaml
name: Extract APIM Configuration

on:
  schedule:
    - cron: '0 2 * * *'   # Daily at 2am UTC
  workflow_dispatch:        # Allow manual trigger

permissions:
  contents: write
  pull-requests: write

jobs:
  extract:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Run APIOps Extractor
        uses: Azure/apiops@v5
        with:
          command: extract
          AZURE_RESOURCE_GROUP_NAME: ${{ secrets.APIM_RESOURCE_GROUP }}
          API_MANAGEMENT_SERVICE_NAME: ${{ secrets.APIM_SERVICE_NAME }}
          API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH: apim-artifacts
          # Only extract specific APIs (optional)
          # API_NAMES: example-api,another-api

      - name: Create Pull Request if changed
        uses: peter-evans/create-pull-request@v6
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: "chore: sync APIM configuration from Azure"
          branch: apim-sync/auto-extract
          title: "[APIM Sync] Configuration drift detected"
          body: |
            Automated extraction detected differences between the live APIM
            configuration and what is tracked in this repository.

            Please review the changes and merge if they represent intentional
            updates made directly in the Azure portal.
          labels: apim-sync, automated
```

### Publish Workflow

`.github/workflows/publish.yml` — runs on PR merge to `main`. Publishes `apim-artifacts/` changes to APIM.

```yaml
name: Publish APIM Configuration

on:
  push:
    branches:
      - main
    paths:
      - 'apim-artifacts/**'
      - 'policies/**'

  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        default: 'dev'
        type: choice
        options:
          - dev
          - qa
          - prod

permissions:
  contents: read
  id-token: write   # Required for OIDC auth

jobs:
  publish-dev:
    runs-on: ubuntu-latest
    environment: dev
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure Login (OIDC — no secret needed)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Run APIOps Publisher
        uses: Azure/apiops@v5
        with:
          command: publish
          AZURE_RESOURCE_GROUP_NAME: ${{ secrets.APIM_RESOURCE_GROUP }}
          API_MANAGEMENT_SERVICE_NAME: ${{ secrets.APIM_SERVICE_NAME }}
          API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH: apim-artifacts
          CONFIGURATION_YAML_PATH: configuration.dev.yaml  # env overrides

  publish-qa:
    runs-on: ubuntu-latest
    environment: qa
    needs: publish-dev
    # Add manual approval gate in GitHub environment settings
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.QA_AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Run APIOps Publisher
        uses: Azure/apiops@v5
        with:
          command: publish
          AZURE_RESOURCE_GROUP_NAME: ${{ secrets.QA_APIM_RESOURCE_GROUP }}
          API_MANAGEMENT_SERVICE_NAME: ${{ secrets.QA_APIM_SERVICE_NAME }}
          API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH: apim-artifacts
          CONFIGURATION_YAML_PATH: configuration.qa.yaml
```

---

## Environment Configuration Overrides

APIOps supports a `configuration.<env>.yaml` that overrides specific values per environment — so the same artifact works across dev/qa/prod without modifying the artifact files themselves.

`configuration.dev.yaml`:
```yaml
apimServiceName: contoso-apim-dev
namedValues:
  - name: external-tenant-domain
    value: contosocustomers-dev
  - name: api-app-id
    value: <dev-api-app-id>
apis:
  - name: example-api
    serviceUrl: https://dev-backend.contoso.com/api
```

`configuration.prod.yaml`:
```yaml
apimServiceName: contoso-apim-prod
namedValues:
  - name: external-tenant-domain
    value: contosocustomers
  - name: api-app-id
    value: <prod-api-app-id>
apis:
  - name: example-api
    serviceUrl: https://backend.contoso.com/api
```

---

## OIDC Authentication (No Secrets — Recommended)

Instead of storing a client secret, use federated credentials:

```bash
# Create the app registration
APP_ID=$(az ad app create --display-name "apim-github-oidc" --query appId -o tsv)

# Add federated credential for GitHub Actions
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<org>/<repo>:ref:refs/heads/main",
  "description": "GitHub Actions main branch",
  "audiences": ["api://AzureADTokenExchange"]
}'

# Create SP and assign role
az ad sp create --id $APP_ID
az role assignment create \
  --assignee $APP_ID \
  --role "API Management Service Contributor" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-apim-prod"
```

In GitHub secrets, set `AZURE_CLIENT_ID` to `$APP_ID` — no `AZURE_CLIENT_SECRET` needed.
The workflow uses `id-token: write` permission and `azure/login@v2` with OIDC.

---

## Day-to-Day Developer Workflow

```
1. Pull latest:
   git pull origin main

2. Edit a policy in VS Code:
   apim-artifacts/apis/example-api/policy.xml

3. Test locally using VS Code extension (direct deploy to dev APIM):
   Ctrl+S → saves to dev APIM immediately

4. Once happy, commit and push:
   git checkout -b feat/rbac-admin-endpoint
   git add apim-artifacts/
   git commit -m "feat: restrict /admin to api.admin role"
   git push origin feat/rbac-admin-endpoint

5. Open PR → teammate reviews the policy diff

6. Merge to main → GitHub Actions publishes to dev APIM automatically

7. QA approves → pipeline promotes to qa APIM

8. Production release → promote to prod (manual approval gate in GitHub environment)
```

---

## APIOps Artifact Structure Reference

After extraction, `apim-artifacts/` contains:

```
apim-artifacts/
├── apis/
│   └── <api-name>/
│       ├── apiInformation.json    # API metadata (display name, path, protocols)
│       ├── specification.yaml     # OpenAPI / WADL spec
│       ├── policy.xml             # API-level policy
│       └── operations/
│           └── <operation-id>/
│               └── policy.xml     # Operation-level policy
├── products/
│   └── <product-name>/
│       ├── productInformation.json
│       ├── policy.xml
│       └── apis.json              # List of APIs in this product
├── named-values/
│   └── namedValues.json           # All named values (secrets redacted)
├── backends/
│   └── <backend-name>/
│       └── backendInformation.json
├── subscriptions/
│   └── subscriptions.json
└── loggers/
    └── loggers.json
```

---

## References

- [APIOps GitHub](https://github.com/Azure/apiops)
- [APIOps Documentation](https://azure.github.io/apiops/)
- [Automated API Deployments — Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/devops/automated-api-deployments-apiops)
- [APIM DevOps Resource Kit](https://github.com/Azure/azure-api-management-devops-resource-kit)
- [DevOps and CI/CD for APIs — Microsoft Learn](https://learn.microsoft.com/en-us/azure/api-management/devops-api-development-templates)
