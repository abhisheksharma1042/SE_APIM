# Azure API Management — B2C / Entra External ID Role-Based Access

This repository documents and automates the setup of an **Azure API Management (APIM)** gateway secured with **Microsoft Entra External ID** (formerly Azure AD B2C) for consumer-facing role-based access control (RBAC), using an **external configuration tenant**.

It also provides a full **local development workflow** using VS Code and **APIOps** so you manage all APIM policies and configuration as code — no more editing in the Azure portal.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                      External Clients                         │
│              (SPA / Mobile / Service / CLI)                   │
└────────────────────────┬─────────────────────────────────────┘
                         │  1. Authenticate (PKCE / client creds)
                         ▼
┌──────────────────────────────────────────────────────────────┐
│          Microsoft Entra External ID Tenant                   │
│   (external tenant — separate from your workforce tenant)     │
│                                                               │
│   • App registrations (SPA, API, daemon clients)              │
│   • User flows / custom policies (sign-up, sign-in, MFA)     │
│   • App roles (e.g. reader, writer, admin)                    │
│   • Groups (optional — mapped to roles via claims)            │
└────────────────────────┬─────────────────────────────────────┘
                         │  2. Issues JWT (roles / scp claims)
                         ▼
┌──────────────────────────────────────────────────────────────┐
│              Azure API Management Gateway                     │
│                                                               │
│   Inbound policies per API / operation:                       │
│   • validate-jwt  — verify signature + claims                 │
│   • check-header  — optional subscription key                 │
│   • cors          — origin control                            │
│   • rate-limit-by-key — per-identity throttling               │
│   • set-variable  — extract role from token                   │
│   • choose        — route/reject based on role                │
└────────────────────────┬─────────────────────────────────────┘
                         │  3. Forward validated request
                         ▼
┌──────────────────────────────────────────────────────────────┐
│              Backend APIs / Azure Functions                   │
│         (EasyAuth for defence-in-depth validation)            │
└──────────────────────────────────────────────────────────────┘
```

### Tenant Topology

| Tenant | Purpose |
|--------|---------|
| **Workforce tenant** (`contoso.onmicrosoft.com`) | Your Azure subscription, APIM resource, internal staff |
| **External tenant** (`contosob2c.onmicrosoft.com`) | Consumer / partner identities, Entra External ID |

---

## Repository Structure

```
.
├── README.md                        # This file
├── docs/
│   ├── 01-entra-external-id-setup.md   # Create & configure external tenant
│   ├── 02-apim-setup.md                # Provision APIM, link to external tenant
│   ├── 03-rbac-policies.md             # Role-based JWT validation policies
│   ├── 04-vscode-local-dev.md          # VS Code + APIM extension workflow
│   └── 05-apiops-cicd.md               # APIOps GitHub Actions pipeline
├── policies/
│   ├── global/
│   │   └── global-policy.xml           # Tenant-wide inbound/outbound policies
│   ├── products/
│   │   └── standard-product-policy.xml
│   └── apis/
│       └── example-api/
│           ├── api-policy.xml          # API-level policy (JWT validation)
│           └── get-items-operation-policy.xml  # Operation-level RBAC
├── apim-artifacts/                  # APIOps extractor output (tracked in git)
│   ├── apis/
│   ├── products/
│   ├── named-values/
│   └── backends/
├── scripts/
│   ├── setup-external-tenant.sh    # Entra External ID provisioning via AZ CLI
│   └── extract-apim.sh             # Run APIOps extractor locally
├── .github/
│   └── workflows/
│       ├── extract.yml              # Extract APIM config on schedule / manual
│       └── publish.yml              # Publish config changes to APIM on PR merge
└── .vscode/
    ├── extensions.json              # Recommended extensions
    └── settings.json                # Policy XML schema association
```

---

## Quick Start

### Prerequisites

- Azure CLI (`az`) — [install](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- Node.js 18+ (for APIOps runner)
- VS Code with extensions listed in [`.vscode/extensions.json`](.vscode/extensions.json)
- An Azure subscription with Contributor access

### 1. Read the docs in order

| Step | Guide |
|------|-------|
| 1 | [Entra External ID Setup](docs/01-entra-external-id-setup.md) |
| 2 | [APIM Provisioning & Identity Linking](docs/02-apim-setup.md) |
| 3 | [Role-Based Access Policies](docs/03-rbac-policies.md) |
| 4 | [VS Code Local Dev Workflow](docs/04-vscode-local-dev.md) |
| 5 | [APIOps CI/CD Pipeline](docs/05-apiops-cicd.md) |

### 2. Clone and configure

```bash
git clone https://github.com/<your-org>/apim-b2c-rbac.git
cd apim-b2c-rbac

# Copy and fill in your environment values
cp .env.example .env
```

---

## Key Technology Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Identity provider | **Entra External ID** (external tenant) | B2C retired for new customers May 2025 |
| Policy management | **APIOps + Git** | Built-in APIM Git repo retired March 2025 |
| Local editing | **VS Code APIM Extension** | IntelliSense, policy debugging, direct deploy |
| CI/CD | **GitHub Actions + APIOps** | GitOps-style promotion Dev → QA → Prod |
| RBAC mechanism | **JWT `roles` claim** | App roles assigned in Entra; validated in APIM inbound policy |

---

## Important Retirement Notices

> **Azure AD B2C** is no longer available for new customers as of **May 1, 2025**.
> Use **Microsoft Entra External ID** for new deployments.
> Reference: [Microsoft Learn — Entra External ID](https://learn.microsoft.com/en-us/azure/active-directory/external-identities/)

> **APIM Built-in Git Repository** was retired **March 15, 2025**.
> Use **APIOps** with your own Git repository.
> Reference: [Git configuration retirement](https://learn.microsoft.com/en-us/azure/api-management/breaking-changes/git-configuration-retirement-march-2025)

---

## References

- [Protect APIs with Azure AD B2C](https://learn.microsoft.com/en-us/azure/api-management/howto-protect-backend-frontend-azure-ad-b2c)
- [Authorize APIM Developer Portal — Entra External ID](https://learn.microsoft.com/en-ca/azure/api-management/api-management-howto-entra-external-id)
- [validate-jwt policy reference](https://learn.microsoft.com/en-us/azure/api-management/validate-jwt-policy)
- [APIOps — Automated API Deployments](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/devops/automated-api-deployments-apiops)
- [Azure APIOps GitHub](https://github.com/Azure/apiops)
- [APIM VS Code Extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-apimanagement)
- [APIM Policy Snippets GitHub](https://github.com/Azure/api-management-policy-snippets)
- [APIM DevOps Resource Kit](https://github.com/Azure/azure-api-management-devops-resource-kit)
