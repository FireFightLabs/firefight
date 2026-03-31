# Incident Forms and Fields Plan

## Context

After the catalogue backend is in place, Firefight needs a clean way to control what data is collected during each step of the incident lifecycle.

The right separation is:

- incident types classify the kind of incident
- incident fields define reusable pieces of incident data
- forms decide which fields appear during each lifecycle action

This follows the same core model used by incident.io.

## Goals

- Keep incident declaration fast
- Make field visibility configurable by lifecycle action
- Support both built-in fields and catalogue-backed fields
- Keep incident types separate from form structure
- Leave room for later per-incident-type overrides

## Non-goals

- Building arbitrary freeform custom fields in v1
- Building workflow automation rules in this phase
- Building Slack-specific UI in this doc
- Reworking catalogue backend design

## Core Separation

### 1. Incident Types

Incident types answer:

- what kind of incident is this?

Examples:

- `production`
- `security`
- `data`
- `performance`

They are classification, not form layout.

### 2. Incident Field Definitions

Field definitions answer:

- what reusable fields can incident forms show?

Examples:

- severity
- status
- summary
- visibility
- incident type
- affected services
- affected environments
- affected functionalities

These fields are reusable across multiple forms.

### 3. Forms

Forms answer:

- which fields appear during which lifecycle action?
- in what order?
- which are required?

Examples:

- declare
- accept
- update
- resolve
- escalate

## Recommended v1 Product Model

Firefight should start with three admin concepts:

1. `Incident Types`
2. `Incident Fields`
3. `Forms`

That gives us the right architecture without overbuilding.

## Field Kinds

In v1, incident field definitions should support two broad categories.

### Built-in fields

These map directly to existing incident data.

Examples:

- severity
- status
- summary
- visibility
- incident_type

### Catalogue-backed fields

These map to catalogue types and store selected catalogue entry ids.

Examples:

- affected services
- affected teams
- affected environments
- affected functionalities

These should reference the catalogue backend, not reimplement its schema.

## Schema Direction

### `incident_form_definitions`

Represents a lifecycle form.

Suggested columns:

```ruby
create_table :incident_form_definitions, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.string :key, null: false
  t.string :name, null: false
  t.text :description
  t.integer :position, null: false
  t.timestamps
end

add_index :incident_form_definitions, [ :workspace_id, :key ], unique: true
```

Reserved form keys for v1:

- `declare`
- `update`
- `resolve`

Potential later additions:

- `accept`
- `escalate`
- `postmortem`

### `incident_field_definitions`

Represents a reusable incident field.

Suggested columns:

```ruby
create_table :incident_field_definitions, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.string :key, null: false
  t.string :name, null: false
  t.string :field_kind, null: false # built_in | catalog
  t.string :built_in_key
  t.references :catalog_type, type: :uuid, null: true, foreign_key: true
  t.string :selection_mode, null: false, default: "single" # single | multiple
  t.text :help_text
  t.boolean :active, null: false, default: true
  t.integer :position, null: false
  t.timestamps
end

add_index :incident_field_definitions, [ :workspace_id, :key ], unique: true
```

Rules:

- built-in fields require `built_in_key` and no `catalog_type_id`
- catalogue-backed fields require `catalog_type_id` and no `built_in_key`
- `key` is stable and never user-facing
- `selection_mode` applies primarily to catalogue-backed fields

### `incident_form_fields`

Join table assigning fields to forms.

Suggested columns:

```ruby
create_table :incident_form_fields, id: :uuid do |t|
  t.references :incident_form_definition, type: :uuid, null: false, foreign_key: true
  t.references :incident_field_definition, type: :uuid, null: false, foreign_key: true
  t.boolean :required, null: false, default: false
  t.integer :position, null: false
  t.timestamps
end

add_index :incident_form_fields,
  [ :incident_form_definition_id, :incident_field_definition_id ],
  unique: true,
  name: "index_incident_form_fields_uniqueness"
```

This table answers:

- is this field shown on this form?
- is it required here?
- where does it appear in the form order?

## Built-in Field Keys

Suggested built-in keys for v1:

- `severity`
- `status`
- `summary`
- `visibility`
- `incident_type`
- `update_message`
- `resolution_summary`

These should be constants, not raw strings.

## Catalogue-backed Field Examples

Suggested seeded defaults:

- `affected_functionalities`
  - `field_kind: catalog`
  - `catalog_type: functionality`
  - `selection_mode: multiple`
- `affected_services`
  - `field_kind: catalog`
  - `catalog_type: service`
  - `selection_mode: multiple`
- `affected_environments`
  - `field_kind: catalog`
  - `catalog_type: environment`
  - `selection_mode: multiple`
- `affected_teams`
  - `field_kind: catalog`
  - `catalog_type: team`
  - `selection_mode: multiple`

## Recommended v1 Default Forms

### Declare

Should stay minimal.

Recommended default fields:

- severity
- summary
- visibility
- incident_type
- affected_functionalities
- affected_environments

`affected_services` should usually not be required on declare.

### Update

Used once responders know more.

Recommended default fields:

- update_message
- severity
- status
- affected_functionalities
- affected_services
- affected_teams
- affected_environments

### Resolve

Used to ensure good final data quality.

Recommended default fields:

- resolution_summary
- status
- affected_services
- affected_environments

This is a good place to require fields that are optional during declare.

## How This Fits Incident Types

Incident types should not directly own form layouts in v1.

Instead:

- forms define default field visibility for the workspace
- incident types remain classification only

Later, we can support per-type overrides.

## Future v2: Type-specific Form Overrides

If we later need incident-type-specific form behavior, add a new layer such as:

### `incident_type_form_field_overrides`

Suggested columns:

```ruby
create_table :incident_type_form_field_overrides, id: :uuid do |t|
  t.references :incident_type, type: :uuid, null: false, foreign_key: true
  t.references :incident_form_field, type: :uuid, null: false, foreign_key: true
  t.boolean :enabled
  t.boolean :required
  t.integer :position
  t.timestamps
end
```

This allows rules like:

- security incidents show extra fields on resolve
- production incidents require affected services on declare
- data incidents require a customer-impact field on update

That should be a later phase, not part of v1.

## How Values Should Be Stored

Form configuration defines visibility and requirements, but actual selected values should live on the incident domain.

For catalogue-backed fields, that likely means a separate join table in a later incident integration phase, such as:

```ruby
create_table :incident_catalog_entries, id: :uuid do |t|
  t.references :incident, type: :uuid, null: false, foreign_key: true
  t.references :incident_field_definition, type: :uuid, null: false, foreign_key: true
  t.references :catalog_entry, type: :uuid, null: false, foreign_key: true
  t.timestamps
end
```

This allows the same catalog entry type to be used by different incident fields if needed later.

## Service Layer Direction

Suggested services:

- `IncidentForms::SeedDefaults`
- `IncidentForms::CreateFieldDefinition`
- `IncidentForms::UpdateFieldDefinition`
- `IncidentForms::UpdateForm`

Controllers should remain thin and delegate to these services.

## Recommended Delivery Order

1. Add `incident_form_definitions`
2. Add `incident_field_definitions`
3. Add `incident_form_fields`
4. Seed default forms and field definitions
5. Build settings read path
6. Build settings write path
7. Wire forms into incident create/update/resolve flows
8. Add incident value persistence for catalogue-backed selections

## Summary

Firefight should follow this architecture:

- `Incident Types` = classification
- `Incident Fields` = reusable field definitions
- `Forms` = lifecycle-specific field configuration

That keeps the system flexible, matches competitor direction, and avoids coupling catalogue schema or incident types directly to lifecycle UI behavior.
