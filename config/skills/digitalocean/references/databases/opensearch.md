# OpenSearch Reference

Complete guide for DigitalOcean Managed OpenSearch on App Platform.

---

## Create Cluster and User

```bash
# Create cluster
doctl databases create my-opensearch \
  --engine opensearch \
  --region nyc3 \
  --size db-s-2vcpu-4gb \
  --version 2

CLUSTER_ID=$(doctl databases list --format ID,Name --no-header | grep my-opensearch | awk '{print $1}')

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
  - name: search
    engine: OPENSEARCH
    production: true
    cluster_name: my-opensearch
    db_user: myappuser

services:
  - name: api
    envs:
      - key: OPENSEARCH_URL
        scope: RUN_TIME
        value: https://${search.USERNAME}:${search.PASSWORD}@${search.HOSTNAME}:${search.PORT}
```

---

## Constraints and Defaults

| Constraint | Details |
|------------|---------|
| Protocol | HTTPS with basic auth |
| Port | Typically 25060 |
| Compatibility | Elasticsearch clients work (OpenSearch is a fork) |
| Dashboard | Available at cluster URL |
| Default user | `doadmin` — cannot be deleted |
| User management | **API/CLI only** — Console doesn't support user management |
| Trusted sources | Supported for database connections |
| **Logging** | **NOT supported with trusted sources enabled** |

> **Important**: If you want App Platform to send logs to OpenSearch, you must disable trusted sources on the OpenSearch cluster. Regular database connections (queries, indexing) work fine with trusted sources.

---

## Access Control Lists (ACLs)

For fine-grained access control, use the API to create ACLs:

```bash
# List current ACLs
curl -X GET "https://api.digitalocean.com/v2/databases/$CLUSTER_ID/opensearch/acl" \
  -H "Authorization: Bearer $DO_TOKEN"

# Update ACLs (example: restrict user to specific index pattern)
curl -X PUT "https://api.digitalocean.com/v2/databases/$CLUSTER_ID/opensearch/acl" \
  -H "Authorization: Bearer $DO_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "acl_enabled": true,
    "acls": [
      {"username": "myappuser", "index": "logs-*", "permission": "readwrite"}
    ]
  }'
```

---

## Troubleshooting

### "Connection refused"

Ensure using HTTPS protocol:

```bash
# Wrong
http://host:25060

# Correct
https://user:pass@host:25060
```

### Logs not appearing in OpenSearch

Trusted sources blocks App Platform logging. Disable trusted sources if you need log ingestion:

```bash
doctl databases firewalls remove-uuid $CLUSTER_ID <rule-uuid>
```

### User management via Console

OpenSearch user management is API/CLI only. Use:

```bash
doctl databases user create $CLUSTER_ID username
```

---

## Documentation Links

- [OpenSearch on DigitalOcean](https://docs.digitalocean.com/products/databases/opensearch/)
- [doctl databases reference](https://docs.digitalocean.com/reference/doctl/reference/databases/)
