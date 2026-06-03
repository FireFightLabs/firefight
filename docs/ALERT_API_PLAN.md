# Alert API — Implementation Plan

## Context

Today Firefight is declared-only: humans hit `/ff new` or the REST `POST /incidents` endpoint. The two questions every prospect asks are "how does this connect to our monitoring?" and "what about PagerDuty?" Both are answered by an Alert API: a normalized ingestion surface that monitoring tools post to, plus routing logic that decides whether an alert becomes an incident, updates an existing one, or is recorded and ignored.

This is the highest-leverage feature gap for the $99/mo segment. It is not on-call/paging (we are explicitly not building that yet) — it is the inbound integration point that lets us pair cleanly with PagerDuty/Opsgenie while still owning incident response and retrospectives. It also doubles as the foundation for AI-assisted triage later: every alert is a structured record we can correlate, dedupe, and reason over.

**Reference implementations analyzed:**
- **incident.io Alerts V2** — alert source / alert route abstraction. Source = "where it came from" (Datadog, Grafana, …), route = "what to do with it" (declarative rules: if severity ≥ high and service = checkout, create incident type X). Each source gets a unique webhook URL + secret. Status lifecycle: `firing → resolved`. Routes evaluate on every alert event.
- **Rootly `POST /v1/alerts`** — single normalized endpoint, JSON:API shape. Required: `summary`. Optional: `description`, `status` (open/triggered), `noise` (noise/not_noise), `service_ids`, `group_ids`, `functionality_ids`, `environment_ids`, `external_id`, `external_url`, `started_at`, `ended_at`, `deduplication_key`, `labels` (key/value array), `data` (free-form object), `notification_target_*`. Status enum on read: `open | triggered | acknowledged | resolved | deferred`. Deduplication: same `deduplication_key` = same logical alert.

**Phase 1 scope:** Alert ingestion (generic + per-source), deduplication, alert lifecycle, alert routes that create/update incidents, six one-click provider recipes (Datadog, Grafana, New Relic, Sentry, PagerDuty, CloudWatch), generic webhook recipe.

**Out of scope (deferred):**
- On-call paging / escalation policies — pair with existing PagerDuty, do not replace it.
- Noise classification ML — `noise` flag exists but is manually set in v1.
- Alert grouping/correlation — single-alert-to-incident only; correlation logic ships later.
- Bidirectional resolve (Firefight close → tell Datadog to resolve) — out for v1, log only.

---

## Concepts

Four entities, mirroring the incident.io model because it is the cleaner abstraction:

```
Alert Source  →  Alert Event  →  Alert  →  (Route)  →  Incident
   (config)      (raw payload)   (normalized)         (existing or new)
```

- **Alert Source** — a configured inbound integration. Has a provider (`datadog`, `grafana`, `generic`, …), a unique webhook URL, a signing secret, and an optional payload transformer. One source per monitoring tool (you can have multiple Datadog sources if you want to scope per team).
- **Alert Event** — a single raw POST from a source. Stored verbatim for replay/debugging. Cheap, append-only.
- **Alert** — the normalized, deduplicated thing. State machine: `firing → acknowledged → resolved`. Same `dedup_key` within a source updates the existing alert instead of creating a new one.
- **Alert Route** — declarative rules that decide what to do when an alert fires. Conditions (severity, source, label match) → action (create incident with type/severity X, attach to open incident matching service Y, or do nothing).

---

## Database Schema

### `alert_sources`

```
id                 uuid PK
workspace_id       uuid FK NOT NULL
name               string NOT NULL                -- "Datadog (prod)", "Grafana – billing"
provider           string NOT NULL                -- enum: datadog, grafana, new_relic, sentry, pagerduty, cloudwatch, generic, prometheus
secret_digest      string NOT NULL                -- HMAC signing secret hash
secret_prefix      string(12) NOT NULL            -- display-only; raw shown once on create
webhook_token      string NOT NULL UNIQUE         -- URL-safe identifier in the webhook path
active             boolean NOT NULL DEFAULT true
created_by_id      uuid FK (workspace_memberships) NOT NULL
last_event_at      datetime NULL
event_count        bigint NOT NULL DEFAULT 0
deleted_at         datetime NULL
created_at, updated_at
```

Indexes: `webhook_token` (unique), `[workspace_id, deleted_at]`, `[workspace_id, provider]`.

Webhook URL shape: `POST /api/v1/alert_sources/:webhook_token/events`. The token is opaque (`SecureRandom.base58(24)`), not the UUID — keeps `id` private and lets us rotate.

### `alert_events`

```
id                 uuid PK
workspace_id       uuid FK NOT NULL
alert_source_id    uuid FK NOT NULL
alert_id           uuid FK NULL                   -- set after normalization
raw_payload        jsonb NOT NULL
headers            jsonb NOT NULL DEFAULT '{}'    -- subset; for debugging signature failures
signature_valid    boolean NOT NULL
status             string NOT NULL                -- received, processed, failed, ignored
error_message      text NULL
received_at        datetime NOT NULL
processed_at       datetime NULL
```

Indexes: `[alert_source_id, received_at desc]`, `[alert_id]`, `[workspace_id, status, received_at]`. Retain 30 days, then prune via cron.

### `alerts`

```
id                  uuid PK
workspace_id        uuid FK NOT NULL
alert_source_id     uuid FK NOT NULL
incident_id         uuid FK NULL                  -- set when a route creates/attaches
dedup_key           string NOT NULL               -- (source_id, dedup_key) is unique
title               string NOT NULL
description         text NULL
status              string NOT NULL               -- firing, acknowledged, resolved
severity            string NULL                   -- normalized: critical, high, medium, low, info
source_url          string NULL                   -- link back to Datadog/Grafana/…
external_id         string NULL                   -- provider's own alert id
labels              jsonb NOT NULL DEFAULT '[]'   -- [{key, value}, ...]
metadata            jsonb NOT NULL DEFAULT '{}'   -- normalized service/team/env hints
noise               boolean NOT NULL DEFAULT false
fired_at            datetime NOT NULL
acknowledged_at     datetime NULL
resolved_at         datetime NULL
last_event_at       datetime NOT NULL             -- timestamp of most recent matching event
event_count         integer NOT NULL DEFAULT 1
created_at, updated_at
```

Indexes: `[alert_source_id, dedup_key]` (unique), `[workspace_id, status, fired_at desc]`, `[incident_id]`, `[workspace_id, fired_at desc]` (list/filter).

### `alert_routes`

```
id                  uuid PK
workspace_id        uuid FK NOT NULL
name                string NOT NULL
position            integer NOT NULL              -- evaluation order, first match wins
conditions          jsonb NOT NULL                -- see below
action              string NOT NULL               -- create_incident, attach_to_open, ignore
action_config       jsonb NOT NULL DEFAULT '{}'   -- incident_type_id, severity_id, attach matcher
active              boolean NOT NULL DEFAULT true
created_at, updated_at
```

Conditions format (v1, simple AND of clauses):
```json
{
  "all": [
    {"field": "source.provider", "op": "eq", "value": "datadog"},
    {"field": "severity",         "op": "in", "value": ["critical", "high"]},
    {"field": "label",            "op": "match", "key": "service", "value": "checkout"}
  ]
}
```

Supported `field`s in v1: `source.provider`, `source.id`, `severity`, `title` (substring), `label` (with `key`). Supported `op`s: `eq`, `in`, `match`. We deliberately ship a small grammar — extend later. No CEL/jq.

Action configs:
- `create_incident`: `{incident_type_id, severity_id, name_template}`. `name_template` defaults to `{{ alert.title }}`.
- `attach_to_open`: `{match_by: "service" | "label:<key>"}` — finds an open incident with matching custom-field/label, attaches the alert (no new incident).
- `ignore`: `{}` — records the alert but does not create an incident.

Default route shipped on workspace setup: `position 999`, no conditions, `action: ignore` — so nothing creates an incident until the user configures it.

### `api_keys` permissions

Add new resource:
```json
{ "alerts": ["read", "create", "update"] }
```

Existing `ApiKey::RESOURCE_*` constants get `RESOURCE_ALERTS = "alerts"`.

---

## API Endpoints

Two ingestion surfaces. Both create the same `Alert` rows; they differ only in auth and payload format.

### 1. Per-source webhook (untrusted, raw provider payload)

```
POST /api/v1/alert_sources/:webhook_token/events
```

- **Auth**: HMAC signature in `X-Firefight-Signature: sha256=<hex>` over the raw body, using the source's secret. Datadog/Grafana/etc. each have a way to compute and send a signature; the recipe docs spell out the exact header. If a provider can't sign (rare), we accept an unsigned mode at create time, clearly flagged in the UI as lower trust.
- **Body**: whatever the provider sends. The server resolves the source by `webhook_token`, looks up the provider's parser, and normalizes.
- **Response**: `202 Accepted` with `{ "alert_event_id": "..." }`. Normalization and routing happen asynchronously in `AlertIngestionWorkflow` — keeps the response fast and isolates parser failures from the sender.

### 2. Generic normalized endpoint (trusted, our shape)

```
POST /api/v1/alerts
Authorization: Bearer <api_key>
Idempotency-Key: <optional>
```

Request body — heavily inspired by Rootly, trimmed to fields we'll actually use in v1:

| Field | Type | Required | Notes |
|---|---|---|---|
| `alert_source_id` | uuid | yes | Must belong to workspace; provider `generic` is fine |
| `dedup_key` | string | yes | Scoped to `alert_source_id`; same key updates existing alert |
| `title` | string | yes | Short summary; becomes incident name unless route overrides |
| `description` | string | no | Longer context |
| `status` | enum | no | `firing` (default), `acknowledged`, `resolved` |
| `severity` | enum | no | `critical | high | medium | low | info` |
| `source_url` | url | no | Link back to monitor |
| `external_id` | string | no | Provider's id |
| `labels` | array | no | `[{key, value}]`; used for routing and display |
| `metadata` | object | no | Free-form; preserved verbatim |
| `fired_at` | iso8601 | no | Defaults to `Time.current` |
| `noise` | boolean | no | Marks low-signal alerts |

Response: `201` on first event, `200` on subsequent dedup-matching events. Body returns the alert (same shape as `GET /api/v1/alerts/:id`).

Status transitions on POST:
- `firing` event with existing `firing` alert → bump `event_count`, update `last_event_at`, no state change.
- `resolved` event with existing `firing`/`acknowledged` alert → set `status: resolved`, `resolved_at`. If the alert has an `incident_id` and that incident's lifecycle is open, **do not auto-close** in v1 — record the event on the incident timeline and leave the close decision to humans. (We can flip a workspace setting later: "auto-close incidents when their primary alert resolves.")

### 3. Read endpoints

```
GET    /api/v1/alerts
GET    /api/v1/alerts/:id
PATCH  /api/v1/alerts/:id         # update status, noise flag
GET    /api/v1/alerts/:id/events  # raw event history for this alert
GET    /api/v1/alert_sources
POST   /api/v1/alert_sources
PATCH  /api/v1/alert_sources/:id  # rotate secret, deactivate
DELETE /api/v1/alert_sources/:id  # soft-delete
```

Filters on list: `status`, `alert_source_id`, `severity`, `dedup_key`, `incident_id`, `fired_at[gte/lte]`. Standard pagination (20/page, max 50) matching existing API conventions.

---

## Deduplication

Lookup is `(alert_source_id, dedup_key)`. Critical detail: **dedup_key is scoped per source**, never global. Two different Datadog monitors with the same internal id won't collide with two CloudWatch alarms.

For per-source webhooks, the parser is responsible for computing `dedup_key` from the provider's payload:

- **Datadog** → `payload["alert_id"]` (Datadog's own alert id; stable across firings of the same monitor).
- **Grafana** → `payload["alerts"][i]["fingerprint"]` (Grafana provides this directly).
- **PagerDuty** → `payload["messages"][i]["incident"]["id"]`.
- **Sentry** → `payload["data"]["issue"]["id"]`.
- **CloudWatch** → `payload["AlarmArn"]` (one alert per alarm).
- **New Relic** → `payload["issueId"]` (stable per issue).
- **Generic** → caller supplies `dedup_key`; reject if missing.

When a parser can't extract a stable key (rare, misconfigured providers), fall back to `Digest::SHA256.hexdigest(provider + title + critical labels)` and surface a warning in the UI so the user knows dedupe quality is degraded.

---

## Alert Routing

`AlertRouter.route!(alert)` runs after normalization, inside `AlertIngestionWorkflow`:

1. Skip routing entirely if `alert.noise == true`.
2. Skip routing if the alert is an update to an existing alert that already has an `incident_id` — just record the event on the incident timeline.
3. Otherwise evaluate `alert_routes` in `position` order; first match wins.
4. Execute the matched action:
   - `create_incident` → call `IncidentLifecycleService#create` with `source: "alert"`, `source_alert_id: alert.id`, plus the configured type/severity. Pass the alert's title (or templated name) and labels into the incident's metadata.
   - `attach_to_open` → find an open incident matching the configured field; if found, set `alert.incident_id` and record an `INCIDENT_ALERT_ATTACHED` event on it. If no match, fall through to the next route.
   - `ignore` → record alert, no incident.

Every routing decision is logged on the alert (`routed_to_action`, `routed_to_route_id`, `routed_at`) so the UI can show "matched route X, created incident Y" — debuggability is the #1 thing that makes routing usable, and the #1 thing that makes it horrible if missing.

---

## Provider Recipes (One-Click Configurations)

The shipping unit for "this connects to your monitoring in 60 seconds" is six recipes. Each is a server-side parser + a documented setup snippet. The user flow:

1. Workspace → Settings → Alert Sources → "New source"
2. Pick provider (Datadog | Grafana | New Relic | Sentry | PagerDuty | CloudWatch | Generic)
3. Name it ("Datadog prod")
4. Click Create → modal shows webhook URL + signing secret + provider-specific setup snippet (copy-pasteable) → "I've configured it" button
5. Setup test: send a synthetic event from our side, confirm round-trip; warn if no event seen in 5 minutes

### Per-provider parser surface

```
app/services/alerts/
  base_parser.rb                    # Common normalize interface
  datadog_parser.rb                 # Datadog webhook payload
  grafana_parser.rb                 # Grafana alerting webhook contact point
  new_relic_parser.rb               # NR workflow → webhook destination
  sentry_parser.rb                  # Sentry internal integration webhook
  pagerduty_parser.rb               # PD outbound webhook (v3)
  cloudwatch_parser.rb              # SNS → HTTPS subscription
  prometheus_parser.rb              # Alertmanager webhook receiver (bonus, trivial)
  generic_parser.rb                 # Pass-through of our normalized shape
```

Each parser exposes `parse(raw_payload, headers) -> NormalizedAlert | [NormalizedAlert]` and `verify_signature(raw_body, headers, secret) -> bool`. Returns one or more `NormalizedAlert` POROs (Grafana sends batches).

`NormalizedAlert` fields: `dedup_key, status, title, description, severity, source_url, external_id, labels, metadata, fired_at`.

### Recipe documentation page (per provider)

Lives in `docs/alert_recipes/<provider>.md`, surfaced on docs site and inside the source-creation modal. Each recipe is exactly:
- Why connect (one sentence)
- Step-by-step config in the provider's UI, with screenshots
- The exact webhook URL pattern (`https://app.firefight.io/api/v1/alert_sources/<token>/events`)
- How signing is configured on that provider
- A "test it" curl/script
- Known field mappings (their severity → ours)

### Severity normalization

Each parser maps provider severities to our enum. Examples:

| Provider | Provider value | Firefight |
|---|---|---|
| Datadog | `P1`, `critical` | `critical` |
| Datadog | `P2`, `error` | `high` |
| Datadog | `P3`, `warning` | `medium` |
| Grafana | `critical` | `critical` |
| Grafana | `warning` | `medium` |
| Sentry | `fatal`, `error` | `high` |
| PagerDuty | `critical` | `critical` |
| PagerDuty | `error` | `high` |
| CloudWatch | `ALARM` | `high` (unless `Severity` tag overrides) |

The mapping table is data, not code — lives in a YAML so we can tune it without redeploying parsers.

---

## Workflow

`AlertIngestionWorkflow` (subject: `AlertEvent`, context: `{ workspace_id }`):

```
step :parse_payload
step :upsert_alert,        depends_on: [:parse_payload]
step :evaluate_routes,     depends_on: [:upsert_alert]
step :execute_route_action, depends_on: [:evaluate_routes]
step :mark_event_processed, depends_on: [:execute_route_action]
```

- `parse_payload` — resolve `AlertSource`, verify signature, dispatch to provider parser, return list of `NormalizedAlert`s. Failures mark event `status: failed` with the parse error stored for debugging.
- `upsert_alert` — for each normalized alert: find by `(source_id, dedup_key)` or create. Update timestamps and `event_count`.
- `evaluate_routes` — run `AlertRouter` for new or transitioning alerts.
- `execute_route_action` — calls `IncidentLifecycleService` for `create_incident`/`attach_to_open`. Errors here do *not* fail the event — the alert is recorded; the failure is logged on `alert.routing_error` and surfaced in the UI for the user to retry.
- `mark_event_processed` — set `alert_events.status = processed`.

Generic endpoint (`POST /api/v1/alerts`) skips parsing and goes straight to `upsert_alert`. Same workflow class, different entry point.

---

## UI Surface

### Settings → Alert Sources (new page)

- List of sources, status (active/inactive), last event timestamp, event count last 24h.
- "New source" → provider picker → setup modal with webhook URL, signing secret (shown once), copy-paste config snippet.
- Click into a source: tabbed view — Events (raw payloads, last 100), Alerts (alerts from this source), Settings (rotate secret, deactivate, rename).

### Settings → Alert Routes (new page)

- Ordered list of routes with drag-to-reorder.
- Each route: conditions builder (dropdown for field, op, value), action picker, action config.
- "Test route" — paste a sample alert JSON, see which route would match.

### Dashboard surfacing

- New top-nav item: **Alerts** (above Incidents in the "Respond" section).
- Alerts list: filter by status / source / severity, link to attached incident.
- Alert detail page: title, status, labels, source link, event history, attached incident.
- On incident detail page: "Alerts" section showing alerts attached to this incident, linkable.

### Per-page TypeScript types

Auto-generated from new serializers (`AlertSerializer`, `AlertSourceSerializer`, `AlertRouteSerializer`, `AlertEventSerializer`). Page props extend `SharedProps` per the frontend conventions in CLAUDE.md.

---

## Webhooks (Outbound)

Add to existing webhook event types:

- `alert.firing` — new alert created in `firing` state
- `alert.acknowledged`
- `alert.resolved`
- `alert.attached` — alert attached to an incident (either path)
- `alert.routing_failed` — surfaces route execution errors

Existing webhook delivery infrastructure (HMAC signing, retries, delinquency tracking) covers this with no new code beyond event type constants and payloads.

---

## Shipping Plan

**Milestone 1 — Core ingestion (Week 1-2)**
- Migrations: `alert_sources`, `alert_events`, `alerts`, `alert_routes`.
- Models + `Trackable`/`Recordable` for `Alert` (every status transition becomes an event on the alert).
- Generic endpoint `POST /api/v1/alerts` + `GET /api/v1/alerts*`.
- `AlertIngestionWorkflow` with generic parser only.
- `api_keys.permissions["alerts"]` plumbing.

**Milestone 2 — Routing (Week 2-3)**
- Routes model + evaluator + UI (Settings → Alert Routes).
- Route-driven incident creation via `IncidentLifecycleService` with `source: "alert"`.
- Routing log on each alert + UI to show which route matched.
- Outbound webhook events for alert lifecycle.

**Milestone 3 — Three priority recipes (Week 3-4)**
- Datadog, Grafana, PagerDuty parsers + signature verify + recipe docs + setup-modal UI.
- These three cover ~70% of monitoring stacks we'll see in the first 10 customers.

**Milestone 4 — Remaining recipes (Week 4-5)**
- Sentry, New Relic, CloudWatch, Prometheus/Alertmanager.
- Test harness: per-provider fixture payloads in `test/fixtures/alert_payloads/` exercised in parser tests.

**Milestone 5 — Polish (Week 5-6)**
- Alerts top-nav + dashboard.
- Incident detail page "Alerts" section.
- "Test source" synthetic event flow.
- Documentation site recipe pages with screenshots.

Total: ~6 weeks for one engineer, faster with two working in parallel on parsers vs. core.

---

## Open Questions

1. **Auto-close on resolve?** Default off in v1 (humans decide). Workspace-level toggle in v2. Risk of premature auto-close on flappy alerts argues for opt-in even later.
2. **Alert grouping / correlation?** Punted to a later phase. We have the data (labels, source, time window) — the v1 design doesn't preclude adding `alert_groups` later.
3. **Per-source rate limiting?** Probably yes — a misconfigured monitoring tool can flood. Start with a flat `100 events/minute/source`, return `429`, document it. Adjust based on real traffic.
4. **Custom field mapping from alert labels?** Not in v1. Users with custom fields can configure routes that use labels for matching, but labels don't auto-populate custom fields. Add label→field mapping as a per-source config in v2.
5. **GUI route builder vs. expression DSL?** v1 is the dropdown builder described above. If users hit the wall on expressiveness, add a "raw mode" with a small expression syntax later — do not lead with the DSL.

---

## Non-Goals

- On-call schedules, escalation policies, paging notifications. Pair with PagerDuty's free tier instead.
- Bidirectional sync (Firefight closes incident → tell Datadog to resolve). Outbound webhook in v1; deeper integrations later.
- ML-based noise detection. The `noise` flag is manual in v1; behavioral classification later.
- Multi-alert correlation into a single incident.
- Native Slack ingestion of alerts (e.g. parsing alert messages from a #alerts channel). The recipe for that is "configure your monitor to also POST to Firefight" — not "we screen-scrape Slack."
