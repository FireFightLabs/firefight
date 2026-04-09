# Code Review Plan

> Systematic feature-by-feature review of the entire codebase before building the Ability Gateway.
> Reference findings: `docs/CODEBASE_AUDIT.md`

---

## Why feature-by-feature, not entry-point-by-entry-point

Reviewing by entry point (Slack → API → Dashboard) means reviewing the same logic three times in different contexts and losing the "is this consistent" check. Reviewing by feature gives you the full vertical slice — migration → model → service → all entry points → frontend → tests — and forces verification of the architectural rule: **services are the single source of truth for writes**.

Each review session has a clear definition of done: "this feature is reviewed."

---

## Layer checklist (apply to every feature)

For each feature, walk through the stack in this order:

### 1. Database + Model
- [ ] Migration: NOT NULL where expected, FKs present, indexes on query paths, CHECK constraints on enum-like strings
- [ ] Associations: correct `dependent:` (history tables → `:restrict_with_error`)
- [ ] Validations: match DB constraints, format, uniqueness scoped correctly to workspace
- [ ] Scopes: `active` (soft delete), workspace scoping helpers, eager loading scopes
- [ ] Callbacks: no business logic, no job enqueuing — only state management
- [ ] Concerns: well-organized, no leakage of responsibilities

### 2. Service
- [ ] Is there a service? If not, should there be (cross-platform orchestration)?
- [ ] Is it the **single write path**? All entry points go through it?
- [ ] Transaction safety: writes wrapped in `transaction` block
- [ ] Idempotency: can be called twice safely or uses idempotency key
- [ ] Takes platform-agnostic inputs (WorkspaceMembership, not platform_user_id)
- [ ] Records domain events via `record_change!` / `create_initial_update!`

### 3. Workflow (if applicable)
- [ ] Thin orchestrator, delegates to services
- [ ] Message-posting steps use `checkpointed()` — no duplicate sends on retry
- [ ] Dependencies declared correctly (parallel where possible)
- [ ] Retry config set per step where needed
- [ ] Guards for missing prerequisites (e.g., `return unless incident.channel_id`)

### 4. Entry Points (verify consistency)
- [ ] **Slack handler**: Thin, normalizes input, calls service, returns platform response
- [ ] **API controller**: Thin, auth + authorize, calls service, renders Jbuilder
- [ ] **Inertia controller**: Thin, chains scopes + serializers, renders props
- [ ] **All three call the SAME service method** with equivalent arguments
- [ ] No duplicated logic across entry points
- [ ] No `to_unsafe_h` — use strong params

### 5. Serializer + Types
- [ ] Serializer uses `BaseSerializer`, camelCase keys
- [ ] Types regenerate cleanly (`rake types_from_serializers:generate`)
- [ ] No `Record<string, unknown>` where tighter types exist
- [ ] No N+1 — all accessed associations preloaded via `with_list_associations` / `with_detail_associations`

### 6. Frontend
- [ ] Pages are thin routing shells
- [ ] Feature code in `modules/<feature>/` — components, hooks, lib, types
- [ ] No cross-module imports between features
- [ ] Mock data only at page level, never in components
- [ ] shadcn/ui components in `components/ui/` unmodified
- [ ] Hooks follow React patterns (useMemo, useCallback)
- [ ] Dead UI removed or wired up

### 7. Tests
- [ ] Model test with validations, scopes, key methods
- [ ] Service test with happy path, error paths, edge cases
- [ ] Workflow test using `start_inline!`
- [ ] Handler test with `Interaction`/`Command` objects
- [ ] API controller test covering auth, validation, pagination
- [ ] Inertia controller test covering prop shape
- [ ] No `Model.last` in tests
- [ ] Fixtures complete for parallel execution

---

## Feature Review Order

Start with simple CRUD features to get the review rhythm, then move to complex features where consistency matters most.

---

### Pass 1: Simple CRUD Features

Goal: establish the review rhythm, catch duplicated patterns across similar controllers.

#### 1. Severities

**Models:** `incident_severity.rb`, `incident_lifecycle_stage.rb`

**Services:** (none — pure CRUD)

**Controllers:** `incident_severities_controller.rb`, `api/v1/severities_controller.rb`

**Frontend:** `modules/settings/components/severities-tab.tsx` (and related)

**Serializers:** `severity_compact_serializer.rb`, `severity_option_serializer.rb`

**Focus areas:**
- Controller business logic (slug generation, position) — audit issue 2.2
- API read-only authorization
- Rank ordering consistency
- Default severity logic

---

#### 2. Statuses

**Models:** `incident_status.rb`, `incident_lifecycle_stage.rb`

**Controllers:** `incident_statuses_controller.rb`, `api/v1/statuses_controller.rb`

**Frontend:** `modules/settings/components/statuses-tab.tsx`

**Serializers:** `status_compact_serializer.rb`

**Focus areas:**
- Same controller issues as severities — look for duplication
- Lifecycle stage mapping correctness
- Status transition validation

---

#### 3. Incident Types

**Models:** `incident_type.rb`

**Controllers:** `incident_types_controller.rb`, `api/v1/incident_types_controller.rb`

**Frontend:** `modules/settings/components/types-tab.tsx`

**Focus areas:**
- Default type handling
- Soft deletion consistency
- Controller business logic (slug, position)

---

#### 4. Roles

**Models:** `incident_role.rb`, `incident_role_assignment.rb`

**Controllers:** `incident_roles_controller.rb`

**Frontend:** `modules/settings/components/roles-tab.tsx`

**Focus areas:**
- Role assignment validation (same workspace)
- Lead assignment flow consistency (tied to IncidentLifecycleService.assign_lead)
- Multiple role support (currently lead only)
- Dependent destroy on role_assignments — audit issue 1.1

**After Pass 1:** You should have a list of duplicated controller patterns and the shape of the fix. Extract any common helpers now before continuing.

---

### Pass 2: Dynamic Schema Features

Goal: review the custom fields and forms system — this is the most complex part of the settings area.

#### 5. Custom Fields (Field Definitions)

**Models:** `incident_field_definition.rb`, `incident_system_field.rb`

**Controllers:** `incident_field_definitions_controller.rb`

**Frontend:** `modules/settings/components/custom-fields-tab.tsx`

**Focus areas:**
- Field type enum validation
- Option source handling (static, dynamic, catalogue reference)
- Immutable key once set
- `to_unsafe_h` usage — audit issue 2.6
- Reference field resolution

---

#### 6. Forms + Form Fields + Conditions

**Models:** `incident_form.rb`, `incident_form_field.rb`, `incident_condition.rb`, `incident_condition_evaluator.rb`

**Controllers:** `incident_form_fields_controller.rb`

**Frontend:** `modules/settings/components/forms-tab.tsx` (and form builder)

**Focus areas:**
- Form lifecycle (declare/accept/update/resolve) mapping
- Conditional visibility evaluation
- Required modes (optional, required, fixed_required)
- Visibility modes
- Field ordering and position management
- **Form extraction logic** — audit issue 2.1 (duplicated across 4+ handlers)
- Nested resource authorization — audit issue

---

### Pass 3: Service Catalogue

#### 7. Catalogue

**Models:** `catalog_type.rb`, `catalog_attribute_definition.rb`, `catalog_entry.rb`, `catalog_entry_relationship.rb`

**Controllers:** `catalogue_controller.rb`

**Frontend:** `modules/catalogue/` (full module)

**Focus areas:**
- Attribute definition key immutability
- Entry attribute resolution (scalar vs relationships)
- Circular reference prevention in relationships
- Soft deletion consistency
- Serializer N+1 — audit issue 4.2
- `to_unsafe_h` usage

---

### Pass 4: Core Incident Lifecycle

Goal: the heaviest feature. By now you've seen the patterns enough to catch drift.

#### 8. Incidents — Core Lifecycle

**Models:**
- `incident.rb`
- `incident_update.rb`
- `incident_event.rb`
- `app/models/concerns/incident/*` (sequencing, snapshots, role_management, lifecycle, metrics, channel_naming, serialization)

**Service:** `incident_lifecycle_service.rb` — **THE critical service to review**

**Workflows:**
- `incident_creation_workflow.rb` — missing checkpoints, audit issue 1.2
- `incident_update_workflow.rb`
- `incident_close_workflow.rb`
- `incident_reopen_workflow.rb`
- `lead_assignment_workflow.rb`

**Entry points:**
- **Slack:** `incident_creation_handler.rb`, `incident_update_handler.rb`, `close_incident_handler.rb`, `reopen_incident_handler.rb`, `accept_incident_handler.rb`, `set_lead_handler.rb`
- **API:** `api/v1/incidents_controller.rb`
- **Dashboard:** `dashboard_controller.rb`, `incidents_controller.rb`

**Serializers:** `incident_list_item_serializer.rb`, `incident_detail_serializer.rb`

**Frontend:** `modules/dashboard/`, `modules/incidents/`

**Focus areas (this is the big one):**
- **Transaction safety** — audit issue 1.3, IncidentLifecycleService methods
- **Checkpoint coverage** — audit issue 1.2, IncidentCreationWorkflow
- **Dependent destroy** — audit issue 1.1, history tables
- **Soft deletion** — audit issue 1.4, no `scope :active` on Incident
- **workspace_id on audit tables** — audit issue 1.5
- **Snapshot completeness** — concerns/incident/snapshots.rb
- **Role management** — concerns/incident/role_management.rb
- **Lifecycle state machine** — concerns/incident/lifecycle.rb callbacks
- **Entry point consistency** — do Slack, API, and dashboard all call `IncidentLifecycleService` identically?
- **Dashboard filtering + pagination** — server-side correctness
- **Dead UI in incident header** — audit issue 3.8
- **Deferred data error handling** — audit issue 3.9

---

### Pass 5: Incident Extensions

#### 9. Postmortems

**Models:** `postmortem.rb`, `postmortem_update.rb`, `app/models/concerns/postmortem/*`

**Services:** postmortem generation (engines/firefight_ai/app/services/firefight_ai/postmortem_generator.rb)

**Handlers:** postmortem-related Slack handlers

**Frontend:** `modules/incidents/components/` — postmortem editor

**Focus areas:**
- Snapshot pattern on postmortem updates
- AI generation job error handling
- Revision history completeness
- HTML/markdown content handling
- Edit tracking (manual vs AI)

---

#### 10. Actions (Follow-ups)

**Models:** `incident_action.rb`, `incident_action_update.rb`, `app/models/concerns/incident_action/*`

**Handlers:** action creation, pick up, mark done

**Focus areas:**
- Action status transitions
- Assignee validation (same workspace)
- Snapshot pattern on action updates
- Dependent destroy — audit issue 1.1

---

#### 11. Incident Relationships

**Models:** `incident_relationship.rb`

**Handlers:** mark duplicate, merge into, relationship creation

**Focus areas:**
- Circular reference prevention
- Same-workspace validation
- Inverse relationship consistency
- Relationship type validation

---

### Pass 6: External Interfaces

#### 12. Webhooks (Outbound)

**Models:** `webhook.rb`, `webhook_delivery.rb`, `webhook_delinquency_tracker.rb`

**Services:** `webhooks/delivery_service.rb`, `webhooks/payload_renderer.rb`

**Events:** `app/events/webhooks/event_subscriber.rb`

**Controllers:** `webhooks_controller.rb`, `webhook_deliveries_controller.rb`

**Jobs:** `webhooks/dispatch_job.rb`, `webhooks/delivery_job.rb`

**Frontend:** `modules/settings/components/webhooks-tab.tsx`

**Focus areas:**
- HMAC signing correctness
- Retry logic and delinquency tracking
- Timeout handling
- Response size limits
- Payload template coverage for all events
- Event router completeness — audit issue 3.4

---

#### 13. API Keys + API v1

**Models:** `api_key.rb`, `idempotency_key.rb`

**Controllers:** `api/v1/api_controller.rb` (base), all `api/v1/*` controllers

**Concerns:** `app/controllers/concerns/api_authentication.rb`

**Frontend:** `modules/settings/components/api-keys-tab.tsx`

**Focus areas:**
- Bearer token auth + SHA256 digest
- Permission enforcement on every endpoint — audit issue
- Idempotency key flow
- Rate limiting
- Pagination `count` performance — audit issue 3.3
- Error response consistency
- `to_unsafe_h` in api_keys_controller — audit issue 2.6
- Raw error message exposure — audit issue 4.6

---

### Pass 7: Cross-Cutting

#### 14. Auth + Sessions

**Controllers:** `sessions_controller.rb`, `auth/omniauth_callbacks_controller.rb`

**Models:** `user.rb`, `workspace.rb`, `workspace_membership.rb`

**Services:** `workspace_setup_service.rb`, `workspace_member_provisioner.rb`

**Focus areas:**
- OAuth callback error handling — audit issue 4.3 (broad rescue)
- Workspace membership provisioning race conditions
- Session management
- Authorization checks on workspace access — audit issue

---

#### 15. Dashboard + Settings

**Controllers:** `dashboard_controller.rb`, `settings_controller.rb`, `inertia_controller.rb`

**Frontend:** `modules/dashboard/`, `modules/settings/`

**Focus areas:**
- Inertia shared data via serializers not `as_json` — audit issue 2.8
- Workspace authorization check — audit issue 2.6
- Settings page duplication — audit issue 4.5
- Dashboard server-side filter + pagination correctness

---

#### 16. Slack Platform Boundary

**Adapters:** `app/adapters/slack/*` (all files)

**Normalizers:** `slack/command_adapter.rb`, `slack/interaction_normalizer.rb`

**Dispatchers:** `command_dispatcher.rb`, `interaction_dispatcher.rb`, `event_dispatcher.rb`

**Focus areas:**
- Adapter abstraction cleanliness — no Slack-specific code outside adapter
- Error translation (Slack errors → AdapterError subclasses)
- Modal builder and message builder internal to adapter
- Dispatcher completeness — any missing routes
- Interaction normalizer coverage

---

#### 17. Workflow Engine

**Files:** `engines/solid_workflow/` (full engine)

**Focus areas (not feature code, engine code):**
- Step execution idempotency
- Retry logic correctness
- Sweeper reliability
- Orchestrator race conditions — audit issue 3.5
- Checkpoint idempotency — audit issue 3.6
- Optimistic locking correctness
- Event audit trail (state transitions)

**Note:** This is not a "fix everything now" pass — just identify issues to file for later. The engine is working; the improvements are optimization and edge cases.

---

## Review Output

For each feature review session, write findings to a single file: `docs/review/<feature-name>.md`

Template:

```markdown
# <Feature> Review

## Scope reviewed
- Models: ...
- Services: ...
- Entry points: ...
- Frontend: ...
- Tests: ...

## Issues found
### Critical
- Description + file:line

### High
- ...

### Medium
- ...

### Low
- ...

## Consistency check
- Slack and API and Dashboard call the same service: YES/NO
- Duplicated logic across entry points: ...

## Test coverage gaps
- ...

## Follow-ups
- ...
```

After each pass, update `docs/CODEBASE_AUDIT.md` with any new findings.

---

## Definition of Done

Before moving to Ability Gateway implementation:

- [ ] All 17 features reviewed
- [ ] Priority 1 issues from `CODEBASE_AUDIT.md` all fixed
- [ ] Priority 2 issues from `CODEBASE_AUDIT.md` all fixed (open source readiness)
- [ ] All `docs/review/<feature>.md` files complete
- [ ] `bin/ci` passes
- [ ] Test coverage on critical paths (incidents, API, webhooks)
- [ ] No TODO comments on critical security paths

---

## Time Estimate Per Feature

Not a schedule, just a rough sense of scale:

| Feature | Relative scope |
|---------|---------------|
| Severities, Statuses, Types, Roles | Small (similar patterns) |
| Custom Fields, Forms, Conditions | Medium (complex schema) |
| Catalogue | Medium |
| **Incidents core** | **Large (THE critical review)** |
| Postmortems, Actions, Relationships | Medium each |
| Webhooks | Medium |
| API v1 + API Keys | Medium |
| Auth, Dashboard, Settings | Medium each |
| Slack adapter | Medium |
| Workflow engine | Small (scan only) |

The incidents core review is the biggest. Budget accordingly.
