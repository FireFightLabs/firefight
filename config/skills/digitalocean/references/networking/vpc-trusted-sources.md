# VPC and Trusted Sources

## VPC Architecture

```
VPC Network
┌─────────────────────────────────────────────────────────┐
│   App Platform    ←── Private 10.x.x.x ──→   Database  │
│   (vpc.id set)                               (in VPC)   │
└─────────────────────────────────────────────────────────┘
```

VPC must be configured on BOTH the app AND the database.

## Enabling VPC

```bash
doctl vpcs list  # Get VPC UUID
```

```yaml
vpc:
  id: c22d8f48-4bc4-49f5-8ca0-58e7164427ac
```

## Trusted Sources Mental Model

```
CRITICAL INSIGHT:
`app:$APP_ID` rules ONLY whitelist the app's PUBLIC egress IP.
They do NOT whitelist the app's VPC private IP.

For VPC deployments:
Use VPC CIDR whitelisting (`ip_addr:10.126.0.0/20`) instead.
```

## Decision Tree

| Setup | Connection | Trusted Source Rule |
|-------|------------|---------------------|
| Public only | Public endpoint | `app:$APP_ID` |
| VPC enabled | Private endpoint | `ip_addr:<vpc-cidr>` (recommended) |
| VPC enabled | Private endpoint | `ip_addr:<app-vpc-ip>` (fine-grained) |

## Trusted Sources by Service

| Service | Public + TS | VPC + TS |
|---------|-------------|----------|
| PostgreSQL | `app:$APP_ID` | `ip_addr:<vpc-ip>` |
| MySQL | `app:$APP_ID` | `ip_addr:<vpc-ip>` |
| MongoDB | `app:$APP_ID` | `ip_addr:<vpc-ip>` |
| Valkey/Redis | `app:$APP_ID` | `ip_addr:<vpc-ip>` |
| OpenSearch | `app:$APP_ID` | `ip_addr:<vpc-ip>` |
| **Kafka** | NOT SUPPORTED | `ip_addr:<vpc-ip>` |
| **OpenSearch logs** | NOT SUPPORTED | NOT SUPPORTED |

## VPC CIDR Whitelisting (Recommended)

```bash
# Get VPC CIDR
doctl vpcs get $VPC_ID --format IPRange
# Example: 10.126.0.0/20

# Add to database
doctl databases firewalls append $CLUSTER_ID --rule ip_addr:10.126.0.0/20
```

**Benefits:**
- One-time setup per database
- All apps in VPC work immediately
- Simplifies multi-app architectures

## Per-App IP Whitelisting

```bash
# Get VPC egress IP (run from laptop, not container)
VPC_EGRESS_IP=$(doctl apps get $APP_ID -o json | jq -r '.. | .egress_ips? // empty | .[0].ip // empty' | head -1)

# Add to database
doctl databases firewalls append $CLUSTER_ID --rule ip_addr:$VPC_EGRESS_IP
```

## Private Connection Strings

Bindable variables (`${db.DATABASE_URL}`) return PUBLIC hostnames even with VPC.

**Get private URLs:**
```bash
doctl databases connection --private <cluster-id> --format URI
```

**Dual-variable pattern:**
```yaml
envs:
  # Public (bindable)
  - key: DATABASE_URL
    value: ${db.DATABASE_URL}
  # Private (VPC)
  - key: DATABASE_PRIVATE_URL
    type: SECRET
    value: postgresql://user:pass@private-xxx:25060/db?sslmode=require
```

Use `DATABASE_PRIVATE_URL` in VPC-enabled apps.

## Regional Datacenter Mapping

| App Region | VPC Datacenter |
|------------|----------------|
| ams | ams3 |
| nyc | nyc1 |
| sfo | sfo3 |
| syd | syd1 |

## VPC Limitations

- Functions not supported
- Single datacenter per region
- Requires IP-based trusted sources
- VPC egress IP may change on major redeploys

## Verifying VPC Connectivity

```bash
# From container (via SDK or console)
dig +short private-xxx.db.ondigitalocean.com
# Should return: 10.x.x.x

psql "postgresql://user:pass@private-xxx:25060/db" -c "SELECT inet_server_addr();"
# Should return VPC IP
```
