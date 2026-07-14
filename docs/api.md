# Public API

REST API at `/api/v1/` with Bearer token authentication via `ApiKey` model. API controllers inherit from `Api::V1::ApiController` (NOT from `Api::V1::BaseController` which does Slack signature verification). Read this before working on API endpoints, keys, auth, or idempotency.

**Authentication**: `ApiAuthentication` concern extracts Bearer token, looks up `ApiKey` by SHA256 digest (cached 24h, busted on key update), sets `Current.workspace` and `Current.api_key`.

**Authorization**: `authorize!(ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_CREATE)` — raises `ApiAuthentication::ForbiddenError` if the key lacks permission. Permissions stored as jsonb on `ApiKey`: `{ "incidents" => ["read", "create", "update"] }`.

**Idempotency**: `POST /api/v1/incidents` requires `idempotency_key`. Duplicate key returns existing incident (200) instead of creating new (201). Keys expire after 24h via `CleanupIdempotencyKeysJob`.

**Source tracking**: Incidents have a `source` field (free-form string) and optional `source_api_key_id` FK. API callers specify source (e.g., "datadog", "pagerduty"). Slack-created incidents use `Incident::SOURCE_SLACK`.

**Serialization**: Jbuilder templates in `app/views/api/v1/` — external contract decoupled from internal models.

**Key files**:
```
app/controllers/concerns/api_authentication.rb  # Bearer token auth + permission checking
app/controllers/api/v1/api_controller.rb        # Base controller (error handling, pagination)
app/controllers/api/v1/incidents_controller.rb   # Incident CRUD
app/controllers/api/v1/custom_fields_controller.rb # Custom field values
app/controllers/api/v1/catalog/                  # Catalogue read/write endpoints
app/controllers/api/v1/severities_controller.rb  # Read-only
app/controllers/api/v1/statuses_controller.rb    # Read-only
app/controllers/api/v1/incident_types_controller.rb # Read-only
app/models/api_key.rb                            # Token auth, permissions, caching
app/models/idempotency_key.rb                    # Deduplication
app/views/api/v1/                                # Jbuilder response templates
```

**Namespace gotcha**: `commands_controller.rb`, `interactions_controller.rb`, and `events_controller.rb` also live under `app/controllers/api/v1/`, but they are the **Slack entry points** (inherit `Api::V1::BaseController`, Slack signature verification) — not part of the public API.

`alerts_controller.rb` is a third auth mechanism in the same namespace: the alert ingest endpoint (`POST /api/v1/alerts/:endpoint_path`). It inherits `ActionController::API` directly and authenticates per alert source (secret token verified by the source's provider adapter under `app/adapters/alert_providers/`) — neither Slack signatures nor public-API Bearer keys.
