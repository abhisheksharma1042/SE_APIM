# 04 — VS Code Local Development Workflow

Edit, test, and deploy APIM policies from your machine — never touch the Azure portal for policy changes.

---

## Required VS Code Extensions

Install all at once:

```bash
code --install-extension ms-azuretools.vscode-apimanagement
code --install-extension ms-vscode.azure-account
code --install-extension ms-azuretools.vscode-bicep
code --install-extension redhat.vscode-xml
code --install-extension GitHub.copilot
```

Or open this repo in VS Code — it will prompt you to install the recommended extensions from `.vscode/extensions.json`.

---

## `.vscode/extensions.json`

```json
{
  "recommendations": [
    "ms-azuretools.vscode-apimanagement",
    "ms-vscode.azure-account",
    "ms-azuretools.vscode-bicep",
    "redhat.vscode-xml",
    "GitHub.copilot",
    "ms-azuretools.vscode-azureresourcegroups"
  ]
}
```

## `.vscode/settings.json`

Associates APIM XML policy files with the APIM XML schema for IntelliSense:

```json
{
  "xml.fileAssociations": [
    {
      "pattern": "**/policies/**/*.xml",
      "systemId": "https://schema.management.azure.com/schemas/policy/policy.xsd"
    }
  ],
  "xml.validation.enabled": true,
  "[xml]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "redhat.vscode-xml"
  }
}
```

---

## Workflow 1: Edit Policies Locally → Deploy via VS Code Extension

### Step 1: Sign in to Azure

1. Open the **Azure** sidebar (`Ctrl+Shift+A` / `Cmd+Shift+A`)
2. Click **Sign in to Azure**
3. Complete the browser auth flow

### Step 2: Browse to your APIM instance

In the Azure sidebar:
```
AZURE
└─ API Management
     └─ contoso-apim (subscription: ...)
          ├─ APIs
          │    └─ Example Items API
          │         ├─ GET /items
          │         └─ POST /items
          ├─ Products
          └─ Named Values
```

### Step 3: Edit a policy

Right-click an API or operation → **Edit Policy**

VS Code opens the policy XML with:
- **IntelliSense** for policy elements and attributes
- **Schema validation** — red squiggles for invalid XML
- **Hover documentation** — hover any policy element to see docs

Make your edits directly in the XML file.

### Step 4: Save to deploy immediately

**Ctrl+S** (or **Cmd+S**) — the extension saves the policy directly to Azure.

> **Tip:** For production changes, use the APIOps GitOps workflow (doc 05) instead of direct save, so changes go through PR review first.

---

## Workflow 2: APIOps Extract → Edit Locally → Commit → CI/CD Deploy

This is the recommended GitOps approach for production.

### Step 1: Extract current APIM state

```bash
# Run the APIOps extractor
./scripts/extract-apim.sh
```

This pulls all APIM config into `apim-artifacts/`:

```
apim-artifacts/
├── apis/
│   └── example-api/
│       ├── apiInformation.json      # API metadata
│       ├── specification.yaml       # OpenAPI spec
│       └── policy.xml               # API-level policy
├── products/
│   └── standard/
│       ├── productInformation.json
│       └── policy.xml
├── named-values/
│   └── namedValues.json
└── backends/
    └── example-backend/
        └── backendInformation.json
```

### Step 2: Edit policies in VS Code

Open `apim-artifacts/apis/example-api/policy.xml` — full IntelliSense and validation.

### Step 3: Commit and push

```bash
git checkout -b feat/add-rate-limiting
git add apim-artifacts/apis/example-api/policy.xml
git commit -m "feat: add per-user rate limiting to example-api"
git push origin feat/add-rate-limiting
```

### Step 4: Open PR → automated pipeline deploys on merge

See [APIOps CI/CD →](05-apiops-cicd.md).

---

## Workflow 3: Policy Debugging in VS Code

The APIM VS Code extension includes a **policy debugger** that lets you step through the policy pipeline on a live gateway request.

### Prerequisites

- APIM **Developer** tier (policy debugger requires Developer tier or consumption with specific setup)
- The VS Code extension v1.x+

### Enable the debugger

1. In VS Code, right-click your API operation → **Debug Policy**
2. The extension:
   - Activates a special debug subscription key
   - Installs a temporary listener policy
   - Opens the debugger panel

### Set breakpoints

Open the policy XML, click in the gutter to add a breakpoint on any policy element:

```xml
<validate-jwt ...>   <!-- ← breakpoint here: inspect incoming token -->
  ...
</validate-jwt>
<set-variable name="callerRole" .../>   <!-- ← breakpoint: inspect extracted role -->
<choose>   <!-- ← breakpoint: see which branch is taken -->
```

### Send a test request

In the extension's test panel, add:
- **Authorization**: `Bearer <your-token>`
- **Headers**: any custom headers

Click **Send** — execution pauses at your breakpoints. Inspect:
- `context.Request.Headers`
- `context.Variables` (your `callerRole` variable)
- `context.Response.StatusCode`

---

## Workflow 4: GitHub Copilot for Policy Authoring

With GitHub Copilot installed:

1. Open a policy XML file
2. Add a comment describing what you need:

```xml
<!-- validate JWT from Entra External ID, require api.write or api.admin role, return 403 with JSON body on failure -->
```

3. Copilot suggests the full `<validate-jwt>` block — review and accept

Or use the Copilot chat sidebar:
> "Write an APIM policy that validates a JWT from `contoso.ciamlogin.com`, extracts the `roles` claim, and returns a 403 if the caller doesn't have `api.admin`"

---

## Common Policy Editing Tips

### Named Values in policies

Reference Named Values with double curly braces — VS Code IntelliSense lists available values:
```xml
<openid-config url="https://{{external-tenant-domain}}.ciamlogin.com/{{external-tenant-id}}/v2.0/.well-known/openid-configuration" />
```

### Policy expressions (C#)

Policy expressions use C# inline — VS Code highlights them:
```xml
<set-variable name="userId" value="@(context.Request.Headers.GetValueOrDefault("X-User-Id", "anonymous"))" />
```

### Validate before deploying

```bash
# Lint XML structure
xmllint --noout policies/apis/example-api/api-policy.xml
```

### View policy effective state

In the Azure portal or VS Code extension: **Effective Policy** shows the merged result of global + product + API + operation policies — useful for debugging inheritance.

---

## Quick Reference: VS Code Extension Commands

| Command | Action |
|---------|--------|
| Right-click API → Edit Policy | Open policy XML for editing |
| Ctrl+S on policy file | Save and deploy to Azure directly |
| Right-click operation → Debug Policy | Launch policy debugger |
| Right-click API → Test | Send test HTTP request |
| Right-click API → Extract to file | Download OpenAPI spec |
| Azure sidebar → Named Values | Manage named values |

Next: [APIOps CI/CD Pipeline →](05-apiops-cicd.md)
