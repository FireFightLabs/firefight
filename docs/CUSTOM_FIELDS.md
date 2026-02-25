# Custom Fields — Future Implementation

> **Status**: Future implementation. This document captures the full design for when custom fields are built. The system catalog (services, features, teams, environments) covers the most common tagging use cases. Custom fields handle everything else — organization-specific data like "Customer Impact Level", "Detection Method", "Customer ID".

---

## Context

Custom fields let workspaces define their own incident properties beyond the built-in fields (severity, status, type) and system catalog entities (services, features, environments, teams). Both incident.io and Rootly treat custom fields as a core feature that enables organization-specific data capture, analytics, and workflow automation.

---

## Schema

### `custom_field_definitions`

Workspace-scoped field definitions. Admin-managed.

```ruby
create_table :custom_field_definitions, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.string :name, null: false                          # "Customer Impact Level"
  t.string :slug, null: false                          # "customer_impact_level"
  t.text :description                                  # Help text shown in forms
  t.string :field_type, null: false                    # "text", "number", "single_select", "multi_select", "link", "checkbox", "date", "datetime"
  t.jsonb :options, default: []                        # For select types: [{"value": "none", "label": "None"}, {"value": "some", "label": "Some"}]
  t.jsonb :default_value                               # Pre-populated value
  t.integer :position, null: false                     # Ordering in forms
  t.boolean :enabled, default: true, null: false       # Disabled fields not shown
  t.datetime :deleted_at
  t.timestamps
end

add_index :custom_field_definitions, [ :workspace_id, :slug ], unique: true
```

**Field types:**

| Type | Slack Block Kit element | Stored as |
|---|---|---|
| `text` | Plain text input | `{"value": "string"}` |
| `number` | Plain text input (validated) | `{"value": 42}` |
| `single_select` | Static select dropdown | `{"value": "option_slug"}` |
| `multi_select` | Multi-static select | `{"value": ["slug1", "slug2"]}` |
| `link` | URL text input | `{"value": "https://..."}` |
| `checkbox` | Checkbox | `{"value": true}` |
| `date` | Date picker | `{"value": "2026-02-22"}` |
| `datetime` | Date picker + time select | `{"value": "2026-02-22T14:30:00Z"}` |

### `custom_field_values`

Per-incident values for custom fields.

```ruby
create_table :custom_field_values, id: :uuid do |t|
  t.references :incident, type: :uuid, null: false, foreign_key: true
  t.references :custom_field_definition, type: :uuid, null: false, foreign_key: true
  t.jsonb :value, null: false                          # Typed value (see above)
  t.references :set_by, type: :uuid, null: true, foreign_key: { to_table: :workspace_memberships }
  t.timestamps
end

add_index :custom_field_values, [ :incident_id, :custom_field_definition_id ], unique: true
```

### `custom_field_form_configs`

Controls which fields appear on which forms, with per-form required/optional and conditional visibility.

```ruby
create_table :custom_field_form_configs, id: :uuid do |t|
  t.references :custom_field_definition, type: :uuid, null: false, foreign_key: true
  t.string :form_type, null: false                     # "create", "update", "close", "cancel"
  t.boolean :visible, default: true, null: false       # Show on this form?
  t.boolean :required, default: false, null: false     # Required on this form?
  t.jsonb :conditions, default: []                     # Conditional visibility rules
  t.timestamps
end

add_index :custom_field_form_configs, [ :custom_field_definition_id, :form_type ], unique: true
```

**Conditions format:**
```json
[
  {
    "field": "severity_slug",
    "operator": "in",
    "values": ["critical", "major"]
  }
]
```

When conditions are present, the field is only shown if ALL conditions are met. Empty conditions = always shown.

---

## Model Relationships

```
Workspace
  └── has_many :custom_field_definitions

CustomFieldDefinition
  ├── belongs_to :workspace
  ├── has_many :custom_field_values
  └── has_many :custom_field_form_configs

CustomFieldValue
  ├── belongs_to :incident
  ├── belongs_to :custom_field_definition
  └── belongs_to :set_by (WorkspaceMembership, optional)

Incident
  ├── has_many :custom_field_values
  └── has_many :custom_field_definitions, through: :custom_field_values
```

---

## Where Custom Fields Appear in Slack

### Forms and when fields are shown

| Form | Triggered by | Custom fields shown |
|---|---|---|
| **Create** | `/ff`, shortcut, create button | Only fields with `form_type: "create"` and `visible: true`. Recommend keeping this minimal — speed matters. |
| **Update** | `/ff update`, quick action button | Fields with `form_type: "update"`. Primary place to set custom fields during an incident. |
| **Close** | `/ff close`, quick action button | Fields with `form_type: "close"`. Good place for required fields like "Root Cause Category". |
| **Cancel** | Quick action button | Fields with `form_type: "cancel"`. Minimal — maybe just "Cancellation Reason". |

### Slack modal rendering

Custom fields are appended to the existing modal blocks. For each visible field:

```ruby
# In Slack::ModalBuilder (pseudocode)
def custom_field_blocks(workspace, form_type, incident = nil)
  definitions = workspace.custom_field_definitions
    .enabled
    .joins(:custom_field_form_configs)
    .where(custom_field_form_configs: { form_type: form_type, visible: true })
    .ordered

  definitions.filter_map do |definition|
    next unless conditions_met?(definition, form_type, incident)
    build_block_for(definition, current_value: incident&.custom_field_value_for(definition))
  end
end
```

Each field type maps to a Slack Block Kit element:

| Field type | Block Kit element |
|---|---|
| `text` | `plain_text_input` |
| `number` | `plain_text_input` with validation |
| `single_select` | `static_select` with options |
| `multi_select` | `multi_static_select` with options |
| `link` | `url_text_input` |
| `checkbox` | `checkboxes` |
| `date` | `datepicker` |
| `datetime` | `datepicker` + `timepicker` (two elements) |

### Block ID convention

```
custom_field_<slug>_block.custom_field_<slug>_input
```

Example: `custom_field_customer_impact_block.custom_field_customer_impact_input`

### Extracting values from submission

```ruby
# In handler (pseudocode)
def extract_custom_fields(interaction, workspace)
  workspace.custom_field_definitions.enabled.each_with_object({}) do |definition, fields|
    block_id = "custom_field_#{definition.slug}_block"
    action_id = "custom_field_#{definition.slug}_input"
    raw_value = interaction.dig_value(block_id, action_id)
    fields[definition.id] = parse_value(definition.field_type, raw_value) if raw_value.present?
  end
end
```

---

## Conditional Visibility

Fields can be conditionally shown based on:
- **Incident severity** — show "Executive Escalation Contact" only for Critical
- **Incident type** — show "Data Classification" only for Security Incidents
- **Lifecycle stage** — show "Root Cause Category" only when closing

Conditions are evaluated server-side before building the modal. Slack modals don't support dynamic show/hide, so conditions determine which fields are included when the modal is built.

**Limitation:** Since Slack modals are static once opened, changing severity in the modal won't dynamically show/hide conditional fields. The field visibility is based on the incident's current state when the modal opens. This is acceptable — users can always reopen the modal after a status/severity change.

---

## Channel Topic and Quick Actions

Custom field values are NOT shown in channel topic (too noisy). They ARE shown in:
- **Quick actions message** — summary section lists set custom fields
- **Announcement message** — high-priority fields can be included (configurable per field)
- **Incident detail** — future web UI

---

## Analytics

Custom fields enable filtering and grouping in analytics:
- "MTTR by Customer Impact Level"
- "Incidents grouped by Detection Method"
- "Show only incidents where Root Cause Category = 'Configuration Change'"

Query pattern:
```sql
SELECT cfd.name, cfv.value, COUNT(*), AVG(resolved_at - declared_at)
FROM incidents i
JOIN custom_field_values cfv ON cfv.incident_id = i.id
JOIN custom_field_definitions cfd ON cfd.id = cfv.custom_field_definition_id
WHERE cfd.slug = 'customer_impact_level'
GROUP BY cfd.name, cfv.value
```

---

## What the System Catalog Already Covers

These common use cases do NOT need custom fields:

| Use case | Covered by |
|---|---|
| Affected services | `incident_services` join table |
| Affected features | `incident_features` join table |
| Affected environments | `incident_environments` join table |
| Team ownership | `teams` table + service/feature ownership |
| Incident type | `incident_types` table |

Custom fields are for everything else — organization-specific dimensions like:
- Customer Impact Level (None / Some / Many / All)
- Detection Method (Monitoring / Customer Report / Manual / Alert)
- Customer ID (text)
- Affected Region (single-select)
- External Ticket URL (link)
- Data Classification (for security incidents)
- Root Cause Category (at resolution)

---

## Verification (when implemented)

1. Admin can create/edit/disable custom field definitions
2. Fields appear in correct Slack modals based on form_type config
3. Conditional fields only show when conditions are met
4. Required fields block form submission when empty
5. Custom field values persisted and retrievable per incident
6. Analytics queries work with custom field values
7. `bin/ci` passes
