# Event Architecture

## Context

Handlers and services currently create `IncidentEvent` records synchronously inline — calling `incident_events.create!` or `record_change!` directly. This works for timeline recording but makes it impossible to add reactions (webhooks, search vectorization, automated workflows) without modifying every call site.

This document describes a two-phase architecture:
- **Phase 1:** Keep sync event recording as-is + add a domain event bus that fires async after each event is created. External subscribers (webhooks, workflows, AI) react to events without touching the recording logic.
- **Phase 2:** Evolve event storage to use delegated types (`IncidentUpdate`, `IncidentActionUpdate`) for structured queryable data. Event bus and publish sites are unchanged.

---

## Architecture

```
Handler/Service → IncidentEvent.create! (sync, in transaction)
                    → after_create_commit
                      → ProcessDomainEventJob (async, events queue)
                        → EventRouter dispatches to subscribers:
                            → WebhookSubscriber   → fires user-configured webhooks (future)
                            → SearchSubscriber    → vectorizes for search (future)
                            → AutomationSubscriber → triggers user-configured rules (future)
```

Timeline recording is **synchronous and transactional** — the `IncidentEvent` record is guaranteed to exist before the transaction commits. The event bus is a **notification mechanism** for external systems, not for timeline storage. If a job fails, the timeline is unaffected.

### Event Descriptions

Each event type has a static human-readable description. Used by webhooks and external consumers.

```ruby
# On IncidentEvent
EVENT_DESCRIPTIONS = {
  INCIDENT_CREATED => "Incident was created",
  INCIDENT_UPDATED => "Incident was updated",
  LEAD_ASSIGNED => "Incident lead was assigned",
  ACTION_CREATED => "Action item was created",
  ACTION_PICKED_UP => "Action item was picked up",
  ACTION_COMPLETED => "Action item was completed",
  INCIDENT_ESCALATED => "Incident was escalated",
  INCIDENT_RESOLVED => "Incident was resolved",
  INCIDENT_REOPENED => "Incident was reopened",
  POSTMORTEM_GENERATED => "Postmortem was generated"
}.freeze

def description
  EVENT_DESCRIPTIONS[event_type]
end
```

---

## Phase 1: Domain Event Bus

Timeline recording stays exactly as it is today. The event bus is added as a notification layer on top of `IncidentEvent`.

Zero schema changes. `IncidentEvent` table is unchanged.

### New Files

#### `app/events/domain_event.rb` — Value Object

Plain PORO (same pattern as `Interaction`). Holds `event_type`, `incident_id`, `user_id`, `data`, `metadata`, `occurred_at`. Has `to_h`/`from_h` for job serialization and lazy `incident`/`user` accessors for rehydrating AR objects in subscribers.

#### `app/events/event_router.rb` — Central Hub

Static `SUBSCRIBERS` hash mapping event type constants to arrays of subscriber classes. Iterates subscribers, calls `handle(event)`, logs + re-raises on failure.

No subscribers are registered in Phase 1 — the infrastructure is ready for Phase 2 and future subscribers.

#### `app/jobs/process_domain_event_job.rb` — Async Processing

Queue: `events` (existing, 3 threads, 0.1s polling). Deserializes hash to `DomainEvent`, calls `EventRouter.route`. Retries 5x with polynomial backoff. Discards on `RecordNotFound`.

### Modified Files

#### `app/models/incident_event.rb`

Add `after_create_commit` to publish to the event bus. The event is already persisted — the bus is purely for notifications.

```ruby
class IncidentEvent < ApplicationRecord
  after_create_commit :publish_to_event_bus

  private

  def publish_to_event_bus
    ProcessDomainEventJob.perform_later(
      "event_type" => event_type,
      "incident_id" => incident_id,
      "user_id" => user_id,
      "data" => metadata,
      "occurred_at" => created_at.iso8601(6)
    )
  end
end
```

#### `app/models/concerns/incident/snapshots.rb`

Add `message:` parameter to `record_change!`. No other changes — it still creates `IncidentEvent` directly.

```ruby
def record_change!(event_type, details: nil, changed_by: nil, message: nil)
  before_snapshot = snapshot
  yield
  after_snapshot = reload.snapshot
  changed_fields = before_snapshot.keys.select { |key| before_snapshot[key] != after_snapshot[key] }

  incident_events.create!(
    event_type: event_type,
    user: changed_by,
    metadata: {
      schema_version: 1,
      before: before_snapshot,
      after: after_snapshot,
      changed_fields: changed_fields,
      details: details,
      message: message
    }
  )
end
```

#### `app/services/interactions/incident_update_handler.rb`

Add `message: message` to `record_change!` call (line 20).

```ruby
incident.record_change!(IncidentEvent::INCIDENT_UPDATED, changed_by: member, message: message) do
```

#### `app/services/interactions/reopen_incident_handler.rb`

Add `message: reason` to `record_change!` call (line 14).

```ruby
incident.record_change!(IncidentEvent::INCIDENT_REOPENED, changed_by: member, message: reason, details: { reason: reason }) do
```

#### No changes to `IncidentCreationService` or `IncidentActionService`

These already create `IncidentEvent` records synchronously. The `after_create_commit` callback handles event bus publishing automatically.

### Handler Summary

| Handler | Change |
|---------|--------|
| `IncidentUpdateHandler` | Add `message: message` to `record_change!` call |
| `ReopenIncidentHandler` | Add `message: reason` to `record_change!` call |
| `CloseIncidentHandler` | No change |
| `SetLeadHandler` | No change |
| `SetLeadSelfHandler` | No change |
| `UpdateSummaryHandler` | No change |
| `IncidentCreationService` | No change |
| `IncidentActionService` | No change |

### Test Changes

**New test files:**
- `test/events/domain_event_test.rb` — serialization round-trip, lazy accessors
- `test/events/event_router_test.rb` — routes to subscriber, no-op for unknown types
- `test/jobs/process_domain_event_job_test.rb` — end-to-end: job -> router

**Modified tests:**
- Tests that assert `IncidentEvent` creation stay unchanged (sync creation is preserved)
- Handler tests for `IncidentUpdateHandler` and `ReopenIncidentHandler` may need minor updates for the new `message:` parameter

### Implementation Order

1. `DomainEvent` value object
2. `EventRouter` (empty subscribers for now)
3. `ProcessDomainEventJob`
4. Add `after_create_commit :publish_to_event_bus` to `IncidentEvent`
5. Add `message:` param to `record_change!` in Snapshots
6. Modify `IncidentUpdateHandler` — pass `message:`
7. Modify `ReopenIncidentHandler` — pass `message:`
8. New tests for event bus components
9. `bin/ci`

---

## Phase 2: Delegated Types

Evolve event storage to use structured detail tables instead of JSONB blobs. The event bus and all publish sites are **unchanged** — only the storage layer changes.

References: [37signals Delegated Type Pattern](https://dev.37signals.com/the-rails-delegated-type-pattern/), [Rails API docs](https://api.rubyonrails.org/classes/ActiveRecord/DelegatedType.html)

### Three-Layer Model

```
incidents               = mutable current state (fast reads, all columns)
incident_events         = universal timeline (ties all events together via delegated_type)
incident_updates        = append-only incident snapshots (same columns as incidents + update fields)
incident_action_updates = append-only action snapshots (same columns as incident_actions + update fields)
```

```
incident_events (unified timeline)
  |-- eventable: IncidentUpdate        -> incident_updates table
  |-- eventable: IncidentActionUpdate  -> incident_action_updates table
  |-- eventable: nil                   (future simple events)
```

### Schema

#### Modified table: `incident_events`

Add delegated type columns. Keep existing `metadata` column for backward compatibility.

```ruby
add_column :incident_events, :eventable_type, :string
add_column :incident_events, :eventable_id, :uuid
add_index :incident_events, [ :eventable_type, :eventable_id ]
```

#### New table: `incident_updates`

Each row is a complete snapshot of the incident at a point in time. Mirrors ALL `incidents` columns + additional fields.

```ruby
create_table :incident_updates, id: :uuid do |t|
  t.references :incident, type: :uuid, null: false, foreign_key: true

  # State snapshot (mirrors incidents table exactly)
  t.uuid :workspace_id, null: false
  t.references :declared_by, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships }
  t.references :incident_status, type: :uuid, null: false, foreign_key: true
  t.references :incident_severity, type: :uuid, null: false, foreign_key: true
  t.integer :sequence_number, null: false
  t.string :identifier, null: false
  t.string :name
  t.text :summary
  t.boolean :is_private, default: false, null: false
  t.string :channel_id
  t.string :channel_name
  t.string :initial_message_ts
  t.string :announcement_message_ts
  t.jsonb :platform_data, default: {}, null: false
  t.jsonb :custom_fields, default: {}, null: false
  t.datetime :declared_at, null: false
  t.datetime :resolved_at
  t.datetime :channel_archived_at
  t.string :channel_archived_by
  t.datetime :next_update_at
  t.datetime :deleted_at

  # Denormalized (not on incidents table, but needed for historical tracking)
  # incident_role_assignments are overwritten, not appended — without this, historical lead info is lost
  t.references :lead, type: :uuid, null: true, foreign_key: { to_table: :workspace_memberships }

  # Update-specific fields
  t.string :update_type, null: false
  t.references :created_by, type: :uuid, null: true, foreign_key: { to_table: :workspace_memberships }
  t.text :message
  t.jsonb :changed_fields, default: [], null: false

  t.timestamps
end

add_index :incident_updates, [ :incident_id, :created_at ]
add_index :incident_updates, :update_type
add_foreign_key :incident_updates, :workspaces
```

#### Expanded table: `incident_action_updates`

Each row is a complete snapshot of the action at a point in time, mirroring all `incident_actions` columns plus update-specific fields. This follows the same full-snapshot pattern as `incident_updates`.

```ruby
create_table :incident_action_updates, id: :uuid do |t|
  t.references :incident_action, type: :uuid, null: false, foreign_key: true
  t.references :incident, type: :uuid, null: false, foreign_key: true
  t.string :update_type, null: false        # "created", "picked_up", "completed"
  t.string :action_type, null: false        # "action" or "followup"
  t.references :actor, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships }

  # Snapshot columns (mirrors incident_actions)
  t.references :created_by, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships }
  t.references :assignee, type: :uuid, null: true, foreign_key: { to_table: :workspace_memberships }
  t.text :description, null: false
  t.string :status, null: false
  t.string :message_ts
  t.jsonb :platform_data, default: {}, null: false
  t.datetime :deleted_at

  # Change tracking
  t.jsonb :changed_fields, default: [], null: false

  t.timestamps
end
```

### Models

#### IncidentEvent (modified)

```ruby
class IncidentEvent < ApplicationRecord
  belongs_to :incident
  belongs_to :user, class_name: "WorkspaceMembership", optional: true

  delegated_type :eventable, types: %w[IncidentUpdate IncidentActionUpdate], optional: true

  scope :updates, -> { where(eventable_type: "IncidentUpdate") }
  scope :action_updates, -> { where(eventable_type: "IncidentActionUpdate") }
  scope :chronological, -> { order(created_at: :asc) }
  scope :recent, -> { order(created_at: :desc) }

  def changed_fields
    if eventable.is_a?(IncidentUpdate) || eventable.is_a?(IncidentActionUpdate)
      eventable.changed_fields || []
    else
      metadata["changed_fields"] || []
    end
  end

  def before_snapshot
    metadata["before"] || {}
  end

  def after_snapshot
    metadata["after"] || {}
  end

  def details
    metadata["details"]
  end

  def changed?(field)
    changed_fields.include?(field.to_s)
  end
end
```

#### IncidentUpdate (new)

```ruby
class IncidentUpdate < ApplicationRecord
  has_one :incident_event, as: :eventable, touch: true

  belongs_to :incident
  belongs_to :workspace
  belongs_to :incident_status
  belongs_to :incident_severity
  belongs_to :declared_by, class_name: "WorkspaceMembership"
  belongs_to :lead, class_name: "WorkspaceMembership", optional: true
  belongs_to :created_by, class_name: "WorkspaceMembership", optional: true

  CREATED = "created"
  UPDATED = "updated"
  CLOSED = "closed"
  REOPENED = "reopened"
  LEAD_ASSIGNED = "lead_assigned"

  UPDATE_TYPES = [ CREATED, UPDATED, CLOSED, REOPENED, LEAD_ASSIGNED ].freeze

  validates :update_type, presence: true, inclusion: { in: UPDATE_TYPES }

  scope :ordered, -> { order(:created_at) }
  scope :communications, -> { where.not(message: [ nil, "" ]) }
  scope :by_type, ->(type) { where(update_type: type) }
end
```

#### IncidentActionUpdate (expanded to full snapshot)

```ruby
class IncidentActionUpdate < ApplicationRecord
  has_one :incident_event, as: :eventable, touch: true

  belongs_to :incident_action
  belongs_to :incident
  belongs_to :actor, class_name: "WorkspaceMembership"
  belongs_to :created_by, class_name: "WorkspaceMembership"
  belongs_to :assignee, class_name: "WorkspaceMembership", optional: true

  CREATED = "created"
  PICKED_UP = "picked_up"
  COMPLETED = "completed"

  UPDATE_TYPES = [ CREATED, PICKED_UP, COMPLETED ].freeze

  validates :update_type, presence: true, inclusion: { in: UPDATE_TYPES }
  validates :action_type, presence: true, inclusion: { in: IncidentAction::ACTION_TYPES }
  validates :description, presence: true
  validates :status, presence: true, inclusion: { in: IncidentAction::STATUSES }

  scope :ordered, -> { order(:created_at) }
  scope :by_type, ->(type) { where(update_type: type) }
end
```

#### Incident (convenience methods)

```ruby
class Incident < ApplicationRecord
  has_many :incident_events, dependent: :destroy
  has_many :incident_updates, dependent: :destroy

  def last_update
    incident_updates.ordered.last
  end

  def last_communication
    incident_updates.communications.ordered.last
  end

  def update_history
    incident_updates.ordered
  end
end
```

#### IncidentAction (modified)

```ruby
class IncidentAction < ApplicationRecord
  include IncidentAction::Snapshots

  has_many :incident_action_updates, dependent: :destroy
end
```

### Core Implementation: Snapshot Concerns (Phase 2)

#### `IncidentAction::Snapshots` Concern

Mirrors `Incident::Snapshots` for action lifecycle events.

```ruby
module IncidentAction::Snapshots
  extend ActiveSupport::Concern

  UPDATE_TYPE_MAP = {
    IncidentEvent::ACTION_CREATED => IncidentActionUpdate::CREATED,
    IncidentEvent::ACTION_PICKED_UP => IncidentActionUpdate::PICKED_UP,
    IncidentEvent::ACTION_COMPLETED => IncidentActionUpdate::COMPLETED
  }.freeze

  def build_snapshot_attributes
    {
      incident_action: self, incident: incident, created_by: created_by,
      assignee: assignee, action_type: action_type, description: description,
      status: status, message_ts: message_ts, platform_data: platform_data,
      deleted_at: deleted_at
    }
  end

  def record_change!(event_type, actor:)
    before_tracked = trackable_snapshot
    yield
    reload
    after_tracked = trackable_snapshot
    changed_fields = before_tracked.keys.select { |key| before_tracked[key] != after_tracked[key] }

    update = IncidentActionUpdate.create!(
      **build_snapshot_attributes,
      update_type: UPDATE_TYPE_MAP.fetch(event_type),
      actor: actor,
      changed_fields: changed_fields.map(&:to_s)
    )

    incident.incident_events.create!(
      event_type: event_type, user: actor, eventable: update
    )
  end

  def create_initial_update!(actor:)
    update = IncidentActionUpdate.create!(
      **build_snapshot_attributes,
      update_type: IncidentActionUpdate::CREATED,
      actor: actor,
      changed_fields: []
    )

    incident.incident_events.create!(
      event_type: IncidentEvent::ACTION_CREATED,
      user: actor,
      eventable: update
    )
  end

  private

  def trackable_snapshot
    { assignee: assignee_id, status: status, description: description, deleted_at: deleted_at }
  end
end
```

#### `Incident::Snapshots` Concern

`record_change!` evolves to create both the `IncidentUpdate` snapshot and the `IncidentEvent` timeline entry with delegated type.

```ruby
module Incident::Snapshots
  extend ActiveSupport::Concern

  UPDATE_TYPE_MAP = {
    IncidentEvent::INCIDENT_CREATED => IncidentUpdate::CREATED,
    IncidentEvent::INCIDENT_UPDATED => IncidentUpdate::UPDATED,
    IncidentEvent::INCIDENT_RESOLVED => IncidentUpdate::CLOSED,
    IncidentEvent::INCIDENT_REOPENED => IncidentUpdate::REOPENED,
    IncidentEvent::LEAD_ASSIGNED => IncidentUpdate::LEAD_ASSIGNED
  }.freeze

  def build_snapshot_attributes
    {
      incident: self,
      workspace_id: workspace_id,
      incident_status: incident_status,
      incident_severity: incident_severity,
      declared_by: declared_by,
      lead: lead,
      sequence_number: sequence_number,
      identifier: identifier,
      name: name,
      summary: summary,
      is_private: is_private,
      channel_id: channel_id,
      channel_name: channel_name,
      initial_message_ts: initial_message_ts,
      announcement_message_ts: announcement_message_ts,
      platform_data: platform_data,
      custom_fields: custom_fields,
      declared_at: declared_at,
      resolved_at: resolved_at,
      channel_archived_at: channel_archived_at,
      channel_archived_by: channel_archived_by,
      next_update_at: next_update_at,
      deleted_at: deleted_at
    }
  end

  def record_change!(event_type, details: nil, changed_by: nil, message: nil)
    before_attrs = build_snapshot_attributes
    yield
    reload
    after_attrs = build_snapshot_attributes
    changed = before_attrs.keys.select { |key| before_attrs[key] != after_attrs[key] }

    update = IncidentUpdate.create!(
      **after_attrs,
      update_type: UPDATE_TYPE_MAP.fetch(event_type),
      created_by: changed_by,
      message: message,
      changed_fields: changed.map(&:to_s)
    )

    incident_events.create!(
      event_type: event_type,
      user: changed_by,
      eventable: update,
      metadata: details ? { details: details } : {}
    )
  end

  def create_initial_update!(created_by:)
    update = IncidentUpdate.create!(
      **build_snapshot_attributes,
      update_type: IncidentUpdate::CREATED,
      created_by: created_by,
      changed_fields: []
    )

    incident_events.create!(
      event_type: IncidentEvent::INCIDENT_CREATED,
      user: created_by,
      eventable: update
    )
  end
end
```

### How Changes Flow

#### Incident state change (status update with message)

```ruby
# Handler calls record_change!
incident.record_change!(IncidentEvent::INCIDENT_UPDATED, changed_by: member, message: "Root cause identified") do
  incident.update!(incident_status: new_status, incident_severity: new_severity)
end

# Inside record_change!:
# 1. Captures before snapshot (build_snapshot_attributes)
# 2. Yields to perform the change
# 3. Captures after snapshot (reload + build_snapshot_attributes)
# 4. Detects changed fields
# 5. Creates IncidentUpdate (full snapshot row, update_type: "updated", message stored)
# 6. Creates IncidentEvent (event_type: "incident.updated", eventable: incident_update)
# 7. after_create_commit fires ProcessDomainEventJob for external subscribers
```

#### Action created

```ruby
# IncidentActionService#create_action:
action = incident.incident_actions.create!(...)
action.create_initial_update!(actor: created_by)
# Inside create_initial_update!:
# 1. Creates IncidentActionUpdate (full snapshot, update_type: "created", empty changed_fields)
# 2. Creates IncidentEvent (event_type: "action.created", eventable: action_update)
# 3. after_create_commit fires ProcessDomainEventJob for external subscribers
```

#### Action picked up / completed

```ruby
# IncidentActionService#pick_up_action:
action.record_change!(IncidentEvent::ACTION_PICKED_UP, actor: picked_up_by) do
  action.update!(assignee: picked_up_by, status: IncidentAction::STATUS_IN_PROGRESS)
end
# Inside record_change!:
# 1. Captures before snapshot (trackable_snapshot)
# 2. Yields to perform the change
# 3. Captures after snapshot (reload + trackable_snapshot)
# 4. Detects changed fields (assignee, status)
# 5. Creates IncidentActionUpdate (full snapshot, update_type: "picked_up")
# 6. Creates IncidentEvent (event_type: "action.picked_up", eventable: action_update)
```

#### Timeline query

```ruby
# Full timeline (all event types)
incident.incident_events.chronological

# Only incident state changes
incident.incident_events.updates

# Only action updates
incident.incident_events.action_updates

# Eager load eventable for rendering
incident.incident_events.includes(:eventable).chronological
```

### What This Replaces

| Before | After |
|---|---|
| `incident_events.metadata` with JSONB before/after snapshots | `IncidentUpdate` rows with structured columns |
| `incident_events.metadata` with `{ action_id, action_type }` | `IncidentActionUpdate` rows with full snapshot columns |
| `Incident::Snapshots#snapshot` (JSONB hash) | `Incident::Snapshots#build_snapshot_attributes` (AR attributes) |
| `incident_status_transitions` table (proposed) | Derive from consecutive IncidentUpdate rows |

### Deriving Status Transitions

```ruby
incident.incident_updates.ordered.each_cons(2) do |prev, curr|
  if prev.incident_status_id != curr.incident_status_id
    duration = curr.created_at - prev.created_at
    # prev.incident_status -> curr.incident_status took `duration`
  end
end
```

### Deriving Milestone Timestamps

```ruby
# acknowledged_at = first update where status is in active stage
incident.incident_updates.joins(incident_status: :incident_lifecycle_stage)
  .where(incident_lifecycle_stages: { key: "active" })
  .ordered.first&.created_at

# mitigated_at = first update where status has sets_mitigated_at flag
incident.incident_updates.joins(:incident_status)
  .where(incident_statuses: { sets_mitigated_at: true })
  .ordered.first&.created_at
```

### Metrics Queries

```sql
-- MTTR
SELECT AVG(resolved_at - declared_at) FROM incidents WHERE resolved_at IS NOT NULL

-- MTTA
SELECT AVG(acknowledged_at - declared_at) FROM incidents WHERE acknowledged_at IS NOT NULL

-- Update cadence: average time between communications
SELECT incident_id, AVG(time_between_updates)
FROM (
  SELECT incident_id,
    created_at - LAG(created_at) OVER (PARTITION BY incident_id ORDER BY created_at) as time_between_updates
  FROM incident_updates
  WHERE message IS NOT NULL AND message != ''
) sub
GROUP BY incident_id
```

### Handler Changes

| Handler | Change |
|---------|--------|
| `IncidentUpdateHandler` | Add `message: message` to `record_change!` call |
| `ReopenIncidentHandler` | Add `message: reason` to `record_change!` call |
| `CloseIncidentHandler` | No change |
| `SetLeadHandler` | No change |
| `SetLeadSelfHandler` | No change |
| `UpdateSummaryHandler` | No change |
| `IncidentCreationService` | Rename `create_incident_event` to `create_initial_update!` on incident |
| `IncidentActionService` | Use `IncidentAction::Snapshots` concern (`create_initial_update!`, `record_change!`) |

### Future Delegated Types

As the system grows, add new eventable types to `incident_events`:

```ruby
delegated_type :eventable, types: %w[
  IncidentUpdate          # state changes + communications (now)
  IncidentActionUpdate    # action/followup lifecycle snapshots (now)
  IncidentRoleEvent       # role assigned/unassigned (future)
  IncidentTagEvent        # tag added/removed (future)
  IncidentRelationEvent   # incident linked/merged (future)
  IncidentBookmarkEvent   # message bookmarked (future)
]
```

Each new type gets its own table with type-specific columns. The timeline (`incident_events`) stays unified. Adding a new event type requires:
1. New table with type-specific columns
2. New model with `has_one :incident_event, as: :eventable`
3. Add the type string to `IncidentEvent.delegated_type`
4. Write to it from the handler/service

### Implementation Order

1. Migration: add `eventable_type`/`eventable_id` to `incident_events`
2. Migration: create `incident_updates` table
3. Migration: expand `incident_action_updates` to full snapshot
4. `IncidentUpdate` model
5. `IncidentActionUpdate` model (expanded)
6. `IncidentAction::Snapshots` concern
7. Modify `IncidentEvent` — delegated type, scopes, `changed_fields` delegation
8. Modify `Incident` — `has_many :incident_updates`, convenience methods
9. Modify `IncidentAction` — `include IncidentAction::Snapshots`
10. Rewrite `Incident::Snapshots` concern (`build_snapshot_attributes`, `record_change!`, `create_initial_update!`)
11. Modify `IncidentUpdateHandler` — pass `message:`
12. Modify `ReopenIncidentHandler` — pass `message:`
13. Refactor `IncidentCreationService` — use `create_initial_update!`
14. Refactor `IncidentActionService` — use `IncidentAction::Snapshots` concern
14. Add fixtures + new tests
15. Update existing tests
16. `bin/ci`

### Migration Path from Current Data

1. Create new tables and add delegated type columns
2. Update handlers and services to create delegated types
3. Backfill: create `IncidentUpdate`/`IncidentActionUpdate` rows from existing JSONB metadata (separate task)
4. Keep `metadata` column on `incident_events` for backward compatibility during transition

---

## Verification

### Phase 1

1. `bin/ci` passes (rubocop, brakeman, tests, system tests, seeds)
2. Create incident via Slack -> `IncidentEvent` created (sync) -> `ProcessDomainEventJob` enqueued
3. Update incident (status/severity/lead/summary) -> events recorded with message in metadata
4. Close/reopen incident -> events recorded, reopen includes reason as message
5. Create/pick-up/complete actions -> events recorded
6. Solid Queue dashboard shows domain event jobs on `events` queue
7. All `IncidentEvent` records have the same data shape as before (backward compat)
8. Existing tests pass without modification (sync creation preserved)

### Phase 2

1. `bin/ci` passes
2. Create incident -> `IncidentUpdate` with `update_type: "created"`, full snapshot
3. Update incident (status/severity + message) -> `IncidentUpdate` with message persisted
4. Close incident -> `IncidentUpdate` with `update_type: "closed"`
5. Reopen incident -> `IncidentUpdate` with `update_type: "reopened"`, reason as message
6. Assign lead -> `IncidentUpdate` with `lead_id` set, `update_type: "lead_assigned"`
7. Create action -> `IncidentActionUpdate` with `update_type: "created"`, full snapshot, `action_type: "action"`
8. Create followup -> `IncidentActionUpdate` with `action_type: "followup"`, full snapshot
9. Pick up action -> `IncidentActionUpdate` with `update_type: "picked_up"`, changed_fields: ["assignee", "status"]
10. Complete action -> `IncidentActionUpdate` with `update_type: "completed"`, changed_fields: ["status"]
11. `incident.incident_events.chronological` returns unified timeline
12. `incident.incident_events.updates` returns only IncidentUpdate events
13. `incident.incident_events.action_updates` returns only IncidentActionUpdate events
14. `event.eventable` returns the correct typed model
