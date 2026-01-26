# FIR-21: Database Schema & Models - Implementation Guide v2

## Overview

**Updated approach: Mutable incidents + event snapshots**

Create foundational database schema for incident management with:
- Workspace-configurable statuses (with live/closed categories)
- Workspace-configurable severities (with rank)
- Flexible incident role system (supports multiple roles, MVP uses one)
- **3 core tables:** incidents (mutable), incident_events (full snapshots), incident_actions
- **3 configuration tables:** incident_statuses, incident_severities, incident_roles
- **1 join table:** incident_role_assignments

**Key Architecture:** Mutable incidents table with full snapshot events (no separate incident_updates table)

---

## Architecture Decisions

### 1. Configurable Statuses (NOT Hardcoded)

**Why:** Different teams use different terminology and workflows
- Some use: Investigating → Identified → Mitigated → Resolved
- Others use: Triaging → Working → Monitoring → Closed

**Implementation:**
- `incident_statuses` table with workspace_id
- `category` field: "live" (active work) or "closed" (post-incident learning)
- Default statuses seeded on workspace creation

### 2. Configurable Severities (NOT Hardcoded)

**Why:** Different companies use different severity scales
- Some use: SEV1, SEV2, SEV3, SEV4
- Others use: Critical, Major, Minor
- Others use: P0, P1, P2, P3

**Implementation:**
- `incident_severities` table with workspace_id
- `rank` field: Higher number = more severe (for comparison logic)
- Default severities seeded on workspace creation

### 3. Flexible Role System (Future-Proof)

**Why:** Different incident structures need different roles
- Simple teams: Just "Incident Lead"
- Complex teams: Commander, Comms Lead, Tech Lead, Scribe

**Implementation:**
- `incident_roles` table with workspace_id
- `incident_role_assignments` join table
- MVP: Seed one default role "Incident Lead"

### 4. Event-Based Audit Trail (Full Snapshots)

**Why full snapshots instead of diffs:**
- View incident state at ANY point in time
- No need to "replay" diffs to rebuild state
- Handles renamed/deleted statuses (denormalized data)
- Easy to show "what changed" by comparing before/after
- Future-proof: any field changes are captured

**Implementation:**
- `incident_events` table stores full `before` and `after` snapshots
- Denormalized related data (severity name, status name, lead info)
- Timeline is queried directly from events (no reconstruction needed)

---

## Step 1: Create Configuration Table Migrations

### Migration 1: Create Incident Statuses Table

**File:** `db/migrate/YYYYMMDDHHMMSS_create_incident_statuses.rb`

```ruby
class CreateIncidentStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_statuses, id: :uuid do |t|
      t.uuid :workspace_id, null: false

      # Status identification
      t.string :name, null: false # "Investigating", "Identified", etc.
      t.string :slug, null: false # "investigating", "identified"
      t.text :description

      # Lifecycle category
      t.string :category, null: false # "live" or "closed"

      # Ordering and defaults
      t.integer :position, null: false, default: 0
      t.boolean :is_default, default: false # Default status for new incidents

      # UI configuration
      t.string :color # Hex color code like "#FFA500"

      t.timestamps

      # Indexes
      t.index :workspace_id
      t.index [:workspace_id, :slug], unique: true
      t.index [:workspace_id, :position]
      t.index [:workspace_id, :category]
      t.index [:workspace_id, :is_default]
    end

    add_foreign_key :incident_statuses, :workspaces
  end
end
```

---

### Migration 2: Create Incident Severities Table

**File:** `db/migrate/YYYYMMDDHHMMSS_create_incident_severities.rb`

```ruby
class CreateIncidentSeverities < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_severities, id: :uuid do |t|
      t.uuid :workspace_id, null: false

      # Severity identification
      t.string :name, null: false # "SEV1", "Critical", "P0", etc.
      t.string :slug, null: false # "sev1", "critical", "p0"
      t.text :description

      # Severity ranking (higher = more severe)
      t.integer :rank, null: false # 1=lowest severity, 5=highest severity

      # Ordering and defaults
      t.integer :position, null: false, default: 0 # For UI ordering
      t.boolean :is_default, default: false # Default severity for new incidents

      # UI configuration
      t.string :color # Hex color code like "#DC143C"

      t.timestamps

      # Indexes
      t.index :workspace_id
      t.index [:workspace_id, :slug], unique: true
      t.index [:workspace_id, :position]
      t.index [:workspace_id, :rank]
      t.index [:workspace_id, :is_default]
    end

    add_foreign_key :incident_severities, :workspaces
  end
end
```

---

### Migration 3: Create Incident Roles Table

**File:** `db/migrate/YYYYMMDDHHMMSS_create_incident_roles.rb`

```ruby
class CreateIncidentRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_roles, id: :uuid do |t|
      t.uuid :workspace_id, null: false

      # Role identification
      t.string :name, null: false # "Incident Lead", "Commander", "Comms Lead"
      t.string :slug, null: false # "incident_lead", "commander", "comms_lead"
      t.text :description # Role responsibilities

      # Configuration
      t.integer :position, null: false, default: 0
      t.boolean :required, default: false # Must be filled before closing incident

      t.timestamps

      # Indexes
      t.index :workspace_id
      t.index [:workspace_id, :slug], unique: true
      t.index [:workspace_id, :position]
    end

    add_foreign_key :incident_roles, :workspaces
  end
end
```

---

### Migration 4: Create Incidents Table (UPDATED)

**File:** `db/migrate/YYYYMMDDHHMMSS_create_incidents.rb`

```ruby
class CreateIncidents < ActiveRecord::Migration[8.1]
  def change
    create_table :incidents, id: :uuid do |t|
      # Workspace and user references
      t.uuid :workspace_id, null: false
      t.uuid :declared_by_id, null: false # Who declared the incident

      # Configurable references (NOT hardcoded strings)
      t.uuid :incident_status_id, null: false
      t.uuid :incident_severity_id, null: false

      # Sequential numbering (workspace-scoped)
      t.integer :sequence_number, null: false
      t.string :identifier, null: false # "INC-001", "INC-002"

      # Core fields (MUTABLE - edited in place)
      t.string :name
      t.text :summary
      t.boolean :is_private, default: false

      # Slack/Teams integration fields
      t.string :slack_channel_id
      t.string :slack_channel_name
      t.string :initial_message_ts # Pinned quick actions message
      t.string :announcement_message_ts # Message in #incidents channel

      # Platform-agnostic metadata (Slack timestamps, Teams IDs, etc.)
      t.jsonb :platform_data, default: {}

      # Custom fields (future feature)
      t.jsonb :custom_fields, default: {}

      # Lifecycle timestamps
      t.datetime :declared_at, null: false
      t.datetime :resolved_at # Set when moved to "closed" category status

      t.timestamps

      # Indexes for performance
      t.index :workspace_id
      t.index [:workspace_id, :sequence_number], unique: true
      t.index [:workspace_id, :identifier], unique: true
      t.index [:workspace_id, :incident_status_id]
      t.index :incident_status_id
      t.index :incident_severity_id
      t.index :declared_at
      t.index :declared_by_id
    end

    # Foreign key constraints
    add_foreign_key :incidents, :workspaces
    add_foreign_key :incidents, :workspace_memberships, column: :declared_by_id
    add_foreign_key :incidents, :incident_statuses
    add_foreign_key :incidents, :incident_severities
  end
end
```

---

### Migration 5: Create Incident Role Assignments Table

**File:** `db/migrate/YYYYMMDDHHMMSS_create_incident_role_assignments.rb`

```ruby
class CreateIncidentRoleAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_role_assignments, id: :uuid do |t|
      t.uuid :incident_id, null: false
      t.uuid :incident_role_id, null: false
      t.uuid :workspace_membership_id, null: false # Who is assigned

      t.datetime :assigned_at, null: false
      t.uuid :assigned_by_id # Who made the assignment (optional for auto-assignments)

      t.timestamps

      # Indexes
      t.index :incident_id
      t.index [:incident_id, :incident_role_id], unique: true # One person per role per incident
      t.index :workspace_membership_id
      t.index :incident_role_id
    end

    # Foreign key constraints
    add_foreign_key :incident_role_assignments, :incidents
    add_foreign_key :incident_role_assignments, :incident_roles
    add_foreign_key :incident_role_assignments, :workspace_memberships
    add_foreign_key :incident_role_assignments, :workspace_memberships, column: :assigned_by_id
  end
end
```

---

### Migration 6: Create Incident Events Table (UPDATED - Full Snapshots)

**File:** `db/migrate/YYYYMMDDHHMMSS_create_incident_events.rb`

```ruby
class CreateIncidentEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_events, id: :uuid do |t|
      t.uuid :incident_id, null: false
      t.uuid :user_id # Optional: system events have no user
      t.string :event_type, null: false

      # Full snapshots with denormalized data
      # Structure: { schema_version: 1, before: {...}, after: {...}, changed_fields: [...], details: "..." }
      t.jsonb :metadata, default: {}

      t.datetime :created_at, null: false

      # Indexes
      t.index :incident_id
      t.index [:incident_id, :created_at]
      t.index :event_type
      t.index :metadata, using: :gin # For JSONB queries
    end

    # Foreign key constraints
    add_foreign_key :incident_events, :incidents
    add_foreign_key :incident_events, :workspace_memberships, column: :user_id
  end
end
```

**Metadata structure:**
```ruby
{
  schema_version: 1,
  before: {
    identifier: "INC-001",
    name: "Database issue",
    summary: "Users reporting slow queries...",
    severity: { id: "uuid", name: "Minor", slug: "minor", rank: 1, color: "#FFA500" },
    status: { id: "uuid", name: "Investigating", slug: "investigating", category: "live" },
    lead: { id: "uuid", name: "Alice Johnson", email: "alice@..." },
    declared_by: { id: "uuid", name: "Bob Smith" },
    declared_at: "2026-01-23T10:00:00Z",
    resolved_at: nil
  },
  after: {
    identifier: "INC-001",
    name: "Database outage", # Changed
    summary: "Users reporting slow queries...",
    severity: { id: "uuid", name: "Critical", slug: "critical", rank: 5, color: "#DC143C" }, # Changed
    status: { id: "uuid", name: "Investigating", slug: "investigating", category: "live" },
    lead: { id: "uuid", name: "Alice Johnson", email: "alice@..." },
    declared_by: { id: "uuid", name: "Bob Smith" },
    declared_at: "2026-01-23T10:00:00Z",
    resolved_at: nil
  },
  changed_fields: ["name", "severity"],
  details: "Customer impact worse than expected"
}
```

---

### Migration 7: Create Incident Actions Table

**File:** `db/migrate/YYYYMMDDHHMMSS_create_incident_actions.rb`

```ruby
class CreateIncidentActions < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_actions, id: :uuid do |t|
      t.uuid :incident_id, null: false
      t.uuid :created_by_id, null: false
      t.uuid :assignee_id

      t.string :action_type, null: false, default: "action" # "action" or "followup"
      t.text :description, null: false
      t.string :status, default: "open" # "open", "in_progress", "done"

      t.string :slack_message_ts
      t.jsonb :platform_data, default: {}

      t.timestamps

      # Indexes
      t.index [:incident_id, :action_type]
      t.index [:incident_id, :status]
      t.index :assignee_id
    end

    # Foreign key constraints
    add_foreign_key :incident_actions, :incidents
    add_foreign_key :incident_actions, :workspace_memberships, column: :created_by_id
    add_foreign_key :incident_actions, :workspace_memberships, column: :assignee_id
  end
end
```

---

## Step 2: Create Model Files

### Model 1: IncidentStatus

**File:** `app/models/incident_status.rb`

```ruby
class IncidentStatus < ApplicationRecord
  # Associations
  belongs_to :workspace
  has_many :incidents, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :category, inclusion: { in: %w[live closed] }
  validates :position, presence: true, numericality: { only_integer: true }

  # Scopes
  scope :live, -> { where(category: "live") }
  scope :closed, -> { where(category: "closed") }
  scope :ordered, -> { order(:position) }
  scope :default_status, -> { find_by(is_default: true) }

  # Query methods
  def live?
    category == "live"
  end

  def closed?
    category == "closed"
  end
end
```

---

### Model 2: IncidentSeverity

**File:** `app/models/incident_severity.rb`

```ruby
class IncidentSeverity < ApplicationRecord
  # Associations
  belongs_to :workspace
  has_many :incidents, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :rank, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :position, presence: true, numericality: { only_integer: true }

  # Scopes
  scope :ordered, -> { order(:position) }
  scope :by_rank, -> { order(rank: :desc) } # Highest severity first
  scope :default_severity, -> { find_by(is_default: true) }

  # Comparison methods
  def more_severe_than?(other_severity)
    rank > other_severity.rank
  end

  def less_severe_than?(other_severity)
    rank < other_severity.rank
  end
end
```

---

### Model 3: IncidentRole

**File:** `app/models/incident_role.rb`

```ruby
class IncidentRole < ApplicationRecord
  # Associations
  belongs_to :workspace
  has_many :incident_role_assignments, dependent: :destroy
  has_many :incidents, through: :incident_role_assignments

  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :position, presence: true, numericality: { only_integer: true }

  # Scopes
  scope :ordered, -> { order(:position) }
  scope :required_roles, -> { where(required: true) }

  # Class method to find default "Incident Lead" role
  def self.incident_lead
    find_by(slug: "incident_lead")
  end
end
```

---

### Model 4: IncidentRoleAssignment

**File:** `app/models/incident_role_assignment.rb`

```ruby
class IncidentRoleAssignment < ApplicationRecord
  # Associations
  belongs_to :incident
  belongs_to :incident_role
  belongs_to :workspace_membership
  belongs_to :assigned_by, class_name: "WorkspaceMembership", optional: true

  # Validations
  validates :incident_role_id, uniqueness: { scope: :incident_id }

  # Callbacks
  before_validation :set_assigned_at, on: :create

  # Scopes
  scope :recent, -> { order(assigned_at: :desc) }

  private

  def set_assigned_at
    self.assigned_at ||= Time.current
  end
end
```

---

### Model 5: Incident (UPDATED with Snapshot Support)

**File:** `app/models/incident.rb`

```ruby
class Incident < ApplicationRecord
  # Associations
  belongs_to :workspace
  belongs_to :declared_by, class_name: "WorkspaceMembership"
  belongs_to :incident_status
  belongs_to :incident_severity

  has_many :incident_events, dependent: :destroy
  has_many :incident_actions, dependent: :destroy
  has_many :incident_role_assignments, dependent: :destroy
  has_many :incident_roles, through: :incident_role_assignments
  has_many :assigned_members, through: :incident_role_assignments, source: :workspace_membership

  # Validations
  validates :sequence_number, presence: true, uniqueness: { scope: :workspace_id }
  validates :identifier, presence: true, uniqueness: { scope: :workspace_id }
  validates :declared_at, presence: true

  # Callbacks
  before_validation :assign_sequence_number, on: :create
  before_validation :set_declared_at, on: :create
  before_validation :generate_identifier, on: :create
  before_save :update_resolved_at

  # Scopes
  scope :active, -> { joins(:incident_status).where(incident_statuses: { category: "live" }) }
  scope :closed, -> { joins(:incident_status).where(incident_statuses: { category: "closed" }) }
  scope :by_severity, -> { joins(:incident_severity).order("incident_severities.rank DESC") }
  scope :recent, -> { order(declared_at: :desc) }

  # Query methods
  def active?
    incident_status.live?
  end

  def closed?
    incident_status.closed?
  end

  # Role helper for MVP (returns the "Incident Lead" assignment)
  def lead
    lead_role = workspace.incident_roles.incident_lead
    incident_role_assignments.find_by(incident_role: lead_role)&.workspace_membership
  end

  def lead=(workspace_membership)
    lead_role = workspace.incident_roles.incident_lead
    return unless lead_role

    assignment = incident_role_assignments.find_or_initialize_by(incident_role: lead_role)
    assignment.workspace_membership = workspace_membership
    assignment.save!
  end

  # Snapshot for events (denormalized data)
  def snapshot
    {
      identifier: identifier,
      name: name,
      summary: summary&.truncate(200), # Don't store massive text
      severity: incident_severity.as_json(only: [:id, :name, :slug, :rank, :color]),
      status: incident_status.as_json(only: [:id, :name, :slug, :category]),
      lead: lead&.as_json(only: [:id], methods: [:display_name, :email]),
      declared_by: declared_by.as_json(only: [:id], methods: [:display_name]),
      declared_at: declared_at,
      resolved_at: resolved_at
    }
  end

  # Record change with full snapshots
  def record_change!(event_type, details: nil, changed_by: nil)
    before_snapshot = snapshot
    yield # Perform the change
    after_snapshot = reload.snapshot

    # Detect changed fields
    changed_fields = before_snapshot.keys.select do |key|
      before_snapshot[key] != after_snapshot[key]
    end

    incident_events.create!(
      event_type: event_type,
      user: changed_by,
      metadata: {
        schema_version: 1,
        before: before_snapshot,
        after: after_snapshot,
        changed_fields: changed_fields,
        details: details
      }
    )
  end

  # Metrics
  def time_to_resolve
    return nil unless resolved_at
    ((resolved_at - declared_at) / 60).round # minutes
  end

  # Channel naming
  def channel_name
    slug = (name.presence || "untitled").parameterize[0..50]
    "inc-#{sequence_number.to_s.rjust(3, '0')}-#{slug}"
  end

  private

  # Sequential number generation with row-level locking
  def assign_sequence_number
    return if sequence_number.present?

    Incident.transaction do
      max_seq = workspace.incidents.lock.maximum(:sequence_number) || 0
      self.sequence_number = max_seq + 1
    end
  end

  def generate_identifier
    self.identifier = "INC-#{sequence_number.to_s.rjust(3, '0')}"
  end

  def set_declared_at
    self.declared_at ||= Time.current
  end

  # Auto-set resolved_at when status changes to closed category
  def update_resolved_at
    if incident_status_id_changed? && incident_status.closed? && resolved_at.nil?
      self.resolved_at = Time.current
    end
  end
end
```

---

### Model 6: IncidentEvent (UPDATED)

**File:** `app/models/incident_event.rb`

```ruby
class IncidentEvent < ApplicationRecord
  # Associations
  belongs_to :incident
  belongs_to :user, class_name: "WorkspaceMembership", optional: true

  # Validations
  validates :event_type, presence: true

  # Scopes
  scope :chronological, -> { order(created_at: :asc) }
  scope :recent, -> { order(created_at: :desc) }

  # Event type constants
  INCIDENT_CREATED = "incident.created"
  INCIDENT_UPDATED = "incident.updated"
  LEAD_ASSIGNED = "lead.assigned"
  ACTION_CREATED = "action.created"
  ACTION_PICKED_UP = "action.picked_up"
  ACTION_COMPLETED = "action.completed"
  INCIDENT_ESCALATED = "incident.escalated"
  INCIDENT_RESOLVED = "incident.resolved"
  POSTMORTEM_GENERATED = "postmortem.generated"

  # Helper methods
  def before_snapshot
    metadata["before"] || {}
  end

  def after_snapshot
    metadata["after"] || {}
  end

  def changed_fields
    metadata["changed_fields"] || []
  end

  def details
    metadata["details"]
  end

  def changed?(field)
    changed_fields.include?(field.to_s)
  end
end
```

---

### Model 7: IncidentAction

**File:** `app/models/incident_action.rb`

```ruby
class IncidentAction < ApplicationRecord
  # Associations
  belongs_to :incident
  belongs_to :created_by, class_name: "WorkspaceMembership"
  belongs_to :assignee, class_name: "WorkspaceMembership", optional: true

  # Validations
  validates :action_type, inclusion: { in: %w[action followup] }
  validates :status, inclusion: { in: %w[open in_progress done] }
  validates :description, presence: true

  # Scopes
  scope :actions, -> { where(action_type: "action") }
  scope :followups, -> { where(action_type: "followup") }
  scope :open, -> { where(status: "open") }
  scope :completed, -> { where(status: "done") }
  scope :recent, -> { order(created_at: :desc) }

  # Query methods
  def open?
    status == "open"
  end

  def done?
    status == "done"
  end

  def assigned?
    assignee_id.present?
  end
end
```

---

## Step 3: Update Workspace Model

**File:** `app/models/workspace.rb`

Add these associations:

```ruby
# Incident management
has_many :incidents, dependent: :destroy
has_many :incident_statuses, dependent: :destroy
has_many :incident_severities, dependent: :destroy
has_many :incident_roles, dependent: :destroy
```

---

## Step 4: Seed Default Configuration

### Update WorkspaceSetupService

**File:** `app/services/workspace_setup_service.rb`

```ruby
class WorkspaceSetupService
  # Default severities (customize per workspace later)
  DEFAULT_SEVERITIES = [
    { name: "Critical", slug: "critical", rank: 5, position: 1, is_default: false, color: "#DC143C", description: "Service-wide outage or data loss" },
    { name: "Major", slug: "major", rank: 3, position: 2, is_default: false, color: "#FF6B35", description: "Significant feature degradation" },
    { name: "Minor", slug: "minor", rank: 1, position: 3, is_default: true, color: "#FFA500", description: "Limited impact or workaround available" }
  ].freeze

  # Default statuses (live vs closed categories)
  DEFAULT_STATUSES = [
    # Live statuses (active incident work)
    { name: "Investigating", slug: "investigating", category: "live", position: 1, is_default: true, color: "#FFA500", description: "Initial triage and investigation" },
    { name: "Identified", slug: "identified", category: "live", position: 2, is_default: false, color: "#FF6B35", description: "Root cause identified" },
    { name: "Monitoring", slug: "monitoring", category: "live", position: 3, is_default: false, color: "#4169E1", description: "Fix deployed, monitoring for stability" },

    # Closed statuses (post-incident learning)
    { name: "Resolved", slug: "resolved", category: "closed", position: 4, is_default: false, color: "#32CD32", description: "Incident fully resolved" }
  ].freeze

  # Default roles (MVP: one role, extendable later)
  DEFAULT_ROLES = [
    { name: "Incident Lead", slug: "incident_lead", position: 1, required: false, description: "Coordinates incident response and makes decisions" }
  ].freeze

  def initialize(workspace)
    @workspace = workspace
  end

  def setup_incident_configuration!
    ActiveRecord::Base.transaction do
      create_default_severities!
      create_default_statuses!
      create_default_roles!
    end
  end

  private

  def create_default_severities!
    DEFAULT_SEVERITIES.each do |severity_data|
      @workspace.incident_severities.create!(severity_data)
    end
  end

  def create_default_statuses!
    DEFAULT_STATUSES.each do |status_data|
      @workspace.incident_statuses.create!(status_data)
    end
  end

  def create_default_roles!
    DEFAULT_ROLES.each do |role_data|
      @workspace.incident_roles.create!(role_data)
    end
  end
end
```

---

### Hook into Workspace Creation

**File:** `app/models/workspace.rb`

Update the `process_slack_installation` method:

```ruby
def self.process_slack_installation(auth_hash)
  transaction do
    workspace = find_or_create_from_slack!(auth_hash)
    user = User.find_or_create_from_omniauth!(auth_hash)
    membership = WorkspaceMembership.find_or_create_from_omniauth!(user, workspace, auth_hash)

    # Setup incident configuration for new workspaces
    if workspace.previously_new_record?
      WorkspaceSetupService.new(workspace).setup_incident_configuration!
    end

    { workspace: workspace, user: user, membership: membership }
  end
end
```

---

## Step 5: Usage Examples

### Recording Changes

```ruby
# Status change
incident.record_change!("incident.updated", changed_by: current_user, details: "Fix deployed") do
  incident.update!(incident_status: monitoring_status)
end

# Severity escalation
incident.record_change!("incident.updated", changed_by: current_user, details: "Customer impact confirmed") do
  incident.update!(
    incident_severity: critical_severity,
    name: "Production database outage"
  )
end

# Lead assignment
incident.record_change!("lead.assigned", changed_by: current_user) do
  incident.lead = alice
end
```

### Timeline Display

```ruby
class TimelineEntry
  def initialize(event)
    @event = event
  end

  def timestamp
    @event.created_at
  end

  def actor
    @event.user&.display_name || "System"
  end

  def description
    case @event.event_type
    when "incident.created"
      "Incident declared"
    when "incident.updated"
      changes = []
      changes << severity_change if @event.changed?("severity")
      changes << status_change if @event.changed?("status")
      changes << name_change if @event.changed?("name")
      changes.join(", ")
    when "lead.assigned"
      "Assigned #{after_lead_name} as lead"
    end
  end

  def details
    @event.details
  end

  private

  def severity_change
    before = @event.before_snapshot.dig("severity", "name")
    after = @event.after_snapshot.dig("severity", "name")
    "Severity: #{before} → #{after}"
  end

  def status_change
    before = @event.before_snapshot.dig("status", "name")
    after = @event.after_snapshot.dig("status", "name")
    "Status: #{before} → #{after}"
  end

  def name_change
    before = @event.before_snapshot["name"]
    after = @event.after_snapshot["name"]
    "Name: \"#{before}\" → \"#{after}\""
  end

  def after_lead_name
    @event.after_snapshot.dig("lead", "name") || "Unassigned"
  end
end

# Render timeline
incident.incident_events.chronological.each do |event|
  entry = TimelineEntry.new(event)
  puts "#{entry.timestamp} - #{entry.actor}: #{entry.description}"
  puts "  #{entry.details}" if entry.details
end
```

---

## Migration Order

Run migrations in this order:

1. `create_incident_statuses.rb`
2. `create_incident_severities.rb`
3. `create_incident_roles.rb`
4. `create_incidents.rb` (depends on statuses/severities)
5. `create_incident_role_assignments.rb` (depends on incidents/roles)
6. `create_incident_events.rb` (depends on incidents)
7. `create_incident_actions.rb` (depends on incidents)

---

## Key Benefits of This Approach

✅ **Full auditability** - Complete snapshots show incident state at any point in time
✅ **No reconstruction needed** - Timeline queries events directly
✅ **Future-proof** - New fields automatically appear in snapshots
✅ **Handles config changes** - Denormalized data preserves history even if statuses/severities renamed
✅ **Simple** - No separate incident_updates table, everything in events
✅ **Performant** - Composite index `(incident_id, created_at)` handles millions of rows
✅ **Flexible** - JSONB supports any event type (actions, escalations, file attachments, etc.)

---

## Acceptance Criteria

- [ ] All 7 migration files created and run successfully
- [ ] Configuration tables: incident_statuses, incident_severities, incident_roles
- [ ] Core tables: incidents (mutable), incident_role_assignments, incident_events (snapshots), incident_actions
- [ ] All 7 models created with proper associations and validations
- [ ] Workspace model updated with associations
- [ ] WorkspaceSetupService seeds default config on workspace creation
- [ ] `incident.snapshot` method returns denormalized data
- [ ] `incident.record_change!` creates event with before/after snapshots
- [ ] `incident.lead` helper works for MVP
- [ ] `incident.active?` returns true for live statuses
- [ ] `incident.closed?` returns true for closed statuses
- [ ] `resolved_at` auto-sets when status moves to closed category
- [ ] Sequential IDs work with row-level locking (workspace-scoped)
- [ ] Channel name generation: inc-001-title-slug
- [ ] All tests pass
- [ ] Foreign key constraints enforce referential integrity
- [ ] is_private is boolean (not string)
- [ ] Custom fields JSONB ready for future use
- [ ] Timeline renders from events without reconstruction

---

## Files Summary

**New Migrations (7):**
- Configuration: incident_statuses, incident_severities, incident_roles
- Core: incidents (mutable), incident_role_assignments, incident_events (snapshots), incident_actions

**New Models (7):**
- Configuration: IncidentStatus, IncidentSeverity, IncidentRole, IncidentRoleAssignment
- Core: Incident (with snapshot support), IncidentEvent (with helpers), IncidentAction

**Updated Files (2):**
- `app/models/workspace.rb` - Add associations
- `app/services/workspace_setup_service.rb` - Seed defaults

**Test Files (7):**
- Tests for all 7 models
- Fixtures for incidents, statuses, severities, roles

**Total:** ~16 files to create/modify
