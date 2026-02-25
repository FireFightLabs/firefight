# Incident Relationships — Implementation Plan

## Context

Firefight has no way to link incidents to each other. Three relationship types exist in the incident management space: related incidents, merging, and parent/child sub-incidents. For SMB startups, related incidents and merging provide the most value. Parent/child sub-incidents solve a big-company coordination problem and should be deferred.

---

## Priority

1. **Related incidents** — build now. Simple join table, high value for pattern recognition.
2. **Merging incidents** — build now. Handles duplicates cleanly, especially important as alert-based auto-creation is added later.
3. **Parent/child sub-incidents** — defer. Solves multi-team coordination for large orgs. A 15-person startup works in one channel.

---

## 1. Related Incidents (build now)

### Use cases

- "This database timeout looks like INC-38 from last week"
- "We've had 3 similar incidents this month — there's a pattern"
- Linking a follow-up incident to its predecessor

### Schema

```ruby
create_table :incident_relationships, id: :uuid do |t|
  t.references :incident, type: :uuid, null: false, foreign_key: true
  t.references :related_incident, type: :uuid, null: false, foreign_key: { to_table: :incidents }
  t.string :relationship_type, null: false, default: "related"  # "related", "duplicate", "caused_by"
  t.references :created_by, type: :uuid, null: true, foreign_key: { to_table: :workspace_memberships }
  t.timestamps
end

add_index :incident_relationships, [ :incident_id, :related_incident_id ], unique: true
```

### Relationship types

| Type | Meaning | Bidirectional? |
|---|---|---|
| `related` | These incidents are connected somehow | Yes — if A is related to B, B is related to A |
| `duplicate` | This incident is a duplicate of another | Directional — A is duplicate of B (A gets merged/canceled) |
| `caused_by` | This incident was caused by another | Directional — A was caused by B |

### Model

```ruby
# app/models/incident_relationship.rb
class IncidentRelationship < ApplicationRecord
  TYPES = %w[related duplicate caused_by].freeze

  belongs_to :incident
  belongs_to :related_incident, class_name: "Incident"
  belongs_to :created_by, class_name: "WorkspaceMembership", optional: true

  validates :relationship_type, inclusion: { in: TYPES }
  validates :related_incident_id, uniqueness: { scope: :incident_id }
  validate :not_self_referencing

  private

  def not_self_referencing
    errors.add(:related_incident, "can't be the same incident") if incident_id == related_incident_id
  end
end
```

On `Incident`:
```ruby
has_many :incident_relationships, dependent: :destroy
has_many :related_incidents, through: :incident_relationships

# Inverse relationships (incidents that link TO this one)
has_many :inverse_relationships, class_name: "IncidentRelationship", foreign_key: :related_incident_id
has_many :inversely_related_incidents, through: :inverse_relationships, source: :incident

# All related (both directions)
def all_related_incidents
  Incident.where(id: incident_relationships.select(:related_incident_id))
    .or(Incident.where(id: inverse_relationships.select(:incident_id)))
end
```

### Slack UX

- **Link incidents**: Quick action button or `/ff link INC-42` command in an incident channel
  - Opens modal with incident search/select dropdown
  - Select relationship type (default: "related")
- **Show related**: In quick actions message, list linked incidents with their type
- **Event**: Record `incident.linked` event in audit trail

---

## 2. Merging Incidents (build now)

### Use cases

- Two people create incidents for the same problem
- A triage incident turns out to be a duplicate of an active incident
- Alert auto-creation (future) creates a new incident for an existing problem

### How merging works

Merging is NOT deleting one incident — it's closing the duplicate and linking it to the surviving incident.

**Process:**
1. User selects "Merge" on incident A (the duplicate)
2. User picks incident B (the surviving incident) from a dropdown
3. System:
   - Creates a `duplicate` relationship: A → B
   - Moves A to `canceled` stage with a "Merged into INC-XX" reason
   - Posts a message in A's channel: "This incident was merged into INC-XX"
   - Posts a message in B's channel: "INC-YY was merged into this incident"
   - Copies any action items from A to B (optional, confirm with user)
   - Records `incident.merged` event on both incidents
4. A's channel gets archived (or not — configurable)

**What is NOT transferred:**
- Status, severity, timestamps — B keeps its own
- Custom field values — B keeps its own
- Role assignments — B keeps its own

**What IS transferred (optionally):**
- Open action items / followups
- The relationship link for historical reference

### Slack UX

- **Merge button**: In quick actions or `/ff merge` command
- **Modal**: Select the surviving incident from workspace's active incidents
- **Confirmation**: "Merge INC-42 into INC-38? INC-42 will be canceled."

### Schema

No new tables needed — merging uses:
- `incident_relationships` with `relationship_type: "duplicate"`
- Status change to canceled stage
- `incident.merged` event type in incident_events

---

## 3. Parent/Child Sub-Incidents (defer)

> **Status**: Future implementation. This solves multi-team coordination for large organizations where a major incident spans 3+ teams, each needing their own channel and workflow while coordinating under a parent.

### Use cases (enterprise)

- Major outage: parent "INC-100: Platform outage" with children "INC-101: Database team", "INC-102: API team", "INC-103: Frontend team"
- Each sub-team works independently in their own channel
- Parent incident aggregates status and timeline from all children

### Schema (future)

```ruby
# Add to incidents table
add_reference :incidents, :parent_incident, type: :uuid, null: true, foreign_key: { to_table: :incidents }
```

On `Incident`:
```ruby
belongs_to :parent_incident, class_name: "Incident", optional: true
has_many :sub_incidents, class_name: "Incident", foreign_key: :parent_incident_id
```

### Behavior (future)

- Sub-incidents inherit from parent: services, features, environments, severity
- Each sub-incident has its own channel, status, roles, actions
- Parent status reflects worst-case child status
- Parent resolved only when all children resolved
- Timeline aggregates events from all children

### Why defer

- Requires complex status synchronization between parent and children
- Channel coordination across multiple Slack channels
- Metric aggregation logic
- A 15-30 person startup works in one channel — sub-incidents add overhead without value at that scale
- Related incidents + merging cover the practical needs for now

---

## Verification (for related incidents + merging)

1. `bin/ci` passes
2. Can create bidirectional "related" relationship between two incidents
3. Can mark an incident as "duplicate" of another
4. Merge flow: duplicate incident moves to canceled stage
5. Merge flow: messages posted in both channels
6. Merge flow: open action items optionally transferred
7. `all_related_incidents` returns both directions
8. `incident.linked` and `incident.merged` events recorded
