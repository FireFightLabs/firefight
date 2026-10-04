# Valkey (Redis-Compatible) Reference

Complete guide for DigitalOcean Managed Valkey on App Platform.

---

## Create Cluster

```bash
# Create cluster
doctl databases create my-valkey \
  --engine redis \
  --region nyc3 \
  --size db-s-1vcpu-2gb \
  --version 7

CLUSTER_ID=$(doctl databases list --format ID,Name --no-header | grep my-valkey | awk '{print $1}')

# Add to trusted sources
APP_ID=$(doctl apps list --format ID,Spec.Name --no-header | grep my-app | awk '{print $1}')
doctl databases firewalls append $CLUSTER_ID --rule app:$APP_ID
```

---

## App Spec

```yaml
databases:
  - name: cache
    engine: REDIS
    production: true
    cluster_name: my-valkey

services:
  - name: api
    envs:
      - key: REDIS_URL
        scope: RUN_TIME
        value: ${cache.DATABASE_URL}
      # Or individual:
      - key: REDIS_HOST
        value: ${cache.HOSTNAME}
      - key: REDIS_PORT
        value: ${cache.PORT}
      - key: REDIS_PASSWORD
        value: ${cache.PASSWORD}
```

---

## Connection String Format

```
rediss://default:<password>@<host>:25061
```

> **Note**: Protocol is `rediss://` (with SSL) — NOT `redis://`

---

## Constraints and Defaults

| Constraint | Details |
|------------|---------|
| Engine in app spec | `REDIS` (Valkey is Redis-compatible drop-in) |
| Protocol | `rediss://` (with SSL) — NOT `redis://` |
| Port | **25061** (not the standard 6379) |
| Default user | `default` (not configurable) |
| Database number | Always db 0 (no multi-db support) |
| Default eviction | `noeviction` — Valkey stops accepting writes when full |
| Trusted sources | Supported |

---

## Eviction Policies

Default is `noeviction` which can cause Valkey to stop responding when memory is full.

**Change via Console**: Databases → my-valkey → Settings → Eviction Policy

| Policy | Behavior | Use Case |
|--------|----------|----------|
| `noeviction` | Error when full (default) | When app manages key deletion |
| `allkeys-lru` | Evict least recently used | **Recommended for caching** |
| `allkeys-lfu` | Evict least frequently used | Hot/cold data patterns |
| `volatile-ttl` | Evict keys with shortest TTL | When you set explicit TTLs |

> **Tip**: Use `INFO` command to monitor cache hits/misses and tune eviction policy.

---

## Troubleshooting

### "Connection refused"

Ensure using SSL protocol:

```bash
# Wrong
redis://host:25061

# Correct
rediss://default:password@host:25061
```

### "NOAUTH Authentication required"

Include password in connection:

```bash
rediss://default:YOUR_PASSWORD@host:25061
```

### Valkey stops accepting writes

Memory is full with `noeviction` policy. Change to `allkeys-lru` for caching workloads.

---

## Documentation Links

- [Redis/Valkey on DigitalOcean](https://docs.digitalocean.com/products/databases/redis/)
- [doctl databases reference](https://docs.digitalocean.com/reference/doctl/reference/databases/)
