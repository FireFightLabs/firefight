# Bindable Variables Reference

Single source of truth for App Platform bindable environment variables across all skills.

## Overview

Bindable variables are placeholder values in your app spec that App Platform automatically resolves at runtime. They allow components to reference each other and access database credentials without hardcoding values.

## Database Bindable Variables

When you attach a database (dev or managed) to your app, App Platform exposes these variables:

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `${db.DATABASE_URL}` | Full connection string | `postgresql://user:pass@host:25060/dbname?sslmode=require` |
| `${db.HOSTNAME}` | Database host | `cluster-do-user-123.db.ondigitalocean.com` |
| `${db.PORT}` | Database port | `25060` |
| `${db.USERNAME}` | Database user | `myappuser` |
| `${db.PASSWORD}` | Database password | (auto-generated) |
| `${db.DATABASE}` | Database name | `myappdb` |
| `${db.CA_CERT}` | CA certificate for TLS | (certificate content) |

Where `db` is the **component name** from your app spec's `databases` section.

### Database Example

```yaml
databases:
  - name: db                    # This name is used in bindable vars
    engine: PG
    production: true
    cluster_name: my-cluster
    db_name: myappdb
    db_user: myappuser

services:
  - name: api
    envs:
      - key: DATABASE_URL
        scope: RUN_TIME
        value: ${db.DATABASE_URL}    # Uses "db" from database name
      - key: DB_HOST
        scope: RUN_TIME
        value: ${db.HOSTNAME}
```

### Multiple Databases

```yaml
databases:
  - name: primary
    engine: PG
    production: true
    cluster_name: main-db
  - name: analytics
    engine: PG
    production: true
    cluster_name: analytics-db

services:
  - name: api
    envs:
      - key: DATABASE_URL
        value: ${primary.DATABASE_URL}
      - key: ANALYTICS_DB_URL
        value: ${analytics.DATABASE_URL}
```

## Cache/Valkey Bindable Variables

For Valkey (Redis replacement) databases:

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `${cache.DATABASE_URL}` | Valkey connection string | `rediss://user:pass@host:25061?ssl=true` |
| `${cache.HOSTNAME}` | Cache host | `cache-do-user-123.db.ondigitalocean.com` |
| `${cache.PORT}` | Cache port | `25061` |
| `${cache.USERNAME}` | Cache user | `default` |
| `${cache.PASSWORD}` | Cache password | (auto-populated) |

### Valkey Example

```yaml
databases:
  - name: cache
    engine: VALKEY
    production: false           # Dev Valkey database

services:
  - name: api
    envs:
      - key: VALKEY_URL
        scope: RUN_TIME
        value: ${cache.DATABASE_URL}
      # Alias for backwards compatibility with Redis clients
      - key: REDIS_URL
        scope: RUN_TIME
        value: ${cache.DATABASE_URL}
```

## Connection Pool Variables

For PostgreSQL connection pools:

```yaml
envs:
  - key: DATABASE_POOL_URL
    scope: RUN_TIME
    value: ${db.pool-name.DATABASE_URL}
```

Where `pool-name` is the name of the connection pool created via:
```bash
doctl databases pool create $CLUSTER_ID pool-name \
  --db myappdb \
  --mode transaction \
  --size 25 \
  --user myappuser
```

## Component Reference Variables

Reference other components in your app using the format `${component-name.VARIABLE}`.

### App-Wide Variables

Available across all components:

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `${APP_DOMAIN}` | App's primary domain | `myapp-xyz.ondigitalocean.app` |
| `${APP_URL}` | App's URL with protocol | `https://myapp-xyz.ondigitalocean.app` |
| `${APP_ID}` | App's unique identifier | `a1b2c3d4-5678-90ab-cdef` |

### Self-Reference Prefix

Use `_self` to reference the current component without hardcoding its name:

```yaml
services:
  - name: api
    envs:
      - key: MY_PUBLIC_URL
        scope: RUN_TIME
        value: ${_self.PUBLIC_URL}    # Resolves to this component's URL
      - key: COMMIT
        scope: RUN_TIME
        value: ${_self.COMMIT_HASH}   # Git commit for this build
```

### Variables by Component Type

**Services:**

| Variable | Description | Availability |
|----------|-------------|--------------|
| `${_self.PRIVATE_DOMAIN}` | Internal domain for VPC communication | Runtime |
| `${_self.PRIVATE_URL}` | Internal URL with port | Runtime |
| `${_self.PRIVATE_PORT}` | Internal HTTP port | Runtime |
| `${_self.PUBLIC_URL}` | Public URL with route | Build & Runtime |
| `${_self.PUBLIC_ROUTE_PATH}` | Public routable path | Build & Runtime |
| `${_self.COMMIT_HASH}` | Git commit hash | Build & Runtime |

**Static Sites:**

| Variable | Description | Availability |
|----------|-------------|--------------|
| `${_self.PUBLIC_URL}` | Public URL with route | Build & Runtime |
| `${_self.PUBLIC_ROUTE_PATH}` | Public routable path | Build & Runtime |
| `${_self.COMMIT_HASH}` | Git commit hash | Build & Runtime |

**Workers:**

| Variable | Description | Availability |
|----------|-------------|--------------|
| `${_self.COMMIT_HASH}` | Git commit hash | Build & Runtime |

**Functions:**

| Variable | Description | Availability |
|----------|-------------|--------------|
| `${_self.PUBLIC_URL}` | Public URL with route | Build & Runtime |
| `${_self.PUBLIC_ROUTE_PATH}` | Public routable path | Build & Runtime |
| `${_self.COMMIT_HASH}` | Git commit hash | Build & Runtime |
| `${_self.FUNCTIONS_LOG_DESTINATION_JSON}` | JSON of log forwarding config | Runtime |

### Cross-Component Reference

Reference other components by name:

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `${component.PRIVATE_URL}` | Internal URL (VPC) | `http://api.myapp.internal:8080` |
| `${component.PUBLIC_URL}` | Public URL | `https://api-xyz.ondigitalocean.app` |

### Component Reference Example

```yaml
services:
  - name: api
    http_port: 8080
    # ...

static_sites:
  - name: frontend
    envs:
      - key: NEXT_PUBLIC_API_URL
        scope: BUILD_TIME
        value: ${api.PUBLIC_URL}

workers:
  - name: processor
    envs:
      - key: API_INTERNAL_URL
        scope: RUN_TIME
        value: ${api.PRIVATE_URL}    # Use internal URL for VPC communication
```

## Supported Database Engines

| Engine | Slug | Dev DB Available | Bindable Variables |
|--------|------|------------------|-------------------|
| PostgreSQL | `PG` | Yes | All standard vars |
| MySQL | `MYSQL` | No | All standard vars |
| Valkey | `VALKEY` | Yes | All standard vars |
| MongoDB | `MONGODB` | No | All standard vars |
| Kafka | `KAFKA` | No | Special vars (brokers, etc.) |
| OpenSearch | `OPENSEARCH` | No | All standard vars |

## Requirements for Bindable Variables to Work

### For Dev Databases
- Set `production: false` (or omit)
- App Platform creates and manages the database automatically

### For Managed Databases
1. **Cluster must exist** before deployment
2. **User must be created via DO interface** (Console, API, or `doctl`)
3. Set `production: true` in app spec
4. Set `cluster_name` to match existing cluster exactly
5. Optionally set `db_name` and `db_user`

### What Does NOT Work

❌ **Users created via raw SQL**
```sql
-- This user's password is NOT accessible to App Platform
CREATE USER myuser WITH PASSWORD 'mypassword';
```
App Platform can only retrieve credentials for users created through DigitalOcean's interface.

❌ **External databases**
Bindable variables only work with DigitalOcean Managed Databases.

## Common Patterns

### Standard Web App with Database

```yaml
databases:
  - name: db
    engine: PG
    production: false

services:
  - name: web
    envs:
      - key: DATABASE_URL
        scope: RUN_TIME
        value: ${db.DATABASE_URL}
```

### API with Database and Cache

```yaml
databases:
  - name: db
    engine: PG
    production: true
    cluster_name: prod-db
    db_user: apiuser
  - name: cache
    engine: VALKEY
    production: false

services:
  - name: api
    envs:
      - key: DATABASE_URL
        scope: RUN_TIME
        value: ${db.DATABASE_URL}
      - key: CACHE_URL
        scope: RUN_TIME
        value: ${cache.DATABASE_URL}
```

### Frontend Referencing API

```yaml
services:
  - name: api
    http_port: 8080

static_sites:
  - name: frontend
    envs:
      - key: VITE_API_URL
        scope: BUILD_TIME
        value: ${api.PUBLIC_URL}
```

### Multi-App Shared Cluster

```yaml
databases:
  - name: app1db
    engine: PG
    production: true
    cluster_name: shared-cluster
    db_name: app1db
    db_user: app1user
  - name: app2db
    engine: PG
    production: true
    cluster_name: shared-cluster
    db_name: app2db
    db_user: app2user

services:
  - name: app1-api
    envs:
      - key: DATABASE_URL
        value: ${app1db.DATABASE_URL}
  - name: app2-api
    envs:
      - key: DATABASE_URL
        value: ${app2db.DATABASE_URL}
```

## Troubleshooting

### Variables showing `${...}` literally

**Cause**: Name mismatch between database component and reference.

**Fix**: Ensure the name in `${name.DATABASE_URL}` matches the `name:` field in your `databases:` section exactly.

### "password authentication failed"

**Cause**: User was created via SQL instead of doctl/Console.

**Fix**: Create user via `doctl databases user create` or DigitalOcean Console.

### "connection refused"

**Cause**: Firewall rules not allowing App Platform.

**Fix**:
```bash
doctl databases firewalls append $CLUSTER_ID --rule app:$APP_ID
```

## Related Documentation

- [App Spec Reference](https://docs.digitalocean.com/products/app-platform/reference/app-spec/)
- [Managed Databases](https://docs.digitalocean.com/products/databases/)
- [Database Users](https://docs.digitalocean.com/products/databases/postgresql/how-to/manage-users-and-databases/)
