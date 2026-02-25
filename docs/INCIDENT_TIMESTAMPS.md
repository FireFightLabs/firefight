# Incident Timestamps & Milestones — Implementation Plan

## Context

Firefight only tracks `declared_at` and `resolved_at`. Competitors track multiple lifecycle timestamps for metrics (MTTR, MTTA, MTTD) and provide a full status transition history for timeline views.

Decision: Store timestamps at two levels:
1. **Status transitions table** — source of truth, records every status change with timing
2. **Fixed columns on incidents** — cached summaries, auto-set by Lifecycle concern for fast metrics queries

This is the same pattern already used for `resolved_at`.

---

## Schema

### New table: `incident_status_transitions`

Records every status change. Source of truth for timeline and per-status duration calculations.

```ruby
create_table :incident_status_transitions, id: :uuid do |t|
  t.references :incident, type: :uuid, null: false, foreign_key: true
  t.references :from_status, type: :uuid, null: true, foreign_key: { to_table: :incident_statuses }
  t.references :to_status, type: :uuid, null: false, foreign_key: { to_table: :incident_statuses }
  t.datetime :occurred_at, null: false
  t.references :transitioned_by, type: :uuid, null: true, foreign_key: { to_table: :workspace_memberships }
  t.timestamps
end

add_index :incident_status_transitions, [ :incident_id, :occurred_at ]
```

- `from_status` is NULL for the first transition (incident creation)
- `occurred_at` is when the transition happened (usually `Time.current`, but can be retroactively edited)
- `transitioned_by` is NULL for system-triggered transitions

### Modify table: `incidents`

Add cached milestone columns:

```ruby
add_column :incidents, :detected_at, :datetime, null: true
add_column :incidents, :acknowledged_at, :datetime, null: true
add_column :incidents, :mitigated_at, :datetime, null: true
```

Existing columns: `declared_at`, `resolved_at` (unchanged).

---

## Milestone Columns — What Each One Means

| Column | Question it answers | How it's set | Auto or manual? |
|---|---|---|---|
| `detected_at` | "When was the problem first noticed?" | User sets manually | **Manual** — represents a real-world event before incident creation (alert, customer report) |
| `declared_at` | "When was the incident created?" | Auto on creation | **Auto** (exists) |
| `acknowledged_at` | "When did someone confirm this is real?" | Auto: first transition into `active` stage | **Auto** — set once, not cleared on re-entry |
| `mitigated_at` | "When was impact contained?" | Auto: first transition into a status with `sets_mitigated_at` flag | **Auto** — set once, not cleared |
| `resolved_at` | "When was it fully resolved?" | Auto: transition into `closed` stage | **Auto** (exists) — cleared on reopen |

### Key behaviors

- `detected_at`: only set manually. Can be before `declared_at`. Nullable.
- `acknowledged_at`: set ONCE when entering active stage for the first time. Not cleared if incident goes back to triage. Represents "first time someone picked this up."
- `mitigated_at`: set ONCE when entering a status flagged with `sets_mitigated_at`. Default: "Monitoring" status has this flag. Not cleared on subsequent transitions. Represents "first time impact was contained."
- `resolved_at`: set when entering closed stage, CLEARED when reopened (current behavior). Can be set multiple times (re-close after reopen).

---

## How Metrics Work

All use the cached columns — no joins needed:

```sql
-- MTTR (Mean Time to Resolve)
SELECT AVG(EXTRACT(EPOCH FROM (resolved_at - declared_at)) / 60)
FROM incidents
WHERE resolved_at IS NOT NULL
  AND incident_status_id NOT IN (canceled stage statuses)

-- MTTD (Mean Time to Detect)
SELECT AVG(EXTRACT(EPOCH FROM (declared_at - detected_at)) / 60)
FROM incidents
WHERE detected_at IS NOT NULL

-- MTTA (Mean Time to Acknowledge)
SELECT AVG(EXTRACT(EPOCH FROM (acknowledged_at - declared_at)) / 60)
FROM incidents
WHERE acknowledged_at IS NOT NULL

-- MTTM (Mean Time to Mitigate)
SELECT AVG(EXTRACT(EPOCH FROM (mitigated_at - declared_at)) / 60)
FROM incidents
WHERE mitigated_at IS NOT NULL
```

---

## How the Transitions Table Works

Example: INC-42 goes through this journey:

```
9:30   Alert fires (detected_at = 9:30, set manually later)
10:00  Created → Investigating       (active stage)
10:30  Investigating → Triage        ("wait, is this real?")
11:00  Triage → Investigating        ("yes, confirmed")
11:30  Investigating → Identified
12:00  Identified → Monitoring       (sets_mitigated_at = true)
14:00  Monitoring → Resolved         (closed stage)
```

Transitions table:

```
┌──────────────┬──────────────┬───────┬───────────┐
│ from         │ to           │ when  │ by        │
├──────────────┼──────────────┼───────┼───────────┤
│ -            │ Investigating│ 10:00 │ alice     │
│ Investigating│ Triage       │ 10:30 │ alice     │
│ Triage       │ Investigating│ 11:00 │ bob       │
│ Investigating│ Identified   │ 11:30 │ bob       │
│ Identified   │ Monitoring   │ 12:00 │ alice     │
│ Monitoring   │ Resolved     │ 14:00 │ alice     │
└──────────────┴──────────────┴───────┴───────────┘
```

Cached columns on incident:

```
detected_at     = 9:30  (set manually by alice)
declared_at     = 10:00 (auto on creation)
acknowledged_at = 10:00 (first entry into active stage)
mitigated_at    = 12:00 (first entry into Monitoring, which has sets_mitigated_at)
resolved_at     = 14:00 (entry into closed stage)
```

Derivable from transitions table:
- Time in Investigating: (10:00→10:30) + (11:00→11:30) = 60 min
- Time in Triage: 10:30→11:00 = 30 min
- Time in Identified: 11:30→12:00 = 30 min
- Time in Monitoring: 12:00→14:00 = 120 min
- Total active time: 4 hours

---

## `sets_mitigated_at` Flag on Incident Statuses

Since statuses are workspace-configurable, we need a way to mark which status means "mitigated."

```ruby
add_column :incident_statuses, :sets_mitigated_at, :boolean, default: false, null: false
```

Default: "Monitoring" status has `sets_mitigated_at: true`. Workspaces can change this if they rename or replace their statuses.

---

## Lifecycle Concern Changes

`Incident::Lifecycle` concern gains new logic:

```ruby
def update_milestone_timestamps
  return unless incident_status_id_changed?

  stage = incident_status.incident_lifecycle_stage

  # acknowledged_at: set once on first entry to active stage
  if stage.active? && acknowledged_at.nil?
    self.acknowledged_at = Time.current
  end

  # mitigated_at: set once on first entry to mitigated status
  if incident_status.sets_mitigated_at? && mitigated_at.nil?
    self.mitigated_at = Time.current
  end

  # resolved_at: set on close, cleared on reopen (existing behavior)
  if stage.closed? && resolved_at.nil?
    self.resolved_at = Time.current
    self.next_update_at = nil
  elsif stage.active? && resolved_at.present?
    self.resolved_at = nil
  end

  # canceled: clear next_update_at, don't set resolved_at
  if stage.canceled?
    self.next_update_at = nil
  end
end
```

Additionally, create a transition record on every status change:

```ruby
after_save :record_status_transition, if: :saved_change_to_incident_status_id?

def record_status_transition
  IncidentStatusTransition.create!(
    incident: self,
    from_status_id: incident_status_id_before_last_save,
    to_status_id: incident_status_id,
    occurred_at: Time.current,
    transitioned_by: Current.workspace_membership
  )
end
```

---

## Relationship to `incident_events`

Both tables record status changes but serve different purposes:

| | `incident_events` | `incident_status_transitions` |
|---|---|---|
| Purpose | Audit trail (all changes) | Structured timestamp data (status changes only) |
| Data | Full before/after JSONB snapshots | from_status, to_status, occurred_at |
| Query use | Timeline display, audit | Metrics, per-status duration |
| Records | All changes (status, severity, name, etc.) | Status changes only |

Both are created on the same status change event. No conflict — complementary.

---

## Slack UX

| Touchpoint | What's shown | Editable? |
|---|---|---|
| **Creation modal** | Nothing extra | No |
| **Update modal** | `detected_at` field ("When was this first detected?") | Yes — date/time picker |
| **Close modal** | Milestone summary: detected → declared → acknowledged → mitigated → resolved | `detected_at` editable if not set |
| **Quick actions** | Duration since declared ("Active for 2h 15m") | No |
| **Channel topic** | No timestamps | No |

---

## Verification

1. `bin/ci` passes
2. New model tests for `IncidentStatusTransition`
3. Lifecycle concern tests:
   - First entry to active stage sets `acknowledged_at`
   - Re-entry to active stage does NOT overwrite `acknowledged_at`
   - Entry to Monitoring sets `mitigated_at`
   - Entry to closed sets `resolved_at`
   - Reopen clears `resolved_at` but NOT `acknowledged_at` or `mitigated_at`
   - Cancel does NOT set `resolved_at`
4. Transition records created on every status change
5. Per-status duration calculation from transitions table
6. Verify `detected_at` is settable via update modal
