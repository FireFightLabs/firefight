# Incident Forms

Status: Planned

## Goal

Build a configurable incident forms system that lets workspaces define what responders see and complete at key points in the incident lifecycle.

The system should support:

- reusable custom field definitions
- predefined lifecycle forms such as `declare`, `accept`, `update`, and `resolve`
- ordering, show/hide, and required/optional configuration per form
- catalogue-backed fields for structured operational context
- one shared definition model that can be used manually in the product and later by AI, workflows, and MCP-powered actions

This should follow the same architectural direction we have used elsewhere:

- thin controllers
- service-owned write orchestration
- model-level validations and scopes
- serializer-driven frontend contracts
- minimal correct changes first, then richer UX later

## Product Story

Today, incidents can store `custom_fields`, but they do not yet have a first-class forms system.

We want to move from ad hoc JSON storage toward a structured product capability with three layers:

1. Field definitions
2. Form definitions
3. Form rendering and editing

The intended user experience is closer to incident.io's structured forms model than to a freeform page builder:

- a workspace gets built-in lifecycle forms
- admins can add reusable custom fields
- admins can add catalogue-backed fields such as affected services or impacted environments
- admins can reorder fields and decide where they are shown or required
- built-in incident fields remain protected system fields

This gives us a durable foundation for later work:

- richer reporting and filtering
- workflow triggers
- automation rules
- AI-assisted form completion
- MCP/API access to the same field definitions and values

## Design Principles

### 1. Separate fields from forms

Do not encode form visibility, ordering, and requiredness directly on the field definition.

- `IncidentFieldDefinition` describes a reusable field
- `IncidentForm` describes a lifecycle form
- `IncidentFormField` connects the two and stores per-form behavior

This lets one field appear in multiple forms with different rules.

### 2. Preserve system fields as first-class concepts

Some incident inputs are not custom fields and should remain protected system fields.

Examples:

- `name`
- `summary`
- `severity`
- `incident_type`
- `status` in relevant lifecycle steps

Forms should be able to configure how these appear, but they should not become arbitrary user-defined fields.

### 3. Use catalogue as a value source, not as the form system

Catalogue should power structured options for certain incident fields.

Examples:

- affected services
- owning team
- environment
- functionality

But catalogue should not replace the incident form model itself.

### 4. Start constrained, then expand

The first version should prefer:

- built-in lifecycle forms
- a small supported field type set
- simple reorder and show/hide controls
- no full drag-and-drop layout builder
- no arbitrary sections or canvas composition

If later usage proves we need more layout freedom, we can add it on top of the stable data model.

### 5. One definition system for humans and automation

The same field definitions and form configuration should be usable by:

- web UI
- Slack entry points where applicable
- API writes
- future workflow automation
- future AI and MCP tooling

## Desired UX

The UI should feel deliberate and polished, inspired by incident.io's forms UX without becoming a clone.

We want:

- a dedicated `Forms` settings surface
- predefined lifecycle form cards
- an editor for each form
- clear distinction between system fields and custom fields
- a refined, premium admin experience with strong hierarchy and calm density

Initial interaction model:

- form index page with cards for `Declare`, `Accept`, `Update`, `Resolve`
- edit view for a single form
- list-style field editor with reorder handles, visibility state, required state, and field metadata
- add-field flow that supports both reusable custom fields and catalogue-backed fields

Frontend design direction:

- preserve our existing visual language
- elevate the editor with more editorial spacing and stronger affordances
- avoid generic builder chrome
- emphasize clarity over heavy decoration
- treat the field list as a crafted control surface, not a noisy admin table

## Domain Model

### `IncidentFieldDefinition`

Reusable field definition owned by a workspace.

Suggested fields:

- `workspace_id`
- `key`
- `name`
- `description`
- `field_type`
- `option_source`
- `config` jsonb
- `position`
- `deleted_at`

Notes:

- `key` should be immutable after creation
- field definitions should be reusable across multiple forms
- `option_source` allows a field to be backed by fixed options, catalogue, or another dynamic source later

Suggested initial field types:

- `text`
- `number`
- `single_select`
- `multi_select`
- `link`
- `catalog_reference`
- `catalog_multi_reference`

Suggested initial option sources:

- `none`
- `fixed`
- `catalog`

### `IncidentForm`

Represents a built-in lifecycle form.

Suggested fields:

- `workspace_id`
- `slug`
- `name`
- `description`
- `lifecycle_event`
- `position`

Initial built-in slugs:

- `declare`
- `accept`
- `update`
- `resolve`

These should be seeded and treated as protected system forms.

### `IncidentFormField`

Join model between a form and a field-like source.

Suggested fields:

- `incident_form_id`
- `field_source_type`
- `field_source_id`
- `position`
- `visibility_mode`
- `required_mode`
- `config` jsonb

Important detail:

`field_source_type` should support both:

- system incident fields
- custom incident field definitions

This avoids duplicating the concept of built-in fields as fake custom fields.

Example source model:

- system field source represented by constants or a dedicated `IncidentSystemField` abstraction
- custom field source represented by `IncidentFieldDefinition`

## Value Model

Incident values should continue to live on the incident record, but be validated against form and field definitions.

- system fields update first-class incident columns
- custom field values live in `incident.custom_fields`

This keeps the storage model aligned with the existing `Incident` domain while adding structure around it.

## Validation Model

Validation should live in the service layer, not in controllers.

We will likely need an `IncidentFormSubmissionService` or equivalent logic folded into `IncidentLifecycleService`.

Responsibilities:

- resolve the active form
- determine visible and required fields
- validate input values against field definitions
- normalize values
- persist system fields to incident columns
- persist custom values to `incident.custom_fields`

Validation rules should cover:

- required fields
- unknown fields rejected
- fixed option validation
- catalogue reference validation
- type coercion where appropriate

## API and Serialization Direction

The UI should not infer form structure from raw field data.

We should expose explicit serialized shape for:

- form metadata
- ordered field list
- field source details
- field type and option source
- required/visibility configuration

That gives us one stable contract for:

- web forms
- future API clients
- future AI and MCP integrations

## Non-Goals For V1

The first implementation should not include:

- a freeform drag-and-drop page builder
- arbitrary layout sections or columns
- deeply nested conditional logic
- derived fields or formula fields
- dynamic external option providers beyond catalogue
- Slack-native form parity for every advanced field on day one

## Iterative Plan

- [ ] [Step 1: Domain Model And Data Foundations](./step1.md)
- [ ] [Step 2: Services, Validation, And Persistence](./step2.md)
- [ ] [Step 3: Admin UI For Custom Fields](./step3.md)
- [ ] [Step 4: Forms Settings UI And Form Editor](./step4.md)
- [ ] [Step 5: Incident Form Rendering In Product Flows](./step5.md)
- [ ] [Step 6: Reporting, Automation, And AI Readiness](./step6.md)

When a step is completed, we will mark it done here.

## Implementation Sequence

1. Establish the data model.
2. Add write-path services and validation.
3. Build custom field management UI.
4. Build forms settings and form editor UI.
5. Wire forms into incident create and update flows.
6. Expose clean read models for automation and future AI tooling.

## Open Questions

These should be answered before or during implementation:

- Should field definitions be global to a workspace only, or optionally scoped to incident type from the start?
- Should `accept` and `resolve` forms support different requiredness rules for system fields than `declare`?
- Do we need separate field types for single vs multi catalogue reference, or one reference type with config?
- How much conditional visibility do we need in V1?
- Do we want system fields configurable via the same join model from day one, or do we seed them behind a separate abstraction and serialize them uniformly?

## Success Criteria

We will consider this initiative successful when:

- admins can define reusable incident custom fields
- admins can configure predefined lifecycle forms
- forms can include both system fields and catalogue-backed custom fields
- incident submissions are validated against form configuration
- the UI is polished and easy to understand
- the resulting model is stable enough to reuse for workflows, API clients, and future AI tooling
