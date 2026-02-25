# System Catalog — Teams, Services, Features, Environments

## Context

Firefight has no way to record what's affected by an incident — no services, features, environments, or team ownership. Both incident.io and Rootly/FireHydrant treat this as core infrastructure for routing, analytics, and ownership.

We need a system catalog that works for both small teams (10-20 people with a monolith) and growing companies (50+ with microservices). For small teams, **Features** (business capabilities like "Payments", "Onboarding") are the primary concept — services and teams are optional layers they add as they grow.

Decision: Separate tables for each entity type (not a generic catalog). Simple, explicit, type-safe.

---

## Entity Types

### Teams

Groups of workspace members. Optional — a 10-person startup might skip this entirely.

```ruby
create_table :teams, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.string :name, null: false
  t.string :slug, null: false
  t.text :description
  t.string :color
  t.integer :position, null: false
  t.datetime :deleted_at
  t.timestamps
end

add_index :teams, [ :workspace_id, :slug ], unique: true

create_table :team_memberships, id: :uuid do |t|
  t.references :team, type: :uuid, null: false, foreign_key: true
  t.references :workspace_membership, type: :uuid, null: false, foreign_key: true
  t.string :role  # "member", "lead" — nullable, default member
  t.timestamps
end

add_index :team_memberships, [ :team_id, :workspace_membership_id ], unique: true
```

**Defaults**: None seeded. Admin configures.

---

### Services

Technical infrastructure components. For microservices companies. Monolith companies can skip or create a single "Our App" service.

```ruby
create_table :services, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.references :team, type: :uuid, null: true, foreign_key: true  # owning team
  t.string :name, null: false
  t.string :slug, null: false
  t.text :description
  t.string :color
  t.integer :position, null: false
  t.datetime :deleted_at
  t.timestamps
end

add_index :services, [ :workspace_id, :slug ], unique: true
```

**Defaults**: None seeded. Admin configures.

---

### Features

Business capabilities that span services. The primary concept for small teams. What Rootly/FireHydrant call "Functionalities" and incident.io calls "Features".

Examples: "Payments", "User Onboarding", "Search", "Notifications"

```ruby
create_table :features, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.references :team, type: :uuid, null: true, foreign_key: true  # owning team
  t.string :name, null: false
  t.string :slug, null: false
  t.text :description
  t.string :color
  t.integer :position, null: false
  t.datetime :deleted_at
  t.timestamps
end

add_index :features, [ :workspace_id, :slug ], unique: true
```

**Features ↔ Services** (many-to-many):

```ruby
create_table :feature_services, id: :uuid do |t|
  t.references :feature, type: :uuid, null: false, foreign_key: true
  t.references :service, type: :uuid, null: false, foreign_key: true
  t.timestamps
end

add_index :feature_services, [ :feature_id, :service_id ], unique: true
```

**Defaults**: None seeded. Admin configures.

---

### Environments

Deployment targets. Most companies have these.

```ruby
create_table :environments, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.string :name, null: false
  t.string :slug, null: false
  t.text :description
  t.string :color
  t.integer :position, null: false
  t.datetime :deleted_at
  t.timestamps
end

add_index :environments, [ :workspace_id, :slug ], unique: true
```

**Defaults**: Seeded per workspace — Production, Staging, Development.

---

## Incident Connections

All optional. Multi-select via join tables.

```ruby
create_table :incident_services, id: :uuid do |t|
  t.references :incident, type: :uuid, null: false, foreign_key: true
  t.references :service, type: :uuid, null: false, foreign_key: true
  t.timestamps
end

create_table :incident_features, id: :uuid do |t|
  t.references :incident, type: :uuid, null: false, foreign_key: true
  t.references :feature, type: :uuid, null: false, foreign_key: true
  t.timestamps
end

create_table :incident_environments, id: :uuid do |t|
  t.references :incident, type: :uuid, null: false, foreign_key: true
  t.references :environment, type: :uuid, null: false, foreign_key: true
  t.timestamps
end
```

Add unique indexes on `[incident_id, service_id]`, `[incident_id, feature_id]`, `[incident_id, environment_id]`.

---

## Model Relationships

```
Workspace
  ├── has_many :teams
  ├── has_many :services
  ├── has_many :features
  └── has_many :environments

Team
  ├── belongs_to :workspace
  ├── has_many :team_memberships
  ├── has_many :workspace_memberships, through: :team_memberships
  ├── has_many :services (owned)
  └── has_many :features (owned)

Service
  ├── belongs_to :workspace
  ├── belongs_to :team (optional, owner)
  ├── has_many :feature_services
  └── has_many :features, through: :feature_services

Feature
  ├── belongs_to :workspace
  ├── belongs_to :team (optional, owner)
  ├── has_many :feature_services
  └── has_many :services, through: :feature_services

Environment
  └── belongs_to :workspace

Incident
  ├── has_many :incident_services
  ├── has_many :services, through: :incident_services
  ├── has_many :incident_features
  ├── has_many :features, through: :incident_features
  ├── has_many :incident_environments
  └── has_many :environments, through: :incident_environments
```

---

## Slack UX

### Not shown at creation

Incident creation stays fast — name, severity, summary, visibility. That's it.

### Shown in update flow

When updating an incident (via `/ff update` or quick action), optional dropdowns appear:
- Affected features (multi-select, only if workspace has features configured)
- Affected services (multi-select, only if workspace has services configured)
- Affected environments (multi-select, only if workspace has environments configured)

### Shown in channel topic / announcement

If tagged, include in channel topic:
```
Sev: Critical | Status: Investigating | Feature: Payments | Env: Production
```

### Shown in quick actions message

If tagged, listed in the pinned incident summary block.

---

## Usage by Company Size

| Company type | Teams | Services | Features | Environments |
|---|---|---|---|---|
| **10-person startup** | Skip | Skip | "Payments", "Onboarding", "Search" | Prod, Staging |
| **30-person startup** | "Engineering", "Product" | "our-api", "our-frontend" | "Payments", "Onboarding" | Prod, Staging, Dev |
| **50+ microservices** | "Payments Team", "Platform" | "payment-api", "gateway", "user-svc" | "Checkout Flow", "Billing" | Prod, Staging, Dev |

The system catalog grows with the company. Small teams start with features + environments. Growing teams add services and teams.

---

## Future Enhancements (not now)

- Auto-import from GitHub repos → services
- Auto-import from PagerDuty → services with on-call
- Service dependencies graph
- Auto-suggest incident lead based on feature/service ownership
- Feature → service auto-tag: selecting a feature auto-adds its linked services
