# Incident Types — Implementation Plan

## Context

Firefight has no incident type concept. All incidents follow the same workflow regardless of whether it's a service outage, security breach, or performance issue. Both incident.io and Rootly support workspace-configurable incident types that drive field visibility, role requirements, and automation conditions.

Incident types answer "what kind of problem?" — orthogonal to the system catalog (features, services, environments) which answers "what's affected?"

Decision: Simple workspace-scoped table with seeded defaults. Single-select FK on incidents. Optional — not shown at creation to keep it fast.

---

## Schema

### New table: `incident_types`

Follows the same pattern as `incident_severities`.

```ruby
create_table :incident_types, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.string :name, null: false
  t.string :slug, null: false
  t.text :description
  t.string :color
  t.integer :position, null: false
  t.boolean :is_default, default: false, null: false
  t.datetime :deleted_at
  t.timestamps
end

add_index :incident_types, [ :workspace_id, :slug ], unique: true
```

### Modify table: `incidents`

```ruby
add_reference :incidents, :incident_type, type: :uuid, null: true, foreign_key: true
```

Nullable — incidents can exist without a type. Can be set during update, close, or anytime.

---

## Default Seeded Types (per workspace)

| Name | Slug | Position | Color | Description |
|---|---|---|---|---|
| Service Outage | service_outage | 1 | #DC143C | Service or infrastructure is down or unreachable |
| Security Incident | security_incident | 2 | #8B0000 | Security breach, vulnerability exploit, or unauthorized access |
| Performance Degradation | performance_degradation | 3 | #FF6B35 | Slow response times, elevated error rates, or capacity issues |
| Data Issue | data_issue | 4 | #FFA500 | Data integrity, data loss, or incorrect data |

No default type marked as `is_default: true` — since the field is optional, there's no need for a default value.

---

## Model

### New model: `IncidentType`

```
app/models/incident_type.rb
```

- `belongs_to :workspace`
- `has_many :incidents, dependent: :restrict_with_error`
- Validates: name, slug (unique per workspace), position
- Scopes: `.active` (not deleted), `.ordered` (by position)
- Soft delete via `deleted_at`

### Modified model: `Incident`

```
app/models/incident.rb
```

- `belongs_to :incident_type, optional: true`

### Modified concern: `Workspace::IncidentDefaults`

```
app/models/concerns/workspace/incident_defaults.rb
```

- Seed 4 default incident types when workspace is set up

---

## Slack UX

### Not shown at creation

Keep incident creation fast. Type is set later.

### Shown in update modal

When updating an incident, an optional dropdown appears for incident type (single-select).

### Shown in channel topic / quick actions

If set, include in channel topic:
```
Sev: Critical | Status: Investigating | Type: Security Incident
```

### Shown in announcement

If set, include in the incidents channel announcement.

---

## What Incident Types Enable (future)

These are NOT built now, but the schema supports them:

- **Field visibility**: certain custom fields shown only for specific types
- **Role requirements**: Security Lead required for Security Incidents
- **Severity scoping**: some types may not need all severity levels
- **Workflow conditions**: different automations per type
- **Analytics**: "how many security incidents vs outages this quarter?"

---

## Verification

1. `bin/ci` passes
2. New model tests for `IncidentType`
3. Verify default seeding: `Workspace.create!` seeds 4 incident types
4. Verify incident can be created without a type (nullable FK)
5. Verify incident can be updated to add/change type
