# doctl Database Reference

Common `doctl databases` commands for Postgres management.

## Cluster Management

```bash
# List clusters
doctl databases list

# Get cluster details
doctl databases get <cluster-id>

# Get admin connection string
doctl databases connection <cluster-id>

# Create new cluster
doctl databases create my-cluster \
  --engine pg \
  --version 16 \
  --region nyc3 \
  --size db-s-1vcpu-2gb \
  --num-nodes 1
```

## Users & Databases

```bash
# Create database
doctl databases db create <cluster-id> myappdb

# List databases
doctl databases db list <cluster-id>

# Create user (DO manages password)
doctl databases user create <cluster-id> myappuser

# List users
doctl databases user list <cluster-id>
```

## Connection Pools

```bash
# Create pool
doctl databases pool create <cluster-id> myapp_pool \
  --db myappdb \
  --mode transaction \
  --size 25 \
  --user myappuser

# List pools
doctl databases pool list <cluster-id>

# Get pool connection string
doctl databases pool get <cluster-id> myapp_pool
```

**Pool modes**:
| Mode | Use Case |
|------|----------|
| `transaction` | Default, most apps |
| `session` | Long-running connections |
| `statement` | Simple queries only |

## Firewall Rules

```bash
# Add IP whitelist
doctl databases firewalls append <cluster-id> --rule ip_addr:203.0.113.0

# Add App Platform app
doctl databases firewalls append <cluster-id> --rule app:<app-id>

# List rules
doctl databases firewalls list <cluster-id>
```

## Replicas

```bash
# Create read replica
doctl databases replica create <cluster-id> my-replica \
  --region nyc3 \
  --size db-s-1vcpu-2gb

# List replicas
doctl databases replica list <cluster-id>

# Get replica connection
doctl databases replica connection <cluster-id> my-replica
```

## Connection Tuning SQL

Run as doadmin after pool setup:

```sql
-- Statement timeout
ALTER USER myappuser SET statement_timeout = '30s';

-- Idle transaction timeout
ALTER USER myappuser SET idle_in_transaction_session_timeout = '60s';

-- Connection limit per user
ALTER USER myappuser CONNECTION LIMIT 50;
```

## Diagnostic Queries

```sql
-- Current connections
SELECT count(*) FROM pg_stat_activity;

-- Max connections
SHOW max_connections;

-- Who's connected
SELECT usename, application_name, client_addr, state, query_start
FROM pg_stat_activity
WHERE datname = 'myappdb'
ORDER BY query_start DESC;
```
