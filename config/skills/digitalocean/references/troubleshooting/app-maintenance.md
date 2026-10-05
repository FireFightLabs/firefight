# App Maintenance: Archive and Unarchive

Pause compute while preserving configuration, domains, and DNS.

## What Archiving Does

| Aspect | Archived State |
|--------|----------------|
| Compute | Stopped, no charges |
| Configuration | Preserved |
| Domain/DNS | Preserved |
| Incoming Traffic | Maintenance page |
| Logs | Retained |
| Billing | Stopped |

> Archived apps are free. DO may charge for >20 apps or >3 months.

## Archive via App Spec

```yaml
name: my-app
region: syd1

maintenance:
  archive: true
  # Optional custom page
  # offline_page_url: https://example.com/maintenance.png

services:
  - name: web
    # ... config preserved
```

## Archive via CLI

```bash
# Get current spec
doctl apps spec get <app-id> > app-spec.yaml

# Edit: add maintenance.archive: true

# Apply
doctl apps update <app-id> --spec app-spec.yaml

# Verify
doctl apps get <app-id> -o json | jq '.[0].spec.maintenance.archive'
```

## Unarchive

Set `archive: false` or remove `maintenance` block:

```yaml
maintenance:
  archive: false

# Or remove entirely
```

```bash
doctl apps update <app-id> --spec app-spec.yaml

# Monitor restoration
doctl apps get <app-id> -o json | jq '.[0].active_deployment.phase'
# Wait for: ACTIVE
```

## Verification

```bash
# Check archived status
doctl apps get <app-id> -o json | jq '.[0].spec.maintenance.archive'

# Check URL
curl -I https://<app-url>
# Archived: 503, Active: 200
```

## Timing

| Operation | Duration |
|-----------|----------|
| Archive | ~10 seconds |
| Unarchive | ~60 seconds |
| DNS | Immediate |

## Custom Maintenance Page

```yaml
maintenance:
  archive: true
  offline_page_url: https://your-cdn.com/maintenance.png
```

Requirements:
- PNG format
- ~660x437 pixels
- Public HTTPS URL
- Hosted outside App Platform

## When to Archive vs Delete

| Scenario | Archive | Delete |
|----------|---------|--------|
| Temporary pause | Yes | No |
| Seasonal workload | Yes | No |
| Cost reduction during dev | Yes | No |
| Permanent removal | No | Yes |
| Reuse app name | No | Yes |
| Complex config to preserve | Yes | No |
