# Incident Tags — Implementation Plan

## Context

Firefight has incident types (structured classification), system catalog entities (services, features, environments), and future custom fields (admin-defined structured data). Tags fill a different niche: lightweight, freeform, ad-hoc labeling that anyone can apply during an incident without admin setup.

Tags are like GitHub issue labels — they capture cross-cutting patterns that emerge organically rather than through upfront planning.

---

## Schema

### `incident_tags`

Workspace-scoped tag definitions. Created on-the-fly or pre-defined by admins.

```ruby
create_table :incident_tags, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.string :name, null: false                  # "recurring", "customer-reported", "deploy-related"
  t.string :slug, null: false
  t.string :color                              # Hex color for display
  t.text :description                          # Optional — what this tag means
  t.integer :usage_count, default: 0, null: false  # Denormalized for sorting by popularity
  t.datetime :deleted_at
  t.timestamps
end

add_index :incident_tags, [ :workspace_id, :slug ], unique: true
```

### `incident_taggings`

Join table connecting incidents to tags.

```ruby
create_table :incident_taggings, id: :uuid do |t|
  t.references :incident, type: :uuid, null: false, foreign_key: true
  t.references :incident_tag, type: :uuid, null: false, foreign_key: true
  t.references :tagged_by, type: :uuid, null: true, foreign_key: { to_table: :workspace_memberships }
  t.timestamps
end

add_index :incident_taggings, [ :incident_id, :incident_tag_id ], unique: true
```

---

## Model

```ruby
# app/models/incident_tag.rb
class IncidentTag < ApplicationRecord
  belongs_to :workspace
  has_many :incident_taggings, dependent: :destroy
  has_many :incidents, through: :incident_taggings

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }

  scope :kept, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:name) }
  scope :popular, -> { order(usage_count: :desc) }
end
```

On `Incident`:
```ruby
has_many :incident_taggings, dependent: :destroy
has_many :incident_tags, through: :incident_taggings
```

---

## How Tags Differ from Other Concepts

| Concept | Structured? | Admin setup? | Use case |
|---|---|---|---|
| **Incident Type** | Yes — single-select FK | Admin defines types | "What kind of problem?" (Service Outage, Security) |
| **Services/Features** | Yes — catalog entities | Admin configures | "What's affected?" (payment-api, Onboarding) |
| **Custom Fields** | Yes — typed, validated | Admin defines fields | Structured data (Customer ID, Impact Level) |
| **Tags** | No — freeform | Anyone can create on-the-fly | Ad-hoc patterns (recurring, deploy-related, customer-reported) |

Tags complement structured data. They capture things that don't fit into predefined schemas.

---

## Defaults

No default tags seeded. Tags emerge organically from usage.

Admins can pre-create common tags if they want, but the system works without any setup.

---

## Slack UX

### Adding tags

- **Quick action button** "Tag" or `/ff tag` command in incident channel
- Opens a multi-select with existing workspace tags + ability to type a new tag name
- New tag names auto-create the tag (no admin approval needed)
- Tags shown sorted by popularity (most used first)

### Where tags appear

| Touchpoint | How |
|---|---|
| **Quick actions message** | Listed as comma-separated labels below incident summary |
| **Channel topic** | Not shown (too noisy) |
| **Announcement** | Not shown |
| **Update modal** | Optional tag selector included |
| **Close modal** | Optional tag selector included (good time to categorize) |

### Removing tags

- Same multi-select — deselect to remove
- Or `/ff untag <tag-name>`

---

## Analytics

Tags enable ad-hoc analytics:
- "How many incidents tagged `deploy-related` this month?"
- "What's the MTTR for `customer-reported` vs internally detected?"
- "Show me all `recurring` incidents — what's the common pattern?"

Query pattern:
```sql
SELECT it.name, COUNT(*), AVG(EXTRACT(EPOCH FROM (i.resolved_at - i.declared_at)) / 60) as avg_mttr_minutes
FROM incidents i
JOIN incident_taggings itn ON itn.incident_id = i.id
JOIN incident_tags it ON it.id = itn.incident_tag_id
GROUP BY it.name
ORDER BY COUNT(*) DESC
```

---

## `usage_count` Maintenance

Denormalized counter for sorting by popularity. Updated via counter cache or callback:

```ruby
# In IncidentTagging
after_create  -> { incident_tag.increment!(:usage_count) }
after_destroy -> { incident_tag.decrement!(:usage_count) }
```

---

## Verification

1. `bin/ci` passes
2. Can create a tag on-the-fly when tagging an incident
3. Can select existing tags from workspace pool
4. Tags appear in quick actions message
5. Can remove tags
6. `usage_count` updates correctly
7. Analytics queries work (filter/group by tag)
8. `incident.tagged` event recorded in audit trail
