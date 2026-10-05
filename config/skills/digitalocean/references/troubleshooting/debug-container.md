# Debug Container

Isolate infrastructure from application issues in ~30-45 seconds.

**Source**: [github.com/bikramkgupta/do-app-debug-container](https://github.com/bikramkgupta/do-app-debug-container)

## Why Use It

| Aspect | Debug Container | Full App Redeploy |
|--------|-----------------|-------------------|
| Deploy time | ~30-45 seconds | 5-7 minutes |
| DB clients | Pre-installed | None |
| Network tools | Pre-installed | None |
| Purpose | Infrastructure validation | Everything |

**Available Images**:
- `ghcr.io/bikramkgupta/debug-python:latest`
- `ghcr.io/bikramkgupta/debug-node:latest`

## Decision Logic

```
Database/Network Issue?
├── Step 1: Deploy debug container (~30-45s)
├── Step 2: Run validate-infra
├── If works → Issue is APPLICATION code
└── If fails → Issue is INFRASTRUCTURE
```

## Add to App Spec

```yaml
vpc:
  id: <vpc-uuid>

services:
  - name: debug
    image:
      registry_type: GHCR
      registry: ghcr.io
      repository: bikramkgupta/debug-python
      tag: latest
    http_port: 8080
    instance_count: 1
    instance_size_slug: apps-s-1vcpu-2gb
    envs:
      - key: DATABASE_URL
        scope: RUN_TIME
        value: ${db.DATABASE_URL}
      - key: DATABASE_PRIVATE_URL
        scope: RUN_TIME
        type: SECRET
        value: postgresql://user:pass@private-xxx:25060/db?sslmode=require

databases:
  - name: db
    engine: PG
    production: true
    cluster_name: your-cluster
    db_name: your-database
    db_user: your-user
```

## Deploy and Connect

```bash
# Deploy
doctl apps update <app-id> --spec app-spec.yaml

# Wait for ACTIVE
doctl apps get <app-id> -o json | jq -r '.[0].active_deployment.phase'
```

**SDK (for AI assistants)**:
```python
from do_app_sandbox import Sandbox

debug = Sandbox.get_from_id(app_id="your-app-id", component="debug")
result = debug.exec("whoami")
```

**Console (for humans)**:
```bash
doctl apps console <app-id> debug
```

## Validation Suite

```bash
# Full validation
validate-infra all

# Specific checks
validate-infra database      # PostgreSQL/MySQL/MongoDB CRUD
validate-infra cache         # Redis/Valkey PING, SET, GET
validate-infra kafka         # Auth, topics, produce/consume
validate-infra opensearch    # Health, index CRUD, search
validate-infra spaces        # S3 PUT, GET, LIST, DELETE
validate-infra network       # DNS, HTTPS egress
validate-infra env           # Environment variables
```

**What it validates**:

| Command | Checks |
|---------|--------|
| `database` | SSL, auth, CREATE/INSERT/UPDATE/DELETE |
| `cache` | PING, SET/GET/DELETE |
| `kafka` | SASL auth, topics, produce/consume |
| `opensearch` | Health, index CRUD, search |
| `spaces` | Bucket access, object operations |
| `network` | DNS, HTTPS, registry access |
| `env` | Required vars set, bindables resolved |

## Built-in Scripts

```bash
# Comprehensive diagnostic
/app/scripts/diagnose.sh

# Test specific database
/app/scripts/test-db.sh postgres  # or: mysql, mongo, redis, kafka

# Test network
/app/scripts/test-connectivity.sh

# Test Spaces (map variables first)
export SPACES_KEY="$SPACES_ACCESS_KEY"
export SPACES_SECRET="$SPACES_SECRET_KEY"
export SPACES_ENDPOINT="${SPACES_ENDPOINT#https://}"
/app/scripts/test-spaces.sh
```

## Interpreting Results

| Symptom | Cause | Fix |
|---------|-------|-----|
| Variables empty | Database not attached | Check `databases` section |
| Variables show `${name.X}` literally | Name mismatch | Match database `name` field |
| DNS fails | Network/region mismatch | Check VPC settings |
| Connection refused | Trusted sources | Add VPC CIDR to trusted sources |
| Auth failed | SQL-created user | Recreate via `doctl databases user create` |
| SSL error | Missing sslmode | Use bindable variable |

## Lifecycle Management

**Archive when done** (preserve config, stop charges):
```yaml
maintenance:
  archive: true
```

**Delete when complete**:
```bash
doctl apps delete <debug-app-id>
```

## When to Use

**Use when:**
- App deploys but can't connect to database
- Setting up new managed database
- Troubleshooting connection refused errors
- Testing VPC connectivity

**Skip when:**
- Using dev database
- Issue is clearly application-level
- Infrastructure already verified
