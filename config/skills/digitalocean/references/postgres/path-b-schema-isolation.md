# Path B: Schema Isolation

Use when: Multi-tenant SaaS, multiple apps sharing one cluster, schema-level isolation needed.

## Security Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      PATH B: CREDENTIAL MANAGEMENT                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  OPTION 1: HANDS-FREE SECURE SETUP (RECOMMENDED)                         │
│  • Agent generates password, creates user, stores in GitHub Secrets      │
│  • Password NEVER displayed — flows directly to secrets                  │
│  • Requires: gh CLI authenticated with repo access                       │
│                                                                          │
│  OPTION 2: MANUAL SETUP                                                  │
│  • Generate SQL scripts with password placeholders                       │
│  • User generates password, edits scripts, executes                      │
│  • User manually adds to GitHub Secrets                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Hands-Free Secure Setup (Recommended)

When `gh` CLI is available and authenticated:

```bash
# Single command — password never visible
./scripts/secure_setup.sh \
  --admin-url "$ADMIN_URL" \
  --app-name myapp \
  --schema myapp \
  --repo owner/repo \
  --env production
```

**What it does**:
1. Generates secure password (never printed)
2. Creates schema and user in database
3. Grants full permissions with isolation
4. Stores `DATABASE_URL` directly in GitHub Secrets
5. Clears password from memory

**Prerequisites**:
```bash
gh auth status
gh secret list --repo owner/repo  # Test access
```

## Manual Setup

Generate these artifacts:

### 1. `db-setup.sql` (Schema creation)

```sql
\c defaultdb
CREATE SCHEMA IF NOT EXISTS {app_name};
```

### 2. `db-users.sql` (User creation)

```sql
-- Generate password: openssl rand -base64 32
CREATE USER {app_name}_user WITH PASSWORD 'CHANGE_ME_SECURE_PASSWORD';
```

### 3. `db-permissions.sql` (Grants with isolation)

```sql
-- Grant schema access
GRANT USAGE ON SCHEMA {app_name} TO {app_name}_user;

-- Grant table permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA {app_name} TO {app_name}_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA {app_name} TO {app_name}_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA {app_name} TO {app_name}_user;

-- For future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA {app_name}
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO {app_name}_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA {app_name}
  GRANT USAGE, SELECT ON SEQUENCES TO {app_name}_user;

-- Set default search_path
ALTER USER {app_name}_user SET search_path TO {app_name};

-- SECURITY: Revoke public schema access
REVOKE ALL ON SCHEMA public FROM {app_name}_user;
```

### 4. `db-connections.env` (Connection templates)

```bash
# Store in GitHub Secrets
DATABASE_URL=postgresql://{app_name}_user:PASSWORD@HOST:25060/defaultdb?sslmode=require
DB_SCHEMA={app_name}
```

## Multi-Tenant Setup (Multiple Schemas)

Single database with separate schemas:

```
└── defaultdb
    ├── app1 schema  ←── app1_user
    ├── app2 schema  ←── app2_user
    └── app3 schema  ←── app3_user
```

### Setup SQL

```sql
-- Create schemas
CREATE SCHEMA IF NOT EXISTS app1;
CREATE SCHEMA IF NOT EXISTS app2;
CREATE SCHEMA IF NOT EXISTS app3;

-- Create users (generate passwords: openssl rand -base64 32)
CREATE USER app1_user WITH PASSWORD 'CHANGE_ME_APP1_PASSWORD';
CREATE USER app2_user WITH PASSWORD 'CHANGE_ME_APP2_PASSWORD';
CREATE USER app3_user WITH PASSWORD 'CHANGE_ME_APP3_PASSWORD';

-- Permissions for each
GRANT USAGE ON SCHEMA app1 TO app1_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA app1 TO app1_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA app1 TO app1_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app1 GRANT ALL ON TABLES TO app1_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app1 GRANT ALL ON SEQUENCES TO app1_user;
ALTER USER app1_user SET search_path TO app1;
REVOKE ALL ON SCHEMA public FROM app1_user;

-- Repeat for app2, app3...
```

### Verify Isolation

```sql
-- Each user should only see their schema
SET ROLE app1_user;
SELECT schema_name FROM information_schema.schemata;
RESET ROLE;
```

## Read-Only User (Schema Isolation)

```sql
-- Create read-only user
CREATE USER {app_name}_reader WITH PASSWORD 'CHANGE_ME_READONLY_PASSWORD';

-- Grant read-only permissions
GRANT USAGE ON SCHEMA {app_name} TO {app_name}_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA {app_name} TO {app_name}_reader;

ALTER DEFAULT PRIVILEGES IN SCHEMA {app_name}
  GRANT SELECT ON TABLES TO {app_name}_reader;

ALTER USER {app_name}_reader SET search_path TO {app_name};
REVOKE ALL ON SCHEMA public FROM {app_name}_reader;
```

## Password Generation

```bash
# Recommended: 32-character base64
openssl rand -base64 32

# Alternative: 32-character hex
openssl rand -hex 16

# Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

Avoid special characters that need URL encoding: `@`, `:`, `/`, `?`, `#`

## Execution Guide

### Step 1: Generate Passwords

```bash
openssl rand -base64 32  # For each user
```

### Step 2: Edit SQL Files

Replace `CHANGE_ME_*` placeholders in `db-users.sql`.

### Step 3: Run Scripts

```bash
ADMIN_URL=$(doctl databases connection $CLUSTER_ID --format Uri --no-header)

psql "$ADMIN_URL" -f db-setup.sql
psql "$ADMIN_URL" -f db-users.sql
psql "$ADMIN_URL" -f db-permissions.sql
```

### Step 4: Verify

```bash
APP_URL="postgresql://{app_name}_user:PASSWORD@host:25060/defaultdb?sslmode=require"
psql "$APP_URL" -c "SELECT current_schema();"
# Should return: {app_name}
```

### Step 5: Store Credentials

**GitHub Secrets**: Repository → Settings → Secrets → Actions → `DATABASE_URL`

**Local development**: Add to `.env.local` (git-ignored)

## Bundled Scripts

| Script | Purpose |
|--------|---------|
| `secure_setup.sh` | Hands-free setup with GitHub Secrets |
| `secure_setup.py` | Cross-platform Python version |
| `create_schema_user.py` | Create schema + user (generate or execute) |
| `list_schemas_users.py` | Audit existing schemas/users |
| `generate_connection_string.py` | Build connection strings |
| `add_client.py` | Add new tenant to multi-tenant setup |
| `cleanup_client.py` | Remove tenant (with confirmation) |

See [bundled-scripts.md](bundled-scripts.md) for detailed usage.
