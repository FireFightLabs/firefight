# Postgres Troubleshooting

Common issues and fixes for DO Managed Postgres.

## Permission Errors

### "permission denied for schema"

**Cause**: User lacks USAGE permission on schema.

**Fix**:
```sql
GRANT USAGE ON SCHEMA {schema_name} TO {username};
```

### "permission denied for table"

**Cause**: User lacks table permissions.

**Fix**:
```sql
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA {schema_name} TO {username};
ALTER DEFAULT PRIVILEGES IN SCHEMA {schema_name}
  GRANT ALL ON TABLES TO {username};
```

## Connection Errors

### "relation does not exist"

**Cause**: Wrong `search_path` or schema not specified.

**Diagnosis**:
```sql
SHOW search_path;
```

**Fixes**:
```sql
-- Option 1: Use schema-qualified name
SELECT * FROM myapp.users;

-- Option 2: Set search_path
SET search_path TO myapp;

-- Option 3: Set default for user
ALTER USER myappuser SET search_path TO myapp;
```

### "too many connections"

**Cause**: Connection pool exhausted.

**Diagnosis**:
```sql
SELECT count(*) FROM pg_stat_activity;
SHOW max_connections;
```

**Fixes**:
1. Use connection pooling (see [doctl-reference.md](doctl-reference.md))
2. Set per-user limits: `ALTER USER myappuser CONNECTION LIMIT 20;`
3. Tune application pool size
4. Upgrade cluster size

### "SSL connection required"

**Cause**: Missing `sslmode=require` in connection string.

**Fix**: Ensure connection string includes:
```
?sslmode=require
```

### "Connection refused" from App Platform

**Cause**: Firewall rules not allowing App Platform.

**Fix**:
```bash
doctl apps list  # Get app ID
doctl databases firewalls append <cluster-id> --rule app:<app-id>
```

## Schema Isolation Issues

### "User can access wrong schema"

**Cause**: Public schema access not revoked.

**Diagnosis**:
```sql
SELECT nspname, has_schema_privilege('{username}', nspname, 'USAGE')
FROM pg_namespace;
```

**Fix**:
```sql
REVOKE ALL ON SCHEMA public FROM {username};
```

## Bindable Variables Issues

### Variables not populated

**Cause**: Missing `production: true` or name mismatch.

**Checklist**:
- [ ] `production: true` in database block
- [ ] `cluster_name` matches exactly (case-sensitive)
- [ ] `db_name` matches exactly
- [ ] `db_user` matches exactly
- [ ] Cluster exists before deploy

**Verify in container**:
```bash
echo $DATABASE_URL
# Should show: postgresql://user:pass@host:25060/db?sslmode=require
```

### "AVNS_" password visible but connection fails

**Cause**: Permissions not granted to user.

**Fix**: Run permission SQL as doadmin (see [path-a-bindable-vars.md](path-a-bindable-vars.md)).

## Verification Queries

```sql
-- Check schema exists
SELECT schema_name FROM information_schema.schemata WHERE schema_name = '{app_name}';

-- Check user permissions
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = '{username}';

-- Test isolation
SET ROLE {username};
SELECT schema_name FROM information_schema.schemata;
RESET ROLE;

-- Check current user
SELECT current_user, current_database(), current_schema();
```

## When to Escalate

Use the **troubleshooting skill** for:
- Runtime connectivity issues
- Container debugging
- Network/VPC problems
- Health check failures
