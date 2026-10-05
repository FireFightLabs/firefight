# Ingress and Routing

Use `ingress.rules` for all routing. The `routes` field is deprecated.

## Path-Based Routing

```yaml
ingress:
  rules:
    - component: { name: api }
      match: { path: { prefix: /api } }
    - component: { name: frontend }
      match: { path: { prefix: / } }
```

**Rule order matters:** More specific rules first.

## Path Rewriting

```yaml
ingress:
  rules:
    # /v1/api/* → /api/*
    - component:
        name: api
        rewrite: /api
      match:
        path:
          prefix: /v1/api
```

## preserve_path_prefix

```yaml
# preserve_path_prefix: true → /api/users/123 → /api/users/123
# preserve_path_prefix: false → /api/users/123 → /users/123
```

## Authority-Based (Subdomain) Routing

```yaml
ingress:
  rules:
    - component: { name: api }
      match:
        authority: { exact: api.example.com }
        path: { prefix: / }

    - component: { name: frontend }
      match:
        authority: { exact: app.example.com }
        path: { prefix: / }
```

## Regex Authority Matching

```yaml
ingress:
  rules:
    # Any tenant subdomain
    - component: { name: tenant-app }
      match:
        authority:
          regex: ^[a-z0-9-]+\.example\.com$
        path: { prefix: / }
```

## Combined Authority + Path

```yaml
ingress:
  rules:
    - component: { name: api-legacy }
      match:
        authority: { exact: api.example.com }
        path: { prefix: /v1 }

    - component: { name: api-v2 }
      match:
        authority: { exact: api.example.com }
        path: { prefix: / }
```

## HTTP Redirects

```yaml
ingress:
  rules:
    # Path redirect
    - redirect:
        uri: /new-path
        redirect_code: 301
      match:
        path: { prefix: /old-path }

    # Domain redirect
    - redirect:
        authority: newsite.com
        redirect_code: 302
      match:
        path: { prefix: /legacy }
```

**Redirect codes:**
| Code | Use |
|------|-----|
| 301 | Permanent (SEO) |
| 302 | Temporary |
| 307 | Preserve method |
| 308 | Permanent, preserve method |

## Starter Domain Redirect

```yaml
- redirect:
    authority: app.example.com
    redirect_code: 301
  match:
    authority: { exact: ${STARTER_DOMAIN} }
    path: { prefix: / }
```

## www to non-www

```yaml
- redirect:
    authority: example.com
    redirect_code: 301
  match:
    authority: { exact: www.example.com }
    path: { prefix: / }
```

## Rewrite vs Redirect

| Aspect | Rewrite | Redirect |
|--------|---------|----------|
| Browser URL | Unchanged | Changes |
| HTTP status | 200 | 301/302 |
| Cross-domain | No | Yes |
