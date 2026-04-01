# Step 1: Domain Model And Data Foundations

Status: Planned

## Goal

Create the durable data model for incident custom fields and lifecycle forms.

## Scope

- add schema and models for reusable incident field definitions
- add schema and models for built-in incident forms
- add join/config model for ordered fields within forms
- seed default lifecycle forms and built-in system field mappings
- add serializers or DTO-ready shapes for admin UI consumption where helpful

## Deliverables

### Database

Add tables for:

- `incident_field_definitions`
- `incident_forms`
- `incident_form_fields`

Suggested `incident_field_definitions` columns:

- `workspace_id`
- `key`
- `name`
- `description`
- `field_type`
- `option_source`
- `config` jsonb default `{}`
- `position`
- `deleted_at`
- timestamps

Suggested `incident_forms` columns:

- `workspace_id`
- `slug`
- `name`
- `description`
- `lifecycle_event`
- `position`
- timestamps

Suggested `incident_form_fields` columns:

- `incident_form_id`
- `field_source_type`
- `field_source_id`
- `position`
- `visibility_mode`
- `required_mode`
- `config` jsonb default `{}`
- timestamps

## Model Responsibilities

### `IncidentFieldDefinition`

Owns reusable custom field metadata.

Should validate:

- workspace presence
- key presence and uniqueness within workspace
- key immutability on update
- field type inclusion
- option source inclusion
- config validity for the chosen field type and source
- position presence

### `IncidentForm`

Represents a built-in lifecycle form.

Should validate:

- workspace presence
- slug presence and uniqueness within workspace
- lifecycle event presence
- position presence

Built-in slugs should be protected from deletion or arbitrary mutation.

### `IncidentFormField`

Represents one ordered field in a form.

Should validate:

- form presence
- source presence
- uniqueness of the source within a given form
- position presence
- visibility/required mode inclusion

## System Field Strategy

Do not create fake custom records for system fields.

Instead, define a stable system-field registry in Ruby, for example:

- `name`
- `summary`
- `severity`
- `incident_type`
- `status`

`IncidentFormField` should be able to reference either:

- a system field source
- an `IncidentFieldDefinition`

We can represent this with polymorphic source fields plus a system-field identifier strategy, or a dedicated source abstraction serialized uniformly.

## Seeds

Seed default forms per workspace:

- `declare`
- `accept`
- `update`
- `resolve`

Seed each form with a sensible ordered set of system fields.

Examples:

### Declare

- name
- incident_type
- severity
- summary

### Update

- summary

### Resolve

- summary
- status

This seed set should be minimal and easy to evolve.

## Serializer Direction

Prepare explicit serialized structures for admin pages.

We will likely need:

- field definition serializer
- form serializer
- form field serializer

Important: frontend should receive fully-shaped field descriptors and avoid reconstructing meaning from raw DB columns.

## Acceptance Criteria

- models and migrations exist
- default lifecycle forms are seeded per workspace
- workspace can store reusable field definitions
- form definitions can include ordered field references
- tests cover core validations and seeds

## Risks

- overcomplicating system field representation too early
- mixing field definition concerns with form concerns
- encoding future conditional logic before the base model is stable

## Notes For Later Steps

This step should not include:

- submission validation
- admin editing UI
- incident create/update form rendering

It is a foundation step only.
