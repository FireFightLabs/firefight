# DigitalOcean App Platform - App Spec Reference

> **When to use this reference:** Consult this document when you need precise field syntax, constraints, regex patterns, or default values for app spec fields. For workflow guidance and architecture patterns, see the [designer skill](../skills/designer/SKILL.md).

## Overview

App Platform is a fully managed Platform-as-a-Service (PaaS) that deploys applications from Git repositories or container images. Apps are defined using YAML specifications.

**Related references:**
- Instance sizes: [`shared/instance-sizes.yaml`](./instance-sizes.yaml)
- Regions: [`shared/regions.yaml`](./regions.yaml)
- Bindable variables: [`shared/bindable-variables.md`](./bindable-variables.md)
- Credential patterns: [`shared/credential-patterns.md`](./credential-patterns.md)

---

## Root-Level Fields

### `name` (String)
- **Purpose**: The name of the app
- **Constraints**: 2-32 characters, unique across all apps in account
- **Pattern**: `^[a-z][a-z0-9-]{0,30}[a-z0-9]$`

### `region` (String)
- **Purpose**: The slug form of the geographical origin of the app
- **Default**: Nearest available region
- **Reference**: See [`shared/regions.yaml`](./regions.yaml) for available regions

---

## Components Overview

DigitalOcean App Spec supports four primary component types:

1. **Services** - Expose publicly-accessible HTTP services
2. **Static Sites** - Static web assets
3. **Workers** - Workloads without public HTTP services
4. **Jobs** - Pre/post deployment workloads

All component types share common properties with some variations.

---

## Services

### Structure
```yaml
services:
  - name: string
    git | github | gitlab | bitbucket | image: (object)
    dockerfile_path: string
    build_command: string
    run_command: string
    source_dir: string
    environment_slug: string
    envs: (array)
    instance_size_slug: string
    instance_count: integer
    autoscaling: (object)
    http_port: integer
    protocol: string
    routes: (array) [DEPRECATED]
    health_check: (object)
    liveness_health_check: (object)
    cors: (object) [DEPRECATED - use ingress]
    internal_ports: (array)
    alerts: (array)
    log_destinations: (array)
    termination: (object)
```

### Key Fields

#### `name` (String)
- **Constraints**: 2-32 characters, unique within app
- **Pattern**: `^[a-z][a-z0-9-]{0,30}[a-z0-9]$`

#### Source Configuration (Choose one)

**Git Clone URL**
```yaml
git:
  repo_clone_url: string # e.g., https://github.com/digitalocean/sample-golang.git
  branch: string
```

**GitHub**
```yaml
github:
  repo: string # Format: owner/repo
  branch: string
  deploy_on_push: boolean
```
- **Pattern**: `^[^/]+/[^/]+$`

**GitLab**
```yaml
gitlab:
  repo: string # Format: owner/repo or owner/subgroup/repo
  branch: string
  deploy_on_push: boolean
```
- **Pattern**: `^[^/]+(/[^/]+)+$`

**Bitbucket**
```yaml
bitbucket:
  repo: string # Format: owner/repo
  branch: string
  deploy_on_push: boolean
```
- **Pattern**: `^[^/]+(/[^/]+)+$`

**Container Image**
```yaml
image:
  registry_type: string # DOCR | DOCKER_HUB | GHCR
  registry: string # Empty for DOCR, required for others (max 192 chars)
  repository: string # Max 192 chars
  tag: string # Max 192 chars, default: latest
  digest: string # Max 192 chars, mutually exclusive with tag
  registry_credentials: string # Format: $username:$access_token
  deploy_on_push:
    enabled: boolean # Only for DOCR
```

#### Build & Runtime
- **`dockerfile_path`** (String): Path to Dockerfile relative to repo root
- **`build_command`** (String): Optional build command
- **`run_command`** (String): Override default run command
- **`source_dir`** (String): Working directory for build, relative to repo root
- **`environment_slug`** (String): Buildpack identifier
  - Available: `node-js`, `python`, `go`, `ruby`, `php`, `hugo`, `bun`

#### Environment Variables
```yaml
envs:
  - key: string # Must match: ^[_A-Za-z][_A-Za-z0-9]*$
    value: string # Encrypted if type: SECRET
    scope: string # RUN_TIME | BUILD_TIME | RUN_AND_BUILD_TIME
    type: string # GENERAL | SECRET
```

#### Scaling

**Fixed Scaling**
- **`instance_size_slug`** (String): See [`shared/instance-sizes.yaml`](./instance-sizes.yaml)
- **`instance_count`** (Integer): Number of instances, default: 1, min: 1, max: 250

**Autoscaling**
```yaml
autoscaling:
  min_instance_count: integer # Minimum instances
  max_instance_count: integer # Maximum instances (max: 250)
  metrics:
    cpu:
      percent: integer # Target CPU utilization (0-100)
```

#### HTTP Configuration
- **`http_port`** (Integer): Port service listens on, default: 8080
  - Auto-creates PORT environment variable if not set
- **`protocol`** (String): `HTTP` (default) or `HTTP2`
- **`internal_ports`** (Array of Integers): Ports for internal traffic

#### Health Checks

**Readiness Health Check**
```yaml
health_check:
  initial_delay_seconds: integer # Default: 0, min: 0, max: 3600
  period_seconds: integer # Default: 10, min: 1, max: 300
  timeout_seconds: integer # Default: 1, min: 1, max: 120
  success_threshold: integer # Default: 1, min: 1, max: 50
  failure_threshold: integer # Default: 9, min: 1, max: 50
  http_path: string # Health check endpoint
  port: integer # Health check port (defaults to http_port)
```

**Liveness Health Check**
```yaml
liveness_health_check:
  initial_delay_seconds: integer # Default: 5, min: 0, max: 3600
  period_seconds: integer # Default: 10, min: 1, max: 300
  timeout_seconds: integer # Default: 1, min: 1, max: 120
  success_threshold: integer # Default: 1, min: 1, max: 1
  failure_threshold: integer # Default: 18, min: 1, max: 50
  http_path: string
  port: integer
```

#### Termination
```yaml
termination:
  drain_seconds: integer # Default: 15, min: 1, max: 110
  grace_period_seconds: integer # Default: 120, min: 1, max: 600
```

#### Alerts
See [Alerts](#alerts) section below.

#### Log Destinations
See [Log Destinations](#log-destinations) section below.

---

## Static Sites

### Structure
```yaml
static_sites:
  - name: string
    git | github | gitlab | bitbucket: (object)
    dockerfile_path: string
    build_command: string
    source_dir: string
    output_dir: string
    environment_slug: string
    index_document: string
    error_document: string
    envs: (array)
    routes: (array) [DEPRECATED]
    cors: (object) [DEPRECATED]
    catchall_document: string
```

### Key Fields

#### `name` (String)
- **Constraints**: 2-32 characters, unique within app
- **Pattern**: `^[a-z][a-z0-9-]{0,30}[a-z0-9]$`

#### Build Configuration
- **`dockerfile_path`** (String): Optional path to Dockerfile
- **`build_command`** (String): Optional build command
- **`source_dir`** (String): Working directory for build
- **`output_dir`** (String): Path to built assets relative to build context
  - Auto-scans: `_static`, `dist`, `public`, `build` if not set

#### Document Handling
- **`index_document`** (String): Default: `index.html`
- **`error_document`** (String): Default: `404.html` (auto-generated if missing)
- **`catchall_document`** (String): Fallback for not-found documents (mutually exclusive with `error_document`)

---

## Workers

### Structure
```yaml
workers:
  - name: string
    git | github | gitlab | bitbucket | image: (object)
    dockerfile_path: string
    build_command: string
    run_command: string
    source_dir: string
    environment_slug: string
    envs: (array)
    instance_size_slug: string
    instance_count: integer
    autoscaling: (object)
    alerts: (array)
    log_destinations: (array)
    termination: (object)
    liveness_health_check: (object)
```

**Note**: Workers do not expose HTTP ports and don't include `http_port`, `health_check`, `protocol`, or `routes`.

---

## Jobs

### Structure
```yaml
jobs:
  - name: string
    git | github | gitlab | bitbucket | image: (object)
    dockerfile_path: string
    build_command: string
    run_command: string
    source_dir: string
    environment_slug: string
    envs: (array)
    instance_size_slug: string
    instance_count: integer
    kind: string
    schedule: (object)
    alerts: (array)
    log_destinations: (array)
    termination: (object)
```

### Key Fields

#### `kind` (String)
Specifies when the job runs:
- `UNSPECIFIED`: Default, auto-completes to POST_DEPLOY
- `PRE_DEPLOY`: Runs before app deployment
- `POST_DEPLOY`: Runs after app deployment
- `FAILED_DEPLOY`: Runs after component fails to deploy
- `SCHEDULED`: Runs periodically based on cron

#### `schedule` (Object)
For SCHEDULED jobs:
```yaml
schedule:
  cron: string # Cron expression
  time_zone: string # From tz database (e.g., "Asia/Kolkata")
```

---

## Databases

### Structure
```yaml
databases:
  - name: string
    engine: string
    version: string
    production: boolean
    cluster_name: string
    db_name: string
    db_user: string
```

### Key Fields

#### `name` (String)
- **Constraints**: 2-32 characters, unique within app, lowercase only
- **Pattern**: `^[a-z][a-z0-9-]{0,30}[a-z0-9]$`

#### `engine` (String)
- `PG`: PostgreSQL
- `MYSQL`: MySQL
- `VALKEY`: Valkey (use instead of Redis)
- `MONGODB`: MongoDB
- `KAFKA`: Kafka
- `OPENSEARCH`: OpenSearch

#### `version` (String)
Specific version of the database engine

#### `production` (Boolean)
- `true`: Production database (requires `cluster_name`)
- `false`: Dev database (auto-provisions cluster if `cluster_name` not set)

#### `cluster_name` (String)
Name of the underlying DigitalOcean DBaaS cluster

#### `db_name` (String)
For MySQL/PostgreSQL: Database name to configure

#### `db_user` (String)
For MySQL/PostgreSQL: User to configure

> **For detailed database patterns and bindable variables**, see [`shared/bindable-variables.md`](./bindable-variables.md)

---

## Domains

### Structure
```yaml
domains:
  - domain: string
    type: string
    wildcard: boolean
    zone: string
    minimum_tls_version: string
```

### Key Fields

#### `domain` (String)
- **Constraints**: 4-253 characters
- **Pattern**: `^([a-zA-Z0-9]+(-+[a-zA-Z0-9]+)*\.)+(xn--)?[a-zA-Z0-9]{2,}\.?$`

#### `type` (String)
- `DEFAULT`: Default .ondigitalocean.app domain
- `PRIMARY`: Primary domain (displayed by default, used in env vars)
- `ALIAS`: Non-primary domain

#### `wildcard` (Boolean)
Includes all sub-domains of the given domain zone

#### `zone` (String)
For DigitalOcean DNS management, the domain zone name (e.g., `domain.com` for `app.domain.com`)

#### `minimum_tls_version` (String)
- `"1.2"` or `"1.3"` (string format with quotes)

---

## Ingress

### Structure
```yaml
ingress:
  rules:
    - match: (object)
      component: (object) | redirect: (object)
      cors: (object)
```

### `match` Object
Conditions to match requests:
```yaml
match:
  path: (object)
    prefix: string # Max 256 chars
    exact: string # Max 256 chars
  authority: (object)
    prefix: string # Max 256 chars
    exact: string # Max 256 chars
```

### `component` Object (mutually exclusive with `redirect`)
Route to a component:
```yaml
component:
  name: string # Component name
  preserve_path_prefix: boolean # Default: false
  rewrite: string # Mutually exclusive with preserve_path_prefix
```

**Example**:
- Path `/api/list` with `preserve_path_prefix: true` → component receives `/api/list`
- Path `/api/list` with `rewrite: /v1/` → component receives `/v1/list`

### `redirect` Object (mutually exclusive with `component`)
HTTP redirect:
```yaml
redirect:
  uri: string # Rewrite entire request URI
  authority: string # Host/IP to redirect to
  port: integer # Redirect port
  scheme: string # http or https (default: https)
  redirect_code: integer # 300, 301, 302, 303, 304, 307, 308 (default: 302)
```

### `cors` Object
Cross-Origin Resource Sharing configuration:
```yaml
cors:
  allow_origins: (array of objects)
    - exact: string # Exact string match (max 256)
    - prefix: string # Prefix match (max 256)
    - regex: string # RE2 regex (max 256)
  allow_methods: (array) # HTTP methods (e.g., ["GET", "POST"])
  allow_headers: (array) # Request headers
  expose_headers: (array) # Response headers
  max_age: string # Duration (e.g., "5h30m")
  allow_credentials: boolean
```

---

## Alerts

### Alert Types

#### Component-Level Alerts
- `CPU_UTILIZATION`: CPU for a container instance
- `MEM_UTILIZATION`: RAM for a container instance
- `RESTART_COUNT`: Restart count for a container instance

#### App-Level Alerts
- `DEPLOYMENT_FAILED`: Deployment failure
- `DEPLOYMENT_LIVE`: Deployment success
- `DEPLOYMENT_STARTED`: Deployment start
- `DEPLOYMENT_CANCELED`: Deployment cancellation
- `DOMAIN_FAILED`: Domain configuration failure
- `DOMAIN_LIVE`: Domain configuration success
- `AUTOSCALE_FAILED`: Autoscaling failure
- `AUTOSCALE_SUCCEEDED`: Autoscaling success

### Structure
```yaml
alerts:
  - rule: string # Alert type (from above)
    disabled: boolean # Default: false
    operator: string # GREATER_THAN or LESS_THAN
    value: number # Threshold value
    window: string # FIVE_MINUTES, TEN_MINUTES, THIRTY_MINUTES, ONE_HOUR
```

---

## Log Destinations

### Structure
```yaml
log_destinations:
  - name: string # 2-42 chars, pattern: ^[A-Za-z0-9()\[\]'"][-A-Za-z0-9_. \/\(\)\[\]]{0,40}[A-Za-z0-9()\[\]'"]$
    papertrail: (object) | datadog: (object) | logtail: (object) | open_search: (object)
```

### Papertrail
```yaml
papertrail:
  endpoint: string # Syslog endpoint (e.g., logs.papertrailapp.com:12345)
```

### Datadog
```yaml
datadog:
  endpoint: string # HTTP log intake endpoint
  api_key: string # Datadog API key
```

### Logtail
```yaml
logtail:
  token: string # Logtail token
```

### OpenSearch
```yaml
open_search:
  endpoint: string # HTTPS only, format: https://host:port
  # OR
  cluster_name: string # DigitalOcean DBaaS cluster name
  # If using endpoint:
  basic_auth:
    user: string # Required for endpoint
    password: string # Required for endpoint
  index_name: string # Default: "logs"
```

**Note**: Either `endpoint` OR `cluster_name` must be set (mutually exclusive)

---

## Global Environment Variables

### Structure
```yaml
envs: (array)
  - key: string
    value: string
    scope: string
    type: string
```

Same as component-level environment variables but applied to all components.

---

## Global Alerts

### Structure
```yaml
alerts: (array)
  - rule: string
    disabled: boolean
    operator: string
    value: number
    window: string
```

Applied at the app level (see [Alerts](#alerts) section for available rules)

---

## Example: Complete Working App Spec

```yaml
name: your-app
region: nyc

services:
  - name: api
    github:
      repo: git-user-name/api
      branch: main
      deploy_on_push: true
    http_port: 8080
    instance_count: 2
    instance_size_slug: apps-s-1vcpu-1gb
    run_command: bin/api
    source_dir: /

static_sites:
  - name: website
    github:
      repo: git-user-name/website
      branch: master
      deploy_on_push: true
    source_dir: /

domains:
  - domain: app.example.com
    type: PRIMARY

ingress:
  rules:
    - match:
        path:
          prefix: /api
      component:
        name: api
        preserve_path_prefix: true
    - match:
        path:
          prefix: /
      component:
        name: website
      cors:
        allow_origins:
          - prefix: https://internal.example-app.com

alerts:
  - rule: DEPLOYMENT_FAILED
  - rule: DOMAIN_FAILED
```

---

## Notes for AI Assistants

- **Validation**: All regex patterns must match exactly
- **Mutations**: Encrypted values use format `EV[...]` - preserve on subsequent submissions
- **Limits**:
  - Instance count: max 250 (use larger instance size if exceeding)
  - Max instance count for autoscaling: 250
- **Defaults**: Most integer fields have sensible defaults; explicitly set if different
- **Constraints**: Names must be lowercase alphanumeric with hyphens, starting and ending with alphanumeric
- **Deprecation**: Routes and component-level CORS are deprecated in favor of ingress.rules

---

## Documentation References

- App Spec Reference: https://docs.digitalocean.com/products/app-platform/reference/app-spec/
- Pricing: https://docs.digitalocean.com/products/app-platform/details/pricing/
- Buildpacks: https://docs.digitalocean.com/products/app-platform/reference/buildpacks/
