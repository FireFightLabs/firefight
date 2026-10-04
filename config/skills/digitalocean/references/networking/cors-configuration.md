# CORS Configuration

Cross-Origin Resource Sharing controls which domains can make API requests.

## Basic Configuration

```yaml
ingress:
  rules:
    - component: { name: api }
      match: { path: { prefix: /api } }
      cors:
        allow_origins:
          - exact: https://example.com
        allow_methods:
          - GET
          - POST
        allow_headers:
          - Content-Type
        max_age: "1h"
```

## CORS Fields

| Field | Description |
|-------|-------------|
| `allow_origins` | Domains allowed to make requests |
| `allow_methods` | HTTP methods allowed |
| `allow_headers` | Request headers allowed |
| `expose_headers` | Response headers exposed |
| `max_age` | Preflight cache ("1h" to "24h") |
| `allow_credentials` | Allow cookies/auth |

## allow_origins Patterns

**Exact match:**
```yaml
allow_origins:
  - exact: https://example.com
  - exact: https://app.example.com
```

**Regex match:**
```yaml
allow_origins:
  - regex: ^https://.*\.example\.com$
```

**Combined:**
```yaml
allow_origins:
  - exact: https://example.com
  - regex: ^https://[a-z0-9-]+\.example\.com$
```

## Cross-Subdomain CORS

```yaml
cors:
  allow_origins:
    - exact: https://app.example.com
    - exact: https://admin.example.com
  allow_methods:
    - GET
    - POST
    - PUT
    - DELETE
    - OPTIONS
  allow_headers:
    - Content-Type
    - Authorization
  allow_credentials: true
```

## CORS with Credentials

When `allow_credentials: true`:
- Cannot use regex in `allow_origins`
- Must use exact origins only
- Cookies and auth headers will be sent

```yaml
cors:
  allow_origins:
    - exact: https://app.example.com  # Must be exact
  allow_credentials: true
```

## Preflight Requests

Browsers send OPTIONS preflight for:
- Non-simple methods (PUT, DELETE)
- Custom headers (Authorization)
- Non-standard Content-Type

**Always include OPTIONS:**
```yaml
cors:
  allow_methods:
    - GET
    - POST
    - PUT
    - DELETE
    - OPTIONS  # Required for preflight
```

## Common CORS Errors

| Error | Fix |
|-------|-----|
| No Access-Control-Allow-Origin | Add origin to allow_origins |
| Method not allowed | Add method to allow_methods |
| Preflight fails | Add OPTIONS to allow_methods |
| Credentials not supported | Use exact origins only |
