# Database Schema Improvements Plan

Analysis of the Firefight PostgreSQL schema against best practices.

## 1. UUIDs: v4 Fragmentation Risk

All application tables use `gen_random_uuid()` (UUIDv4). This is fully random, which causes B-tree index page splits and poor cache locality as tables grow.

**Impact**: Low right now, but `incident_events`, `workflow_steps`, and `workflow_events` are append-heavy tables that will feel this first. UUIDv7 is time-ordered, giving you the external-ID benefits of UUIDs with sequential insert performance.

**Recommendation**: Switch new tables to `uuidv7()` (Postgres 17+ native, or via `pgcrypto`/`pg_uuidv7` extension). Existing tables can stay on v4 — migration isn't worth the effort until you hit scale issues.

## 2. Missing FK Indexes

Postgres does **not** auto-index foreign keys. Two FK columns lack indexes:

| Table | Column | FK Target |
|---|---|---|
| `incident_actions` | `created_by_id` | `workspace_memberships` |
| `incident_role_assignments` | `assigned_by_id` | `workspace_memberships` |

Even if you rarely query "all actions by person X", Postgres must scan these columns when checking FK constraints on `workspace_membership` deletes/updates. Without indexes, that's a sequential scan.

```ruby
add_index :incident_actions, :created_by_id
add_index :incident_role_assignments, :assigned_by_id
```

## 3. Redundant Indexes

A composite index on `(A, B)` satisfies queries on `A` alone, making a standalone `A` index redundant. These standalone indexes add write overhead and storage for zero benefit:

| Redundant Index | Covered By |
|---|---|
| `incident_events` on `(incident_id)` | `(incident_id, created_at)` |
| `incident_roles` on `(workspace_id)` | `(workspace_id, position)`, `(workspace_id, slug)` |
| `incident_severities` on `(workspace_id)` | `(workspace_id, position)`, `(workspace_id, rank)`, `(workspace_id, slug)` |
| `incident_statuses` on `(workspace_id)` | `(workspace_id, category)`, `(workspace_id, slug)`, etc. |
| `incidents` on `(workspace_id)` | `(workspace_id, deleted_at)`, `(workspace_id, identifier)`, etc. |
| `workflow_events` on `(workflow_id)` | `(workflow_id, created_at)` |
| `workflow_steps` on `(workflow_id)` | `(workflow_id, name)`, `(workflow_id, status)` |
| `workflow_steps` on `(status)` | `(status, updated_at)` |
| `workflows` on `(state)` | `(state, updated_at)` |

Dropping these saves ~9 indexes worth of write amplification.

```ruby
remove_index :incident_events, :incident_id
remove_index :incident_roles, :workspace_id
remove_index :incident_severities, :workspace_id
remove_index :incident_statuses, :workspace_id
remove_index :incidents, :workspace_id
remove_index :workflow_events, :workflow_id
remove_index :workflow_steps, :workflow_id
remove_index :workflow_steps, :status
remove_index :workflows, :state
```

## 4. Missing Index: `incidents.channel_id`

The `in_channel` scope does `where(channel_id: ...)` — this is likely called on every inbound Slack event for a channel. No index exists. With many incidents, this becomes a sequential scan.

```ruby
add_index :incidents, :channel_id
```

## 5. Soft Delete Indexes Could Be Partial

Several tables have standalone `deleted_at` indexes (`incident_actions`, `incident_roles`, `incident_severities`, `incident_statuses`). Since the vast majority of rows will have `deleted_at IS NULL`, a **partial index** is more efficient:

```ruby
# Instead of: add_index :incident_actions, :deleted_at
# Use:
add_index :incident_actions, :id, where: "deleted_at IS NULL", name: "index_incident_actions_active"
```

The `incidents` table already handles this better with the composite `(workspace_id, deleted_at)` index. The other tables' standalone `deleted_at` indexes are low-value — you're rarely querying "all deleted records globally."

## 6. No DB-Level CHECK Constraints on Enum-like Columns

Multiple string columns act as enums validated only at the Rails model level:

- `incident_actions.action_type` — "action", "followup"
- `incident_actions.status` — "open", "in_progress", "done"
- `incident_statuses.category` — "live", "closed"
- `workspace_memberships.role` — "member", "admin", "owner"
- `workflows.state` — "pending", "running", "paused", "succeeded", "failed", "cancelled"
- `workflow_steps.status` — "pending", "running", "succeeded", "failed", "skipped", "cancelled"

Anyone with console/SQL access can insert invalid values. CHECK constraints provide defense-in-depth:

```ruby
add_check_constraint :incident_actions, "status IN ('open', 'in_progress', 'done')", name: "incident_actions_status_check"
add_check_constraint :incident_actions, "action_type IN ('action', 'followup')", name: "incident_actions_action_type_check"
add_check_constraint :incident_statuses, "category IN ('live', 'closed')", name: "incident_statuses_category_check"
add_check_constraint :workspace_memberships, "role IN ('member', 'admin', 'owner')", name: "workspace_memberships_role_check"
add_check_constraint :workflows, "state IN ('pending', 'running', 'paused', 'succeeded', 'failed', 'cancelled')", name: "workflows_state_check"
add_check_constraint :workflow_steps, "status IN ('pending', 'running', 'succeeded', 'failed', 'skipped', 'cancelled')", name: "workflow_steps_status_check"
```

## 7. `is_default` Uniqueness Gap

`incident_severities` and `incident_statuses` both have `is_default` with a Rails-level uniqueness validation scoped to workspace. The DB index is `(workspace_id, is_default)` but **not unique**. Concurrent requests could create two defaults for the same workspace. A partial unique index enforces this at the DB level:

```ruby
add_index :incident_severities, :workspace_id,
  unique: true,
  where: "is_default = true AND deleted_at IS NULL",
  name: "index_incident_severities_one_default_per_workspace"

add_index :incident_statuses, :workspace_id,
  unique: true,
  where: "is_default = true AND deleted_at IS NULL",
  name: "index_incident_statuses_one_default_per_workspace"
```

## 8. Database Configuration Note

**Good**: Production uses separate databases for cache, queue, and cable — proper isolation.

**Note**: Staging shares a single database for all four. If staging load-tests ever become a thing, queue/cable traffic could compete with primary connections.

## 9. What's Done Well

- **FK constraints everywhere** — strong referential integrity, including cross-references like `declared_by_id`, `assigned_by_id`
- **No `default_scope`** — soft delete filtering is explicit (`.active`), avoiding the common Rails foot-gun
- **Composite unique indexes** match business rules: `(workspace_id, identifier)`, `(workspace_id, slug)`, `(workspace_id, sequence_number)`, `(platform, platform_id)`
- **GIN index on `incident_events.metadata`** — correct choice for JSONB queries
- **`incident_events` has no `updated_at`** — append-only by design, no wasted writes
- **`restrict_with_error`** on severity/status — prevents orphan incidents
- **Row-level locking** for sequence number generation — correct approach for concurrent incident creation
- **Encrypted tokens** with non-deterministic encryption — good security

## Priority Summary

| Priority | Item | Effort |
|---|---|---|
| **High** | Add index on `incidents.channel_id` (Section 4) | 1 migration |
| **High** | Index missing FK columns `created_by_id` and `assigned_by_id` (Section 2) | 1 migration |
| **Medium** | Drop ~9 redundant indexes (Section 3) | 1 migration |
| **Medium** | Partial unique index for `is_default` on severities/statuses (Section 7) | 1 migration |
| **Low** | Replace soft delete indexes with partial indexes (Section 5) | 1 migration |
| **Low** | Add CHECK constraints on enum-like columns (Section 6) | 1 migration |
| **Future** | Switch to UUIDv7 for new tables (Section 1) | Config change |
