# Complete Networking Patterns

## Pattern 1: Single Service + Custom Domain

```yaml
name: simple-app
region: nyc

domains:
  - domain: example.com
    type: PRIMARY

services:
  - name: web
    git:
      repo_clone_url: https://github.com/org/app.git
      branch: main
    http_port: 3000

ingress:
  rules:
    - redirect:
        authority: example.com
        redirect_code: 301
      match:
        authority: { exact: ${STARTER_DOMAIN} }
        path: { prefix: / }
```

## Pattern 2: API + Frontend (Path-Based)

```yaml
name: fullstack-app
region: nyc

domains:
  - domain: example.com
    type: PRIMARY

services:
  - name: api
    http_port: 8080

static_sites:
  - name: frontend
    build_command: npm run build
    output_dir: dist

ingress:
  rules:
    - component: { name: api }
      match: { path: { prefix: /api } }
      cors:
        allow_origins:
          - exact: https://example.com
        allow_methods: [GET, POST, PUT, DELETE, OPTIONS]
        allow_headers: [Content-Type, Authorization]

    - component: { name: frontend }
      match: { path: { prefix: / } }
```

## Pattern 3: Microservices (Subdomain-Based)

```yaml
name: microservices-app
region: nyc

domains:
  - domain: example.com
    type: PRIMARY
    wildcard: true
    zone: example.com

services:
  - name: api
    http_port: 8080
  - name: app
    http_port: 3000
  - name: admin
    http_port: 3000

ingress:
  rules:
    - component: { name: api }
      match:
        authority: { exact: api.example.com }
        path: { prefix: / }
      cors:
        allow_origins:
          - exact: https://app.example.com
          - exact: https://admin.example.com
        allow_credentials: true

    - component: { name: app }
      match:
        authority: { exact: app.example.com }
        path: { prefix: / }

    - component: { name: admin }
      match:
        authority: { exact: admin.example.com }
        path: { prefix: / }

    - redirect:
        authority: app.example.com
        redirect_code: 301
      match:
        authority: { exact: example.com }
        path: { prefix: / }
```

## Pattern 4: Multi-Tenant SaaS (Wildcard)

```yaml
name: saas-app
region: nyc

domains:
  - domain: example.com
    type: PRIMARY
    wildcard: true
    zone: example.com

services:
  - name: tenant-app
    http_port: 3000
  - name: marketing
    http_port: 3000
  - name: api
    http_port: 8080

ingress:
  rules:
    # Marketing on root
    - component: { name: marketing }
      match:
        authority: { exact: example.com }
        path: { prefix: / }

    # API subdomain
    - component: { name: api }
      match:
        authority: { exact: api.example.com }
        path: { prefix: / }

    # Tenant subdomains (regex)
    - component: { name: tenant-app }
      match:
        authority:
          regex: ^[a-z0-9-]+\.example\.com$
        path: { prefix: / }
```

## Pattern 5: Enterprise (VPC + Egress + HTTP/2)

```yaml
name: enterprise-app
region: nyc

domains:
  - domain: example.com
    type: PRIMARY
    wildcard: true
    zone: example.com
    minimum_tls_version: "1.3"

vpc:
  id: your-vpc-uuid

egress:
  type: DEDICATED_IP

enhanced_threat_control_enabled: true

services:
  - name: api
    http_port: 8080
    internal_ports: [9090]
    envs:
      - key: AUTH_URL
        value: ${auth.PRIVATE_URL}
      - key: DATABASE_URL
        value: ${db.DATABASE_URL}

  - name: auth
    http_port: 8080

  - name: grpc-service
    http_port: 50051
    protocol: HTTP2

  - name: dashboard
    http_port: 3000

workers:
  - name: worker
    envs:
      - key: API_URL
        value: ${api.PRIVATE_URL}

databases:
  - name: db
    engine: PG
    production: true

ingress:
  rules:
    - component: { name: api }
      match:
        authority: { exact: api.example.com }
        path: { prefix: / }
      cors:
        allow_origins:
          - exact: https://app.example.com
          - regex: ^https://.*\.example\.com$
        allow_methods: [GET, POST, PUT, DELETE, OPTIONS]
        allow_headers: [Content-Type, Authorization]
        allow_credentials: true

    - component: { name: dashboard }
      match:
        authority: { exact: app.example.com }
        path: { prefix: / }

    - redirect:
        authority: app.example.com
        redirect_code: 301
      match:
        authority: { exact: ${STARTER_DOMAIN} }
        path: { prefix: / }
```

## Validation

```bash
doctl apps spec validate .do/app.yaml
```

| Error | Fix |
|-------|-----|
| routes deprecated | Use ingress.rules |
| wildcard requires zone | Add zone field |
| rule conflict | Reorder (specific first) |
| credentials with regex | Use exact origins |
