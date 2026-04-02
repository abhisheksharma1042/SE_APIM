# 01 — Microsoft Entra External ID Setup (External Tenant)

> **Note:** Azure AD B2C is no longer available for new customers as of May 1, 2025.
> This guide uses **Microsoft Entra External ID** with an **external tenant**, which is Microsoft's replacement.
> If you have an existing B2C tenant, see the migration note at the bottom.

---

## What Is an External Tenant?

An **external tenant** is a dedicated Microsoft Entra ID directory specifically for your consumer or partner-facing identities. It is completely separate from your workforce (employee) tenant.

- Lives under its own domain, e.g. `contosocustomers.onmicrosoft.com`
- Manages sign-up/sign-in user flows for external users
- Issues JWTs that APIM validates via `validate-jwt` policy

---

## Step 1: Create the External Tenant

### Via Azure Portal

1. Go to [portal.azure.com](https://portal.azure.com)
2. Search for **Microsoft Entra External ID** or navigate to **Azure Active Directory** → **External Identities**
3. Click **Create external tenant**
4. Fill in:
   - **Organization name**: e.g. `Contoso Customers`
   - **Initial domain name**: e.g. `contosocustomers` (becomes `contosocustomers.onmicrosoft.com`)
   - **Location**: choose the closest Azure region
5. Click **Review + Create** → **Create**

### Via Azure CLI

```bash
# Login to your workforce tenant first
az login --tenant <workforce-tenant-id>

# Create external tenant (preview command)
az rest --method POST \
  --url "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.AzureActiveDirectory/b2cDirectories/<tenant-name>?api-version=2023-05-17-preview" \
  --body '{
    "location": "United States",
    "sku": { "name": "Standard", "tier": "A0" },
    "properties": {
      "createTenantProperties": {
        "displayName": "Contoso Customers",
        "countryCode": "US"
      }
    }
  }'
```

---

## Step 2: Register Your API in the External Tenant

Switch context to the external tenant:

```bash
az login --tenant <external-tenant-id>
```

### Register the backend API (resource)

```bash
# Register the API app
az ad app create \
  --display-name "Contoso API" \
  --sign-in-audience "AzureADandPersonalMicrosoftAccount"

# Note the appId (client_id) returned — save as API_APP_ID
API_APP_ID="<appId from above>"

# Set the Application ID URI (used as audience in JWT)
az ad app update \
  --id $API_APP_ID \
  --identifier-uris "api://$API_APP_ID"

# Expose a scope
az ad app update --id $API_APP_ID --set api='{
  "oauth2PermissionScopes": [
    {
      "id": "<generate-a-guid>",
      "adminConsentDescription": "Access the Contoso API",
      "adminConsentDisplayName": "Access Contoso API",
      "isEnabled": true,
      "type": "User",
      "userConsentDescription": "Access the Contoso API on your behalf",
      "userConsentDisplayName": "Access Contoso API",
      "value": "access_as_user"
    }
  ]
}'
```

---

## Step 3: Define App Roles (for RBAC)

App roles are the mechanism that maps to the `roles` claim in the JWT. APIM will validate these.

```bash
# Add roles to the API app registration
az ad app update --id $API_APP_ID --set appRoles='[
  {
    "id": "<generate-guid-1>",
    "allowedMemberTypes": ["User", "Application"],
    "displayName": "Reader",
    "description": "Can read data from the API",
    "value": "api.read",
    "isEnabled": true
  },
  {
    "id": "<generate-guid-2>",
    "allowedMemberTypes": ["User", "Application"],
    "displayName": "Writer",
    "description": "Can read and write data",
    "value": "api.write",
    "isEnabled": true
  },
  {
    "id": "<generate-guid-3>",
    "allowedMemberTypes": ["User", "Application"],
    "displayName": "Admin",
    "description": "Full administrative access",
    "value": "api.admin",
    "isEnabled": true
  }
]'
```

### Assigning roles to users

In the external tenant portal:
1. **Enterprise Applications** → select your API app
2. **Users and groups** → **Add user/group**
3. Select the user → select the role → **Assign**

For service principals (daemon clients), assign roles under **App registrations** → **API permissions** → grant the role as an **application permission**.

---

## Step 4: Register the Client Application (SPA or Service)

### Single-Page Application (SPA) — Auth Code + PKCE

```bash
CLIENT_APP_ID=$(az ad app create \
  --display-name "Contoso SPA Client" \
  --sign-in-audience "AzureADandPersonalMicrosoftAccount" \
  --web-redirect-uris "https://jwt.ms" "http://localhost:3000" \
  --query appId -o tsv)

# Add SPA redirect URIs (separate from web)
az ad app update --id $CLIENT_APP_ID --set spa='{
  "redirectUris": ["https://jwt.ms", "http://localhost:3000"]
}'

# Grant API permission (access_as_user scope)
az ad app permission add \
  --id $CLIENT_APP_ID \
  --api $API_APP_ID \
  --api-permissions "<scope-guid>=Scope"

az ad app permission grant \
  --id $CLIENT_APP_ID \
  --api $API_APP_ID \
  --scope "access_as_user"
```

### Daemon / Service Client — Client Credentials

```bash
DAEMON_APP_ID=$(az ad app create \
  --display-name "Contoso Daemon Client" \
  --sign-in-audience "AzureADMyOrg" \
  --query appId -o tsv)

# Create a client secret
az ad app credential reset --id $DAEMON_APP_ID --append

# Grant application role (not delegated)
az ad app permission add \
  --id $DAEMON_APP_ID \
  --api $API_APP_ID \
  --api-permissions "<role-guid>=Role"

# Admin consent required for app roles
az ad app permission admin-consent --id $DAEMON_APP_ID
```

---

## Step 5: Configure User Flows (Sign-up / Sign-in)

In the External tenant:

1. Go to **External Identities** → **User flows**
2. Click **New user flow**
3. Select **Sign up and sign in**
4. Configure:
   - **Name**: `B2C_1_susi` (keep this prefix for compatibility)
   - **Identity providers**: Email + password, optionally Google/Facebook
   - **User attributes to collect**: given name, surname, email
   - **Token claims to return**: `email`, `given_name`, `surname`, `roles`
5. Click **Create**

### OpenID Connect Discovery URL

Once created, note the discovery endpoint — used in `validate-jwt` policy:

```
https://<external-tenant-domain>.ciamlogin.com/<external-tenant-id>/v2.0/.well-known/openid-configuration
```

Or for B2C-style user flows:
```
https://<tenant>.b2clogin.com/<tenant>.onmicrosoft.com/<policy-name>/v2.0/.well-known/openid-configuration
```

---

## Step 6: Verify Token Claims

Test with the Microsoft OAuth 2.0 playground or `curl`:

```bash
# Get a token (auth code flow — use browser for SPA)
# For client credentials (daemon):
curl -X POST \
  "https://login.microsoftonline.com/<external-tenant-id>/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=<daemon-app-id>" \
  -d "client_secret=<daemon-secret>" \
  -d "scope=api://<api-app-id>/.default"

# Decode and inspect at https://jwt.ms
# Verify:
# - "iss": "https://login.microsoftonline.com/<external-tenant-id>/v2.0"
# - "aud": "api://<api-app-id>"
# - "roles": ["api.read"]  (or api.write, api.admin)
```

---

## Migration Note: Existing Azure AD B2C Tenant

If you have an existing B2C tenant (`*.onmicrosoft.com` with B2C feature):

1. Your existing `validate-jwt` policies referencing `*.b2clogin.com` still work
2. The discovery URL format is:
   ```
   https://<tenant>.b2clogin.com/<tenant>.onmicrosoft.com/<policy>/v2.0/.well-known/openid-configuration
   ```
3. Migrate to Entra External ID by registering apps in the new tenant and updating `openid-config-url` in your policies
4. Run both identity providers in parallel during migration (APIM supports multiple JWT validators)

---

## Summary of Values to Record

| Variable | Where to find | Used in |
|----------|--------------|---------|
| `EXTERNAL_TENANT_ID` | External tenant → Overview | Policy `openid-config-url` |
| `EXTERNAL_TENANT_DOMAIN` | External tenant → Overview | Policy `openid-config-url` |
| `API_APP_ID` | App registration → Overview | Policy `audience` |
| `ROLE_READER_VALUE` | App registration → App roles | Policy `required-claims` |
| `ROLE_WRITER_VALUE` | App registration → App roles | Policy `required-claims` |
| `USER_FLOW_NAME` | External Identities → User flows | Policy `openid-config-url` |

Next: [APIM Provisioning & Identity Linking →](02-apim-setup.md)
