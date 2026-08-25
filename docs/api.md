# Public API

REST API at `/api/v1/` with Bearer token authentication via `ApiKey` model. API controllers inherit from `Api::V1::ApiController` (NOT from `Api::V1::BaseController` which does Slack signature verification). Read this before working on API endpoints, keys, auth, or idempotency.

**Authentication**: `ApiAuthentication` concern extracts Bearer token, looks up `ApiKey` by SHA256 digest (cached 24h, busted on key update), sets `Current.workspace` and `Current.api_key`.

**Authorization**: `authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_CREATE)` raises `ApiAuthentication::ForbiddenError` if the key lacks permission. Permissions stored as jsonb on `ApiKey`: `{ "incidents" => ["read", "create", "update"] }`.

**Idempotency**: `POST /api/v1/incidents` requires `idempotency_key`. Duplicate key returns existing incident (200) instead of creating new (201). Keys expire after 24h via `CleanupIdempotencyKeysJob`.

**Source tracking**: Incidents have a `source` field (free-form string) and optional `source_api_key_id` FK. API callers specify source (e.g., "datadog", "pagerduty"). Slack-created incidents use `Incident::SOURCE_SLACK`.

**Serialization**: Jbuilder templates in `app/views/api/v1/` — external contract decoupled from internal models.

**Key files**:
```
app/controllers/concerns/api_authentication.rb  # Bearer token auth + permission checking
app/controllers/api/v1/api_controller.rb        # Base controller (error handling, pagination)
app/controllers/api/v1/incidents_controller.rb   # Incident CRUD
app/controllers/api/v1/timeline_controller.rb    # Incident timeline (index) + dismiss one AI note
app/controllers/api/v1/custom_fields_controller.rb # Custom field values
app/controllers/api/v1/catalog/                  # Catalogue read/write endpoints
app/controllers/api/v1/severities_controller.rb  # Read-only
app/controllers/api/v1/statuses_controller.rb    # Read-only
app/controllers/api/v1/incident_types_controller.rb # Read-only
app/controllers/api/v1/runbooks_controller.rb    # Read-only (index + show by slug or id)
app/controllers/api/v1/abilities_controller.rb   # Gateway: grantable abilities (permissions:read)
app/controllers/api/v1/principals_controller.rb  # Gateway: people, agents, service keys and their grants
app/controllers/api/v1/permission_sets_controller.rb # Gateway: sets by slug, abilities by key
app/controllers/api/v1/grants_controller.rb      # Gateway: grants by id, environments by slug
app/controllers/api/v1/approval_rules_controller.rb # Gateway: rules by id, partial updates, move_up/move_down
app/controllers/api/v1/approvals_controller.rb   # Gateway: list, approve, deny (deciding is human-only)
app/controllers/api/v1/activity_controller.rb    # Gateway: the invocation ledger
app/models/api_key.rb                            # Token auth, permissions, caching
app/models/idempotency_key.rb                    # Deduplication
app/views/api/v1/                                # Jbuilder response templates
```

**Timeline endpoints**: `GET /api/v1/incidents/:incident_id/timeline` returns the incident's recorded events in order, paginated, each with `event_type`, `description`, `actor` and, for `milestone.noted`, a `milestone` object carrying `kind`, `statement`, `said_by`, `message_text` and `permalink`. That is how an agent learns how an incident was debugged without reading the channel. `PATCH /api/v1/incidents/:incident_id/timeline/:id/dismiss` (`incidents:update`) dismisses one AI note. Anything that is not a note is refused 422. Dismissed notes leave the index, matching the MCP `get_incident` timeline and `dismiss_timeline_note`.

**Gateway endpoints**: everything under Gateway → Permissions is reachable over REST, through the same model calls the dashboard uses (`Ability::Principal.find!`, `Ability::Grant.grant!`/`#rescope!`, `Ability::Role#sync_actions!`, `PolicyRule::ApprovalRuleChanges.attributes`). They authorize as `permissions:*`, which is admin-only, so only an admin's personal token reaches them. Principals are addressed by `principal_kind` (`user`, `agent`, `api_key`) plus id, abilities by key, sets by slug, environments by catalog slug. Approving or denying an approval additionally requires `Current.principal` to be a `WorkspaceMembership`, since `Ability::Approval#resolve!` takes a membership.

**Token kinds**: an ApiKey is either a **service key** (standalone principal, scoped by its `permissions` jsonb) or a **personal token** (`workspace_membership_id` set — acts with that member's authority: read everything, participate in incidents, configure nothing; destroyed with the membership). `ApiKey#principal` resolves who a request is authorized as; `Current.principal` carries it. The rule itself lives on `WorkspaceMembership#implicitly_permits?` so the token and the human can never drift.

**Namespace gotcha**: `commands_controller.rb`, `interactions_controller.rb`, and `events_controller.rb` also live under `app/controllers/api/v1/`, but they are the **Slack entry points** (inherit `Api::V1::BaseController`, Slack signature verification) — not part of the public API.

`alerts_controller.rb` is a third auth mechanism in the same namespace: the alert ingest endpoint (`POST /api/v1/alerts/:endpoint_path`). It inherits `ActionController::API` directly and authenticates per alert source (secret token verified by the source's provider adapter under `app/adapters/alert_providers/`) — neither Slack signatures nor public-API Bearer keys.
