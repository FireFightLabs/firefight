# Firefight

Incident management platform built with Rails 8.1. Currently integrates with Slack, designed for multi-platform support (Teams, etc.).

## CI

Run `bin/ci` to validate changes. It runs rubocop, bundler-audit, brakeman, rails test (parallel), system tests, and seeds.

## Code Style

- No unnecessary comments — only explain non-obvious logic
- No ticket numbers in comments
- No emojis unless requested
- No direct `Rails.logger` helper wrappers — call `Rails.logger.info(...)` inline where needed
- Keep it simple, avoid over-engineering
- Rubocop enforced: `[ {...} ]` not `[{...}]` (SpaceInsideArrayLiteralBrackets)
- Never use raw strings for identifiers, resource names, action names, or event types — always use constants (e.g., `ApiKey::RESOURCE_INCIDENTS` not `"incidents"`, `IncidentEvent::INCIDENT_CREATED` not `"incident.created"`, `Identifiers::INCIDENT_CREATION_MODAL` not the string)
- Model concerns live next to their model in `app/models/<model>/`, not in `app/models/concerns/`. E.g. `Incident::Lifecycle` lives at `app/models/incident/lifecycle.rb`. Don't use `rails g concern` (it generates into `app/models/concerns/`) — create the file manually in the right directory.

## Architecture

### Layer Hierarchy

```
Controller → Dispatcher → Handler → Service → Adapter → Slack::Client
                                  ↘ Job → Service → Adapter → Slack::Client   (heavy work only)
```

Each layer has a single responsibility. Never skip layers.

Commands dispatch **synchronously** by default — Slack's 3-second budget covers the common path (modal openers, ephemerals, fast DB work). A handler enqueues its own job only when the work can't fit: AI generation, paginated Slack lookups, large fan-outs. See [When to enqueue from a handler](#when-to-enqueue-from-a-handler).

### Entry Points (Boundary Layers)

Slack and the Public API are **entry points** into the same system. They are thin boundary layers that normalize platform-specific input and call shared services. All business logic and side effects live in shared services — never in entry points.

```
Slack:  Controller → Dispatcher → Handler → IncidentLifecycleService → Workflows
API:    Controller                        → IncidentLifecycleService → Workflows
Teams:  (future)   → ...                  → IncidentLifecycleService → Workflows
```

#### What entry points do (boundary concerns only)
1. **Normalize input** — parse platform-specific payload into resolved records (Slack: dig into interaction values, resolve slugs; API: parse JSON params, resolve UUIDs)
2. **Call shared service** — `IncidentLifecycleService.new(workspace).create(...)` / `.update(...)` / `.close(...)` etc.
3. **Platform-specific response** — Slack: return modal hash, delete temp messages; API: render JSON
4. **Platform-specific extras** — only when the platform requires it (e.g., Slack handler creates channel synchronously before the workflow so the confirmation modal can include a channel link)

#### What entry points must NOT do
- Business logic (event type determination, transcript cache management, channel archival)
- Workflow orchestration (deciding which workflow to start)
- Side effects (these belong in the service)
- Duplicate logic that exists in another entry point

#### Adding a new entry point (e.g., Teams, Discord, new API endpoint)
1. Create a controller/handler that normalizes input
2. Call `IncidentLifecycleService` — same methods, same interface
3. Return platform-specific response
4. Never duplicate the service logic — if the service doesn't support what you need, extend the service

### IncidentLifecycleService

All incident write operations go through `IncidentLifecycleService` (`app/services/incident_lifecycle_service.rb`). This is the single source of truth for what happens when an incident is created, updated, closed, reopened, or has a lead assigned.

```ruby
service = IncidentLifecycleService.new(workspace)

# Create — creates incident record, starts IncidentCreationWorkflow (channel, announcements, etc.)
incident = service.create(declared_by:, incident_status:, incident_severity:, name:, source:, ...)

# Update — records change event, starts IncidentUpdateWorkflow (channel topic, announcement update)
service.update(incident, { summary: "New info" }, changed_by: member, message: "Status update")

# Close — records change, expires transcript cache, starts IncidentCloseWorkflow, schedules channel archival
service.close(incident, { incident_status: resolved_status }, changed_by: member)

# Reopen — records change, clears transcript cache, unarchives channel, starts IncidentReopenWorkflow
service.reopen(incident, { incident_status: active_status }, changed_by: member, reason: "False alarm")

# Assign lead — records change, starts LeadAssignmentWorkflow (channel topic, lead DM, announcement)
service.assign_lead(incident, lead_member, changed_by: member)
```

The service:
- Takes `changed_by` as a `WorkspaceMembership` (works for both Slack users and API key creators)
- Derives workflow context (e.g., `platform_user_id`) from the membership — no platform-specific IDs passed by callers
- Handles all side effects: transcript cache, channel archival, workflow start
- Is independently testable (`test/services/incident_lifecycle_service_test.rb`)

### Thin Controllers

Controllers validate requests, normalize payloads, dispatch synchronously, and render the response. No business logic. Slack requires response within 3 seconds (trigger_id expiration) — the controller stays in-process and meets that budget by relying on handlers to enqueue jobs when their work is heavy.

```
Api::V1::CommandsController     → Slack::CommandAdapter.parse → ensure_membership! → CommandDispatcher.dispatch → render JSON / head :ok
Api::V1::InteractionsController → Slack::InteractionNormalizer.call → ensure_membership! → InteractionDispatcher.dispatch → render JSON / head :ok
```

`ensure_membership!` (in `Api::V1::BaseController`) lazily provisions a `WorkspaceMembership` for the acting Slack user via `WorkspaceMemberProvisioner` so downstream handlers can trust `find_by!(platform_user_id:)`. Best-effort — provisioning failure logs and dispatch continues.

Controllers are the platform-specific boundary — they normalize payloads into platform-agnostic objects before passing to dispatchers.

#### When to enqueue from a handler

Most handlers stay sync. A handler should enqueue its own job when **any** of these is true:

- The work calls an AI provider or another slow external API (`PostmortemHandler`, `CatchupHandler`).
- The work hits paginated Slack endpoints (`users.list`, `conversations.list`) or fans out N sequential API calls (`InviteHandler` resolve+invite path).
- The work could plausibly exceed ~1.5s on the slowest realistic workspace (leaves headroom inside Slack's 3s budget for signature verify, membership provisioning, and dispatch).

Pattern (see `Commands::InviteHandler` + `IncidentInviteJob` + `IncidentInviteService#resolve_and_notify!` as the reference):

1. Handler does cheap precondition checks; if heavy work is needed, calls `MyJob.perform_later(...)` with primitive args (ids, text, channel_id, user_id — never AR records).
2. Handler returns an immediate ephemeral acknowledgment (`Command.ephemeral(":hourglass_flowing_sand: …")`).
3. Job loads records and calls a single service method that owns the whole flow (work + final notification via `adapter.post_ephemeral`).
4. Job is a thin shell — no business logic, no Slack calls. Service owns the orchestration; adapter owns the platform calls.

Handlers that must stay sync regardless of cost: anything that opens a modal. `trigger_id` expires in 3s and cannot be used from a job.

**Inertia controllers** follow the same thin pattern. Query filtering belongs in model scopes (chainable, independently testable). Serialization belongs in serializer classes (`app/serializers/`). Aggregations and computed metrics belong in POROs (e.g., `DashboardStats`). The controller parses params, chains scopes, paginates, and renders — no inline SQL, no serialization loops, no metric calculations.

### Dashboard

The incidents dashboard demonstrates the full Inertia data flow pattern. Use it as a reference when building new dashboard-style pages.

**Data flow:**
```
Controller → Incident.filtered_list(filters:, page:, per_page:) → IncidentListItemSerializer.many(...)
           → DashboardStats.new(workspace).to_a (deferred)
           → SeverityOptionSerializer.many(...)
           ↓
Inertia props → usePage<DashboardPageProps>()
           ↓
Frontend    → useIncidentsTable(data, columns, filters, pagination) → router.get() on filter change
```

**Server-side filtering + pagination** (`Incident.filtered_list`):
- Accepts `filters: { search:, severities:, lifecycle_stages: }` hash (extensible) + `page:` + `per_page:`
- Chains model scopes: `search`, `by_severity_slugs`, `by_lifecycle_stage_keys`
- Returns `{ incidents:, pagination: { page, perPage, totalCount, totalPages } }`
- Eager-loads associations via `with_list_associations` scope to prevent N+1

**Deferred stats** (`DashboardStats` PORO):
- Wrapped in `InertiaRails.defer { ... }` — loads after initial page render so the table appears instantly
- Frontend uses `<Deferred data="stats" fallback={<StatCardsSkeleton />}>` for loading state
- Filter navigations use `only: ["incidents", "pagination", "filters"]` to skip re-fetching stats
- MTTR cached per workspace for 24h via `Rails.cache` (key: `dashboard_stats/{workspace_id}/mttr`)

**Frontend filter navigation** (`useIncidentsTable` hook):
- Filter/pagination changes call `router.get(dashboardPath(), params, { preserveState: true, preserveScroll: true, only: [...] })`
- Search input debounced 300ms before triggering navigation
- Severity/status toggles and page changes navigate immediately
- Column visibility and sorting remain client-side (within the current page)

**Key files:**
```
app/controllers/dashboard_controller.rb           # Thin — parses params, calls filtered_list, renders
app/models/incident.rb                            # filtered_list class method + filter scopes
app/models/dashboard_stats.rb                     # PORO for stat card metrics
app/serializers/incident_list_item_serializer.rb  # Serializes incidents → auto-generates TS type
app/serializers/severity_option_serializer.rb     # Serializes severity options → auto-generates TS type
app/frontend/modules/dashboard/hooks/             # useIncidentsTable — server-side filter navigation
app/frontend/modules/dashboard/components/        # Table, toolbar, pagination, stat cards + skeleton
app/frontend/types/serializers/                   # Auto-generated TS types (never edit manually)
app/frontend/modules/dashboard/types.ts           # Manual TS types (Pagination, DashboardFilters, DashboardStat)
```

### Dispatchers

Route to handlers using lookup tables. Fall back to `UnknownHandler`.

- `CommandDispatcher` — routes on `command.command_name` + `command.subcommand`
- `InteractionDispatcher` — routes on `interaction.type` + `callback_id`/`action_id`

### Handlers

Class methods with `self.execute(command)` or `self.execute(interaction)`. Stateless. Return response hashes or nil.

Handlers are thin — only guards, routing, and delegation:
- Guard clauses (`return ephemeral("...") unless command.workspace`)
- Route to the right service or adapter method
- Return the response hash

Never put in a handler: DB queries beyond `command.workspace` / `command.incident`, business logic, platform-specific formatting (Block Kit, Slack mrkdwn), or response building. That belongs in services (business logic) or the adapter (platform-specific output).

`command.workspace` and `command.incident` are memoized on `Command` — call them directly, no local variable needed.

Handlers decide whether to dispatch sync or enqueue a job — see [When to enqueue from a handler](#when-to-enqueue-from-a-handler). The controller never decides; it always calls the handler the same way.

### Normalizers

Platform-specific payloads are normalized into platform-agnostic POJOs at the boundary (controllers/jobs) before reaching dispatchers and handlers.

- `Slack::CommandAdapter.parse(payload)` → `Command` (ActiveModel with validations) — called in `CommandsController`
- `Slack::InteractionNormalizer.call(payload)` → `Interaction` (plain PORO with attr_readers) — called in `InteractionsController`

Dispatchers and handlers only receive normalized objects — never raw payloads. Handlers access normalized fields (`interaction.user_id`, `command.trigger_id`).

### Services

Encapsulate business logic. Each method is independently callable (from workflows, console, or controllers). Use adapters for platform operations.

- `IncidentLifecycleService` — **shared write operations for all entry points** (create, update, close, reopen, assign lead). Both Slack handlers and API controller call this. See [IncidentLifecycleService](#incidentlifecycleservice) above.
- `IncidentCreationService` — incident creation flow details (channel, metadata, announcements). Called by `IncidentCreationWorkflow`.
- `WorkspaceSetupService` — workspace setup flow

Pattern:
```ruby
adapter = WorkspaceAdapter.for(workspace)
adapter.create_channel(name: ..., is_private: ...)
```

**Why services exist here — platform-agnostic coordination:**
Services are not a generic "service layer." They exist because Firefight bridges to external platforms (Slack now, Teams later). The business logic (record event, start workflow, set metadata) is identical regardless of platform, but the operations (create channel, post announcement) are platform-specific. Services own the shared "what happens," adapters own the platform-specific "how." Without multi-platform coordination, most services could live on models.

**When to use a service vs. model methods:**
- **Service** — orchestrates across platform boundaries or multiple systems: model writes + workflow starts, cache expiry, channel archival, job scheduling (e.g., `IncidentLifecycleService#close` updates the incident, expires transcript cache, starts a workflow, and schedules channel archival)
- **Model** — manages its own state and records its own events. If the logic is just "update my fields and record the change," it belongs on the model or a concern (e.g., `Postmortem#update_content!` wraps `record_change!` + `update!` — no service needed)

Don't create a service class that wraps a single model call. That's unnecessary indirection, not architecture.

### Serializers

`oj_serializers` serialize data for Inertia props (and eventually API responses). `types_from_serializers` auto-generates TypeScript interfaces from serializer definitions — no manual type maintenance.

```
app/serializers/
  base_serializer.rb              # Oj::Serializer + TypesFromSerializers::DSL, transform_keys :camelize
  incident_list_item_serializer.rb  # Incident → dashboard list view
  severity_compact_serializer.rb    # IncidentSeverity → {name, rank}
  status_compact_serializer.rb      # IncidentStatus → {name, lifecycleStage}
  severity_option_serializer.rb     # IncidentSeverity → {name, slug}
```

**Generated TypeScript** lives in `app/frontend/types/serializers/` — auto-generated, never edit manually. Regenerate with `bundle exec rake types_from_serializers:generate`. In development, types regenerate automatically on serializer file changes.

**Usage in controllers:**
```ruby
IncidentListItemSerializer.many(incidents)   # Array of hashes
SeverityOptionSerializer.many(severities)    # Array of hashes
```

**Adding a new serializer:**
1. Create `app/serializers/foo_serializer.rb` extending `BaseSerializer`
2. Use `attributes(name: {type: :string})` for pass-through fields with explicit types, or `type :string` + method definition for computed fields
3. Use `has_one`/`has_many` with `serializer:` for nested objects
4. Run `bundle exec rake types_from_serializers:generate` (or let dev mode auto-regenerate)
5. Import the generated type from `@/types/serializers` in frontend code

**When to use serializers vs raw hashes:**
- Model-backed data flowing to the frontend → serializer (auto-generates TS types)
- Simple computed value objects (pagination metadata, filter echo) → raw hash + manual TS types in module `types.ts`

### Adapters

Platform abstraction layer. `WorkspaceAdapter.for(workspace)` is the factory — returns platform-specific adapter (e.g., `Slack::WorkspaceAdapter`). Always use the factory, never instantiate platform adapters directly.

Adapters have two levels of methods:
- **Low-level**: generic operations (`post_message`, `open_modal`, `pin_message`, `post_ephemeral`)
- **High-level**: intent-based operations that encapsulate UI building (`open_incident_creation_modal`, `open_home_modal`, `update_home_modal`, `post_incident_quick_actions`, `post_incident_announcement`)

Handlers and services call high-level adapter methods — never reference platform-specific builders (`Slack::ModalBuilder`, `Slack::IncidentMessageBuilder`) directly. UI building stays inside the adapter layer.

Adapters catch platform-specific errors and re-raise as `AdapterError` subclasses:
- `Slack::Client::TriggerExpiredError` → `AdapterError::TriggerExpired`
- `Slack::Client::ChannelExistsError` → `AdapterError::ChannelExists`

Services and handlers rescue `AdapterError` subclasses — never platform-specific errors.

Adapters return normalized hashes: `{ channel_id:, channel_name: }`, `{ message_ts: }`, `{ success: true }`.

**Platform boundary rule**: `Slack::Client` is only called from `Slack::WorkspaceAdapter`. No Slack-specific code outside `app/adapters/slack/`.

### Domain Events

`IncidentEvent` records are created via `incident.record_change!` or `incident.create_initial_update!` (defined in `Incident::Snapshots`). Both return the created `IncidentEvent`.

Domain event publication (`ProcessDomainEventJob`) belongs in the **service layer**, not in model callbacks. Models must not enqueue jobs.

### Workflows

Built on the SolidWorkflow engine (`engines/solid_workflow/`). Thin orchestrators that delegate all logic to services.

#### Step DSL

```ruby
class IncidentCreationWorkflow < Base
  step :create_slack_channel
  step :set_channel_metadata, depends_on: [:create_slack_channel]
  step :notify, retry_config: { max_attempts: 3, backoff: "fixed" }

  def create_slack_channel(workflow:, step:, input:)
    service(workflow).create_channel(workflow.subject)
  end

  def set_channel_metadata(workflow:, step:, input:)
    channel_id = input["create_slack_channel"]["channel_id"]
    service(workflow).set_channel_metadata(workflow.subject, channel_id)
  end
end
```

- `step :name, depends_on: [...]` — declares a step with dependency ordering
- `step :name, retry_config: { max_attempts:, backoff: }` — per-step retry override
- Steps without dependencies run in parallel automatically
- Step methods receive `workflow:` (AR record, access `workflow.subject` and `workflow.context`), `step:` (AR record), `input:` (hash of dependency outputs keyed by step name)
- Return value becomes the step's `output` hash

#### Execution

- `start!(subject, context: {})` — async via background jobs (`RunStepJob`)
- `start_inline!(subject, context: {})` — synchronous (tests/console)
- Subject is a polymorphic AR object the workflow operates on

#### Orchestration

After each step completes, the engine finds newly ready steps (all dependencies succeeded/skipped, `run_at` passed) and enqueues them. Optimistic locking on `updated_at` prevents double execution of the same step.

#### States

- **Step**: `pending → running → succeeded/failed/skipped/cancelled`
- **Workflow**: `pending → running → succeeded/failed/cancelled/paused`

#### Retry

- Default: 5 attempts, exponential backoff (`2^attempt` seconds, capped at 300s)
- Strategies: `exponential` (default), `linear` (`attempt * 30s`), `fixed` (configurable or 60s)
- Per-step override via `retry_config: { max_attempts:, backoff:, backoff_seconds: }`

#### Pause / Resume / Cancel

- `workflow.pause!(reason:, by:)` — running steps finish, no new steps enqueued
- `workflow.resume!(by:)` — resumes orchestration
- `workflow.cancel!(reason:, by:)` — permanent, cancels all pending/running steps

#### Recovery

`SweeperJob` handles crashes: resumes stuck workflows (idle >5min), resets orphaned running steps (idle >10min), fails timed-out workflows.

#### Event Timeline

Every state transition records a `SolidWorkflow::Event` (workflow-level and step-level). `workflow.timeline` returns the chronological audit trail.

#### Key Engine Files

```
engines/solid_workflow/
  lib/solid_workflow/base.rb              # DSL (step, start!, start_inline!)
  lib/solid_workflow.rb                   # Module config (queue, retries, thresholds)
  app/models/solid_workflow/workflow.rb   # Workflow AR model + concerns
  app/models/solid_workflow/step.rb       # Step AR model + concerns
  app/models/solid_workflow/event.rb      # Audit trail events
  app/jobs/solid_workflow/run_step_job.rb # Executes a single step
  app/jobs/solid_workflow/sweeper_job.rb  # Recovers stuck/orphaned steps
```

### Identifiers

All callback_ids, action_ids, and subcommand strings are centralized in the platform-agnostic `Identifiers` module (`app/models/identifiers.rb`). Never use magic strings. Reference as `Identifiers::INCIDENT_CREATION_MODAL`, `Identifiers::SUBCOMMAND_CLOSE`, etc.

### Public API

REST API at `/api/v1/` with Bearer token authentication via `ApiKey` model. API controllers inherit from `Api::V1::ApiController` (NOT from `Api::V1::BaseController` which does Slack signature verification).

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
app/controllers/api/v1/severities_controller.rb  # Read-only
app/controllers/api/v1/statuses_controller.rb    # Read-only
app/controllers/api/v1/incident_types_controller.rb # Read-only
app/models/api_key.rb                            # Token auth, permissions, caching
app/models/idempotency_key.rb                    # Deduplication
app/views/api/v1/                                # Jbuilder response templates
```

## Key Files

```
app/adapters/
  adapter_error.rb                    # Platform-agnostic error hierarchy
  workspace_adapter.rb                # Factory: WorkspaceAdapter.for(workspace)
  slack/
    client.rb                         # Slack API wrapper (Net::HTTP::Persistent pool, see http_pool)
    workspace_adapter.rb              # Slack adapter (low-level + high-level methods)
    interaction_normalizer.rb         # Raw payload → Interaction POJO
    command_adapter.rb                # Raw payload → Command POJO
    modal_builder.rb                  # Block Kit modal definitions (internal to adapter)
    incident_message_builder.rb       # Incident Block Kit messages (internal to adapter)

app/models/
  command.rb                          # Platform-agnostic command (ActiveModel)
  interaction.rb                      # Platform-agnostic interaction (PORO, has platform attr)
  identifiers.rb                      # Platform-agnostic callback_ids/action_ids
  incident.rb                         # AR model with concerns (Sequencing, ChannelNaming, etc.)

app/serializers/
  base_serializer.rb                  # Oj::Serializer base with camelCase keys + TS generation
  incident_list_item_serializer.rb    # Incident → dashboard list props (auto-generates TS)
  severity_compact_serializer.rb      # IncidentSeverity → {name, rank}
  status_compact_serializer.rb        # IncidentStatus → {name, lifecycleStage}
  severity_option_serializer.rb       # IncidentSeverity → {name, slug}

app/services/
  incident_lifecycle_service.rb       # Shared write operations (create, update, close, reopen, lead)
  incident_invite_service.rb          # Resolve targets + invite + notify (used by InviteHandler + IncidentInviteJob)
  command_dispatcher.rb               # Routes commands → handlers
  interaction_dispatcher.rb           # Routes interactions → handlers
  incident_creation_service.rb        # Incident creation details (channel, metadata, announcements)
  workspace_setup_service.rb          # Workspace setup business logic
  workspace_member_provisioner.rb     # Lazy provisions WorkspaceMembership from a Slack user_id

app/jobs/
  incident_invite_job.rb              # Async resolve+invite for InviteHandler (paginated users.list path)

app/views/shared/
  _incident.json.jbuilder             # Shared incident serialization (used by API + webhooks)
  _actor.json.jbuilder                # Shared actor serialization (used by API + webhooks)

app/workflows/
  base.rb                             # Workflow engine with step DSL
  incident_creation_workflow.rb       # Thin delegates to IncidentCreationService
  slack_workspace_setup_workflow.rb   # Thin delegates to WorkspaceSetupService
```

## Frontend Architecture

### Stack

React 19 + TypeScript + Inertia.js (server-driven routing) + Vite + Tailwind CSS 4. UI primitives from shadcn/ui (Radix-based). Icons from `@tabler/icons-react`. Rich text editing with Tiptap.

### Directory Structure

```
app/frontend/
  components/              # Shared reusable components
    layout/                # App shell (authenticated-layout, theme-toggle)
    navigation/            # Sidebar, nav items, site header
    ui/                    # shadcn/ui primitives — NEVER modify directly
  modules/                 # Feature-specific code
    dashboard/
      components/          # UI components (incidents-table, stat-cards, toolbar, pagination)
      hooks/               # Feature hooks (use-incidents-table)
      lib/                 # Helpers, constants, columns, mock data
      types.ts             # Feature-specific types
    incidents/
      components/          # incident-header, incident-timeline, incident-actions, etc.
      types.ts             # Incident, IncidentListItem, IncidentAction, TimelineEvent
    settings/
      components/          # Tab components (roles-tab, webhooks-tab, api-keys-tab, etc.)
      types.ts             # Settings-specific types
    catalogue/
      components/          # type-card, entry-table, entry-detail-sheet, form dialogs
      lib/                 # icon-map, mock-data, constants
      types.ts             # CatalogType, AttributeDefinition, CatalogEntry
    auth/
      components/          # slack-auth-button
  pages/                   # Thin routing shells ONLY — no business logic
    dashboard/index.tsx
    incidents/show.tsx
    incidents/postmortem.tsx
    settings/index.tsx
    catalogue/index.tsx
    catalogue/show.tsx
    auth/login.tsx
  types/                   # Shared app-level types (SharedProps, User, Workspace)
  hooks/                   # Shared hooks (use-mobile)
  lib/                     # Shared utilities (routes, utils)
  entrypoints/             # Vite entrypoints (inertia.tsx, application.css)
```

### Rules

**Pages are thin routing shells:**
- Pages compose module components, receive props via `usePage<>()`, and set `<Head>` title
- No business logic, no mock data defaults, no complex markup in pages
- Mock data fallbacks use `??` at the page level, never default props inside components

**Module isolation:**
- Feature-specific code lives in `modules/<feature>/`
- Each module owns its `components/`, `hooks/`, `lib/`, and `types.ts`
- No cross-module imports between features (dashboard must not import from settings)
- Shared domain types (e.g., `IncidentListItem`) live in the owning module's `types.ts` and are imported directly

**shadcn/ui components are untouched:**
- Never modify files in `components/ui/` — they may be updated by `npx shadcn` later
- Wrap or compose shadcn components if you need custom behavior
- ESLint ignores `components/ui/` for this reason
- Prefer shadcn/ui components when one exists for your use case; write a custom component only if shadcn doesn't have it

**Type discipline:**
- No `Record<string, string>` when a tighter type exists — use typed keys from const arrays
- Flexible schemas (catalogue attributes) key by stable `key`/`slug`, never by mutable display `name`
- Attribute keys are immutable once set — auto-generate from name only for new attributes (empty key), never overwrite existing keys during edit
- Reference fields store entry IDs, not display labels — resolve at render time via `resolveReference()` or equivalent
- Use `Pick<>` from shared types instead of redefining inline shapes
- Page props are typed via `usePage<InterfaceName>()`

**Dependency direction:**
- Pages import from modules — never the reverse
- Module components receive data as props — never import mock data or lookup functions directly
- Lookup helpers (e.g., `getTypeById`, `resolveReference`) are acceptable in leaf display components but all available options (e.g., list of types for a dropdown) must be passed as props from the page level
- Search/filter logic in components should resolve references before matching (users search by display name, not stored IDs)

**Data flow:**
- Controllers send typed Inertia props → pages receive via `usePage<>()` → pass to module components
- Components receive data as required props — no internal mock fallbacks
- Mock data lives in `modules/<feature>/lib/mock-data.ts` and is only imported at the page level
- Lookup/resolver functions (e.g., `resolveReference()`) are called at render time, not stored in data

**Component patterns:**
- Dynamic icon selection uses a `<ComponentName>` component, not a function returning a component (React compiler requirement)
- `useCallback` for functions passed to memoized children or returned from hooks
- `useMemo` for derived/filtered data
- Impure functions (`Date.now()`) captured in `useMemo` with eslint-disable comment if needed

**Naming conventions:**
- Components: `PascalCase` (`IncidentsTable`, `StatCards`)
- Files: `kebab-case` (`incidents-table.tsx`, `stat-cards.tsx`)
- Types: `PascalCase` (`IncidentListItem`, `DashboardStat`)
- Constants: `UPPER_SNAKE_CASE` (`SEVERITY_OPTIONS`, `STATUS_LABELS`)
- Hooks: `camelCase` with `use` prefix (`useIncidentsTable`)
- Module directories: `kebab-case` (`dashboard`, `incidents`, `catalogue`)

**Navigation:**
- Sidebar sections: "Respond" (Incidents), "Configure" (Catalogue, Integrations, Settings)
- Active page determined by URL match
- Inertia `<Link>` for SPA navigation, `<a>` only for external links
- Route helpers from generated `@/lib/routes` (e.g., `dashboardPath()`, `incidentPath(id)`)

### Tooling

- `npm run typecheck` — TypeScript strict check (`tsc --noEmit`)
- `npm run lint` — ESLint with TypeScript + React Hooks plugins
- `npm run lint:fix` — auto-fix lint issues
- Both must pass clean before any PR
- ESLint config: `eslint.config.js` (flat config, ignores `components/ui/` and generated routes)

### Theme

Dark navy theme with cyan primary accent. Colors defined as CSS custom properties in `application.css` using oklch. Both light and dark themes supported via `.dark` class toggle.

- Background hue: 255 (navy blue tint, not pure gray)
- Primary: hue 195 (cyan/teal)
- Chroma on dark backgrounds: 0.035 (visibly blue, not grayish)

## Testing

- Framework: Minitest + Mocha (mocking)
- Tests run in parallel (14 processes)
- **Never use `Model.last`** in tests — unreliable with parallel execution. Use `find_by!` with specific attributes or scoped queries like `@incident.incident_events.find_by!(event_type: ...)`
- Fixtures require complete FK loading — declare all dependencies up the chain. `incidents` needs `:workspaces, :users, :workspace_memberships, :incident_statuses, :incident_severities, :incident_lifecycle_stages`. Missing fixtures cause random FK violations under parallel execution.
- Slack API stubs: `test/support/slack_client_stub_helper.rb` provides `stub_create_channel`, `stub_post_message`, `stub_successful_slack_workflow`, etc.
- Mocha auto-unstubs after each test — thread-safe isolation
- Handler tests build `Interaction.new(platform: Platforms::SLACK, ...)` or `Command` objects directly — never raw hashes
- Workflow tests use `start_inline!` for synchronous execution
- Use `Interaction::VIEW_SUBMISSION`, `Interaction::BLOCK_ACTIONS`, etc. — never raw type strings
- Use `Identifiers::INCIDENT_CREATION_MODAL`, etc. — never `Slack::Identifiers::`
