# 03 — Role-Based Access Control Policies

APIM policies are XML documents applied at four scopes (outer to inner):

```
Global (service-wide)
  └─ Product
       └─ API
            └─ Operation
```

Policies at inner scopes override or extend outer ones using `<base />`.

---

## RBAC Strategy

| Role value (JWT `roles` claim) | Allowed operations |
|-------------------------------|-------------------|
| `api.read` | GET only |
| `api.write` | GET + POST + PUT |
| `api.admin` | All — including DELETE, admin endpoints |

The flow in each policy:
1. **Validate the JWT** — verify signature, issuer, audience, expiry
2. **Extract the role** — read `roles` claim from validated token
3. **Enforce authorization** — allow/deny based on role vs. the current operation

---

## Global Policy

`policies/global/global-policy.xml` — applied to every request through the gateway.

```xml
<policies>
  <inbound>
    <base />
    <!-- CORS — allow your SPA origins -->
    <cors allow-credentials="true">
      <allowed-origins>
        <origin>https://app.contoso.com</origin>
        <origin>http://localhost:3000</origin>
      </allowed-origins>
      <allowed-methods preflight-result-max-age="300">
        <method>GET</method><method>POST</method>
        <method>PUT</method><method>DELETE</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>Authorization</header>
        <header>Content-Type</header>
        <header>Ocp-Apim-Subscription-Key</header>
      </allowed-headers>
    </cors>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <!-- Strip internal headers before returning to client -->
    <set-header name="X-Powered-By" exists-action="delete" />
    <set-header name="X-AspNet-Version" exists-action="delete" />
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
```

---

## API-Level Policy — JWT Validation

`policies/apis/example-api/api-policy.xml`

This policy runs for every call to the `example-api` regardless of operation. It validates the JWT and extracts the role into a variable for use by operation-level policies.

```xml
<policies>
  <inbound>
    <base />

    <!--
      validate-jwt: Verify the Bearer token issued by Entra External ID.
      Replace these values with your Named Values or literals:
        - openid-config-url: OIDC discovery endpoint for your external tenant
        - audience:          Application ID URI of your registered API
    -->
    <validate-jwt
      header-name="Authorization"
      failed-validation-httpcode="401"
      failed-validation-error-message="Unauthorized: valid Bearer token required"
      require-expiration-time="true"
      require-scheme="Bearer"
      require-signed-tokens="true">

      <openid-config url="https://{{external-tenant-domain}}.ciamlogin.com/{{external-tenant-id}}/v2.0/.well-known/openid-configuration" />

      <!--
        For B2C user flows (existing tenants), use:
        <openid-config url="https://{{b2c-tenant}}.b2clogin.com/{{b2c-tenant}}.onmicrosoft.com/{{user-flow-name}}/v2.0/.well-known/openid-configuration" />
      -->

      <audiences>
        <audience>{{api-app-id}}</audience>
        <!-- Also accept the Application ID URI form -->
        <audience>api://{{api-app-id}}</audience>
      </audiences>

      <issuers>
        <issuer>https://login.microsoftonline.com/{{external-tenant-id}}/v2.0</issuer>
        <!-- Entra External ID CIAM issuer -->
        <issuer>https://{{external-tenant-domain}}.ciamlogin.com/{{external-tenant-id}}/v2.0</issuer>
      </issuers>

    </validate-jwt>

    <!--
      Extract the roles claim from the validated JWT and store it in a
      context variable for use in operation-level policies.
      The roles claim is an array; we take the first (or specific) value.
    -->
    <set-variable
      name="callerRole"
      value="@{
        var jwt = context.Request.Headers.GetValueOrDefault("Authorization","").Split(' ').Last();
        var decoded = System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler()
                        .ReadJwtToken(jwt);
        var roles = decoded.Claims
                      .Where(c => c.Type == "roles")
                      .Select(c => c.Value)
                      .ToArray();
        // Return highest privilege role found
        if (roles.Contains("api.admin"))  return "api.admin";
        if (roles.Contains("api.write"))  return "api.write";
        if (roles.Contains("api.read"))   return "api.read";
        return "none";
      }" />

  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
```

---

## Operation-Level Policies — Enforce Role Per HTTP Method

### GET /items — Reader role required

`policies/apis/example-api/get-items-operation-policy.xml`

```xml
<policies>
  <inbound>
    <base />
    <!-- Allow api.read, api.write, or api.admin -->
    <choose>
      <when condition="@(
        context.Variables.GetValueOrDefault<string>("callerRole") == "none"
      )">
        <return-response>
          <set-status code="403" reason="Forbidden" />
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>{"error": "Forbidden", "message": "api.read role or higher required"}</set-body>
        </return-response>
      </when>
    </choose>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
```

### POST /items — Writer role required

```xml
<policies>
  <inbound>
    <base />
    <choose>
      <when condition="@{
        var role = context.Variables.GetValueOrDefault<string>("callerRole", "none");
        return role != "api.write" && role != "api.admin";
      }">
        <return-response>
          <set-status code="403" reason="Forbidden" />
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>{"error": "Forbidden", "message": "api.write role or higher required"}</set-body>
        </return-response>
      </when>
    </choose>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
```

### DELETE /items/{id} — Admin role required

```xml
<policies>
  <inbound>
    <base />
    <choose>
      <when condition="@(
        context.Variables.GetValueOrDefault<string>("callerRole") != "api.admin"
      )">
        <return-response>
          <set-status code="403" reason="Forbidden" />
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>{"error": "Forbidden", "message": "api.admin role required"}</set-body>
        </return-response>
      </when>
    </choose>
    <!-- Add rate limiting for admin ops -->
    <rate-limit-by-key
      calls="100"
      renewal-period="60"
      counter-key="@(context.Request.Headers.GetValueOrDefault("Authorization",""))" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
```

---

## Product-Level Policy — Rate Limiting by Subscription

`policies/products/standard-product-policy.xml`

```xml
<policies>
  <inbound>
    <base />
    <!-- Per-subscription rate limit -->
    <rate-limit calls="1000" renewal-period="3600" />
    <!-- Per-subscription quota -->
    <quota calls="10000" renewal-period="86400" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
```

---

## Alternative: `validate-jwt` with Required Claims (Simpler)

For cases where a single role check is needed at the API level without `set-variable`:

```xml
<validate-jwt header-name="Authorization"
              failed-validation-httpcode="403"
              failed-validation-error-message="Insufficient permissions">
  <openid-config url="https://{{external-tenant-domain}}.ciamlogin.com/{{external-tenant-id}}/v2.0/.well-known/openid-configuration" />
  <audiences>
    <audience>{{api-app-id}}</audience>
  </audiences>
  <required-claims>
    <!-- User must have AT LEAST ONE of these roles -->
    <claim name="roles" match="any">
      <value>api.read</value>
      <value>api.write</value>
      <value>api.admin</value>
    </claim>
  </required-claims>
</validate-jwt>
```

---

## Delegated vs. Application Permissions

| Token type | Flow | `roles` claim present? | Use case |
|-----------|------|----------------------|---------|
| User token | Auth code / PKCE | Yes — user's assigned roles | SPA calling on behalf of user |
| App token | Client credentials | Yes — app's assigned roles | Daemon / service-to-service |
| User token | Resource Owner Password | Yes | Legacy (avoid) |

> For delegated flows, check both `roles` (app roles) and `scp` (delegated scopes) depending on your model.

---

## Testing Policies with the Policy Debugger

See [VS Code Local Dev →](04-vscode-local-dev.md) for step-by-step debugging.

Next: [VS Code Local Dev Workflow →](04-vscode-local-dev.md)
