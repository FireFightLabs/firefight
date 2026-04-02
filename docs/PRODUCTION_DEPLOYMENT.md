# Production Deployment

## Architecture

Three Hetzner Cloud servers. App and DB in Ashburn, VA for low user latency. Observability in Falkenstein, EU for cost savings. Kamal deploys the application as Docker containers. PostgreSQL runs natively on a dedicated-vCPU VPS.

Ashburn was chosen as a latency compromise: ~60-70ms for US west coast users, ~90-110ms for EU users. Cloudflare CDN caches static assets at edge nodes globally.

```
                  Cloudflare (DNS + DDoS proxy + SSL)
                              │
                              ▼
                ┌──────────────────────────┐
                │  App Server              │
                │  CCX13 · 2 vCPU · 8GB    │
                │  Ashburn, VA (us-east)   │
                │                          │
                │  ┌─────────┐ ┌─────────┐ │
                │  │   Web   │ │ Worker  │ │
                │  │ (Kamal) │ │ (Kamal) │ │
                │  └─────────┘ └─────────┘ │
                │  Thruster (SSL)          │
                │  Promtail ──────────────────┐
                └────────────┬─────────────┘  │
                             │ Private network│
                             ▼                │
                ┌──────────────────────────┐  │
                │  DB Server               │  │
                │  CCX23 · 4 vCPU · 16GB   │  │
                │  Ashburn, VA (us-east)   │  │
                │                          │  │
                │  pgbouncer (6432)        │  │
                │       ▼                  │  │
                │  PostgreSQL 17           │  │
                │       ▼                  │  │
                │  pgbackrest ──────────► Cloudflare R2
                │  Promtail ──────────────────┤
                └──────────────────────────┘  │
                                              │ logs (async)
                ┌──────────────────────────┐  │
                │  Observability Server    │◄─┘
                │  CX22 · 2 vCPU · 4GB    │
                │  Falkenstein (eu-central)│
                │                          │
                │  Grafana (3000)          │
                │  Loki (3100)             │
                └──────────────────────────┘
```

### Why this setup

- No Redis dependency. Solid Queue, Solid Cache, and Solid Cable are all PostgreSQL-backed.
- PostgreSQL is the only stateful component. Dedicated-vCPU server with 16GB RAM provides consistent performance with no noisy neighbors.
- The app server is stateless. Replaceable, scalable, cheap.
- Both servers in the same US datacenter. Low latency for US users, acceptable for EU.
- Observability on a separate, cheap EU server. Promtail ships logs async — latency doesn't matter.
- Total cost: ~€56/month (~$61). Well under the $100/month budget.

### Cost breakdown

| Component                       | Location    | Cost      |
|---------------------------------|-------------|-----------|
| App (CCX13, 2 vCPU, 8GB)       | Ashburn, VA | €16.99/mo |
| DB (CCX23, 4 vCPU, 16GB)       | Ashburn, VA | €33.99/mo |
| Observability (CX22, 2 vCPU, 4GB) | Falkenstein | ~€4.50/mo |
| Hetzner private network         | —           | Free      |
| Cloudflare (free tier)          | —           | Free      |
| GHCR (free tier)                | —           | Free      |
| **Total**                       |             | **~€56/mo** |

## Infrastructure as Code

### Terraform

Terraform manages all three Hetzner Cloud servers and Cloudflare DNS. Everything is provisioned via `terraform apply`.

```
infra/
  terraform/
    main.tf              # Provider config (hcloud + cloudflare), state backend
    variables.tf         # Server sizes, regions, domain, SSH key path
    app_server.tf        # hcloud_server (CCX13, Ashburn) + hcloud_server_network
    db_server.tf         # hcloud_server (CCX23, Ashburn) + hcloud_server_network
    obs_server.tf        # hcloud_server (CX22, Falkenstein)
    network.tf           # hcloud_network + hcloud_network_subnet (Ashburn)
    firewall.tf          # hcloud_firewall (app, db, observability)
    ssh_keys.tf          # hcloud_ssh_key
    dns.tf               # cloudflare_record (A records → app + grafana subdomain)
    outputs.tf           # Public IPs, private IPs, server IDs
```

State backend: Terraform Cloud free tier (1 workspace).

### DB server setup scripts

Idempotent shell scripts configure the DB server after Terraform provisions it:

```
infra/
  db-server/
    setup.sh                    # Orchestrator — runs all scripts in order
    scripts/
      01-base.sh                # System updates, ufw, fail2ban, NTP
      02-postgres.sh            # Install PG 17, create databases, pg_hba.conf
      03-pgbouncer.sh           # Install pgbouncer, transaction-mode config
      04-pgbackrest.sh          # Install pgbackrest, configure R2, initial backup
    config/
      postgresql.conf.template  # Tuned for 16GB dedicated-vCPU server
      pgbouncer.ini.template    # Connection pool settings
      pgbackrest.conf.template  # R2 endpoint, retention policy
      pg_hba.conf.template      # Only accept from app server private IP
```

## Networking

### Private network

Both servers in the same Hetzner Cloud location (Ashburn, VA). A Hetzner Cloud private network connects them.

- App VPS private IP: `10.0.0.2`
- DB server private IP: `10.0.0.1`
- All database traffic stays on the private network

### Firewall rules

**App VPS** (Hetzner Cloud Firewall, Terraform-managed):
- Inbound: 22/tcp (SSH, restricted to admin IP), 80/tcp, 443/tcp
- Outbound: all (Slack API, Anthropic API, R2, GHCR)

**DB server** (ufw, script-managed):
- Inbound: 22/tcp (SSH, restricted to admin IP), 6432/tcp (pgbouncer, only from `10.0.0.2`)
- Outbound: 443/tcp (R2 for pgbackrest)
- No public PostgreSQL access

## PostgreSQL

### Configuration (CCX23, 16GB RAM)

| Parameter              | Value  | Rationale                          |
|------------------------|--------|------------------------------------|
| `shared_buffers`       | 4GB    | 25% of RAM                         |
| `effective_cache_size` | 12GB   | 75% of RAM (OS cache + PG buffers) |
| `work_mem`             | 64MB   | Proportional to available RAM      |
| `maintenance_work_mem` | 512MB  | Faster VACUUM, index builds        |
| `wal_level`            | replica| Required for pgbackrest PITR       |
| `archive_mode`         | on     | Enable WAL archiving               |
| `archive_command`      | pgbackrest | Ship WAL to R2                 |

### Databases

Four PostgreSQL databases, all on the same server. Configured via environment variables in `config/database.yml`:

| Database                   | Env var                      | Purpose          |
|----------------------------|------------------------------|------------------|
| `firefight_production`       | `FIREFIGHT_DATABASE`         | Primary app data |
| `firefight_production_cache` | `FIREFIGHT_DATABASE_CACHE`   | Solid Cache      |
| `firefight_production_queue` | `FIREFIGHT_DATABASE_QUEUE`   | Solid Queue      |
| `firefight_production_cable` | `FIREFIGHT_DATABASE_CABLE`   | Solid Cable      |

### pgbouncer

Runs on the DB server, listening on port 6432. All app connections go through pgbouncer.

- Mode: transaction
- Default pool size: 20 per database
- Max client connections: 200

The app connects to `FIREFIGHT_DATABASE_HOST:<private-ip>` on port 6432 (set via `FIREFIGHT_DATABASE_PORT` or included in host config).

### Backups (pgbackrest → Cloudflare R2)

| Schedule     | Type         | Retention       |
|-------------|-------------|-----------------|
| Continuous  | WAL archive  | Until oldest full backup expires |
| Daily       | Differential | 7 days          |
| Weekly (Sun)| Full         | 4 weeks         |

Backups are stored in Cloudflare R2 (S3-compatible). pgbackrest handles encryption and compression.

Recovery: restore to any point in time within the retention window. Test the restore procedure before go-live and periodically after.

## Kamal Deployment

### deploy.yml

```yaml
service: firefight
image: ghcr.io/<org>/firefight

servers:
  web:
    hosts:
      - <app-vps-public-ip>
    options:
      memory: 2g
  worker:
    hosts:
      - <app-vps-public-ip>
    cmd: bin/jobs
    options:
      memory: 2g

proxy:
  ssl: true
  host: <domain>

registry:
  server: ghcr.io
  username:
    - KAMAL_REGISTRY_USERNAME
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    SOLID_QUEUE_IN_PUMA: false
    FIREFIGHT_DATABASE_HOST: <db-private-ip>
    FIREFIGHT_DATABASE_PORT: 6432
    WEB_CONCURRENCY: 2
    RAILS_LOG_LEVEL: info
  secret:
    - RAILS_MASTER_KEY
    - FIREFIGHT_DATABASE
    - FIREFIGHT_DATABASE_CACHE
    - FIREFIGHT_DATABASE_QUEUE
    - FIREFIGHT_DATABASE_CABLE
    - FIREFIGHT_DATABASE_USERNAME
    - FIREFIGHT_DATABASE_PASSWORD

volumes:
  - "firefight_storage:/rails/storage"

asset_path: /rails/public/assets

builder:
  arch: amd64

aliases:
  console: app exec --interactive --reuse "bin/rails console"
  shell: app exec --interactive --reuse "bash"
  logs: app logs -f
  dbc: app exec --interactive --reuse "bin/rails dbconsole --include-password"
```

### Secrets (.kamal/secrets)

```bash
KAMAL_REGISTRY_USERNAME=<github-username>
KAMAL_REGISTRY_PASSWORD=<ghcr-pat>
RAILS_MASTER_KEY=<from config/master.key>
FIREFIGHT_DATABASE=firefight_production
FIREFIGHT_DATABASE_CACHE=firefight_production_cache
FIREFIGHT_DATABASE_QUEUE=firefight_production_queue
FIREFIGHT_DATABASE_CABLE=firefight_production_cable
FIREFIGHT_DATABASE_USERNAME=firefight
FIREFIGHT_DATABASE_PASSWORD=<generated>
```

### Container registry

GitHub Container Registry (ghcr.io). Free tier for private repos. Create a personal access token with `write:packages` scope.

## DNS and SSL

- Domain registered at Porkbun, nameservers pointed to Cloudflare
- Cloudflare manages DNS: A record → app VPS public IP
- Cloudflare proxy enabled (DDoS protection, WAF)
- Cloudflare SSL mode: **Full (strict)**
- Origin SSL: Kamal's Thruster handles Let's Encrypt on the server
- Slack webhook URLs route through Cloudflare

## Observability

### Grafana + Loki stack

Runs on a dedicated CX22 in Falkenstein (eu-central). Cheap shared-resource VPS — observability tooling doesn't need dedicated vCPUs or low user-facing latency.

```
Observability server (CX22, Falkenstein)
├── Grafana     (port 3000) — dashboards, alerts, log exploration
└── Loki        (port 3100) — log aggregation and storage

App server (Ashburn)
└── Promtail    — tails Docker container logs (web + worker), ships to Loki

DB server (Ashburn)
└── Promtail    — tails PostgreSQL + pgbouncer logs, ships to Loki
```

**Access**: Grafana exposed via subdomain (e.g., `grafana.firefight.dev`) behind Cloudflare proxy. Auth via Grafana's built-in login.

**Log retention**: Loki stores logs on local disk with a retention period (e.g., 30 days). At low volume, 80GB SSD on CX22 is sufficient. If retention needs grow, Loki can ship chunks to R2.

**Setup scripts**:
```
infra/
  obs-server/
    setup.sh                      # Orchestrator
    scripts/
      01-base.sh                  # System updates, ufw, fail2ban
      02-grafana.sh               # Install Grafana
      03-loki.sh                  # Install Loki
    config/
      loki.yml                    # Loki config (storage, retention, limits)
      grafana-datasources.yml     # Auto-provision Loki as data source
```

**Promtail on app/DB servers**:
```
infra/
  promtail/
    setup.sh                      # Install Promtail on any server
    config/
      promtail-app.yml            # Scrape Docker container logs
      promtail-db.yml             # Scrape PG + pgbouncer logs
```

**Firewall — Observability server**:
- Inbound: 22/tcp (SSH, restricted to admin IP), 3000/tcp (Grafana, via Cloudflare), 3100/tcp (Loki, from app + DB server IPs only)
- Outbound: 443/tcp (Grafana plugin downloads, alerts)

### Uptime monitoring

Free tier of Uptime Robot or BetterUptime:
- Monitor the app URL (dashboard)
- Monitor the Slack webhook health endpoint
- Alert via Slack/email on downtime

### PostgreSQL monitoring

- `pg_stat_statements` enabled for query performance tracking
- PG logs shipped to Loki via Promtail for centralized search
- Grafana dashboards for PG metrics (connections, query duration, cache hit ratio) added over time

## Deployment Steps

### Phase 1: Provision infrastructure

1. Write and apply Terraform config: all 3 servers + private network + firewalls + DNS
2. Verify private network connectivity between app and DB servers

### Phase 2: Database setup

3. SSH into DB server, run `setup.sh`
4. Verify databases and roles are created
5. Run initial pgbackrest full backup to R2
6. Test PITR restore (restore to a new database, verify data)

### Phase 3: Application deployment

7. Create GHCR access token, test `docker login ghcr.io`
8. Update `config/deploy.yml` with real IPs and domain
9. Create `.kamal/secrets` with credentials
10. Run `kamal setup` (first deploy — installs Docker, starts containers)
11. Run `kamal app exec 'bin/rails db:prepare'` (runs migrations on all 4 databases)
12. Verify app responds, SSL terminates correctly

### Phase 4: Go live

13. Point Cloudflare A record to app server public IP
14. Update Slack app manifest with production URL (`config/slack_manifests/production.yml`)
15. Smoke test: create incident via Slack, verify dashboard loads, check webhook response times

### Phase 5: Observability

16. SSH into observability server, run `setup.sh` (Grafana + Loki)
17. Install Promtail on app server and DB server
18. Verify logs flowing: app container logs + PG logs visible in Grafana
19. Configure Grafana dashboards (log search, PG metrics)
20. Set up Grafana alerting (error rate spikes, PG connection saturation)

### Phase 6: Operational baseline

21. Set up uptime monitoring (Uptime Robot / BetterUptime)
22. Verify pgbackrest cron is running (check R2 for daily diffs)
23. Document and test the disaster recovery procedure

## Scaling Path

Each step is a config change in `deploy.yml` + `terraform apply`. No architecture rewrite.

### Current: ~€56/month
```
1 CCX13 (web + worker) → 1 CCX23 (PG) + 1 CX22 (Grafana + Loki)
```

### Step 1: Separate worker (~€68/month)
Move worker to its own VPS when background jobs compete with web requests.
```yaml
# deploy.yml
servers:
  web:
    hosts:
      - <web-vps-ip>
  worker:
    hosts:
      - <worker-vps-ip>       # new server
    cmd: bin/jobs
```

### Step 2: Horizontal web scaling (~€82/month)
Add a second web VPS and a Hetzner Cloud Load Balancer when a single web server isn't enough.
```yaml
# deploy.yml
servers:
  web:
    hosts:
      - <web-vps-1-ip>
      - <web-vps-2-ip>        # new server
  worker:
    hosts:
      - <worker-vps-ip>
```
- Add `hcloud_load_balancer` + targets in Terraform
- Move SSL termination to the load balancer
- Update Cloudflare A record to point to LB IP
- Kamal does rolling deploys across web hosts automatically

### Step 3: Scale workers
Add more worker VPS instances. Solid Queue distributes jobs across all connected workers automatically.
```yaml
  worker:
    hosts:
      - <worker-vps-1-ip>
      - <worker-vps-2-ip>     # just add IPs
```

### Step 4: Database HA (~€200+/month)
When downtime has real business cost:
- Add a PG streaming replica on a second dedicated server
- pgbouncer routes reads to replica
- pgbackrest backs up from replica (offloads primary)

### Future: Managed cloud
If SOC2 or enterprise compliance requires it, evaluate AWS RDS + ECS or similar. The app has no infrastructure-specific code — it connects to PG via standard env vars and deploys via Docker.

## Disaster Recovery

### App server failure
Hetzner Cloud auto-migrates VPS on hardware failure (~5-15 min). Alternatively, `terraform apply` provisions a new VPS, `kamal setup` deploys the app. The app server is stateless.

### Database server failure
1. Provision a new CCX23 via Terraform (or manually)
2. Install PG 17 + pgbackrest via setup scripts
3. `pgbackrest restore --type=time --target="<timestamp>"` from R2
4. Update app server to point to new DB IP
5. `kamal deploy` to pick up the new config

Target recovery time: 30-60 minutes depending on database size. Practice this procedure before go-live.

### Bad deploy
```bash
kamal rollback
```
Rolls back to the previous container image. Takes ~30 seconds.
