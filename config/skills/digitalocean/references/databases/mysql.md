# MySQL Reference

Complete guide for DigitalOcean Managed MySQL on App Platform.

---

## Create Cluster and User

```bash
# Create cluster
doctl databases create my-mysql \
  --engine mysql \
  --region nyc3 \
  --size db-s-1vcpu-2gb \
  --version 8

# Get cluster ID
CLUSTER_ID=$(doctl databases list --format ID,Name --no-header | grep my-mysql | awk '{print $1}')

# Create database
doctl databases db create $CLUSTER_ID myappdb

# Create user (DO stores password internally)
doctl databases user create $CLUSTER_ID myappuser

# Add App Platform to trusted sources
APP_ID=$(doctl apps list --format ID,Spec.Name --no-header | grep my-app | awk '{print $1}')
doctl databases firewalls append $CLUSTER_ID --rule app:$APP_ID
```

---

## App Spec

```yaml
databases:
  - name: db
    engine: MYSQL
    production: true
    cluster_name: my-mysql
    db_name: myappdb
    db_user: myappuser

services:
  - name: api
    envs:
      - key: DATABASE_URL
        scope: RUN_TIME
        value: ${db.DATABASE_URL}
      # Or individual components:
      - key: MYSQL_HOST
        value: ${db.HOSTNAME}
      - key: MYSQL_PORT
        value: ${db.PORT}
      - key: MYSQL_USER
        value: ${db.USERNAME}
      - key: MYSQL_PASSWORD
        value: ${db.PASSWORD}
      - key: MYSQL_DATABASE
        value: ${db.DATABASE}
```

---

## Connection String Format

```
mysql://<user>:<password>@<host>:25060/<database>?ssl-mode=REQUIRED
```

---

## Constraints and Defaults

| Constraint | Details |
|------------|---------|
| Port | **25060** (not standard 3306) |
| SSL | Required (`ssl-mode=REQUIRED`) |
| Default database | `defaultdb` — cannot be deleted |
| Default user | `doadmin` — cannot be deleted |
| Trusted sources | Supported |
| Admin users | **Cannot create additional admins** — only `doadmin` has full privileges |

---

## Password Encryption

MySQL 8+ uses `caching_sha2_password` by default. Some older applications (PHP 7.1 and older) may have connection issues.

**Change via Console**: Databases → my-mysql → Users & Databases → More → Edit Password Encryption

| Encryption | Compatibility |
|------------|---------------|
| `caching_sha2_password` | MySQL 8+ default, more secure |
| `mysql_native_password` | Legacy, for older PHP/apps |

---

## Restricted Databases (Read-Only)

Users can SELECT from but cannot INSERT/UPDATE these system databases:

- `mysql`
- `sys`
- `metrics_user_telegraf`
- `performance_schema`
- `information_schema`

---

## User Privileges

Privileges are managed via SQL (not Console). Connect as `doadmin` and use GRANT/REVOKE:

```sql
-- Grant all on specific database
GRANT ALL ON myappdb.* TO 'myappuser'@'%';

-- Grant read-only
GRANT SELECT ON myappdb.* TO 'readonly_user'@'%';

-- Grant with ability to grant others
GRANT ALL ON myappdb.* TO 'myappuser'@'%' WITH GRANT OPTION;

-- Revoke privileges
REVOKE ALL ON myappdb.* FROM 'myappuser'@'%';

-- View privileges
SHOW GRANTS FOR 'myappuser';
```

---

## Connection Pools

```bash
# Create pool
doctl databases pool create $CLUSTER_ID myapp_pool \
  --db myappdb \
  --mode transaction \
  --size 25 \
  --user myappuser

# Reference in app spec
# value: ${db.myapp_pool.DATABASE_URL}
```

---

## Troubleshooting

### "Access denied" after user creation

Users created via doctl have no permissions by default. Grant them:

```sql
GRANT ALL ON myappdb.* TO 'myappuser'@'%';
```

### Connection issues with older PHP

Switch password encryption to `mysql_native_password` via Console.

### "SSL connection required"

Ensure connection string includes `?ssl-mode=REQUIRED`.

---

## Documentation Links

- [MySQL on DigitalOcean](https://docs.digitalocean.com/products/databases/mysql/)
- [doctl databases reference](https://docs.digitalocean.com/reference/doctl/reference/databases/)
