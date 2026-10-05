# Bundled Scripts

Helper scripts for database setup and management.

## secure_setup.sh / secure_setup.py (Recommended for Path B)

Hands-free secure setup — creates user and stores credentials directly in GitHub Secrets. Password is NEVER displayed.

```bash
# Bash version
./scripts/secure_setup.sh \
  --admin-url "$ADMIN_URL" \
  --app-name myapp \
  --schema myapp \
  --repo owner/repo \
  --env production

# Python version (cross-platform)
python scripts/secure_setup.py \
  --admin-url "$ADMIN_URL" \
  --app-name myapp \
  --repo owner/repo \
  --env production
```

**Options**:
| Flag | Description |
|------|-------------|
| `--admin-url` | Admin connection string (required) |
| `--app-name` | Application name (required) |
| `--repo` | GitHub repository owner/repo (required) |
| `--schema` | Schema name (defaults to app-name) |
| `--env` | GitHub environment (staging, production) |
| `--secret-name` | Secret name (default: DATABASE_URL) |
| `--dry-run` | Show plan without executing |
| `--skip-confirm` | Skip confirmation prompt |

**Prerequisites**:
```bash
psql --version          # PostgreSQL client
gh auth status          # GitHub CLI (authenticated)
gh secret list --repo owner/repo  # Test access
```

## create_schema_user.py

Creates a schema with dedicated user. Supports generate and execute modes.

```bash
# Generate SQL files (for manual review)
python scripts/create_schema_user.py myapp myapp_user "password" \
  --generate --output-dir ./sql

# Execute directly (dev/test only)
python scripts/create_schema_user.py myapp myapp_user "password" \
  --execute --connection-string "$ADMIN_URL"
```

## list_schemas_users.py

Audit existing schemas and their permissions.

```bash
python scripts/list_schemas_users.py "$ADMIN_URL"
```

**Output**: Table of schemas, owners, users, and table counts.

## generate_connection_string.py

Generate formatted connection strings for application users.

```bash
python scripts/generate_connection_string.py "$ADMIN_URL" myapp_user "password"
```

**Output**: Connection string in multiple formats (URI, components, env vars).

## add_client.py

Batch operation: Add new client/tenant to multi-tenant setup.

```bash
python scripts/add_client.py \
  <cluster-id> \
  "$ADMIN_URL" \
  new_client \
  --create-pool
```

## cleanup_client.py

Remove a client/tenant (with confirmation).

```bash
python scripts/cleanup_client.py "$ADMIN_URL" old_client --confirm
```

## get_admin_conn.sh

Helper to fetch admin connection string via doctl.

```bash
./scripts/get_admin_conn.sh <cluster-id>
```

## Prerequisites

```bash
# Install psycopg2 with uv
uv pip install psycopg2-binary
```
