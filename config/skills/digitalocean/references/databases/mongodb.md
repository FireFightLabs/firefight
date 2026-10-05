# MongoDB Reference

Complete guide for DigitalOcean Managed MongoDB on App Platform.

---

## Create Cluster and User

```bash
# Create cluster
doctl databases create my-mongo \
  --engine mongodb \
  --region nyc3 \
  --size db-s-1vcpu-2gb \
  --version 7

CLUSTER_ID=$(doctl databases list --format ID,Name --no-header | grep my-mongo | awk '{print $1}')

# Create user
doctl databases user create $CLUSTER_ID myappuser

# Add to trusted sources
APP_ID=$(doctl apps list --format ID,Spec.Name --no-header | grep my-app | awk '{print $1}')
doctl databases firewalls append $CLUSTER_ID --rule app:$APP_ID
```

---

## App Spec

```yaml
databases:
  - name: db
    engine: MONGODB
    production: true
    cluster_name: my-mongo
    db_user: myappuser

services:
  - name: api
    envs:
      - key: MONGODB_URI
        scope: RUN_TIME
        value: ${db.DATABASE_URL}
```

---

## Connection String Format

```
mongodb+srv://<user>:<password>@<host>/<database>?tls=true&authSource=admin
```

---

## Constraints and Defaults

| Constraint | Details |
|------------|---------|
| Database naming | **Cannot contain capital letters** in app spec |
| Database creation | No separate `db_name` — created on first write |
| Connection string | Use `authSource=admin` |
| Replica set | Auto-configured by DO |
| Trusted sources | Supported |
| Default users | `doadmin` (admin), `do-readonly` — cannot be deleted |
| User creation | **Must use DO interface** (Console/API/doctl) — not mongo shell |

---

## User Roles (API Only)

New users created via Console get admin permissions by default. For read-only or read-write users, use the API:

| Role | Permissions |
|------|-------------|
| Admin | Full access (default via Console) |
| Read/Write | Read and write to all databases |
| Read-Only | Read-only access |

```bash
# Create read-only user via API (not available in Console)
curl -X POST "https://api.digitalocean.com/v2/databases/$CLUSTER_ID/users" \
  -H "Authorization: Bearer $DO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "readonly-user", "role": "read-only"}'
```

---

## Troubleshooting

### "Authentication failed"

Ensure connection string includes `authSource=admin`:

```
mongodb+srv://user:pass@host/mydb?tls=true&authSource=admin
```

### Database name with capitals rejected

MongoDB database names in app spec cannot contain capital letters. Use lowercase:

```yaml
# Wrong
db_name: MyAppDB

# Correct
db_name: myappdb
```

### User not found

Users must be created via DO Console, API, or doctl — not via mongo shell.

---

## Documentation Links

- [MongoDB on DigitalOcean](https://docs.digitalocean.com/products/databases/mongodb/)
- [doctl databases reference](https://docs.digitalocean.com/reference/doctl/reference/databases/)
