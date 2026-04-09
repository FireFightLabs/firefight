# Codebase Audit

> Full audit performed April 2026 before building the Ability Gateway and open-sourcing.
> Three areas audited: database/models, services/workflows, frontend/controllers/API.

---

## Verdict

The architecture is solid — layer hierarchy, adapter pattern, event system, workflow engine, serializers, and Inertia patterns are well-designed. The issues are data integrity and consistency fixes, not rewrites.

**5 critical fixes** required before building the Ability Gateway. **5 high-priority fixes** required before open sourcing. The rest is ongoing improvement.

---

## Priority 1: Critical — Fix Before Ability Gateway

### 1.1 `dependent: :destroy` on audit tables

Deleting an incident destroys its entire event history, updates, and action history. Violates audit trail immutability.

| File | Association | Fix |
|------|------------|-----|
| `app/models/incident.rb` | `has_many :incident_events, dependent: :destroy` | → `:restrict_with_error` |
| `app/models/incident.rb` | `has_many :incident_updates, dependent: :destroy` | → `:restrict_with_error` |
| `app/models/incident.rb` | `has_many :incident_actions, dependent: :destroy` | → `:restrict_with_error` |
| `app/models/incident_action.rb` | `has_many :incident_action_updates, dependent: :destroy` | → `:restrict_with_error` |
| `app/models/postmortem.rb` | `has_many :postmortem_updates, dependent: :destroy` | → `:restrict_with_error` |

Incidents are soft-deleted — hard delete should never cascade through history.

### 1.2 IncidentCreationWorkflow missing checkpoints

Message-posting steps in `IncidentCreationWorkflow` don't use `checkpointed()`. If the workflow retries, messages post twice to Slack. All other workflows do this correctly — this one was missed.

**File:** `app/workflows/incident_creation_workflow.rb`

**Steps missing checkpoint:** `post_quick_actions_message`, `post_announcement`

### 1.3 IncidentLifecycleService missing transaction wrapping

State changes in `create`, `close`, `reopen`, `assign_lead` are not wrapped in database transactions. If the workflow start fails after the incident is updated, state is inconsistent. Concurrent `assign_lead` calls have last-write-wins without locking.

**File:** `app/services/incident_lifecycle_service.rb`

**Fix:** Wrap each lifecycle method in `ActiveRecord::Base.transaction { }`. Operations after `record_change!` (cache expiry, workflow start, job scheduling) happen outside any transaction.

### 1.4 Inconsistent soft deletion

Some models have `scope :active` filtering `deleted_at IS NULL`, others don't. The `Incident` model has no scope excluding deleted records. Queries may return deleted incidents.

**Fix:** Create a shared `SoftDeletable` concern with:
- `scope :active, -> { where(deleted_at: nil) }`
- `scope :deleted, -> { where.not(deleted_at: nil) }`
- `soft_delete!` method
- Applied to all 16 models with `deleted_at`
- No `default_scope` — use explicit `active` scope

### 1.5 Missing workspace_id on audit tables

`incident_events` and `incident_action_updates` have no `workspace_id` column. They rely on joining through `incident.workspace_id`. Makes workspace-scoped queries slower and isolation harder to enforce.

**Fix:** Add `workspace_id` FK to both tables. Populate from `incident.workspace_id` on creation. Add index on `(workspace_id, created_at)`.

---

## Priority 2: High — Fix Before Open Source

### 2.1 Business logic in handlers (duplicated form extraction)

Form value extraction logic is duplicated across 4+ handlers. Each has 40-60 lines of nearly identical Slack interaction parsing.

**Files:** `app/services/interactions/` — incident_creation_handler, close_incident_handler, incident_update_handler, reopen_incident_handler

**Fix:** Extract to shared services:
- `IncidentFormExtractor` — form values from interaction payloads
- `InteractionMetadataParser` — metadata from private_metadata
- `TemporaryMessageCleaner` — temp message deletion (duplicated in close + reopen)

### 2.2 Controller business logic

Several Inertia controllers contain slug generation, position calculation, and type casting that belongs in models.

**Files:** `app/controllers/incident_types_controller.rb`, `incident_severities_controller.rb`, `incident_statuses_controller.rb`, `incident_roles_controller.rb`

**Fix:** Move slug generation to model `before_validation`. Move position auto-increment to model. Use strong params with coercion.

### 2.3 Inconsistent job retry policies

Some jobs have explicit `retry_on`, others use defaults, others have commented-out retry logic. No consistent pattern across 10+ job classes.

**Fix:** Add explicit `retry_on` and `discard_on` to every job. All jobs: `discard_on ActiveJob::DeserializationError`.

### 2.4 Missing controller tests

Only 2 controller test files exist. No tests for dashboard, incidents, settings, or most API endpoints.

**Fix:** Add tests for dashboard (filtering, pagination), incidents (show, timeline), settings (CRUD), API v1 (auth, pagination, idempotency).

### 2.5 Missing model tests

11 models have no test coverage: command.rb, incident_form.rb, incident_system_field.rb, interaction.rb, platforms.rb, shoutout.rb, user.rb, workspace.rb, workspace_membership.rb, and others.

### 2.6 `to_unsafe_h` usage

Multiple controllers bypass strong parameter protection.

**Files:** `catalogue_controller.rb`, `incident_field_definitions_controller.rb`, `api_keys_controller.rb`

**Fix:** Replace with explicit strong params. For dynamic fields (catalogue attributes), permit known keys from type definition.

---

## Priority 3: Medium — Next Quarter

### 3.1 String enums without database constraints

20+ columns store enum values as strings without CHECK constraints. Data corruption possible via direct writes.

**Fix:** Add CHECK constraints for critical columns: `incident_events.event_type`, `incident_actions.status`, `webhook_deliveries.state`, `workspaces.platform`.

### 3.2 Missing indexes

| Table | Missing index |
|-------|--------------|
| `incident_action_updates` | `(status)` |
| `incident_action_updates` | `(incident_id, status)` composite |
| `incidents` | `(workspace_id, source)` composite |
| `incident_events` | `(user_id, created_at)` composite |

### 3.3 API pagination count performance

`scope.count` on every paginated request performs full table count. Expensive at scale.

**File:** `app/controllers/api/v1/api_controller.rb`

**Options:** `COUNT(*) OVER()` window function, cached counts, or `pg_class.reltuples` estimates.

### 3.4 Event router dead subscribers

Some event types have empty subscriber arrays. Events created but never processed. No logging.

**File:** `app/events/event_router.rb`

### 3.5 Workflow race conditions in step scheduling

`enqueue_next_steps()` can be called concurrently, potentially double-scheduling steps. Optimistic locking in `RunStepJob` mitigates double execution but not double enqueue.

**File:** `engines/solid_workflow/app/models/solid_workflow/workflow/orchestratable.rb`

**Fix:** Row-level lock (`FOR UPDATE SKIP LOCKED`) when fetching ready steps.

### 3.6 RunStepJob checkpoint idempotency

If a step fails between `execute!()` and status update, rerun re-executes. Side effects duplicate.

**Fix:** Add "execution started" marker in checkpoint before calling execute.

### 3.7 Missing workflow observability

No UI or API to see workflow progress, retry failed steps, or cancel stuck workflows.

**Fix:** API endpoint for workflow state, dashboard progress indicator, admin retry/cancel.

### 3.8 Dead UI in incident header

Dropdown menu items (Edit, Change Status, Assign Lead, Close) render but are non-functional placeholders.

**File:** `app/frontend/modules/incidents/components/incident-header.tsx`

### 3.9 Deferred data error handling

Timeline events use `<Deferred>` with no error boundary. Network failure shows skeleton indefinitely.

**File:** `app/frontend/pages/incidents/show.tsx`

---

## Priority 4: Low — Technical Debt

| Issue | Description |
|-------|------------|
| Missing validations | Multiple models lack presence validations matching NOT NULL constraints |
| N+1 in serializers | `IncidentDetailSerializer`, `CatalogEntrySerializer` access unpreloaded associations |
| Broad exception handling | `omniauth_callbacks_controller.rb` uses `rescue => e` |
| Inconsistent handler error handling | Some rescue, some return nil, some don't rescue |
| Settings page duplication | 8 settings pages with identical layout wrapping |
| Raw API error messages | Validation errors expose Rails internals |
| No event versioning | No mechanism for event schema changes over time |

---

## Schema Decision

**Keep everything in public schema.** The workspace_id FK scoping pattern is correct. PostgreSQL schemas add complexity (search_path, migrations, connection pools) without benefit at this scale.

Reconsider only if hard data isolation per workspace is required for compliance. Even then, row-level security is simpler than schema separation.

---

## Implementation Order

### Before Ability Gateway (1-2 weeks)

1. Change `dependent: :destroy` → `:restrict_with_error` on audit associations
2. Add `checkpointed()` to IncidentCreationWorkflow message steps
3. Wrap IncidentLifecycleService methods in transactions
4. Create `SoftDeletable` concern, apply to all 16 models with `deleted_at`
5. Add `workspace_id` to `incident_events` and `incident_action_updates` (migration + backfill)

### Before Open Source (2-3 weeks)

6. Extract form extraction to `IncidentFormExtractor`, `InteractionMetadataParser`, `TemporaryMessageCleaner`
7. Move slug/position logic from controllers to models
8. Add explicit retry policies to all jobs
9. Replace `to_unsafe_h` with strong params
10. Add controller and model tests for critical paths

### Ongoing

11. Database CHECK constraints for enums
12. Missing indexes
13. Workflow observability (API + UI)
14. Frontend fixes (dead UI, error boundaries)
15. Serializer N+1 fixes
16. Handler error handling standardization
