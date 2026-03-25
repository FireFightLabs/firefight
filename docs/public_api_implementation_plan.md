# Public API Implementation Plan

## Context

Firefight needs a public REST API so external systems (monitoring tools, CI/CD, custom dashboards) can create and manage incidents programmatically. Modeled after incident.io and Rootly APIs: workspace-scoped API keys with granular permissions, required idempotency_key for incident creation to prevent duplicates (and Slack channel havoc), and serialized payloads with a stable external contract.

**Phase 1 scope:** Incident CRUD + configuration reads (severities, statuses, types).
**Future phases:** Alert ingestion pipeline, incident actions/events, webhooks management via API.

**Reference implementations analyzed:**
- incident.io - Bearer token, required `idempotency_key` on create, 1200 req/min, granular API key permissions
- Rootly - JSON:API spec, three API key types (global/team/personal), rate limit headers, 3000 req/min
- Fizzy - Bearer token with read/write permissions, `has_secure_token`, jbuilder serialization

---

## API Key Management

### Database: `api_keys` table

```
id              uuid PK
workspace_id    uuid FK NOT NULL
created_by_id   uuid FK (workspace_memberships) NOT NULL
name            string NOT NULL
token_digest    string NOT NULL UNIQUE    -- SHA256 hash of the raw token
token_prefix    string(12) NOT NULL       -- first 12 chars for display (e.g., "ff_abc123...")
permissions     jsonb NOT NULL DEFAULT {} -- granular per-resource permissions
active          boolean NOT NULL DEFAULT true
expires_at      datetime NULL             -- null = never expires
last_used_at    datetime NULL
deleted_at      datetime NULL             -- soft delete
created_at, updated_at
```

Indexes: `token_digest` (unique), `[workspace_id, deleted_at]`

### Model: `app/models/api_key.rb`

- Token format: `ff_` prefix + `SecureRandom.base58(36)` = ~39 chars total
- Storage: `Digest::SHA256.hexdigest(token)` in `token_digest` (fast lookup, not bcrypt)
- Token shown ONCE on creation (like GitHub PATs)
- `self.authenticate(raw_token)` - hash lookup + active + not expired + not soft-deleted
- `has_permission?(resource, action)` - checks jsonb permissions hash
- `touch_last_used!` - debounced (update only if nil or >1 min old)
- `soft_delete!` / `restore!` for soft delete
- Scopes: `active`, `not_expired`

### Permissions structure

```json
{
  "incidents": ["read", "create", "update"],
  "severities": ["read"],
  "statuses": ["read"],
  "incident_types": ["read"]
}
```

Available resources: `incidents`, `severities`, `statuses`, `incident_types`
Available actions: `read`, `create`, `update`, `delete`

---

## Idempotency (Deduplication)

### Database: `idempotency_keys` table

```
id              uuid PK
workspace_id    uuid FK NOT NULL
key             string NOT NULL
resource_type   string NOT NULL
resource_id     uuid NOT NULL
created_at      datetime NOT NULL
```

Indexes: `[workspace_id, key]` (unique), `created_at`

### Model: `app/models/idempotency_key.rb`

- Workspace-scoped uniqueness on `key`
- 24-hour TTL, cleaned by daily `CleanupIdempotencyKeysJob`
- On incident create: if key exists, return existing incident (200); if not, create new (201)

---

## Authentication

### `app/controllers/concerns/api_authentication.rb`

```
1. Extract Bearer token from Authorization header
2. ApiKey.authenticate(token) -> returns ApiKey or nil
3. Set Current.workspace and Current.api_key
4. Return 401 JSON if auth fails
5. authorize!(resource, action) helper checks permissions -> 403 if denied
```

### `app/models/current.rb` (modify)

Add `attribute :workspace, :api_key` to existing Current model.

---

## Base Controller

### `app/controllers/api/v1/api_controller.rb`

Inherits from `ActionController::API` (NOT from existing `Api::V1::BaseController` which does Slack signature verification).

- Includes `ApiAuthentication` concern
- Rate limiting: `rate_limit to: 1000, within: 1.minute, by: -> { Current.api_key&.id }`
- Error handlers: RecordNotFound (404), RecordInvalid (422), ParameterMissing (400)
- Pagination: `paginate(scope)` with `page`/`per_page` params (default 25, max 100)
- Standard error format:

```json
{
  "error": {
    "type": "validation_error",
    "message": "Severity can't be blank",
    "request_id": "req_abc123",
    "errors": [{ "field": "severity_id", "message": "can't be blank" }]
  }
}
```

---

## Endpoints

### Routes (add to existing `config/routes.rb`)

```ruby
namespace :api do
  namespace :v1 do
    # Existing Slack routes (commands, interactions, events) stay as-is

    # Public API (Bearer token auth via Api::V1::ApiController)
    resources :incidents, only: [:index, :show, :create, :update]
    resources :severities, only: [:index]
    resources :statuses, only: [:index]
    resources :incident_types, only: [:index]
  end
end
```

### POST /api/v1/incidents (Create)

**Request:**
```json
{
  "idempotency_key": "monitoring-alert-abc123",  // REQUIRED
  "name": "Database connection pool exhausted",   // REQUIRED
  "severity_id": "uuid",                          // REQUIRED
  "summary": "Connection pool at 100%...",         // optional
  "status_id": "uuid",                             // optional, defaults to workspace default
  "incident_type_id": "uuid",                      // optional
  "declared_by_id": "uuid",                        // optional, defaults to API key creator
  "visibility": "public"                           // optional, default "public"
}
```

**Response (201 Created):**
```json
{
  "incident": {
    "id": "uuid",
    "identifier": "INC-042",
    "name": "Database connection pool exhausted",
    "summary": "...",
    "visibility": "public",
    "status": { "id": "uuid", "name": "Investigating", "lifecycle_stage": "active" },
    "severity": { "id": "uuid", "name": "SEV1", "rank": 1 },
    "type": { "id": "uuid", "name": "Infrastructure" },
    "lead": null,
    "declared_by": { "id": "uuid", "name": "Alice Smith", "email": "alice@example.com" },
    "declared_at": "2026-03-24T10:00:00Z",
    "detected_at": null,
    "resolved_at": null,
    "created_at": "2026-03-24T10:00:00Z",
    "updated_at": "2026-03-24T10:00:00Z",
    "custom_fields": {}
  }
}
```

**Idempotent replay (200 OK):** Same `idempotency_key` returns the original incident.

**Flow:**
```
Authenticate (Bearer token -> ApiKey -> workspace)
  -> authorize!("incidents", "create")
  -> Check IdempotencyKey -> return existing if found (200)
  -> Resolve severity, status (default), type
  -> Incident.create!(...) [sync - assigns identifier via Sequencing concern]
  -> IdempotencyKey.create!(...)
  -> IncidentCreationWorkflow.start!(incident) [async - Slack channel, announcements]
  -> Return 201 with incident
```

Reference pattern: `app/services/interactions/incident_creation_handler.rb:16-27`

### GET /api/v1/incidents (List)

Paginated. Filterable by `status`, `severity`, `lifecycle_stage`.

**Response:**
```json
{
  "incidents": [ ... ],
  "pagination": { "page": 1, "per_page": 25, "total": 142, "total_pages": 6 }
}
```

### GET /api/v1/incidents/:id (Show)

Returns single incident wrapped in `{ "incident": { ... } }`.

### PATCH /api/v1/incidents/:id (Update)

Uses `incident.record_change!` for proper event tracking. Supports: name, summary, severity_id, status_id, incident_type_id, lead_id.

### GET /api/v1/severities (List)

Returns `{ "severities": [{ "id", "name", "rank", "slug" }] }`.

### GET /api/v1/statuses (List)

Returns `{ "statuses": [{ "id", "name", "lifecycle_stage" }] }`.

### GET /api/v1/incident_types (List)

Returns `{ "incident_types": [{ "id", "name" }] }`.

---

## Serialization

Jbuilder templates in `app/views/api/v1/`. External contract is separate from internal models.

### Key templates:
- `app/views/api/v1/incidents/_incident.json.jbuilder` - full incident representation
- `app/views/api/v1/incidents/show.json.jbuilder` - wraps in `{ incident: ... }`
- `app/views/api/v1/incidents/index.json.jbuilder` - array + pagination
- `app/views/api/v1/severities/index.json.jbuilder`
- `app/views/api/v1/statuses/index.json.jbuilder`
- `app/views/api/v1/incident_types/index.json.jbuilder`

---

## Jobs

### `app/jobs/cleanup_idempotency_keys_job.rb`

Daily recurring job via SolidQueue. Deletes records older than 24 hours.

---

## New Files

```
db/migrate/xxx_create_api_keys.rb
db/migrate/xxx_create_idempotency_keys.rb
app/models/api_key.rb
app/models/idempotency_key.rb
app/controllers/concerns/api_authentication.rb
app/controllers/api/v1/api_controller.rb
app/controllers/api/v1/incidents_controller.rb
app/controllers/api/v1/severities_controller.rb
app/controllers/api/v1/statuses_controller.rb
app/controllers/api/v1/incident_types_controller.rb
app/views/api/v1/incidents/_incident.json.jbuilder
app/views/api/v1/incidents/show.json.jbuilder
app/views/api/v1/incidents/index.json.jbuilder
app/views/api/v1/incidents/create.json.jbuilder
app/views/api/v1/severities/index.json.jbuilder
app/views/api/v1/statuses/index.json.jbuilder
app/views/api/v1/incident_types/index.json.jbuilder
app/jobs/cleanup_idempotency_keys_job.rb
test/models/api_key_test.rb
test/models/idempotency_key_test.rb
test/controllers/api/v1/incidents_controller_test.rb
test/controllers/api/v1/severities_controller_test.rb
test/controllers/api/v1/statuses_controller_test.rb
test/controllers/api/v1/incident_types_controller_test.rb
test/jobs/cleanup_idempotency_keys_job_test.rb
test/support/api_test_helper.rb
test/fixtures/api_keys.yml
test/fixtures/idempotency_keys.yml
```

## Modified Files

```
app/models/current.rb       (add workspace, api_key attributes)
config/routes.rb             (add API resource routes)
config/recurring.yml         (add cleanup job schedule)
```

---

## Implementation Order

1. Migrations + models (ApiKey, IdempotencyKey) + fixtures + model tests
2. Current model update + ApiAuthentication concern
3. Api::V1::ApiController base + error handling + pagination + test helper
4. Read-only endpoints (severities, statuses, types) + templates + tests
5. Incidents controller (CRUD) + templates + idempotency + tests
6. Cleanup job + recurring schedule
7. Routes update

---

## Verification

1. `bin/rails db:migrate`
2. `bin/rails test` - all tests pass
3. Manual curl tests (create API key in console, test endpoints)
4. `bin/ci` - full CI passes

---

## Documentation Update (firefight-docs)

The following documentation pages need to be created/updated in the `firefight-docs` project (`../firefight-docs`):

### New pages to create

1. **`content/docs/integrations/index.mdx`** - Integrations overview page
   - Brief intro to API and webhooks
   - Links to sub-pages

2. **`content/docs/integrations/api-overview.mdx`** - API Overview
   - Authentication (Bearer token)
   - Rate limiting (1000 req/min)
   - Error format
   - Pagination
   - Idempotency keys

3. **`content/docs/integrations/api-keys.mdx`** - API Key Management
   - Creating API keys (UI walkthrough)
   - Permission levels (read, create, update, delete per resource)
   - Expiration settings
   - Revoking/disabling keys
   - Security best practices

4. **`content/docs/integrations/creating-incidents.mdx`** - Creating Incidents via API
   - Endpoint reference (POST /api/v1/incidents)
   - Required fields (idempotency_key, name, severity_id)
   - Optional fields
   - Deduplication via idempotency_key
   - What happens after creation (Slack channel, announcements)
   - Example curl requests

5. **`content/docs/integrations/managing-incidents.mdx`** - Managing Incidents via API
   - Listing incidents (GET /api/v1/incidents) with filters
   - Getting incident details (GET /api/v1/incidents/:id)
   - Updating incidents (PATCH /api/v1/incidents/:id)
   - Status transitions via API

6. **`content/docs/integrations/api-reference.mdx`** - Full API Reference
   - All endpoints with request/response schemas
   - Severities, statuses, incident types endpoints
   - Error codes reference

7. **`content/docs/integrations/webhooks.mdx`** - Outgoing Webhooks (already built)
   - Setting up webhooks
   - Available events
   - Payload format
   - Signature verification (X-Webhook-Signature)
   - Delivery tracking

### Navigation update

Update `source.config.ts` or equivalent nav config to add the Integrations section between existing sections.
