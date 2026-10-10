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
app/controllers/api/v1/action_items_controller.rb # Incident action items: list, create, take, hand over, finish
app/controllers/api/v1/incident_participation_controller.rb # Escalate, invite, link, shoutout, claim a runbook step
app/controllers/api/v1/custom_fields_controller.rb # Custom field values
app/controllers/api/v1/catalog/                  # Catalogue read/write endpoints
app/controllers/api/v1/severities_controller.rb  # Read-only
app/controllers/api/v1/statuses_controller.rb    # Read-only
app/controllers/api/v1/incident_types_controller.rb # Read-only
app/controllers/api/v1/runbooks_controller.rb    # CRUD by slug or id, steps with tool and arguments, inputs, aliases, watch
app/controllers/api/v1/handbook_pages_controller.rb # The handbook's pages: list, read, create, update, delete
app/controllers/api/v1/abilities_controller.rb   # Gateway: grantable abilities (permissions:read)
app/controllers/api/v1/principals_controller.rb  # Gateway: people, agents, service keys and their grants
app/controllers/api/v1/permission_sets_controller.rb # Gateway: sets by slug, abilities by key, built-in packs read only
app/controllers/api/v1/grants_controller.rb      # Gateway: grants by id, environments by slug
app/controllers/api/v1/approval_rules_controller.rb # Gateway: rules by id, partial updates, move_up/move_down
app/controllers/api/v1/unattended_rules_controller.rb # Gateway: changes Halon may make on its own, partial updates, delete refused once used
app/controllers/api/v1/approvals_controller.rb   # Gateway: list, approve, deny
app/controllers/api/v1/activity_controller.rb    # Gateway: the invocation ledger
app/models/api_key.rb                            # Token auth, permissions, caching
app/models/idempotency_key.rb                    # Deduplication
app/views/api/v1/                                # Jbuilder response templates
```

**Participation endpoints**: everything a responder does inside an incident, as opposed to moving its status, which stays on `PATCH /api/v1/incidents/:id`. All of them authorize as `incidents:update` and call the same services Slack and the dashboard call, so the timeline cannot tell where the action came from.

```
GET    /api/v1/incidents/:incident_id/action_items
POST   /api/v1/incidents/:incident_id/action_items       # description, kind, assignee_id
PATCH  /api/v1/incidents/:incident_id/action_items/:id   # assignee_id and/or status
POST   /api/v1/incidents/:id/escalate                    # member_id, reason
POST   /api/v1/incidents/:id/invite                      # member_ids
POST   /api/v1/incidents/:id/link                        # other_incident_id, relationship
POST   /api/v1/incidents/:id/shoutout                    # member_id, message
POST   /api/v1/incidents/:id/runbook_steps/claim         # runbook_id, step_id, member_id
```

An action item carries `external_key` and `external_url` when it tracks an issue in an issue tracker, which Halon records for itself as an action or a follow-up (see Issues opened by Halon in [integrations.md](integrations.md)). Both are null otherwise. `issue_status` says, in words, why the item's issue is missing or not kept in step (opening, waiting for approval, refused, declined, deleted in the tracker, an assignee the tracker has no account for), and is null otherwise. Creating an item over the API opens its issue when the workspace opens one for every item of its kind, the same as from Slack or the dashboard. `PATCH` takes `description` to rename an item (at most `IncidentAction::TITLE_LIMIT`, 3,000 characters, which is all Slack's input holds, refused on every surface by `IncidentAction#title_length_refusal` with how long it is, and shown under the field on the dashboard), and `status: open` to reopen a done one or let go of one in progress, since open means nobody holds it. Workspace settings have no API endpoint.

`PATCH action_items/:id` is one call for three verbs because from the caller's side each is the same sentence: this item now looks like this. Sending `assignee_id: null` takes the item for the key itself (a pick-up, no announcement), naming someone else hands it over (announced), and `status: "done"` finishes it. Which event is recorded is `IncidentActionService`'s decision, not the body's, and so is what `status: open` means (`open_action`). Every refusal a body could meet is checked first (`IncidentAction#change_blocked_reason`), so a refused request writes none of it.

`member_id` fields accept an email or a platform user id, never a database id, matching the MCP tools. A reference that resolves to nobody is a 404 rather than a silent no-op.

**Configuration endpoints**: every settings screen has a matching REST surface,
mirroring the MCP tools. The four option lists share
`ApiManagesConfigurableOptions`, which calls the same model methods the
dashboard and MCP call.

```
GET/POST        /api/v1/severities          PATCH/DELETE /api/v1/severities/:slug
GET/POST        /api/v1/statuses            PATCH/DELETE /api/v1/statuses/:slug
GET/POST        /api/v1/incident_types      PATCH/DELETE /api/v1/incident_types/:slug
GET/POST        /api/v1/incident_roles      PATCH/DELETE /api/v1/incident_roles/:slug
GET/POST        /api/v1/alert_sources       PATCH/DELETE /api/v1/alert_sources/:endpoint_path
GET/POST        /api/v1/webhooks            PATCH/DELETE /api/v1/webhooks/:id
GET/POST        /api/v1/api_keys            PATCH/DELETE /api/v1/api_keys/:prefix
GET/POST        /api/v1/agents              PATCH/DELETE /api/v1/agents/:slug
POST            /api/v1/agents/:slug/rotate
DELETE          /api/v1/agents/:slug/tokens/:token_prefix
```

Options are addressed by slug, which renaming never moves, because it is what
stored records point at. **The listing keeps its existing collection key and
still leaves disabled entries out**, so adding writes moved nothing for a
reader. `?include_disabled=true` returns them for a caller managing the list,
since re-enabling one means seeing it first.

`api_keys` and `agents` authorize as `ADMIN_ONLY_RESOURCES`, so an admin's
personal token reaches them and no service key or agent can. A token appears
once, in the response that minted it, and never in a listing.

**Handbook endpoints**: the workspace's handbook pages, authorized as `handbook` (members read it, writing needs a grant, a service key holds only what it is granted), through the same `HandbookService` the dashboard and MCP write through.

```
GET    /api/v1/handbook/pages         # every page in order, without its text
GET    /api/v1/handbook/pages/:id     # one page whole, with wording_id
POST   /api/v1/handbook/pages         # title, text, incident_role (a role's slug, for the page saying who directs Halon), freeze_windows
PATCH  /api/v1/handbook/pages/:id     # title, text and freeze_windows, only what is sent changes, wording_id refuses an edit over someone else's with 409
DELETE /api/v1/handbook/pages/:id     # the page and its history
```

A synced page is read here and changed only at its source, so a write to one answers 422 `page_synced` with why. A personal token writes as its member, which the page's history names, and a service key as nobody.

**Postmortem endpoints**: `GET`, `POST` and `PATCH` on `/api/v1/incidents/:id/postmortem`. `POST` with `generate: true` drafts it from the incident and comes back with a `generation_state` to poll on, otherwise it opens an empty one. `PATCH` takes `html` to replace the body, `status` to move it along, or both.

**The configuration surface is square now.** `custom_fields` and `runbooks` are writable, and `forms`, `routing_rules` and `routing/evaluate` exist, so the only areas still MCP-only are gone. The shared mapping each of those needs lives where both surfaces reach it: `IncidentFieldDefinitionService#upsert!`, `Runbook::Upsert`, `IncidentFormService#upsert_field!` and `IncidentCondition::Values`, which moved out of `app/mcp/` because a model cannot depend on the MCP layer and REST needed it too.

**Timeline endpoints**: `GET /api/v1/incidents/:incident_id/timeline` returns the incident's recorded events in order, paginated, each with `event_type`, `description`, `actor`, an `update` object for an update or a cancellation (`message`, what the responder posted as markdown, and `changes`, each with `field`, `label`, `before` and `after`, null otherwise) and, for `milestone.noted`, a `milestone` object carrying `kind`, `statement`, `said_by`, `message_text` and `permalink`. A change's before is read from the incident's whole history, so it is right on any page. That is how an agent learns how an incident was debugged without reading the channel. `PATCH /api/v1/incidents/:incident_id/timeline/:id/dismiss` (`incidents:update`) dismisses one AI note. Anything that is not a note is refused 422. Dismissed notes leave the index, matching the MCP `get_incident` timeline and `dismiss_timeline_note`.

**Gateway endpoints**: everything under Gateway → Permissions is reachable over REST, through the same model calls the dashboard uses (`Ability::Principal.find!`, `Ability::Grant.grant!`/`#rescope!`, `Ability::Role#sync_actions!`, `PolicyRule::ApprovalRuleChanges.attributes`). They authorize as `permissions:*`, which is admin-only, so only an admin's personal token reaches them. Principals are addressed by `principal_kind` (`user`, `agent`, `api_key`) plus id, abilities by key, sets by slug, environments by catalog slug. Unattended rules (`/unattended_rules`) take `resource` by its map id, name or provider id (`Ability::UnattendedRule.changes_from`, shared with the dashboard and MCP), take only the keys given so `enabled` alone turns one on or off, and refuse a delete with `delete_blocked_reason` as a 422 once Halon acted under the rule. Approving or denying an approval additionally re-validates `Current.principal` through `Ability::Approval#approver?` — a member holding the role, or a named principal when the rule sets `agents_may_approve`.

**Token kinds**: an ApiKey is either a **service key** (standalone principal, scoped by its `permissions` jsonb) or a **personal token** (`workspace_membership_id` set — acts with that member's authority: read everything, participate in incidents, configure nothing; destroyed with the membership). `ApiKey#principal` resolves who a request is authorized as; `Current.principal` carries it. The rule itself lives on `WorkspaceMembership#implicitly_permits?` so the token and the human can never drift.

**Namespace gotcha**: `commands_controller.rb`, `interactions_controller.rb`, and `events_controller.rb` also live under `app/controllers/api/v1/`, but they are the **Slack entry points** (inherit `Api::V1::BaseController`, Slack signature verification) — not part of the public API.

`alerts_controller.rb` is a third auth mechanism in the same namespace: the alert ingest endpoint (`POST /api/v1/alerts/:endpoint_path`). It inherits `ActionController::API` directly and authenticates per alert source (secret token verified by the source's provider adapter under `app/adapters/alert_providers/`) — neither Slack signatures nor public-API Bearer keys.

## Test incidents

Every incident payload carries `test`. A test incident (the onboarding walkthrough, `Incident#is_test`) behaves like a real one on every read and write path and is left out of dashboard figures. Outbound webhooks are never sent for one.
